// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System;
using System.Collections.Generic;
using System.Drawing;

namespace JustTypeIt;

public enum IssueGroup { Correctness, Clarity, Engagement, Delivery }

public enum IssueSource { Rules, Spelling, AI }

public static class IssueGroups
{
    public static string Label(this IssueGroup g) => g.ToString();

    public static Color Color(this IssueGroup g) => g switch
    {
        IssueGroup.Correctness => System.Drawing.Color.FromArgb(227, 64, 77),
        IssueGroup.Clarity => System.Drawing.Color.FromArgb(41, 122, 242),
        IssueGroup.Engagement => System.Drawing.Color.FromArgb(33, 168, 107),
        _ => System.Drawing.Color.FromArgb(140, 84, 235),
    };

    public static string Blurb(this IssueGroup g) => g switch
    {
        IssueGroup.Correctness => "Spelling, grammar and punctuation",
        IssueGroup.Clarity => "Wordiness, passive voice, hard sentences",
        IssueGroup.Engagement => "Vivid words, variety, repetition",
        _ => "Tone, confidence, formality, inclusivity",
    };

    public static IssueGroup Parse(string s) => s.ToLowerInvariant() switch
    {
        "clarity" => IssueGroup.Clarity,
        "engagement" => IssueGroup.Engagement,
        "delivery" => IssueGroup.Delivery,
        _ => IssueGroup.Correctness,
    };
}

/// A suggestion. Start/Length are UTF-16 offsets, the same units as Windows text controls.
public sealed class Issue
{
    public Guid Id { get; } = Guid.NewGuid();
    public int Start { get; set; }
    public int Length { get; set; }
    public string Original { get; set; } = "";
    public List<string> Replacements { get; set; } = new();
    public IssueGroup Group { get; set; }
    public string Kind { get; set; } = "";
    public string Title { get; set; } = "";
    public string Explanation { get; set; } = "";
    public IssueSource Source { get; set; } = IssueSource.Rules;
    public int End => Start + Length;
    public bool Overlaps(Issue o) => Start < o.End && o.Start < End;
    public string Key => $"{Kind}|{Original.ToLowerInvariant()}";
    public override string ToString() => $"{Original} → {(Replacements.Count > 0 ? Replacements[0] : "-")} [{Title}]";
}

public enum Dialect { American, British, Canadian, Australian, Indian }

public enum Formality { Informal, Neutral, Formal }

public enum Domain { General, Academic, Business, Technical, Creative, Casual, Email }

public sealed class Goals
{
    public string Intent { get; set; } = "Inform";
    public string Audience { get; set; } = "Knowledgeable";
    public Formality Formality { get; set; } = Formality.Neutral;
    public Domain Domain { get; set; } = Domain.General;
    public string Summary => $"intent: {Intent}, audience: {Audience}, formality: {Formality}, domain: {Domain}";
}

public sealed class StyleRule
{
    public string Avoid { get; set; } = "";
    public string Use { get; set; } = "";
    public string Note { get; set; } = "";
}

public sealed class CheckOptions
{
    public Dialect Dialect { get; set; } = Dialect.American;
    public Goals Goals { get; set; } = new();
    public HashSet<string> Dictionary { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public List<StyleRule> StyleRules { get; set; } = new();
    public bool Passive { get; set; } = true;
    public bool Inclusive { get; set; } = true;
    public bool Hedging { get; set; } = true;
    public bool Consistency { get; set; } = true;
    /// Optional spell checker (Windows' built-in one in the app; absent in tests).
    public ISpellChecker? Spelling { get; set; }
}

public interface ISpellChecker
{
    /// Returns misspelled words: (start, length, suggestions).
    IEnumerable<(int start, int length, IReadOnlyList<string> suggestions)> Check(string text, Dialect dialect);
}
