// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace JustTypeIt;

static class Program
{
    public static Icon AppIcon = SystemIcons.Application;
    static Mutex? single;

    [STAThread]
    static int Main(string[] args)
    {
        if (args.Contains("--selftest")) return SelfTest.Run(args.SkipWhile(a => a != "--selftest").Skip(1).FirstOrDefault() ?? "selftest-report.txt");

        single = new Mutex(true, "JustTypeIt.SingleInstance", out bool first);
        if (!first)
        {
            // Already running in the tray: ask it to show its window instead of exiting silently.
            try { using var show = EventWaitHandle.OpenExisting("JustTypeIt.ShowWindow"); show.Set(); } catch { }
            return 0;
        }
        ApplicationConfiguration.Initialize();
        try
        {
            using var s = typeof(Program).Assembly.GetManifestResourceStream("JustTypeIt.AppIcon.ico");
            if (s != null) AppIcon = new Icon(s);
        }
        catch { }
        using var app = new TrayApp(showWindow: !args.Contains("--background"));
        Application.Run(app);
        return 0;
    }

    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public static bool IsStartWithWindows()
    {
        try { using var key = Registry.CurrentUser.OpenSubKey(RunKey); return key?.GetValue("JustTypeIt") != null; }
        catch { return false; }
    }

    public static void SetStartWithWindows(bool on)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, true);
            if (key == null) return;
            if (on) key.SetValue("JustTypeIt", $"\"{Application.ExecutablePath}\" --background");
            else key.DeleteValue("JustTypeIt", false);
        }
        catch { }
    }
}

/// Lives in the system tray, keeps checking every app, opens the editor on demand.
sealed class TrayApp : ApplicationContext
{
    readonly NotifyIcon tray = new() { Text = "Just Type It", Visible = true };
    readonly HotkeyWindow hotkeys = new();
    MainWindow? window;

    public TrayApp(bool showWindow)
    {
        tray.Icon = Program.AppIcon;
        // The installer's choice (Run key present or not) wins on first launch; afterwards the tray toggle decides.
        if (!Store.Shared.Prefs.Onboarded) { Store.Shared.Prefs.StartWithWindows = Program.IsStartWithWindows(); Store.Shared.Save(); }
        var menu = new ContextMenuStrip();
        var status = new ToolStripMenuItem("Checking as you type in every app") { Enabled = false };
        menu.Items.Add(status);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Open Just Type It", null, (_, _) => ShowWindow());
        menu.Items.Add("Check selected text  (Ctrl+Alt+G)", null, (_, _) => QuickCheck.Run());
        menu.Items.Add("Rewrite selected text  (Ctrl+Alt+R)", null, (_, _) => RewriteWindow.Run());
        var everywhere = new ToolStripMenuItem("Check in all apps") { Checked = Store.Shared.Prefs.CheckEverywhere, CheckOnClick = true };
        everywhere.CheckedChanged += (_, _) =>
        {
            Store.Shared.Prefs.CheckEverywhere = everywhere.Checked; Store.Shared.Save();
            if (everywhere.Checked) Everywhere.Shared.Start(); else Everywhere.Shared.Stop();
        };
        menu.Items.Add(everywhere);
        var ac = new ToolStripMenuItem("Autocorrect obvious typos") { Checked = Store.Shared.Prefs.Autocorrect, CheckOnClick = true };
        ac.CheckedChanged += (_, _) => { Store.Shared.Prefs.Autocorrect = ac.Checked; Store.Shared.Save(); };
        menu.Items.Add(ac);
        var tone = new ToolStripMenuItem("Show tone emoji") { Checked = Store.Shared.Prefs.ShowTone, CheckOnClick = true };
        tone.CheckedChanged += (_, _) => { Store.Shared.Prefs.ShowTone = tone.Checked; Store.Shared.Save(); };
        menu.Items.Add(tone);
        var languages = new ToolStripMenuItem("Languages");
        LanguageMenu.Fill(languages);
        menu.Items.Add(languages);
        var pause = new ToolStripMenuItem("Pause checking");
        pause.DropDownItems.Add("For 1 hour", null, (_, _) => Everywhere.Shared.PausedUntil = DateTime.Now.AddHours(1));
        pause.DropDownItems.Add("Until tomorrow", null, (_, _) => Everywhere.Shared.PausedUntil = DateTime.Today.AddDays(1));
        pause.DropDownItems.Add("Resume now", null, (_, _) => Everywhere.Shared.PausedUntil = null);
        menu.Items.Add(pause);
        var startup = new ToolStripMenuItem("Start with Windows") { Checked = Store.Shared.Prefs.StartWithWindows, CheckOnClick = true };
        startup.CheckedChanged += (_, _) => { Store.Shared.Prefs.StartWithWindows = startup.Checked; Store.Shared.Save(); Program.SetStartWithWindows(startup.Checked); };
        menu.Items.Add(startup);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("About Just Type It", null, (_, _) => MessageBox.Show("Just Type It\nCreated by Stefano Roman Gunness\nFree, private AI writing assistant.\nMIT License", "About Just Type It"));
        menu.Items.Add("Quit", null, (_, _) => { tray.Visible = false; Everywhere.Shared.Stop(); ExitThread(); });
        menu.Opening += (_, _) =>
        {
            var e = Everywhere.Shared;
            status.Text = e.PausedUntil is { } u ? $"Paused until {u:t}"
                : !e.Running ? "Checking in other apps is off"
                : e.CurrentApp.Length > 0 ? $"{e.CurrentApp}: {e.IssueCount} suggestion{(e.IssueCount == 1 ? "" : "s")}" : "Checking as you type in every app";
        };
        tray.ContextMenuStrip = menu;
        tray.DoubleClick += (_, _) => ShowWindow();
        var failed = new List<string>();
        if (!hotkeys.Register(1, Keys.G, QuickCheck.Run)) failed.Add("Ctrl+Alt+G");
        if (!hotkeys.Register(2, Keys.R, RewriteWindow.Run)) failed.Add("Ctrl+Alt+R");
        if (failed.Count > 0)
            tray.ShowBalloonTip(6000, "Shortcut unavailable", $"{string.Join(" and ", failed)} is used by another app. Use the tray menu instead.", ToolTipIcon.Warning);
        if (Store.Shared.Prefs.CheckEverywhere) Everywhere.Shared.Start();
        // A second launch (Start menu, desktop shortcut) signals this instance to show its window.
        var showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, "JustTypeIt.ShowWindow");
        var ui = SynchronizationContext.Current;
        ThreadPool.RegisterWaitForSingleObject(showSignal, (_, _) => ui?.Post(_ => ShowWindow(), null), null, -1, false);
        if (showWindow) ShowWindow();
        if (!Store.Shared.Prefs.Onboarded)
        {
            tray.ShowBalloonTip(6000, "Just Type It is running", "Type in Outlook, Word, Teams or Chrome and mistakes are underlined. Highlight text and press Ctrl+Alt+R to rewrite it.", ToolTipIcon.Info);
            Store.Shared.Prefs.Onboarded = true; Store.Shared.Save();
        }
    }

    void ShowWindow()
    {
        window ??= new MainWindow();
        window.Show();
        if (window.WindowState == FormWindowState.Minimized) window.WindowState = FormWindowState.Normal;
        window.Activate();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { tray.Dispose(); hotkeys.Dispose(); window?.Dispose(); Everywhere.Shared.Dispose(); }
        base.Dispose(disposing);
    }
}

/// Global hotkeys: Ctrl+Alt+G (check selection) and Ctrl+Alt+R (rewrite selection).
sealed class HotkeyWindow : NativeWindow, IDisposable
{
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
    readonly Dictionary<int, Action> actions = new();
    public HotkeyWindow() => CreateHandle(new CreateParams());
    public bool Register(int id, Keys key, Action a) { actions[id] = a; return RegisterHotKey(Handle, id, 0x0001 | 0x0002 | 0x4000, (uint)key); }
    protected override void WndProc(ref Message m)
    {
        if (m.Msg == 0x0312 && actions.TryGetValue((int)m.WParam, out var a)) a();
        base.WndProc(ref m);
    }
    public void Dispose() { foreach (var id in actions.Keys) UnregisterHotKey(Handle, id); DestroyHandle(); }
}

/// Ctrl+Alt+G: copies the selection from any app, shows suggestions, pastes the fixed text back.
static class QuickCheck
{
    public static async void Run()
    {
        try
        {
            var source = InputHelper.GetForegroundWindow();
            var selection = InputHelper.CaptureSelection();
            var text = await InputHelper.CopySelection(Keys.G);
            if (text.Trim().Length == 0)
            {
                MessageBox.Show("Select some text in any app, then press Ctrl+Alt+G.", "Just Type It");
                return;
            }
            var normalized = text.Replace("\r\n", "\n");
            var issues = RuleEngine.Check(normalized, Store.Shared.Options());
            var fixedText = Rewriter.ApplyIssues(normalized, issues);
            var summary = issues.Count == 0 ? "No suggestions — looks great!" : string.Join("\n", issues.Take(12).Select(i => "• " + i));
            var answer = MessageBox.Show($"{summary}\n\nReplace the selected text with the corrected version?", "Just Type It – Quick Check",
                issues.Any(i => i.Replacements.Count > 0) ? MessageBoxButtons.YesNo : MessageBoxButtons.OK);
            if (answer != DialogResult.Yes) return;
            if (!await RewriteWindow.ReturnTo(source)) { Clipboard.SetText(fixedText.Replace("\n", "\r\n")); MessageBox.Show("Couldn't switch back to the app. The corrected text is on your clipboard; press Ctrl+V to paste it.", "Just Type It"); return; }
            if (!InputHelper.MatchesSelection(selection)) { Clipboard.SetText(fixedText); MessageBox.Show("The original selection changed or could not be verified. The corrected text is on your clipboard; select where it belongs and press Ctrl+V.", "Just Type It"); return; }
            await InputHelper.Paste(fixedText, canPaste: () => InputHelper.MatchesSelection(selection));
        }
        catch (Exception e) { MessageBox.Show("Quick Check couldn't finish: " + e.Message, "Just Type It"); }
    }
}
