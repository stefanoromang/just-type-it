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
        if (!first) return 0;
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
        var menu = new ContextMenuStrip();
        var status = new ToolStripMenuItem("Checking as you type in every app") { Enabled = false };
        menu.Items.Add(status);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Open Just Type It", null, (_, _) => ShowWindow());
        menu.Items.Add("Check selected text  (Ctrl+Alt+G)", null, (_, _) => QuickCheck.Run());
        var everywhere = new ToolStripMenuItem("Check in all apps") { Checked = Store.Shared.Prefs.CheckEverywhere, CheckOnClick = true };
        everywhere.CheckedChanged += (_, _) =>
        {
            Store.Shared.Prefs.CheckEverywhere = everywhere.Checked; Store.Shared.Save();
            if (everywhere.Checked) Everywhere.Shared.Start(); else Everywhere.Shared.Stop();
        };
        menu.Items.Add(everywhere);
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
        hotkeys.Register(QuickCheck.Run);
        Program.SetStartWithWindows(Store.Shared.Prefs.StartWithWindows);
        if (Store.Shared.Prefs.CheckEverywhere) Everywhere.Shared.Start();
        if (showWindow) ShowWindow();
        if (!Store.Shared.Prefs.Onboarded)
        {
            tray.ShowBalloonTip(6000, "Just Type It is running", "Type in Outlook, Word, Teams or Chrome and mistakes are underlined. Select text and press Ctrl+Alt+G to check it.", ToolTipIcon.Info);
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

/// Global Ctrl+Alt+G hotkey.
sealed class HotkeyWindow : NativeWindow, IDisposable
{
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
    Action? action;
    public HotkeyWindow() => CreateHandle(new CreateParams());
    public void Register(Action a) { action = a; RegisterHotKey(Handle, 1, 0x0001 | 0x0002 | 0x4000, (uint)Keys.G); }
    protected override void WndProc(ref Message m)
    {
        if (m.Msg == 0x0312) action?.Invoke();
        base.WndProc(ref m);
    }
    public void Dispose() { UnregisterHotKey(Handle, 1); DestroyHandle(); }
}

/// Ctrl+Alt+G: copies the selection from any app, shows suggestions, pastes the fixed text back.
static class QuickCheck
{
    public static async void Run()
    {
        IDataObject? saved = null;
        try { saved = Clipboard.GetDataObject(); Clipboard.Clear(); } catch { }
        SendKeys.SendWait("^c");
        await Task.Delay(150);
        string text = "";
        try { if (Clipboard.ContainsText()) text = Clipboard.GetText(); } catch { }
        try { if (saved != null) Clipboard.SetDataObject(saved, true); } catch { }
        if (text.Trim().Length == 0)
        {
            MessageBox.Show("Select some text in any app, then press Ctrl+Alt+G.", "Just Type It");
            return;
        }
        var issues = RuleEngine.Check(text.Replace("\r\n", "\n"), Store.Shared.Options());
        var fixedText = text.Replace("\r\n", "\n");
        foreach (var i in issues.Where(x => x.Replacements.Count > 0 && x.Length <= 80).OrderByDescending(x => x.Start))
            fixedText = fixedText.Remove(i.Start, i.Length).Insert(i.Start, i.Replacements[0]);
        var summary = issues.Count == 0 ? "No suggestions — looks great!" : string.Join("\n", issues.Take(12).Select(i => "• " + i));
        var answer = MessageBox.Show($"{summary}\n\nReplace the selected text with the corrected version?", "Just Type It – Quick Check",
            issues.Any(i => i.Replacements.Count > 0) ? MessageBoxButtons.YesNo : MessageBoxButtons.OK);
        if (answer != DialogResult.Yes) return;
        await Task.Delay(200);
        try { Clipboard.SetText(fixedText.Replace("\n", "\r\n")); SendKeys.SendWait("^v"); } catch { }
        await Task.Delay(400);
        try { if (saved != null) Clipboard.SetDataObject(saved, true); } catch { }
    }
}
