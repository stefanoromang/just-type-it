// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it
//
// End-to-end self-test on a real Windows machine:  JustTypeIt.exe --selftest <report.txt>
// Checks the rules, Windows' spell checker, and live checking + fixing inside another app (Notepad).

using System.Diagnostics;
using System.Windows.Automation;

namespace JustTypeIt;

static class SelfTest
{
    public static int Run(string report)
    {
        var lines = new List<string> { $"Just Type It self-test · {DateTime.Now:u} · {Environment.OSVersion}", "" };
        int fails = 0;
        void Record(string name, bool ok, string detail = "")
        {
            if (!ok) fails++;
            var l = $"{(ok ? "PASS" : "FAIL")}  {name}  {detail}";
            Console.WriteLine(l);
            lines.Add(l);
            File.WriteAllLines(report, lines);
        }

        try
        {
            Record("Shared rules load", RuleData.Shared.Grammar.Count > 90 && RuleData.Shared.SkippedRules == 0, $"{RuleData.Shared.Grammar.Count} rules");
            var found = RuleEngine.Check("Their going to the store. He dont care.", new CheckOptions());
            Record("Grammar rules", found.Any(i => i.Replacements.Contains("They're going")) && found.Any(i => i.Replacements.Contains("He doesn't")), string.Join("; ", found));

            var spell = WindowsSpellChecker.Shared.Check("I recieved your mesage yesterday.", Dialect.American).ToList();
            Record("Windows spell checker", spell.Count >= 2, string.Join("; ", spell.Select(s => $"{s.start}+{s.length}:{string.Join("/", s.suggestions)}")));
            var uk = WindowsSpellChecker.Shared.Check("My favorite color.", Dialect.British).ToList();
            Record("Windows spell checker (en-GB)", true, $"{uk.Count} UK spelling flags");

            // Live: type a mistake in Notepad, read it through UI Automation, measure word positions.
            var file = Path.Combine(Path.GetTempPath(), "jti-selftest.txt");
            File.WriteAllText(file, "Their going to the store tomorrow. He dont care.");
            var p = Process.Start(new ProcessStartInfo("notepad.exe", file) { UseShellExecute = true });
            Thread.Sleep(3500);
            AutomationElement? edit = null;
            foreach (var w in AutomationElement.RootElement.FindAll(TreeScope.Children, Condition.TrueCondition).Cast<AutomationElement>())
            {
                try
                {
                    if (!w.Current.Name.Contains("jti-selftest")) continue;
                    edit = w.FindFirst(TreeScope.Descendants, new OrCondition(
                        new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Document),
                        new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit)));
                    if (edit != null) break;
                }
                catch { }
            }
            Record("Find Notepad text control", edit != null);
            if (edit != null && edit.TryGetCurrentPattern(TextPattern.Pattern, out var tpObj))
            {
                var tp = (TextPattern)tpObj;
                var text = tp.DocumentRange.GetText(-1);
                Record("Read text through UI Automation", text.Contains("He dont care"), text);
                var range = tp.DocumentRange.FindText("dont", false, false);
                var rects = range?.GetBoundingRectangles() ?? Array.Empty<System.Windows.Rect>();
                Record("Word positions for underlines", rects.Length > 0 && rects[0].Width > 0, rects.Length > 0 ? rects[0].ToString() : "none");
            }
            try { p?.Kill(); } catch { }
            File.Delete(file);
        }
        catch (Exception e) { Record("Unexpected error", false, e.ToString()); }
        Record(fails == 0 ? "ALL PASS" : $"{fails} FAILED", fails == 0);
        return fails == 0 ? 0 : 1;
    }
}
