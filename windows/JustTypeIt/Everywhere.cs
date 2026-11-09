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
    int elementPid;
    string measuredFor = "";
    Rectangle measuredBounds;
    DateTime measuredAt;
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
        overlay.Hide(); badge.Hide(); SummaryWindow.CloseOpen();
        marks.Clear(); measuredFor = "";
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
            if (element == null || !Automation.Compare(el, element))
            {
                element = el; elementPid = (int)pid; lastText = ""; checkedText = null; autocorrected.Clear(); dismissedCard();
                issues = new(); marks = new(); measuredFor = ""; overlay.Hide(); SummaryWindow.CloseOpen();
            }
            CurrentApp = FriendlyName(proc);
            if (text != lastText)
            {
                bool grew = text.Length > lastText.Length;
                lastText = text; lastChange = DateTime.Now; overlay.HideCard();
                if (grew && Store.Shared.Prefs.Autocorrect) ScheduleAutocorrect(el, text);
            }
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
            var tone = Store.Shared.Prefs.ShowTone ? Proactive.ToneEmoji(text) : null;
            if (issues.Count == 0)
            {
                overlay.Hide();
                if (checkedText == text) badge.Show(bounds, 0, IssueGroup.Correctness, tone); else badge.Hide();
                return;
            }
            var signature = text + "|" + issues.Count;
            if (signature != measuredFor || bounds != measuredBounds || (DateTime.Now - measuredAt).TotalMilliseconds > 1500)
            {
                var snapshot = issues.ToList();
                marks = await Task.Run(() => Measure(el, text, snapshot, bounds));
                measuredFor = signature; measuredBounds = bounds; measuredAt = DateTime.Now;
            }
            overlay.Show(bounds, marks);
            badge.Show(bounds, issues.Count, issues.Any(i => i.Group == IssueGroup.Correctness) ? IssueGroup.Correctness : issues[0].Group, tone);
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
        bool crlf;
        try { crlf = tp.DocumentRange.GetText(-1).Contains("\r\n"); } catch { return outList; }
        foreach (var i in list.Take(80))
        {
            try
            {
                var range = RangeFor(tp, text, i.Start, i.Length, crlf);
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
    static TextPatternRange? RangeFor(TextPattern tp, string text, int start, int length, bool? crlfKnown = null)
    {
        var range = tp.DocumentRange.Clone();
        // Normalized text uses \n; the control may count \r\n as one or two characters. Count line breaks before start.
        int breaks = 0;
        for (int k = 0; k < start && k < text.Length; k++) if (text[k] == '\n') breaks++;
        int crlf = (crlfKnown ?? tp.DocumentRange.GetText(-1).Contains("\r\n")) ? 1 : 0;
        range.MoveEndpointByRange(TextPatternRangeEndpoint.End, range, TextPatternRangeEndpoint.Start);
        if (range.Move(TextUnit.Character, start + breaks * crlf) <= 0 && start > 0) return null;
        range.MoveEndpointByUnit(TextPatternRangeEndpoint.End, TextUnit.Character, length);
        var want = TextUtil.Sub(text, start, length);
        var got = range.GetText(length + 2).Replace("\r\n", "\n");
        if (got.StartsWith(want, StringComparison.Ordinal)) return range;
        // Emoji and other combined characters count as one "character" in some apps (Chrome, Edge, Teams):
        // find the word near the expected spot instead.
        if (want.Length >= 2)
        {
            var near = tp.DocumentRange.Clone();
            near.MoveEndpointByRange(TextPatternRangeEndpoint.End, near, TextPatternRangeEndpoint.Start);
            near.Move(TextUnit.Character, Math.Max(0, start + breaks * crlf - 40));
            near.MoveEndpointByUnit(TextPatternRangeEndpoint.End, TextUnit.Character, length + 80);
            var found = near.FindText(want, false, false);
            if (found != null) return found;
        }
        return null;
    }

    // MARK: Interaction

    void ShowCard(Issue issue, Point at) => overlay.ShowCard(issue, at, rep => _ = Apply(issue, rep), () => Dismiss(issue), () =>
    {
        Store.Shared.AddToDictionary(issue.Original);
        checkedText = null;
    });

    void ShowSummary() => SummaryWindow.ShowFor(CurrentApp, issues,
        Store.Shared.Prefs.PreSendCheck ? Proactive.PreSendWarnings(lastText, issues).Where(w => !w.Title.Contains("correctness")).ToList() : new(),
        i => Apply(i, i.Replacements.FirstOrDefault() ?? ""), FixAll);

    CancellationTokenSource? autocorrectCts;
    readonly HashSet<int> autocorrected = new();

    /// After a short pause in typing, fixes obvious typos in the words just finished (Ctrl+Z undoes it).
    void ScheduleAutocorrect(AutomationElement el, string text)
    {
        autocorrectCts?.Cancel();
        var cts = autocorrectCts = new CancellationTokenSource();
        _ = Task.Delay(450, cts.Token).ContinueWith(async t =>
        {
            if (t.IsCanceled || lastText != text || applying) return;
            int caret = await Task.Run(() => Caret(el, text));
            if (caret < 0) return;
            var dict = new HashSet<string>(Store.Shared.Prefs.Dictionary.Select(w => w.ToLowerInvariant()));
            var fixes = new List<Proactive.Correction>();
            for (int i = caret; i > Math.Max(0, caret - 60); i--)
            {
                var f = Proactive.Autocorrect(text, i, dict);
                if (f != null && !autocorrected.Contains(f.Start) && !fixes.Any(x => x.Start == f.Start)) fixes.Add(f);
            }
            foreach (var f in fixes.OrderByDescending(f => f.Start))
            {
                autocorrected.Add(f.Start);
                var issue = new Issue { Start = f.Start, Length = f.Length, Original = f.Original, Replacements = new() { f.Replacement }, Kind = "Autocorrect" };
                if (!await Apply(issue, f.Replacement, restoreCaret: true, caretBefore: caret)) break;
                caret += f.Replacement.Length - f.Length;
            }
        }, TaskScheduler.FromCurrentSynchronizationContext());
    }

    static int Caret(AutomationElement el, string text)
    {
        try
        {
            if (!el.TryGetCurrentPattern(TextPattern.Pattern, out var tp)) return -1;
            var sel = ((TextPattern)tp).GetSelection();
            if (sel.Length == 0) return -1;
            var before = ((TextPattern)tp).DocumentRange.Clone();
            before.MoveEndpointByRange(TextPatternRangeEndpoint.End, sel[0], TextPatternRangeEndpoint.Start);
            return before.GetText(-1).Replace("\r\n", "\n").Replace('\r', '\n').Length;
        }
        catch { return -1; }
    }

    void Dismiss(Issue i)
    {
        dismissed.Add(i.Key);
        issues.Remove(i);
        checkedText = null;
        Changed?.Invoke();
    }

    async Task FixAll()
    {
        int lastStart = int.MaxValue;
        foreach (var i in issues.Where(x => x.Replacements.Count > 0 && x.Length <= 80).OrderByDescending(x => x.Start).ToList())
        {
            if (i.End > lastStart) continue;   // overlapping suggestion: skip
            if (!await Apply(i, i.Replacements[0])) break;
            lastStart = i.Start;
        }
    }

    /// Replaces the flagged text inside the other app, then verifies the result.
    public async Task<bool> Apply(Issue issue, string replacement, bool restoreCaret = false, int caretBefore = -1)
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
            // Abort if the user kept typing or switched apps: never paste into the wrong place.
            var still = await Task.Run(() => ReadText(el));
            if (still != before || InputHelper.ForegroundProcessId() != (uint)elementPid) { checkedText = null; return false; }
            string? now = null;
            await InputHelper.Paste(replacement, async () =>
            {
                now = await Task.Run(() => ReadText(el));
                return now == expected || (now != null && now != before);
            });
            if (now == expected)
            {
                if (restoreCaret && caretBefore >= 0)
                {
                    // Put the cursor back where the user was typing (shifted by the fix if it was before it).
                    int caret = caretBefore + (issue.End <= caretBefore ? replacement.Length - issue.Length : 0);
                    await Task.Run(() =>
                    {
                        try { if (el.TryGetCurrentPattern(TextPattern.Pattern, out var tp2)) RangeFor((TextPattern)tp2, now, Math.Min(caret, now.Length), 0)?.Select(); }
                        catch { }
                    });
                }
                Store.Shared.Prefs.FixesAccepted++;
                Store.Shared.Save();
                issues.Remove(issue);
                lastText = now; checkedText = null; measuredFor = "";
                Changed?.Invoke();
                return true;
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

}
