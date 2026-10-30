// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace JustTypeIt;

/// Fast, fully offline checker: shared grammar rules, mechanics, sentence structure and style.
/// A port of RuleEngine.swift; the rule data itself comes from the same rules.json.
public static class RuleEngine
{
    public static List<Issue> Check(string text, CheckOptions o)
    {
        if (string.IsNullOrWhiteSpace(text)) return new();
        var issues = new List<Issue>();
        if (o.Spelling != null) issues.AddRange(Spelling(text, o));
        issues.AddRange(CommonMisspellings(text, o));
        issues.AddRange(PatternRules(text, o));
        issues.AddRange(Mechanics(text));
        issues.AddRange(Structure(text));
        issues.AddRange(StyleChecks.Run(text, o));
        return Dedupe(issues, text);
    }

    static Issue Make(int start, int length, string original, IEnumerable<string> reps, IssueGroup g, string kind, string title, string why,
        IssueSource src = IssueSource.Rules) =>
        new() { Start = start, Length = length, Original = original, Replacements = reps.ToList(), Group = g, Kind = kind, Title = title, Explanation = why, Source = src };

    // MARK: Spelling (Windows spell checker)

    static IEnumerable<Issue> Spelling(string text, CheckOptions o)
    {
        foreach (var (start, length, suggestions) in o.Spelling!.Check(text, o.Dialect))
        {
            var word = TextUtil.Sub(text, start, length);
            if (word.Length == 0 || o.Dictionary.Contains(word)) continue;
            if (word.Any(char.IsDigit) || word.Contains('@') || word.StartsWith("http")) continue;
            if (word.Skip(1).Any(char.IsUpper)) continue; // iPhone, GitHub, camelCase
            int end = start + length;
            if ((end + 1 < text.Length && text[end] == '.' && char.IsLetter(text[end + 1])) || (start > 0 && text[start - 1] == '.')) continue; // Node.js
            bool apostrophe = suggestions.Count > 0 && suggestions[0].Replace("'", "").Equals(word, StringComparison.OrdinalIgnoreCase);
            yield return Make(start, length, word, suggestions.Take(4), IssueGroup.Correctness,
                apostrophe ? "Punctuation/Apostrophe" : "Spelling/Misspelled", apostrophe ? "Missing apostrophe" : "Spelling",
                apostrophe ? "Contractions need an apostrophe where letters are left out."
                           : $"“{word}” isn't in the {o.Dialect} English dictionary. If it's a name or term you use, add it to your dictionary.",
                IssueSource.Spelling);
        }
    }

    /// Frequent misspellings, caught even before Windows' spell checker is consulted.
    static readonly Dictionary<string, string> Misspellings = new(StringComparer.OrdinalIgnoreCase)
    {
        ["recieve"] = "receive", ["recieved"] = "received", ["recieving"] = "receiving", ["definately"] = "definitely",
        ["goverment"] = "government", ["seperate"] = "separate", ["seperately"] = "separately", ["occured"] = "occurred",
        ["untill"] = "until", ["wich"] = "which", ["tommorow"] = "tomorrow", ["tomorow"] = "tomorrow", ["accomodate"] = "accommodate",
        ["acheive"] = "achieve", ["adress"] = "address", ["arguement"] = "argument", ["begining"] = "beginning", ["beleive"] = "believe",
        ["calender"] = "calendar", ["collegue"] = "colleague", ["comming"] = "coming", ["commited"] = "committed", ["concious"] = "conscious",
        ["enviroment"] = "environment", ["existance"] = "existence", ["foward"] = "forward", ["freind"] = "friend", ["grammer"] = "grammar",
        ["immediatly"] = "immediately", ["independant"] = "independent", ["knowlege"] = "knowledge", ["libary"] = "library",
        ["maintainance"] = "maintenance", ["neccessary"] = "necessary", ["necesary"] = "necessary", ["noticable"] = "noticeable",
        ["occassion"] = "occasion", ["persistant"] = "persistent", ["posession"] = "possession", ["prefered"] = "preferred",
        ["publically"] = "publicly", ["realy"] = "really", ["recomend"] = "recommend", ["refered"] = "referred", ["relevent"] = "relevant",
        ["responsability"] = "responsibility", ["sincerly"] = "sincerely", ["succesful"] = "successful", ["suprise"] = "surprise",
        ["thier"] = "their", ["truely"] = "truly", ["wierd"] = "weird", ["writting"] = "writing", ["buisness"] = "business",
        ["managment"] = "management", ["schedual"] = "schedule", ["teh"] = "the", ["alot"] = "a lot", ["thru"] = "through",
    };

    static IEnumerable<Issue> CommonMisspellings(string text, CheckOptions o)
    {
        foreach (var w in TextUtil.Words(text))
            if (!o.Dictionary.Contains(w.Text) && Misspellings.TryGetValue(w.Text, out var fix))
                yield return Make(w.Start, w.Length, w.Text, new[] { TextUtil.MatchCase(fix, w.Text) }, IssueGroup.Correctness,
                    "Spelling/Misspelled", "Spelling", $"“{w.Text}” is a common misspelling of “{fix}”.");
    }

    // MARK: Shared pattern rules

    public static IEnumerable<Issue> PatternRules(string text, CheckOptions o)
    {
        foreach (var rule in RuleData.Shared.Grammar)
        {
            MatchCollection ms;
            try { ms = rule.Regex.Matches(text); _ = ms.Count; }
            catch (RegexMatchTimeoutException) { continue; }
            foreach (Match m in ms)
            {
                var orig = m.Value;
                if (orig.Length == 0 || o.Dictionary.Contains(orig)) continue;
                List<string> reps;
                if (rule.Replacement.Length > 0)
                {
                    var rep = Morph.Resolve(m.Result(rule.Replacement));
                    rep = TextUtil.MatchCase(rep, orig);
                    if (rep == orig) continue;
                    reps = new() { rep };
                }
                else reps = FallbackFix(rule.Kind, orig);
                if (rule.Kind == "Grammar/SubjectVerbAgreement" && orig.StartsWith("i was", StringComparison.OrdinalIgnoreCase)) continue;
                reps = reps.Select(FixThirdPerson).ToList();
                yield return Make(m.Index, m.Length, orig, reps, rule.Group, rule.Kind, rule.Title, rule.Explanation);
            }
        }
    }

    static readonly Dictionary<string, string> PastTense = new() { ["go"] = "went", ["eat"] = "ate", ["see"] = "saw", ["come"] = "came", ["run"] = "ran", ["buy"] = "bought", ["write"] = "wrote", ["take"] = "took", ["give"] = "gave", ["make"] = "made", ["do"] = "did" };
    static readonly Dictionary<string, string> BaseForm = new() { ["went"] = "go", ["gone"] = "go", ["ate"] = "eat", ["wrote"] = "write", ["took"] = "take", ["gave"] = "give", ["saw"] = "see", ["did"] = "do", ["was"] = "be", ["has"] = "have" };
    static readonly Dictionary<string, string> Contractions = new(StringComparer.OrdinalIgnoreCase)
    {
        ["dont"] = "don't", ["cant"] = "can't", ["wont"] = "won't", ["didnt"] = "didn't", ["doesnt"] = "doesn't", ["isnt"] = "isn't",
        ["wasnt"] = "wasn't", ["arent"] = "aren't", ["werent"] = "weren't", ["shouldnt"] = "shouldn't", ["couldnt"] = "couldn't",
        ["wouldnt"] = "wouldn't", ["havent"] = "haven't", ["hasnt"] = "hasn't", ["im"] = "I'm", ["ive"] = "I've", ["youre"] = "you're",
        ["theyre"] = "they're", ["thats"] = "that's", ["whats"] = "what's", ["lets go"] = "let's go",
    };

    static string FixThirdPerson(string s)
    {
        foreach (var (k, v) in new[] { ("gos", "goes"), ("dos", "does"), ("trys", "tries"), ("haves", "has") })
            s = Regex.Replace(s, $@"\b{k}\b", v);
        return s;
    }

    static string Cap(string s, string like) => like.Length > 0 && char.IsUpper(like[0]) ? char.ToUpperInvariant(s[0]) + s[1..] : char.ToLowerInvariant(s[0]) + s[1..];

    public static List<string> FallbackFix(string kind, string orig)
    {
        var parts = orig.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        switch (kind)
        {
            case "Punctuation/Apostrophe":
                if (Contractions.TryGetValue(orig, out var c)) return new() { c is "I'm" or "I've" ? c : TextUtil.MatchCase(c, orig) };
                break;
            case "Grammar/VerbTense" when Regex.IsMatch(orig, @"^(am|is|are) \w+ing\b", RegexOptions.IgnoreCase):
                var aux = parts[0].ToLowerInvariant();
                return new() { (aux == "is" ? "has been" : "have been") + orig[aux.Length..] };
            case "Grammar/VerbTense":
                var s = orig;
                foreach (var (b, p) in PastTense) s = Regex.Replace(s, $@"\b(he|she|it|i|we|they|you) {b}\b", $"$1 {p}", RegexOptions.IgnoreCase);
                return s == orig ? new() : new() { s };
            case "Grammar/SubjectVerbAgreement":
            case "Grammar/CollectiveNoun":
                if (parts.Length == 0) return new();
                var lw = parts[^1].ToLowerInvariant();
                var first = parts[0].ToLowerInvariant();
                if ((first == "me" || first == "my") && parts.Length >= 4)
                {
                    var person = first == "me" ? parts[3] : parts[1];
                    var verbs = new Dictionary<string, string> { ["likes"] = "like", ["loves"] = "love", ["wants"] = "want", ["needs"] = "need", ["has"] = "have", ["is"] = "are", ["was"] = "were", ["goes"] = "go", ["does"] = "do" };
                    return new() { Cap($"My {person} and I {verbs.GetValueOrDefault(lw, lw)}", orig) };
                }
                var sing = new Dictionary<string, string> { ["are"] = "is", ["were"] = "was", ["have"] = "has", ["do"] = "does" };
                return sing.TryGetValue(lw, out var r) ? new() { string.Join(' ', parts[..^1]) + " " + r } : new();
            case "Grammar/UncountableNoun":
                if (parts.Length > 1 && (parts[0].Equals("a", StringComparison.OrdinalIgnoreCase) || parts[0].Equals("an", StringComparison.OrdinalIgnoreCase)))
                {
                    var rest = string.Join(' ', parts[1..]);
                    return new[] { rest, "some " + rest, "a piece of " + rest }.Select(x => TextUtil.MatchCase(x, orig)).ToList();
                }
                return new();
            case "Grammar/AdverbAdjective":
                return new() { Regex.Replace(orig, @"\bgood$", "well") };
            case "Grammar/PronounCase":
                if (parts.Length != 4) return new();
                var subj = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) { ["me"] = "I", ["him"] = "he", ["her"] = "she", ["them"] = "they" };
                var a = subj.GetValueOrDefault(parts[0], parts[0]);
                var bb = subj.GetValueOrDefault(parts[2], parts[2]);
                var other = a == "I" ? bb : a;
                var verb = parts[3].Equals("was", StringComparison.OrdinalIgnoreCase) ? "were" : parts[3];
                return new() { Cap(char.ToUpperInvariant(other[0]) + other[1..] + " and I " + verb, orig) };
            case "Grammar/VerbForm":
                if (parts.Length == 2 && BaseForm.TryGetValue(parts[1].ToLowerInvariant(), out var bf)) return new() { $"{parts[0]} {bf}" };
                break;
        }
        return new();
    }

    // MARK: Mechanics

    public static List<Issue> Mechanics(string text)
    {
        var outList = new List<Issue>();
        void Add(string p, Func<string, string> rep, string kind, string title, string why, bool ci = true, IssueGroup g = IssueGroup.Correctness)
        {
            foreach (var m in TextUtil.Matches(p, text, ci))
                if (m.Length > 0) outList.Add(Make(m.Index, m.Length, m.Value, new[] { rep(m.Value) }, g, kind, title, why));
        }
        Add(@"\b(\w+) \1\b", s => s.Split(' ')[0], "Grammar/RepeatedWord", "Repeated word", "The same word appears twice in a row.");
        Add(@"(?<=\S)  +(?=\S)", _ => " ", "Punctuation/Spacing", "Extra space", "Use a single space between words.");
        Add(@"[ \t]+([,.;:!?])(?!\d)", s => s.Trim(), "Punctuation/Spacing", "Space before punctuation", "Punctuation attaches to the word before it.");
        Add(@"(?<=[a-z])([,;:])(?=[A-Za-z])", s => s + " ", "Punctuation/Spacing", "Missing space", "Add a space after a comma, semicolon or colon.", false);
        Add(@"(?<=[a-z]{2})([.!?])(?=[A-Z][a-z])", s => s + " ", "Punctuation/Spacing", "Missing space", "Add a space after the end of a sentence.", false);
        Add(",,+", _ => ",", "Punctuation/Comma", "Double comma", "Use a single comma.");
        Add(@"(?<![.])\.\.(?![.])", _ => ".", "Punctuation/Period", "Double period", "Use one period, or three for an ellipsis.");
        Add(@"!{2,}|\?{2,}", s => s[..1], "Punctuation/Exclamation", "Repeated punctuation", "One mark is enough in most writing.", g: IssueGroup.Delivery);
        Add(@"\b(however|therefore|moreover|furthermore|nevertheless|consequently) (?=[a-z])", s => s.Trim() + ", ", "Punctuation/Comma", "Missing comma", "Introductory transition words are usually followed by a comma.");
        Add(@"\b(self|ex|all) (aware|employed|confident|esteem|wife|husband|boyfriend|girlfriend|inclusive|important)\b", s => s.Replace(' ', '-'), "Spelling/Misspelled/MissingHyphenInPrefixes", "Missing hyphen", "This prefix is joined with a hyphen.");
        Add(@"\b(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety) (one|two|three|four|five|six|seven|eight|nine)\b", s => s.Replace(' ', '-'), "Spelling/Misspelled/MissingHyphenInNumbers", "Missing hyphen", "Compound numbers from 21 to 99 are hyphenated.");

        var common = "is|are|was|were|the|and|or|but|our|your|their|my|it|this|that|we|you|to|of|for|with|in|on|at|a|an|be|have|has|will|can|please|thank|thanks";
        var capped = string.Join("|", common.Split('|').Select(w => char.ToUpperInvariant(w[0]) + w[1..]));
        foreach (var m in TextUtil.Matches($@"(?<=[a-z,] )({capped})\b", text, false))
            outList.Add(Make(m.Index, m.Length, m.Value, new[] { m.Value.ToLowerInvariant() }, IssueGroup.Correctness, "Grammar/Capitalization", "Capitalization", "Only capitalize the first word of a sentence and proper nouns."));

        var shouty = new HashSet<string> { "DATA", "PLEASE", "THANKS", "IMPORTANT", "URGENT", "VERY", "REALLY", "NOW", "TODAY", "EVERYONE", "ALL", "NEVER", "ALWAYS", "MUST", "NOTE", "FREE", "SOON" };
        foreach (var m in TextUtil.Matches(@"\b[A-Z]{3,}\b", text, false))
        {
            if (!shouty.Contains(m.Value)) continue;
            int ls = text.LastIndexOf('\n', Math.Max(0, m.Index - 1)) + 1;
            int le = text.IndexOf('\n', m.Index); if (le < 0) le = text.Length;
            var line = text[ls..le];
            if (line == line.ToUpperInvariant()) continue;
            outList.Add(Make(m.Index, m.Length, m.Value, new[] { m.Value.ToLowerInvariant() }, IssueGroup.Delivery, "Style/Formatting/AllCaps", "All capitals", "Words in all capitals read like shouting. Use bold or rephrase for emphasis."));
        }
        foreach (var m in TextUtil.Matches(@"(?m)^(Hi|Hello|Hey|Dear|Good morning|Good afternoon|Good evening)( [A-Z][\w.]*(?: [A-Z][\w.]*){0,3})?(?=[ \t]*\r?$)", text, false))
            outList.Add(Make(m.Index, m.Length, m.Value, new[] { m.Value + "," }, IssueGroup.Correctness, "Punctuation/GreetingComma", "Missing comma", "Put a comma after a greeting: “Hi Team,”."));

        foreach (var s in TextUtil.Sentences(text))
        {
            int li = s.Text.TakeWhile(ch => !char.IsLetter(ch)).Count();
            if (li < s.Text.Length && char.IsLower(s.Text[li]) && !s.Text[..li].Contains('"') && !s.Text.StartsWith("http"))
                outList.Add(Make(s.Start + li, 1, s.Text[li].ToString(), new[] { char.ToUpperInvariant(s.Text[li]).ToString() }, IssueGroup.Correctness, "Style/Formatting/LowerCaseSentenceStart", "Capitalization", "Start every sentence with a capital letter."));
            char last = s.Text[^1];
            bool atLineEnd = s.End >= text.Length || text[s.End] is '\n' or '\r';
            if (char.IsLetterOrDigit(last) && s.Text.Split(' ').Length >= 4 && atLineEnd)
            {
                var w = TextUtil.Words(s.Text).LastOrDefault();
                if (w.Text == null) continue;
                var q = new[] { "who", "what", "when", "where", "why", "how", "do", "does", "did", "can", "could", "would", "will", "is", "are", "should" }
                    .Contains(s.Text.Split(' ')[0].ToLowerInvariant());
                outList.Add(Make(s.Start + w.Start, w.Length, w.Text, new[] { w.Text + (q ? "?" : ".") }, IssueGroup.Correctness, "Punctuation/MissingEnd", "Missing end punctuation", q ? "This looks like a question; end it with a question mark." : "End the sentence with a period."));
            }
        }
        return outList;
    }

    // MARK: Structure

    public static List<Issue> Structure(string text)
    {
        var outList = new List<Issue>();
        var intro = new HashSet<string> { "in", "on", "at", "by", "for", "with", "without", "after", "before", "during", "despite", "regardless", "irregardless", "according", "unlike", "like", "as", "to", "from", "since", "until", "upon", "of", "thanks", "due", "given", "once", "even", "although", "though", "whether", "having", "being", "if", "when", "because", "while", "unless" };
        foreach (var s in TextUtil.Sentences(text))
        {
            var words = s.Text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            foreach (var m in TextUtil.Matches(@"(?<=\w), (i|you|he|she|it|we|they|this|that|there) ([a-z']+)\b", s.Text))
            {
                var lead = s.Text[..m.Index].ToLowerInvariant();
                if (!TextUtil.LooksLikeVerb(m.Groups[2].Value) || !TextUtil.HasVerb(lead)) continue;
                if (lead.Contains(" and ") || lead.Contains(" but ") || lead.Split(' ').Length < 3) continue;
                var clause = lead.Split(", ").Last();
                var fw = clause.Split(' ')[0];
                if (intro.Contains(fw) || fw.EndsWith("ing") || fw.EndsWith("ly") || fw.EndsWith("ed")) continue;
                var next = m.Value[2..];
                outList.Add(Make(s.Start + m.Index, m.Length, m.Value,
                    new[] { ". " + (next.StartsWith("i ", StringComparison.OrdinalIgnoreCase) ? next : char.ToUpperInvariant(next[0]) + next[1..]), "; " + next, ", and " + next },
                    IssueGroup.Correctness, "Punctuation/CommaSplice", "Comma splice", "Two complete sentences are joined only by a comma. Use a period, a semicolon, or add a conjunction."));
            }
            int commas = s.Text.Count(ch => ",;:—".Contains(ch));
            if (words.Length >= 35 && commas <= 1)
                outList.Add(Make(s.Start, s.Length, s.Text, Array.Empty<string>(), IssueGroup.Correctness, "Grammar/RunOn", "Run-on sentence", $"This sentence is {words.Length} words long with almost no punctuation. Split it into shorter sentences."));
            else if (words.Length >= 30)
                outList.Add(Make(s.Start, s.Length, s.Text, Array.Empty<string>(), IssueGroup.Clarity, "Style/Clarity/LongSentence", "Long sentence", "Sentences over 30 words are hard to follow. Try splitting this one."));
            bool greeting = Regex.IsMatch(s.Text, @"^(hi|hey|hello|dear|thanks|thank you|cheers|best|regards|sincerely|good (morning|afternoon|evening)|congrats|welcome|ok|okay|yes|no|sure)\b", RegexOptions.IgnoreCase);
            if (words.Length >= 2 && words.Length <= 8 && !greeting && !s.Text.EndsWith('!') && !s.Text.EndsWith('?') && !s.Text.EndsWith(':')
                && s.Text.EndsWith('.') && !TextUtil.HasVerb(s.Text)
                && !words.Skip(1).Any(w => { var l = w.Trim('.', ',').ToLowerInvariant(); return l.EndsWith("es") || l.EndsWith("ed"); }))
                outList.Add(Make(s.Start, s.Length, s.Text, Array.Empty<string>(), IssueGroup.Correctness, "Grammar/Fragment", "Sentence fragment", "This sentence seems to be missing a verb. Join it to the sentence before, or complete it."));
        }
        return outList;
    }

    // MARK: Protected text and de-duplication

    public static List<(int start, int end)> ProtectedRanges(string text)
    {
        string[] patterns =
        {
            @"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}",
            @"\b(?:https?://|www\.)[^\s<>""]+",
            @"\b[A-Za-z0-9-]+\.(?:com|org|net|io|ai|co|dev|app|edu|gov|us|uk|ca|de|fr|me|info|biz)(?:/[^\s]*)?\b",
            @"(?<![\w])[@#][A-Za-z0-9_.-]+",
            @"`[^`\n]+`",
            @"(?:[A-Za-z]:\\|\\\\)[^\s]+",
        };
        return patterns.SelectMany(p => TextUtil.Matches(p, text).Select(m => (m.Index, m.Index + m.Length))).ToList();
    }

    /// Sentence-wide hints (fragments, run-ons) never hide the word-level fixes inside them.
    static bool IsSentenceLevel(Issue i) => i.Length > 40 || i.Kind is "Grammar/Fragment" or "Grammar/RunOn" or "Style/Clarity/LongSentence";

    public static List<Issue> Dedupe(List<Issue> issues, string text)
    {
        var prot = ProtectedRanges(text);
        var filtered = issues.Where(i => i.Length > 40 || !prot.Any(p => i.Start < p.end && p.start < i.End));
        var sorted = filtered.OrderBy(i => (int)i.Group).ThenBy(i => i.Source == IssueSource.Spelling ? 1 : 0).ThenBy(i => i.Length);
        var kept = new List<Issue>();
        foreach (var i in sorted)
        {
            if (i.Length <= 0 || i.End > text.Length) continue;
            if (i.Replacements.Count > 0 && i.Replacements[0] == i.Original) continue;
            bool wide = IsSentenceLevel(i);
            if (!kept.Any(k => IsSentenceLevel(k) == wide && k.Overlaps(i))) kept.Add(i);
        }
        return kept.OrderBy(i => i.Start).ToList();
    }
}
