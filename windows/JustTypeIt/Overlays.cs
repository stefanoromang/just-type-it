// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System.Runtime.InteropServices;

namespace JustTypeIt;

/// Base for small top-most windows that never take focus away from the app you're typing in.
public class FloatingForm : Form
{
    public FloatingForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        AutoScaleMode = AutoScaleMode.Dpi;
    }
    protected override bool ShowWithoutActivation => true;
    const int WS_EX_NOACTIVATE = 0x08000000, WS_EX_TOOLWINDOW = 0x80, WS_EX_TOPMOST = 0x8;
    protected override CreateParams CreateParams
    {
        get { var cp = base.CreateParams; cp.ExStyle |= WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST; return cp; }
    }
    public void ShowQuietly()
    {
        if (!Visible) { Show(); }
        SetWindowPos(Handle, (IntPtr)(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);
    }
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
}

/// Transparent window that draws colored underlines; clicking an underline opens the card.
public sealed class UnderlineOverlay : FloatingForm
{
    List<(Issue issue, List<Rectangle> rects)> marks = new();
    readonly SuggestionCard card = new();
    public event Action<Issue, Point>? MarkClicked;

    public UnderlineOverlay()
    {
        BackColor = Color.Magenta;
        TransparencyKey = Color.Magenta;
        DoubleBuffered = true;
    }

    // Click-through everywhere except right on an underline.
    const int WM_NCHITTEST = 0x84, HTTRANSPARENT = -1;
    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_NCHITTEST)
        {
            var p = new Point((short)(m.LParam.ToInt64() & 0xFFFF), (short)((m.LParam.ToInt64() >> 16) & 0xFFFF));
            if (!marks.Any(x => x.rects.Any(r => Hit(r).Contains(p)))) { m.Result = (IntPtr)HTTRANSPARENT; return; }
        }
        base.WndProc(ref m);
    }

    static Rectangle Hit(Rectangle r) => new(r.X, r.Bottom - 6, r.Width, 10);

    protected override void OnMouseDown(MouseEventArgs e)
    {
        var p = PointToScreen(e.Location);
        var hit = marks.FirstOrDefault(x => x.rects.Any(r => Hit(r).Contains(p)));
        if (hit.issue != null) MarkClicked?.Invoke(hit.issue, new Point(hit.rects[0].Left, hit.rects[0].Bottom + 4));
    }

    public void Show(Rectangle area, List<(Issue, List<Rectangle>)> m)
    {
        marks = m;
        if (Bounds != area) Bounds = area;
        Invalidate();
        if (marks.Count > 0) ShowQuietly(); else Hide();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        foreach (var (issue, rects) in marks)
            foreach (var r in rects)
            {
                var local = new Rectangle(r.X - Left, r.Y - Top, r.Width, r.Height);
                using var pen = new Pen(issue.Group.Color(), 2.2f);
                if (issue.Length > 40) pen.DashStyle = System.Drawing.Drawing2D.DashStyle.Dot;
                e.Graphics.DrawLine(pen, local.Left, local.Bottom - 1, local.Right, local.Bottom - 1);
            }
    }

    public void ShowCard(Issue issue, Point at, Action<string> apply, Action dismiss, Action addWord) => card.ShowFor(issue, at, apply, dismiss, addWord);
    public void HideCard() => card.Hide();
}

/// The round badge in the corner of the text box with the number of suggestions.
public sealed class SuggestionBadge : FloatingForm
{
    int count;
    IssueGroup group;
    public event Action? Clicked;

    public SuggestionBadge()
    {
        Size = new Size(28, 28);
        BackColor = Color.Magenta;
        TransparencyKey = Color.Magenta;
        Cursor = Cursors.Hand;
    }

    public void Show(Rectangle field, int n, IssueGroup g)
    {
        count = n; group = g;
        Location = new Point(field.Right - Width - 8, field.Bottom - Height - 8);
        Invalidate();
        ShowQuietly();
    }

    protected override void OnMouseDown(MouseEventArgs e) => Clicked?.Invoke();

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        using var b = new SolidBrush(group.Color());
        e.Graphics.FillEllipse(b, 1, 1, Width - 3, Height - 3);
        using var f = new Font("Segoe UI", count > 9 ? 8f : 9.5f, FontStyle.Bold);
        TextRenderer.DrawText(e.Graphics, count > 99 ? "99+" : count.ToString(), f, new Rectangle(0, 0, Width, Height), Color.White,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
    }
}

/// Card with the fix, the explanation and one-click actions.
public sealed class SuggestionCard : FloatingForm
{
    readonly FlowLayoutPanel panel = new() { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(12), AutoSize = true };

    public SuggestionCard()
    {
        BackColor = Color.White;
        Padding = new Padding(1);
        Controls.Add(panel);
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        using var p = new Pen(Color.FromArgb(210, 210, 210));
        e.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
    }

    public void ShowFor(Issue issue, Point at, Action<string> apply, Action dismiss, Action addWord)
    {
        panel.SuspendLayout();
        panel.Controls.Clear();
        panel.Controls.Add(new Label { Text = $"{issue.Group.Label().ToUpperInvariant()} · {issue.Title}", ForeColor = issue.Group.Color(), Font = new Font("Segoe UI", 8.5f, FontStyle.Bold), AutoSize = true });
        if (issue.Length <= 80)
            panel.Controls.Add(new Label { Text = issue.Original, Font = new Font("Segoe UI", 10f, FontStyle.Strikeout), ForeColor = Color.Gray, AutoSize = true, MaximumSize = new Size(320, 0) });
        foreach (var r in issue.Replacements.Take(4))
        {
            var b = new Button { Text = r.Length == 0 ? "Remove" : r, AutoSize = true, FlatStyle = FlatStyle.Flat, BackColor = issue.Group.Color(), ForeColor = Color.White, Font = new Font("Segoe UI", 10f, FontStyle.Bold), Margin = new Padding(0, 4, 0, 0), MaximumSize = new Size(320, 0) };
            b.FlatAppearance.BorderSize = 0;
            var rep = r;
            b.Click += (_, _) => { Hide(); apply(rep); };
            panel.Controls.Add(b);
        }
        panel.Controls.Add(new Label { Text = issue.Explanation, AutoSize = true, MaximumSize = new Size(320, 0), ForeColor = Color.FromArgb(80, 80, 80), Font = new Font("Segoe UI", 9f), Margin = new Padding(0, 8, 0, 4) });
        var row = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight };
        var dis = new LinkLabel { Text = "Dismiss", AutoSize = true };
        dis.Click += (_, _) => { Hide(); dismiss(); };
        row.Controls.Add(dis);
        if (issue.Kind.StartsWith("Spelling"))
        {
            var add = new LinkLabel { Text = "Add to dictionary", AutoSize = true };
            add.Click += (_, _) => { Hide(); addWord(); };
            row.Controls.Add(add);
        }
        panel.Controls.Add(row);
        panel.ResumeLayout();
        var screen = Screen.FromPoint(at).WorkingArea;
        var size = GetPreferredSize(new Size(360, 0));
        Location = new Point(Math.Min(at.X, screen.Right - size.Width - 4), at.Y + size.Height > screen.Bottom ? at.Y - size.Height - 30 : at.Y);
        ShowQuietly();
    }
}

/// List of every suggestion in the current text box, with Fix and Fix all.
public sealed class SummaryWindow : FloatingForm
{
    static SummaryWindow? open;

    public static void ShowFor(string app, List<Issue> issues, Func<Issue, Task<bool>> fix, Func<Task> fixAll)
    {
        open?.Close();
        open = new SummaryWindow(app, issues, fix, fixAll);
        var cursor = Cursor.Position;
        var screen = Screen.FromPoint(cursor).WorkingArea;
        open.Location = new Point(Math.Max(screen.Left, Math.Min(cursor.X - open.Width + 20, screen.Right - open.Width)), Math.Max(screen.Top, cursor.Y - open.Height - 20));
        open.ShowQuietly();
    }

    SummaryWindow(string app, List<Issue> issues, Func<Issue, Task<bool>> fix, Func<Task> fixAll)
    {
        Size = new Size(380, 420);
        BackColor = Color.White;
        var header = new Label { Text = $"Just Type It · {app} · {issues.Count} suggestion{(issues.Count == 1 ? "" : "s")}", Dock = DockStyle.Top, Height = 34, Font = new Font("Segoe UI", 10f, FontStyle.Bold), Padding = new Padding(10, 8, 0, 0) };
        var close = new Button { Text = "✕", Dock = DockStyle.Right, Width = 34, FlatStyle = FlatStyle.Flat };
        close.FlatAppearance.BorderSize = 0;
        close.Click += (_, _) => Close();
        header.Controls.Add(close);
        var list = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(8) };
        foreach (var i in issues.Take(60))
        {
            var row = new Panel { Width = 340, Height = 46, Margin = new Padding(0, 0, 0, 6), BackColor = Color.FromArgb(246, 246, 246) };
            row.Controls.Add(new Label { Text = i.Replacements.Count > 0 ? $"{Trim(i.Original)} → {(i.Replacements[0].Length == 0 ? "remove" : Trim(i.Replacements[0]))}" : Trim(i.Original), Location = new Point(10, 5), AutoSize = true, Font = new Font("Segoe UI", 9.5f) });
            row.Controls.Add(new Label { Text = i.Title, Location = new Point(10, 25), AutoSize = true, ForeColor = i.Group.Color(), Font = new Font("Segoe UI", 8f) });
            if (i.Replacements.Count > 0)
            {
                var b = new Button { Text = "Fix", Size = new Size(48, 26), Location = new Point(284, 10), FlatStyle = FlatStyle.Flat };
                var issue = i;
                b.Click += async (_, _) => { b.Enabled = false; if (await fix(issue)) row.Visible = false; else b.Enabled = true; };
                row.Controls.Add(b);
            }
            list.Controls.Add(row);
        }
        var bottom = new Panel { Dock = DockStyle.Bottom, Height = 44 };
        var all = new Button { Text = $"Fix all ({issues.Count(x => x.Replacements.Count > 0)})", Size = new Size(140, 30), Location = new Point(228, 7), FlatStyle = FlatStyle.Flat, BackColor = IssueGroup.Clarity.Color(), ForeColor = Color.White };
        all.Click += async (_, _) => { Close(); await fixAll(); };
        bottom.Controls.Add(all);
        Controls.Add(list);
        Controls.Add(bottom);
        Controls.Add(header);
    }

    static string Trim(string s) => s.Length > 34 ? s[..33] + "…" : s;

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        using var p = new Pen(Color.FromArgb(210, 210, 210));
        e.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
    }
}
