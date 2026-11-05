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
    readonly FlowLayoutPanel styles = new() { Dock = DockStyle.Top, AutoSize = true, Padding = new Padding(0, 6, 0, 6) };
    readonly TextBox result = new() { Multiline = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Font = new Font("Segoe UI", 10.5f) };
    readonly Label status = new() { Dock = DockStyle.Top, Height = 24, ForeColor = Color.Gray };
    readonly ComboBox versionPicker = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 110, Visible = false };
    readonly TextBox custom = new() { Width = 360, PlaceholderText = "Or describe it: “make it sound like a thank-you note”" };
    List<string> versions = new();
    bool showAll;

    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);

    public static async void Run()
    {
        var src = GetForegroundWindow();
        var text = await CopySelection();
        if (string.IsNullOrWhiteSpace(text))
        {
            MessageBox.Show("Highlight some text in any app, then press Ctrl+Alt+R to rewrite it.", "Just Type It");
            return;
        }
        open?.Close();
        open = new RewriteWindow(text, src);
        open.Show();
        open.Activate();
    }

    RewriteWindow(string text, IntPtr src)
    {
        original = text;
        sourceWindow = src;
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
        again.Click += (_, _) => { if (lastMode != null) Go(lastMode.Value, lastCustom); };
        versionPicker.SelectedIndexChanged += (_, _) => { if (versionPicker.SelectedIndex >= 0 && versionPicker.SelectedIndex < versions.Count) result.Text = versions[versionPicker.SelectedIndex]; };
        bottom.Controls.AddRange(new Control[] { replace, copy, again, versionPicker });
        AcceptButton = replace;

        root.Controls.Add(result);
        root.Controls.Add(status);
        root.Controls.Add(customRow);
        root.Controls.Add(styles);
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
        status.Text = model != null
            ? $"Using your local AI model ({model}). Pick a style; you'll get up to three versions."
            : "Pick a style. For every style (enthusiastic, persuasive, reply…), install Ollama — free and offline.";
        foreach (Button b in styles.Controls.OfType<Button>())
            if (b.Tag is RewriteMode m) b.Enabled = model != null || m.WorksOffline();
    }

    void BuildStyles()
    {
        styles.Controls.Clear();
        var modes = showAll ? Enum.GetValues<RewriteMode>() : RewriteModes.Primary;
        foreach (var m in modes)
        {
            var b = new Button { Text = m.Label(), Tag = m, Width = 140, Height = 30, FlatStyle = FlatStyle.System };
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

    async void Go(RewriteMode mode, string? customText = null)
    {
        lastMode = mode; lastCustom = customText;
        status.Text = "Writing…";
        result.Text = "";
        UseWaitCursor = true;
        versions = await Rewriter.Versions(original, mode, customText, options: Store.Shared.Options());
        UseWaitCursor = false;
        versionPicker.Items.Clear();
        for (int i = 0; i < versions.Count; i++) versionPicker.Items.Add($"Version {i + 1}");
        versionPicker.Visible = versions.Count > 1;
        if (versions.Count > 0) { versionPicker.SelectedIndex = 0; result.Text = versions[0]; }
        status.Text = versions.Count == 0
            ? (mode.WorksOffline() ? "No changes needed — this already reads well." : "This style needs a local AI model (install Ollama).")
            : $"{mode.Label()} · {TextUtil.WordCount(original)} → {TextUtil.WordCount(versions[0])} words";
    }

    async Task Replace()
    {
        var text = result.Text;
        if (text.Length == 0) return;
        Close();
        SetForegroundWindow(sourceWindow);
        await Task.Delay(250);
        // The original selection is still active in the source app: paste over it.
        var saved = SaveClipboard();
        try { Clipboard.SetText(text.Replace("\r\n", "\n").Replace("\n", "\r\n")); SendKeys.SendWait("^v"); } catch { }
        await Task.Delay(400);
        RestoreClipboard(saved);
        Store.Shared.Prefs.Rewrites++;
        Store.Shared.Save();
    }

    // MARK: Clipboard helpers (all formats are restored, not just text)

    static IDataObject? SaveClipboard()
    {
        try
        {
            var src = Clipboard.GetDataObject();
            if (src == null) return null;
            var copy = new DataObject();
            foreach (var f in src.GetFormats(false))
                try { var d = src.GetData(f, false); if (d != null) copy.SetData(f, d); } catch { }
            return copy;
        }
        catch { return null; }
    }

    static void RestoreClipboard(IDataObject? saved)
    {
        try { if (saved != null) Clipboard.SetDataObject(saved, true); } catch { }
    }

    /// Copies the current selection in the foreground app (Ctrl+C), then restores the clipboard.
    public static async Task<string> CopySelection()
    {
        var saved = SaveClipboard();
        try { Clipboard.Clear(); } catch { }
        SendKeys.SendWait("^c");
        string text = "";
        for (int i = 0; i < 15 && text.Length == 0; i++)
        {
            await Task.Delay(40);
            try { if (Clipboard.ContainsText()) text = Clipboard.GetText(); } catch { }
        }
        RestoreClipboard(saved);
        return text;
    }
}
