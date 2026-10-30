// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Automation;
using System.Windows.Automation.Text;

namespace JustTypeIt;

/// Checks the text box you're typing in, in any app (Outlook, Word, Teams, Chrome, Edge, Notepad…),
/// using Windows UI Automation. Draws underlines over it and a badge with the number of suggestions.
public sealed class Everywhere : IDisposable
{
    public static readonly Everywhere Shared = new();

    readonly System.Windows.Forms.Timer timer = new() { Interval = 300 };
    readonly UnderlineOverlay overlay = new();
    readonly SuggestionBadge badge = new();
    readonly HashSet<string> dismissed = new();
    AutomationElement? element;
    string lastText = "";
    string? checkedText;
    DateTime lastChange = DateTime.MinValue;
    List<Issue> issues = new();
    List<(Issue issue, List<Rectangle> rects)> marks = new();
    bool busy, applying;
    public string CurrentApp { get; private set; } = "";
    public int IssueCount => issues.Count;
    public bool Running => timer.Enabled;
    public DateTime? PausedUntil { get; set; }
    public event Action? Changed;

    static readonly HashSet<string> Excluded = new(StringComparer.OrdinalIgnoreCase)
    {
        "JustTypeIt", "cmd", "powershell", "pwsh", "WindowsTerminal", "Code", "devenv", "KeePass", "1Password", "Bitwarden", "mstsc",
    };

    Everywhere()
    {
        timer.Tick += async (_, _) => await Tick();
        badge.Clicked += () => ShowSummary();
        overlay.MarkClicked += (i, p) => ShowCard(i, p);
    }

    public void Start() { timer.Start(); }
    public void Stop() { timer.Stop(); HideAll(); }
    public void Dispose() { timer.Dispose(); overlay.Dispose(); badge.Dispose(); }

    void HideAll()
    {
        overlay.Hide(); badge.Hide();
        marks.Clear();
        if (issues.Count != 0) { issues = new(); Changed?.Invoke(); }
    }

    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

    async Task Tick()
    {
        if (busy || applying) return;
        busy = true;
        try
        {
            if (PausedUntil is { } until) { if (DateTime.Now < until) { HideAll(); return; } PausedUntil = null; }
            var hwnd = GetForegroundWindow();
            GetWindowThreadProcessId(hwnd, out var pid);
            string proc;
            try { proc = Process.GetProcessById((int)pid).ProcessName; } catch { HideAll(); return; }
            if (pid == Environment.ProcessId || Excluded.Contains(proc) || Store.Shared.Prefs.PausedApps.Contains(proc, StringComparer.OrdinalIgnoreCase))
            {
                if (pid != Environment.ProcessId) HideAll();
                return;
            }
            // UI Automation can block; never call it on the UI thread.
            var read = await Task.Run(() => ReadFocused((int)pid));
            if (read == null) { element = null; HideAll(); return; }
            var (el, text, bounds) = read.Value;
            if (element == null || !Automation.Compare(el, element)) { element = el; lastText = ""; checkedText = null; dismissedCard(); }
            CurrentApp = FriendlyName(proc);
            if (text != lastText) { lastText = text; lastChange = DateTime.Now; overlay.HideCard(); }
            if (checkedText != text && (DateTime.Now - lastChange).TotalMilliseconds > 450)
            {
                checkedText = text;
                var opts = Store.Shared.Options(GoalsFor(proc));
                opts.Consistency = false;
                var found = await Task.Run(() => RuleEngine.Check(text.Length > 20000 ? text[..20000] : text, opts));
                if (checkedText != lastText) return;
                issues = found.Where(i => !dismissed.Contains(i.Key) && i.Kind is not "Engagement/Repetition" and not "Style/Clarity/LongSentence").ToList();
                Changed?.Invoke();
            }
            if (issues.Count == 0) { overlay.Hide(); badge.Hide(); return; }
            var snapshot = issues.ToList();
            marks = await Task.Run(() => Measure(el, text, snapshot, bounds));
            overlay.Show(bounds, marks);
            badge.Show(bounds, issues.Count, issues.Any(i => i.Group == IssueGroup.Correctness) ? IssueGroup.Correctness : issues[0].Group);
        }
        catch { }
        finally { busy = false; }
    }

    void dismissedCard() => overlay.HideCard();

    static string FriendlyName(string proc) => proc.ToLowerInvariant() switch
    {
        "outlook" or "olk" => "Outlook", "winword" => "Word", "ms-teams" or "teams" => "Teams", "chrome" => "Chrome", "msedge" => "Edge",
        "notepad" => "Notepad", "firefox" => "Firefox", "slack" => "Slack", "excel" => "Excel", "powerpnt" => "PowerPoint", _ => proc,
    };

    static Goals GoalsFor(string proc)
    {
        var g = new Goals { Formality = Store.Shared.Prefs.DefaultGoals.Formality, Domain = Store.Shared.Prefs.DefaultGoals.Domain };
        var p = proc.ToLowerInvariant();
        if (p is "outlook" or "olk" or "thunderbird") { g.Domain = Domain.Email; g.Formality = Formality.Neutral; }
        if (p is "ms-teams" or "teams" or "slack" or "discord" or "whatsapp") { g.Domain = Domain.Casual; g.Formality = Formality.Informal; }
        return g;
    }

    /// Finds the focused, editable text control of the foreground app and reads its text.
    static (AutomationElement el, string text, Rectangle bounds)? ReadFocused(int pid)
    {
        AutomationElement? f;
        try { f = AutomationElement.FocusedElement; } catch { return null; }
        if (f == null) return null;
        try
        {
            var c = f.Current;
            // Outlook (classic and new), Word, Chrome, Edge and Teams can host the editor in a child process.
            if (c.ProcessId != pid && !SameWindowTree(f, pid)) return null;
            if (c.IsPassword) return null;
            var ct = c.ControlType;
            if (ct != ControlType.Edit && ct != ControlType.Document && ct != ControlType.Custom && ct != ControlType.Group && ct != ControlType.Pane) return null;
            var name = (c.Name + " " + c.AutomationId + " " + c.HelpText).ToLowerInvariant();
            if (ct == ControlType.Edit && new[] { "search", "address", "url", "password", "find", "recipient", "to:", "cc:", "bcc" }.Any(name.Contains)) return null;
            if (f.TryGetCurrentPattern(ValuePattern.Pattern, out var vp) && ((ValuePattern)vp).Current.IsReadOnly) return null;
            string? text = null;
            if (f.TryGetCurrentPattern(TextPattern.Pattern, out var tp))
                text = ((TextPattern)tp).DocumentRange.GetText(200_000);
            else if (vp != null)
                text = ((ValuePattern)vp).Current.Value;
            if (string.IsNullOrEmpty(text) || TextUtil.WordCount(text) < 2) return null;
            var r = c.BoundingRectangle;
            if (r.IsEmpty || r.Width < 20 || r.Height < 10) return null;
            var screen = Screen.FromRectangle(new Rectangle((int)r.X, (int)r.Y, (int)r.Width, (int)r.Height)).WorkingArea;
            var bounds = Rectangle.Intersect(new Rectangle((int)r.X, (int)r.Y, (int)r.Width, (int)r.Height), screen);
            return bounds.IsEmpty ? null : (f, text.Replace("\r\n", "\n").Replace('\r', '\n'), bounds);
        }
        catch { return null; }
    }

    static bool SameWindowTree(AutomationElement el, int pid)
    {
        try
        {
            var walker = TreeWalker.ControlViewWalker;
            var node = el;
            for (int i = 0; i < 40 && node != null && node != AutomationElement.RootElement; i++)
            {
                if (node.Current.ProcessId == pid) return true;
                node = walker.GetParent(node);
            }
        }
        catch { }
        return false;
    }

    /// Screen rectangles of each issue, using the text control's own layout.
    static List<(Issue, List<Rectangle>)> Measure(AutomationElement el, string text, List<Issue> list, Rectangle visible)
    {
        var outList = new List<(Issue, List<Rectangle>)>();
        if (!el.TryGetCurrentPattern(TextPattern.Pattern, out var tpObj)) return outList;
        var tp = (TextPattern)tpObj;
        foreach (var i in list.Take(80))
        {
            try
            {
                var range = RangeFor(tp, text, i.Start, i.Length);
                if (range == null) continue;
                var rects = range.GetBoundingRectangles()
                    .Select(r => new Rectangle((int)r.X, (int)r.Y, (int)Math.Ceiling(r.Width), (int)Math.Ceiling(r.Height)))
                    .Where(r => r.Width > 0 && r.Height > 0 && r.Height < 80 && visible.IntersectsWith(r)).ToList();
                if (rects.Count > 0) outList.Add((i, rects));
            }
            catch { }
        }
        return outList;
    }

    /// A TextPatternRange covering [start, start+length) of the normalized text.
    static TextPatternRange? RangeFor(TextPattern tp, string text, int start, int length)
    {
        var range = tp.DocumentRange.Clone();
        // Normalized text uses \n; the control may count \r\n as one or two characters. Count line breaks before start.
        int breaks = text.Take(start).Count(ch => ch == '\n');
        var full = tp.DocumentRange.GetText(-1);
        int crlf = full.Contains("\r\n") ? 1 : 0;
        range.MoveEndpointByRange(TextPatternRangeEndpoint.End, range, TextPatternRangeEndpoint.Start);
        if (range.Move(TextUnit.Character, start + breaks * crlf) <= 0 && start > 0) return null;
        range.MoveEndpointByUnit(TextPatternRangeEndpoint.End, TextUnit.Character, length);
        var got = range.GetText(length + 2).Replace("\r\n", "\n");
        return got.StartsWith(TextUtil.Sub(text, start, length), StringComparison.Ordinal) ? range : null;
    }

    // MARK: Interaction

    void ShowCard(Issue issue, Point at) => overlay.ShowCard(issue, at, rep => _ = Apply(issue, rep), () => Dismiss(issue), () =>
    {
        Store.Shared.AddToDictionary(issue.Original);
        checkedText = null;
    });

    void ShowSummary() => SummaryWindow.ShowFor(CurrentApp, issues, i => Apply(i, i.Replacements.FirstOrDefault() ?? ""), FixAll);

    void Dismiss(Issue i)
    {
        dismissed.Add(i.Key);
        issues.Remove(i);
        checkedText = null;
        Changed?.Invoke();
    }

    async Task FixAll()
    {
        foreach (var i in issues.Where(x => x.Replacements.Count > 0 && x.Length <= 80).OrderByDescending(x => x.Start).ToList())
            if (!await Apply(i, i.Replacements[0])) break;
    }

    /// Replaces the flagged text inside the other app, then verifies the result.
    public async Task<bool> Apply(Issue issue, string replacement)
    {
        if (applying || element == null) return false;
        applying = true;
        overlay.HideCard();
        try
        {
            var el = element;
            var before = lastText;
            if (TextUtil.Sub(before, issue.Start, issue.Length) != issue.Original) { checkedText = null; return false; }
            var expected = before.Remove(issue.Start, issue.Length).Insert(issue.Start, replacement);
            bool selected = await Task.Run(() =>
            {
                try
                {
                    if (!el.TryGetCurrentPattern(TextPattern.Pattern, out var tp)) return false;
                    var range = RangeFor((TextPattern)tp, before, issue.Start, issue.Length);
                    if (range == null) return false;
                    range.Select();
                    return true;
                }
                catch { return false; }
            });
            if (!selected) return false;
            await Task.Delay(60);
            Paste(replacement);
            for (int i = 0; i < 15; i++)
            {
                await Task.Delay(50);
                var now = await Task.Run(() => ReadText(el));
                if (now == expected)
                {
                    Store.Shared.Prefs.FixesAccepted++;
                    Store.Shared.Save();
                    issues.Remove(issue);
                    lastText = now; checkedText = null;
                    Changed?.Invoke();
                    return true;
                }
                if (now != before && now != null) break;
            }
            checkedText = null;
            return false;
        }
        finally { applying = false; }
    }

    static string? ReadText(AutomationElement el)
    {
        try
        {
            if (el.TryGetCurrentPattern(TextPattern.Pattern, out var tp)) return ((TextPattern)tp).DocumentRange.GetText(200_000).Replace("\r\n", "\n").Replace('\r', '\n');
            if (el.TryGetCurrentPattern(ValuePattern.Pattern, out var vp)) return ((ValuePattern)vp).Current.Value.Replace("\r\n", "\n");
        }
        catch { }
        return null;
    }

    /// Pastes text into the focused control and restores the clipboard afterwards.
    static void Paste(string s)
    {
        IDataObject? saved = null;
        try { saved = Clipboard.GetDataObject(); } catch { }
        try
        {
            if (s.Length == 0) SendKeys.SendWait("{DEL}");
            else { Clipboard.SetText(s); SendKeys.SendWait("^v"); }
        }
        catch { }
        Task.Delay(400).ContinueWith(_ =>
        {
            try { if (saved != null) Clipboard.SetDataObject(saved, true); } catch { }
        }, TaskScheduler.FromCurrentSynchronizationContext());
    }
}
