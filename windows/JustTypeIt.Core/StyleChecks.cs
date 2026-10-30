// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace JustTypeIt;

/// Clarity, engagement, delivery and consistency checks (port of StyleChecks.swift).
public static class StyleChecks
{
    static Issue Make(int start, int length, string original, IEnumerable<string> reps, IssueGroup g, string kind, string title, string why) =>
        new() { Start = start, Length = length, Original = original, Replacements = reps.ToList(), Group = g, Kind = kind, Title = title, Explanation = why };

    static string Esc(string s) => Regex.Escape(s);

    public static List<Issue> Run(string text, CheckOptions o)
    {
        var d = RuleData.Shared;
        var outList = new List<Issue>();
        outList.AddRange(PhraseList(text, d.Wordy, IssueGroup.Clarity, "Style/Wordiness/InflatedPhrases", "Wordy phrase",
            (a, b) => b.Length == 0 ? $"“{a}” adds words without meaning. Remove it." : $"“{b}” says the same thing in fewer words."));
        outList.AddRange(PhraseList(text, d.Redundant, IssueGroup.Clarity, "Style/Wordiness/Tautology", "Redundancy",
            (a, b) => $"“{a}” repeats itself. “{b}” is enough."));
        if (o.Passive) outList.AddRange(Passive(text));
        if (o.Hedging) outList.AddRange(Hedging(text));
        if (o.Inclusive) outList.AddRange(Inclusive(text));
        outList.AddRange(Engagement(text, o));
        if (o.Goals.Formality == Formality.Formal || o.Goals.Domain is Domain.Academic or Domain.Business)
            outList.AddRange(PhraseList(text, d.Informal, IssueGroup.Delivery, "Style/Formality/Informal", "Informal language",
                (a, b) => b.Length == 0 ? $"“{a}” is too casual for formal writing." : $"“{a}” is informal. In formal writing use “{b}”."));
        outList.AddRange(DialectSpelling(text, o.Dialect));
        if (o.Consistency) outList.AddRange(Consistency(text));
        foreach (var r in o.StyleRules.Where(r => r.Avoid.Length > 0))
            foreach (var m in TextUtil.Matches($@"\b{Esc(r.Avoid)}\b", text))
                outList.Add(Make(m.Index, m.Length, m.Value, r.Use.Length > 0 ? new[] { r.Use } : Array.Empty<string>(), IssueGroup.Delivery,
                    "StyleGuide/Custom", "Style guide", r.Note.Length > 0 ? r.Note : $"Your style guide recommends “{r.Use}” instead of “{r.Avoid}”."));
        return outList;
    }

    static IEnumerable<Issue> PhraseList(string text, List<(string, string)> list, IssueGroup g, string kind, string title, Func<string, string, string> why)
    {
        foreach (var (p, r) in list)
            foreach (var m in TextUtil.Matches($@"\b{Esc(p)}\b", text))
            {
                int start = m.Index, len = m.Length;
                if (r.Length == 0)
                {
                    if (TextUtil.Sub(text, start + len, 2) == ", ") len += 2;
                    else if (TextUtil.Sub(text, start + len, 1) == " ") len += 1;
                }
                yield return Make(start, len, text.Substring(start, len), new[] { r.Length == 0 ? "" : TextUtil.MatchCase(r, m.Value) }, g, kind, title, why(m.Value, r));
            }
    }

    static readonly string[] Participles = { "done", "made", "given", "taken", "written", "seen", "known", "shown", "found", "built", "sent", "told", "held", "brought", "bought", "caught", "taught", "thought", "chosen", "driven", "eaten", "forgotten", "hidden", "broken", "spoken", "stolen", "frozen", "beaten", "drawn", "grown", "thrown", "worn", "torn", "sold", "paid", "left", "lost", "kept", "led", "met", "put", "set", "won", "begun" };
    static readonly HashSet<string> Adjectives = new() { "interested", "excited", "tired", "bored", "married", "worried", "pleased", "surprised", "scared", "located", "supposed", "used", "concerned", "involved", "based", "related", "qualified", "satisfied", "prepared", "dedicated", "committed", "experienced", "allowed", "open", "often", "seen", "even", "ten", "garden", "happen", "listen", "chicken", "golden", "sudden", "hidden", "children", "eleven", "seven", "heaven", "women", "men", "given" };

    public static IEnumerable<Issue> Passive(string text)
    {
        var pattern = @"\b(am|is|are|was|were|be|been|being|get|gets|got)\s+(?:(?:not|also|already|often|always|never|being|just|then)\s+)?([a-z]+ed|[a-z]+en|" + string.Join("|", Participles) + @")\b(\s+by\s+((?:the|a|an|my|our|your|his|her|their)\s+)?([a-z]+))?";
        foreach (var m in TextUtil.Matches(pattern, text))
        {
            var part = m.Groups[2].Value.ToLowerInvariant();
            if (Adjectives.Contains(part) && !m.Groups[3].Success) continue;
            var reps = new List<string>();
            if (m.Groups[5].Success)
            {
                var agent = m.Groups[4].Value + m.Groups[5].Value;
                var aux = m.Groups[1].Value.ToLowerInvariant();
                var past = RuleData.Shared.Irregular.FirstOrDefault(e => e.Participle == part).Past ?? part;
                var verb = aux is "was" or "were" or "got" ? past : (past.EndsWith("ed") ? past[..^2] + "s" : past);
                reps.Add($"{agent} {verb}");
            }
            yield return Make(m.Index, m.Length, m.Value, reps, IssueGroup.Clarity, "Style/PassiveVoice", "Passive voice",
                "This sentence appears to be in the passive voice. Active voice is usually clearer and more direct: put the person or thing doing the action first.");
        }
    }

    static IEnumerable<Issue> Hedging(string text)
    {
        var taken = new List<(int, int)>();
        foreach (var h in RuleData.Shared.Hedges.OrderByDescending(h => h.Length))
            foreach (var m in TextUtil.Matches($@"\b{Esc(h)}\b,?\s?", text))
            {
                if (taken.Any(t => m.Index < t.Item2 && t.Item1 < m.Index + m.Length)) continue;
                taken.Add((m.Index, m.Index + m.Length));
                yield return Make(m.Index, m.Length, m.Value, new[] { "" }, IssueGroup.Delivery, "Style/Confidence/Hedging", "Hedging language",
                    $"“{h}” can make you sound unsure. Removing it makes your point more confident.");
            }
    }

    static IEnumerable<Issue> Inclusive(string text)
    {
        foreach (var (term, alts, why) in RuleData.Shared.Inclusive)
            foreach (var m in TextUtil.Matches($@"\b{Esc(term)}\b", text))
                yield return Make(m.Index, m.Length, m.Value, alts.Select(a => TextUtil.MatchCase(a, m.Value)), IssueGroup.Delivery, "Style/Sensitivity/Inclusive", "Inclusive language", why);
    }

    static IEnumerable<Issue> Engagement(string text, CheckOptions o)
    {
        var taken = new List<(int, int)>();
        var casual = new HashSet<string> { "good", "bad", "get", "got", "big", "thing", "things", "nice" };
        foreach (var (w, alts) in RuleData.Shared.WeakWords.OrderByDescending(k => k.Key.Length))
            foreach (var m in TextUtil.Matches($@"\b{Esc(w)}\b", text))
            {
                if (taken.Any(t => m.Index < t.Item2 && t.Item1 < m.Index + m.Length)) continue;
                taken.Add((m.Index, m.Index + m.Length));
                if (!w.Contains(' ') && casual.Contains(w) && o.Goals.Formality == Formality.Informal) continue;
                int len = m.Length;
                bool filler = alts.Contains("");
                if (filler && TextUtil.Sub(text, m.Index + len, 1) == " ") len++;
                bool intensifier = w.StartsWith("very ") || w.StartsWith("really ");
                yield return Make(m.Index, len, text.Substring(m.Index, len), alts.Select(a => TextUtil.MatchCase(a, m.Value)), IssueGroup.Engagement,
                    intensifier ? "Engagement/Intensifier" : "Engagement/WeakWord", intensifier ? "Intensifier" : filler ? "Filler word" : "Vague word",
                    filler ? $"“{w}” rarely adds meaning. Consider removing it." : $"“{w}” is overused and vague. A more precise word makes your writing more engaging.");
            }
        foreach (var p in TextUtil.Paragraphs(text))
        {
            var counts = new Dictionary<string, List<Span>>(StringComparer.OrdinalIgnoreCase);
            foreach (var w in TextUtil.Words(p.Text))
            {
                if (w.Text.Length < 4 || TextUtil.Stopwords.Contains(w.Text) || o.Dictionary.Contains(w.Text) || !w.Text.All(char.IsLetter)) continue;
                if (!counts.TryGetValue(w.Text, out var l)) counts[w.Text] = l = new();
                l.Add(new Span(p.Start + w.Start, w.Length, w.Text));
            }
            foreach (var (word, spans) in counts.Where(c => c.Value.Count >= 3))
            {
                var syn = RuleData.Shared.Synonyms.GetValueOrDefault(word.ToLowerInvariant()) ?? Array.Empty<string>();
                foreach (var s in spans.Skip(2))
                    yield return Make(s.Start, s.Length, s.Text, syn.Select(x => TextUtil.MatchCase(x, s.Text)), IssueGroup.Engagement,
                        "Engagement/Repetition", "Repetitive word", $"“{word.ToLowerInvariant()}” appears {spans.Count} times in this paragraph. Varying your words keeps readers interested.");
            }
        }
    }

    static IEnumerable<Issue> DialectSpelling(string text, Dialect d)
    {
        bool british = d != Dialect.American;
        var canadianIze = new HashSet<string> { "organise", "organised", "organisation", "realise", "realised", "recognise", "recognised", "apologise", "analyse", "analysed", "criticise", "prioritise", "optimise", "customise", "emphasise", "summarise" };
        foreach (var (us, uk) in RuleData.Shared.UsToUK)
        {
            var (from, to) = british ? (us, uk) : (uk, us);
            if (d == Dialect.Canadian && canadianIze.Contains(to)) continue;
            foreach (var m in TextUtil.Matches($@"\b{from}\b", text))
                yield return Make(m.Index, m.Length, m.Value, new[] { TextUtil.MatchCase(to, m.Value) }, IssueGroup.Correctness, "Spelling/Regional", $"{d} English spelling",
                    $"In {d} English, this is spelled “{to}”. You can change your English dialect in Settings.");
        }
    }

    static IEnumerable<Issue> Consistency(string text)
    {
        var forms = new Dictionary<string, Dictionary<string, List<int>>>();
        foreach (var w in TextUtil.Words(text).Where(w => w.Length >= 3))
        {
            var key = w.Text.ToLowerInvariant().Replace("-", "");
            if (!forms.TryGetValue(key, out var v)) forms[key] = v = new();
            if (!v.TryGetValue(w.Text, out var l)) v[w.Text] = l = new();
            l.Add(w.Start);
        }
        static string Norm(string s) => char.ToLowerInvariant(s[0]) + s[1..];
        foreach (var variants in forms.Values.Where(v => v.Count >= 2))
        {
            if (variants.Keys.Select(Norm).Distinct().Count() < 2) continue;
            var preferred = variants.OrderByDescending(v => v.Value.Count).First().Key;
            foreach (var (form, starts) in variants)
            {
                if (Norm(form) == Norm(preferred)) continue;
                foreach (var s in starts)
                    yield return Make(s, form.Length, form, new[] { TextUtil.MatchCase(preferred, form) }, IssueGroup.Correctness, "Consistency/Spelling", "Inconsistent spelling",
                        $"You also wrote “{preferred}” in this document. Pick one form and use it throughout.");
            }
        }
    }
}
