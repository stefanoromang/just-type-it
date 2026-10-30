// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

namespace JustTypeIt;

/// The editor window: write or paste text, see underlines and suggestions, fix with a click.
public sealed class MainWindow : Form
{
    readonly RichTextBox editor = new() { Dock = DockStyle.Fill, BorderStyle = BorderStyle.None, Font = new Font("Segoe UI", 12f), DetectUrls = false, AcceptsTab = true };
    readonly FlowLayoutPanel cards = new() { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(10) };
    readonly Label score = new() { Dock = DockStyle.Top, Height = 64, Font = new Font("Segoe UI", 12f, FontStyle.Bold), Padding = new Padding(12, 10, 0, 0) };
    readonly Label stats = new() { Dock = DockStyle.Bottom, Height = 26, ForeColor = Color.Gray, Padding = new Padding(16, 4, 0, 0) };
    readonly ComboBox dialect = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 150 };
    readonly ComboBox formality = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 110 };
    readonly ComboBox domain = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 110 };
    readonly System.Windows.Forms.Timer debounce = new() { Interval = 350 };
    List<Issue> issues = new();
    bool painting;

    public MainWindow()
    {
        Text = "Just Type It";
        Icon = Program.AppIcon;
        Size = new Size(1200, 760);
        MinimumSize = new Size(860, 520);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.White;
        AutoScaleMode = AutoScaleMode.Dpi;

        var toolbar = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 44, Padding = new Padding(12, 8, 0, 0), BackColor = Color.FromArgb(248, 248, 248) };
        void AddButton(string text, Action a) { var b = new Button { Text = text, AutoSize = true, FlatStyle = FlatStyle.Flat }; b.Click += (_, _) => a(); toolbar.Controls.Add(b); }
        AddButton("Open…", OpenFile);
        AddButton("Save as…", SaveFile);
        AddButton("Copy all", () => { if (editor.TextLength > 0) Clipboard.SetText(editor.Text); });
        AddButton("Accept all", AcceptAll);
        toolbar.Controls.Add(new Label { Text = "  English:", AutoSize = true, Padding = new Padding(0, 6, 0, 0) });
        dialect.Items.AddRange(Enum.GetNames<Dialect>());
        dialect.SelectedItem = Store.Shared.Prefs.Dialect.ToString();
        dialect.SelectedIndexChanged += (_, _) => { Store.Shared.Prefs.Dialect = Enum.Parse<Dialect>((string)dialect.SelectedItem!); Store.Shared.Save(); Recheck(); };
        toolbar.Controls.Add(dialect);
        toolbar.Controls.Add(new Label { Text = "  Formality:", AutoSize = true, Padding = new Padding(0, 6, 0, 0) });
        formality.Items.AddRange(Enum.GetNames<Formality>());
        formality.SelectedItem = Store.Shared.Prefs.DefaultGoals.Formality.ToString();
        formality.SelectedIndexChanged += (_, _) => { Store.Shared.Prefs.DefaultGoals.Formality = Enum.Parse<Formality>((string)formality.SelectedItem!); Store.Shared.Save(); Recheck(); };
        toolbar.Controls.Add(formality);
        toolbar.Controls.Add(new Label { Text = "  Domain:", AutoSize = true, Padding = new Padding(0, 6, 0, 0) });
        domain.Items.AddRange(Enum.GetNames<Domain>());
        domain.SelectedItem = Store.Shared.Prefs.DefaultGoals.Domain.ToString();
        domain.SelectedIndexChanged += (_, _) => { Store.Shared.Prefs.DefaultGoals.Domain = Enum.Parse<Domain>((string)domain.SelectedItem!); Store.Shared.Save(); Recheck(); };
        toolbar.Controls.Add(domain);

        var split = new SplitContainer { Dock = DockStyle.Fill, SplitterDistance = 760, FixedPanel = FixedPanel.Panel2 };
        var editorHost = new Panel { Dock = DockStyle.Fill, Padding = new Padding(28, 20, 20, 10), BackColor = Color.White };
        editorHost.Controls.Add(editor);
        split.Panel1.Controls.Add(editorHost);
        split.Panel1.Controls.Add(stats);
        split.Panel2.BackColor = Color.FromArgb(246, 247, 249);
        split.Panel2.Controls.Add(cards);
        split.Panel2.Controls.Add(score);
        Controls.Add(split);
        Controls.Add(toolbar);
        Shown += (_, _) => split.SplitterDistance = Math.Max(400, ClientSize.Width - 400);

        editor.Text = Store.Shared.DraftText;
        editor.TextChanged += (_, _) => { if (painting) return; debounce.Stop(); debounce.Start(); };
        debounce.Tick += (_, _) => { debounce.Stop(); Store.Shared.DraftText = editor.Text; Store.Shared.Save(); Recheck(); };
        Recheck();
    }

    static string Norm(string s) => s.Replace("\r\n", "\n");

    void Recheck()
    {
        var text = Norm(editor.Text);
        issues = RuleEngine.Check(text, Store.Shared.Options());
        var m = Metrics.Compute(text, issues);
        score.Text = $"Score {m.Overall}   ·   {issues.Count} suggestion{(issues.Count == 1 ? "" : "s")}\n" +
                     string.Join("   ", Enum.GetValues<IssueGroup>().Select(g => $"{g}: {m.GroupCounts[g]}"));
        score.Font = new Font("Segoe UI", 10.5f, FontStyle.Bold);
        stats.Text = $"{m.Words} words · {m.Characters} characters · {Math.Max(1, (int)Math.Ceiling(m.ReadingMinutes))} min read · readability {m.Readability:0} ({m.ReadabilityLabel}) · tone: {string.Join(", ", m.Tones.Select(t => t.name))}";
        Underline();
        BuildCards();
    }

    void Underline()
    {
        painting = true;
        int selStart = editor.SelectionStart, selLen = editor.SelectionLength;
        editor.SuspendLayout();
        editor.SelectAll();
        editor.SelectionBackColor = Color.White;
        editor.SelectionFont = new Font("Segoe UI", 12f, FontStyle.Regular);
        foreach (var i in issues.Where(x => x.Length <= 60))
        {
            editor.Select(i.Start, i.Length);
            editor.SelectionFont = new Font("Segoe UI", 12f, FontStyle.Underline);
            editor.SelectionBackColor = Color.FromArgb(40, i.Group.Color());
        }
        editor.Select(selStart, selLen);
        editor.ResumeLayout();
        painting = false;
    }

    void BuildCards()
    {
        cards.SuspendLayout();
        cards.Controls.Clear();
        if (issues.Count == 0)
            cards.Controls.Add(new Label { Text = "✓ Looks great!", AutoSize = true, ForeColor = Color.SeaGreen, Font = new Font("Segoe UI", 12f, FontStyle.Bold), Padding = new Padding(10) });
        foreach (var i in issues.Take(100))
        {
            var card = new Panel { Width = 340, BackColor = Color.White, Padding = new Padding(10), Margin = new Padding(0, 0, 0, 8), AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink };
            var inner = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false, Dock = DockStyle.Fill };
            inner.Controls.Add(new Label { Text = $"{i.Group.Label().ToUpperInvariant()} · {i.Title}", ForeColor = i.Group.Color(), Font = new Font("Segoe UI", 8.5f, FontStyle.Bold), AutoSize = true });
            if (i.Length <= 80) inner.Controls.Add(new Label { Text = i.Original, Font = new Font("Segoe UI", 10f, i.Replacements.Count > 0 ? FontStyle.Strikeout : FontStyle.Regular), ForeColor = Color.Gray, AutoSize = true, MaximumSize = new Size(310, 0) });
            foreach (var r in i.Replacements.Take(3))
            {
                var b = new Button { Text = r.Length == 0 ? "Remove" : r, AutoSize = true, FlatStyle = FlatStyle.Flat, BackColor = i.Group.Color(), ForeColor = Color.White, Font = new Font("Segoe UI", 9.5f, FontStyle.Bold), MaximumSize = new Size(310, 0) };
                b.FlatAppearance.BorderSize = 0;
                var issue = i; var rep = r;
                b.Click += (_, _) => Apply(issue, rep);
                inner.Controls.Add(b);
            }
            inner.Controls.Add(new Label { Text = i.Explanation, AutoSize = true, MaximumSize = new Size(310, 0), ForeColor = Color.FromArgb(90, 90, 90) });
            var row = new FlowLayoutPanel { AutoSize = true };
            var dismiss = new LinkLabel { Text = "Dismiss", AutoSize = true };
            var dIssue = i;
            dismiss.Click += (_, _) => { issues.Remove(dIssue); BuildCards(); };
            row.Controls.Add(dismiss);
            if (i.Kind.StartsWith("Spelling"))
            {
                var add = new LinkLabel { Text = "Add to dictionary", AutoSize = true };
                add.Click += (_, _) => { Store.Shared.AddToDictionary(dIssue.Original); Recheck(); };
                row.Controls.Add(add);
            }
            inner.Controls.Add(row);
            card.Controls.Add(inner);
            var sel = i;
            card.Click += (_, _) => { editor.Focus(); editor.Select(sel.Start, sel.Length); editor.ScrollToCaret(); };
            cards.Controls.Add(card);
        }
        cards.ResumeLayout();
    }

    void Apply(Issue i, string replacement)
    {
        var text = Norm(editor.Text);
        if (TextUtil.Sub(text, i.Start, i.Length) != i.Original) { Recheck(); return; }
        editor.Select(i.Start, i.Length);
        editor.SelectedText = replacement;
        Store.Shared.Prefs.FixesAccepted++;
        Recheck();
    }

    void AcceptAll()
    {
        var text = Norm(editor.Text);
        int lastStart = int.MaxValue;
        foreach (var i in issues.Where(x => x.Replacements.Count > 0 && x.Length <= 80).OrderByDescending(x => x.Start))
        {
            if (i.End > lastStart) continue;
            text = text.Remove(i.Start, i.Length).Insert(i.Start, i.Replacements[0]);
            lastStart = i.Start;
            Store.Shared.Prefs.FixesAccepted++;
        }
        editor.Text = text;
        Recheck();
    }

    void OpenFile()
    {
        using var d = new OpenFileDialog { Filter = "Text and documents|*.txt;*.md;*.rtf|All files|*.*" };
        if (d.ShowDialog(this) != DialogResult.OK) return;
        if (d.FileName.EndsWith(".rtf", StringComparison.OrdinalIgnoreCase)) editor.LoadFile(d.FileName, RichTextBoxStreamType.RichText);
        else editor.Text = File.ReadAllText(d.FileName);
    }

    void SaveFile()
    {
        using var d = new SaveFileDialog { Filter = "Text|*.txt|Rich text|*.rtf", FileName = "Document" };
        if (d.ShowDialog(this) != DialogResult.OK) return;
        if (d.FileName.EndsWith(".rtf", StringComparison.OrdinalIgnoreCase)) editor.SaveFile(d.FileName, RichTextBoxStreamType.RichText);
        else File.WriteAllText(d.FileName, editor.Text);
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        // Keep running in the tray so checking continues in other apps.
        if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); }
        base.OnFormClosing(e);
    }
}
