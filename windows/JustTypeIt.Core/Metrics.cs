// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System;
using System.Collections.Generic;
using System.Linq;

namespace JustTypeIt;

public sealed class Metrics
{
    public int Words, Characters, Sentences, Paragraphs;
    public double ReadingMinutes, Readability, GradeLevel, AvgSentenceLength, UniqueWordsPercent;
    public int Overall = 100;
    public Dictionary<IssueGroup, int> GroupScores = new();
    public Dictionary<IssueGroup, int> GroupCounts = new();
    public List<(string name, double strength)> Tones = new();

    public string ReadabilityLabel => Readability switch
    {
        >= 90 => "Very easy", >= 70 => "Easy", >= 60 => "Plain English", >= 50 => "Fairly difficult", >= 30 => "Difficult", _ => "Very difficult",
    };

    public static Metrics Compute(string text, IReadOnlyList<Issue> issues)
    {
        var m = new Metrics();
        foreach (var g in Enum.GetValues<IssueGroup>()) { m.GroupScores[g] = 100; m.GroupCounts[g] = 0; }
        if (string.IsNullOrWhiteSpace(text)) return m;
        var words = TextUtil.Words(text).Select(w => w.Text).Where(w => w.Any(char.IsLetter)).ToList();
        m.Words = words.Count;
        m.Characters = text.Length;
        m.Sentences = Math.Max(1, TextUtil.Sentences(text).Count);
        m.Paragraphs = TextUtil.Paragraphs(text).Count;
        m.ReadingMinutes = m.Words / 238.0;
        m.AvgSentenceLength = (double)m.Words / m.Sentences;
        if (m.Words > 0)
        {
            double spw = words.Sum(TextUtil.Syllables) / (double)m.Words;
            m.Readability = Math.Clamp(206.835 - 1.015 * m.AvgSentenceLength - 84.6 * spw, 0, 100);
            m.GradeLevel = Math.Max(0, 0.39 * m.AvgSentenceLength + 11.8 * spw - 15.59);
            m.UniqueWordsPercent = words.Select(w => w.ToLowerInvariant()).Distinct().Count() * 100.0 / m.Words;
        }
        double per100 = Math.Max(1, m.Words / 100.0);
        var weights = new Dictionary<IssueGroup, double> { [IssueGroup.Correctness] = 9, [IssueGroup.Clarity] = 6, [IssueGroup.Engagement] = 4, [IssueGroup.Delivery] = 5 };
        double penalty = 0;
        foreach (var g in Enum.GetValues<IssueGroup>())
        {
            int n = issues.Count(i => i.Group == g);
            m.GroupCounts[g] = n;
            double p = n * weights[g] / per100;
            m.GroupScores[g] = Math.Max(0, (int)Math.Round(100 - p));
            penalty += p * (g == IssueGroup.Correctness ? 0.5 : 0.25);
        }
        m.Overall = Math.Clamp((int)Math.Round(100 - penalty), 0, 100);
        m.Tones = Tone(text);
        return m;
    }

    static readonly (string name, string[] cues)[] Lexicon =
    {
        ("Confident", new[] { "will", "definitely", "certainly", "confident", "guarantee", "clearly", "committed", "ensure" }),
        ("Friendly", new[] { "thanks", "thank", "glad", "happy", "great", "love", "hope", "welcome", "appreciate", "wonderful" }),
        ("Formal", new[] { "therefore", "furthermore", "regards", "sincerely", "accordingly", "kindly", "respectfully", "dear" }),
        ("Optimistic", new[] { "excited", "looking forward", "opportunity", "progress", "improve", "success", "positive", "promising" }),
        ("Assertive", new[] { "must", "need to", "required", "immediately", "expect", "insist", "deadline" }),
        ("Worried", new[] { "worried", "concern", "concerned", "afraid", "unfortunately", "risk", "problem", "issue" }),
        ("Unassuming", new[] { "just", "maybe", "perhaps", "i think", "i guess", "sort of", "kind of", "possibly", "sorry" }),
        ("Informal", new[] { "hey", "gonna", "wanna", "lol", "yeah", "cool", "stuff", "kinda", "btw", "guys" }),
    };

    static List<(string, double)> Tone(string text)
    {
        var lower = " " + text.ToLowerInvariant() + " ";
        double words = Math.Max(1, TextUtil.WordCount(text));
        var r = new List<(string, double)>();
        foreach (var (name, cues) in Lexicon)
        {
            int hits = cues.Sum(c => TextUtil.Matches($@"\b{System.Text.RegularExpressions.Regex.Escape(c)}\b", lower).Count());
            if (hits > 0) r.Add((name, Math.Min(1, hits / (words / 25 + 1))));
        }
        if (r.Count == 0) r.Add(("Neutral", 0.5));
        return r.OrderByDescending(x => x.Item2).Take(4).ToList();
    }
}
