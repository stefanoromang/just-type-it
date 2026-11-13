// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System.Runtime.InteropServices;

namespace JustTypeIt;

/// Ctrl+Alt+R in any app: rewrite the highlighted text (more professional, casual, shorter…),
/// pick a version, and replace it in place.
public sealed class RewriteWindow : Form
{
    static RewriteWindow? open;
    readonly string original;
    readonly IntPtr sourceWindow;
    readonly InputHelper.SelectionSnapshot? sourceSelection;
    readonly FlowLayoutPanel styles = new() { Dock = DockStyle.Top, AutoSize = true, Padding = new Padding(0, 6, 0, 6) };
    readonly TextBox result = new() { Multiline = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Font = new Font("Segoe UI", 10.5f) };
    readonly Label status = new() { Dock = DockStyle.Top, Height = 24, ForeColor = Color.Gray };
    readonly ComboBox versionPicker = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 110, Visible = false };
    readonly TextBox custom = new() { Width = 360, PlaceholderText = "Or describe it: “make it sound like a thank-you note”" };
    List<string> versions = new();
    bool showAll;
    bool working;
    CancellationTokenSource? generation;

    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);

    public static async void Run()
    {
        try
        {
        var src = GetForegroundWindow();
        var selection = InputHelper.CaptureSelection();
        var text = await InputHelper.CopySelection(Keys.R);
        if (string.IsNullOrWhiteSpace(text))
        {
            MessageBox.Show("Highlight some text in any app, then press Ctrl+Alt+R to rewrite it.", "Just Type It");
            return;
        }
        open?.Close();
        open = new RewriteWindow(text, src, selection);
        open.Show();
        open.Activate();
        }
        catch (Exception e) { MessageBox.Show("Rewrite couldn't open: " + e.Message, "Just Type It"); }
    }

    RewriteWindow(string text, IntPtr src, InputHelper.SelectionSnapshot? selection)
    {
        original = text;
        sourceWindow = src;
        sourceSelection = selection;
        Text = "Just Type It – Rewrite";
        Icon = Program.AppIcon;
        Size = new Size(640, 600);
        MinimumSize = new Size(520, 460);
        StartPosition = FormStartPosition.Manual;
        var screen = Screen.FromPoint(Cursor.Position).WorkingArea;
        Location = new Point(Math.Max(screen.Left, Math.Min(Cursor.Position.X - 320, screen.Right - Width)), Math.Max(screen.Top, Math.Min(Cursor.Position.Y - 60, screen.Bottom - Height)));
        TopMost = true;
        BackColor = Color.White;
        KeyPreview = true;
        KeyDown += (_, e) => { if (e.KeyCode == Keys.Escape) Close(); };
        FormClosed += (_, _) => { generation?.Cancel(); generation?.Dispose(); };
        AutoScaleMode = AutoScaleMode.Dpi;

        var root = new Panel { Dock = DockStyle.Fill, Padding = new Padding(16) };
        var originalBox = new Label { Text = text.Length > 400 ? text[..400] + "…" : text, Dock = DockStyle.Top, AutoSize = false, Height = 64, ForeColor = Color.DimGray, BackColor = Color.FromArgb(245, 245, 245), Padding = new Padding(8) };
        var customRow = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true };
        var customGo = new Button { Text = "Rewrite", AutoSize = true };
        customGo.Click += (_, _) => { if (custom.Text.Trim().Length > 0) Go(RewriteMode.Improve, custom.Text.Trim()); };
        custom.KeyDown += (_, e) => { if (e.KeyCode == Keys.Enter && custom.Text.Trim().Length > 0) { e.SuppressKeyPress = true; Go(RewriteMode.Improve, custom.Text.Trim()); } };
        customRow.Controls.Add(custom);
        customRow.Controls.Add(customGo);

        var bottom = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 44, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(0, 8, 0, 0) };
        var replace = new Button { Text = "Replace", Width = 100, Height = 30, BackColor = Color.FromArgb(14, 120, 158), ForeColor = Color.White, FlatStyle = FlatStyle.Flat };
        replace.Click += async (_, _) => await Replace();
        var copy = new Button { Text = "Copy", Width = 80, Height = 30 };
        copy.Click += (_, _) => { if (result.Text.Length > 0) Clipboard.SetText(result.Text); copy.Text = "Copied"; };
        var again = new Button { Text = "Try again", Width = 90, Height = 30 };
        again.Click += (_, _) => { if (lastMode != null) Go(lastMode.Value, lastCustom, varied: true); };
        versionPicker.SelectedIndexChanged += (_, _) => { if (versionPicker.SelectedIndex >= 0 && versionPicker.SelectedIndex < versions.Count) result.Text = versions[versionPicker.SelectedIndex]; };
        bottom.Controls.AddRange(new Control[] { replace, copy, again, versionPicker });
        AcceptButton = replace;

        root.Controls.Add(result);
        root.Controls.Add(status);
        root.Controls.Add(customRow);
        root.Controls.Add(styles);
        var configure = new Button { Text = "Customize seven Quick Actions…", Dock = DockStyle.Top, Height = 30 };
        configure.Click += (_, _) => Customize();
        root.Controls.Add(configure);
        root.Controls.Add(originalBox);
        root.Controls.Add(new Label { Text = "Rewrite", Font = new Font("Segoe UI", 13f, FontStyle.Bold), Dock = DockStyle.Top, Height = 32 });
        root.Controls.Add(bottom);
        Controls.Add(root);
        BuildStyles();
        _ = UpdateStatus();
    }

    async Task UpdateStatus()
    {
        var model = await Rewriter.AvailableModel();
        if (IsDisposed || working) return;
        status.Text = model != null
            ? $"Local AI ({model}). Preview a result before replacing. ‘Try again’ gives another version."
            : "Pick a style. For every style (enthusiastic, persuasive, reply…), install Ollama — free and offline.";
        foreach (Button b in styles.Controls.OfType<Button>())
            if (b.Tag is RewriteMode m) b.Enabled = model != null || m.WorksOffline();
    }

    void BuildStyles()
    {
        styles.Controls.Clear();
        var modes = showAll ? Enum.GetValues<RewriteMode>() : RewriteModes.Normalize(Store.Shared.Prefs.QuickActions);
        foreach (var m in modes)
        {
            var b = new Button { Text = m.Label(), Tag = m, Width = 170, Height = 32, FlatStyle = FlatStyle.System, AccessibleName = m.Label() };
            var mode = m;
            b.Click += (_, _) => Go(mode);
            styles.Controls.Add(b);
        }
        var more = new LinkLabel { Text = showAll ? "Fewer styles" : "More styles…", AutoSize = true, Padding = new Padding(4, 8, 0, 0) };
        more.Click += (_, _) => { showAll = !showAll; BuildStyles(); _ = UpdateStatus(); };
        styles.Controls.Add(more);
    }

    RewriteMode? lastMode;
    string? lastCustom;

    async void Go(RewriteMode mode, string? customText = null, bool varied = false)
    {
        if (working) return;
        if (original.Length > 6000) { status.Text = "Select at most 6,000 characters for a rewrite or translation."; return; }
        generation?.Dispose();
        generation = new CancellationTokenSource();
        working = true;
        lastMode = mode; lastCustom = customText;
        status.Text = "Writing…";
        result.Text = "";
        UseWaitCursor = true;
        try { versions = await Rewriter.Versions(original, mode, customText, count: 1, options: Store.Shared.Options(), cancellationToken: generation.Token, varied: varied); }
        catch (Exception e) { if (!IsDisposed) status.Text = "Could not finish: " + e.Message; return; }
        finally { working = false; if (!IsDisposed) UseWaitCursor = false; }
        if (IsDisposed || generation.IsCancellationRequested) return;
        UseWaitCursor = false;
        versionPicker.Items.Clear();
        for (int i = 0; i < versions.Count; i++) versionPicker.Items.Add($"Version {i + 1}");
        versionPicker.Visible = versions.Count > 1;
        if (versions.Count > 0) { versionPicker.SelectedIndex = 0; result.Text = versions[0]; }
        status.Text = versions.Count == 0
            ? "No result returned. The text may already be correct, or this action needs a working local Ollama model."
            : $"{mode.Label()} · {TextUtil.WordCount(original)} → {TextUtil.WordCount(versions[0])} words";
    }

    async Task Replace()
    {
        var text = result.Text;
        if (text.Length == 0) return;
        Close();
        if (!await ReturnTo(sourceWindow))
        {
            try { Clipboard.SetText(text.Replace("\r\n", "\n").Replace("\n", "\r\n")); } catch { }
            MessageBox.Show("Couldn't switch back to the app. The rewrite is on your clipboard; press Ctrl+V to paste it.", "Just Type It");
            return;
        }
        if (!InputHelper.MatchesSelection(sourceSelection))
        {
            Clipboard.SetText(text);
            MessageBox.Show("The original selection changed or could not be verified. The result is on your clipboard; select where it belongs and press Ctrl+V.", "Just Type It");
            return;
        }
        try { await InputHelper.Paste(text, canPaste: () => InputHelper.MatchesSelection(sourceSelection)); }
        catch (Exception e) { MessageBox.Show("The replacement could not be completed: " + e.Message, "Just Type It"); return; }
        Store.Shared.Prefs.Rewrites++;
        Store.Shared.Save();
    }

    /// Brings the source window back and waits until it's really in front, so a paste never lands elsewhere.
    public static async Task<bool> ReturnTo(IntPtr window)
    {
        for (int i = 0; i < 20; i++)
        {
            SetForegroundWindow(window);
            await Task.Delay(60);
            if (InputHelper.GetForegroundWindow() == window) { await Task.Delay(80); return InputHelper.GetForegroundWindow() == window; }
        }
        return false;
    }

    void Customize()
    {
        if (working) return;
        Configure(this); BuildStyles(); _ = UpdateStatus();
    }

    internal static void Configure(Form owner)
    {
        using var dialog = new Form { Text = "Your seven Quick Actions", Width = 460, Height = 380, StartPosition = FormStartPosition.CenterParent, AutoScaleMode = AutoScaleMode.Dpi };
        var list = new FlowLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(16), FlowDirection = FlowDirection.TopDown, WrapContents = false };
        var current = RewriteModes.Normalize(Store.Shared.Prefs.QuickActions);
        var picks = new List<ComboBox>();
        for (int i = 0; i < 7; i++)
        {
            var row = new FlowLayoutPanel { Width = 400, Height = 36 };
            row.Controls.Add(new Label { Text = $"Action {i + 1}", Width = 80, Padding = new Padding(0, 6, 0, 0) });
            var pick = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 270, AccessibleName = $"Action {i + 1}" };
            foreach (var m in Enum.GetValues<RewriteMode>()) pick.Items.Add(m.Label());
            pick.SelectedIndex = (int)current[i];
            picks.Add(pick); row.Controls.Add(pick); list.Controls.Add(row);
        }
        var done = new Button { Text = "Save", DialogResult = DialogResult.OK, AutoSize = true };
        list.Controls.Add(done); dialog.AcceptButton = done; dialog.Controls.Add(list);
        if (dialog.ShowDialog(owner) == DialogResult.OK)
        {
            Store.Shared.Prefs.QuickActions = picks.Select(p => (RewriteMode)p.SelectedIndex).ToList();
            Store.Shared.Save();
        }
    }

}
