// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace JustTypeIt;

public sealed record PatternRule(Regex Regex, string Replacement, IssueGroup Group, string Kind, string Title, string Explanation);

/// Rule data shared with the Mac app. rules.json is exported from the Swift sources
/// (`JustTypeIt --self-test --export-rules windows/JustTypeIt.Core/rules.json`) so both
/// platforms check exactly the same things.
public sealed class RuleData
{
    public List<PatternRule> Grammar { get; } = new();
    public List<(string, string)> Wordy { get; } = new();
    public List<(string, string)> Redundant { get; } = new();
    public List<(string, string)> Informal { get; } = new();
    public List<(string, string)> UsToUK { get; } = new();
    public List<string> Hedges { get; } = new();
    public Dictionary<string, string[]> WeakWords { get; } = new(StringComparer.OrdinalIgnoreCase);
    public List<(string term, string[] alternatives, string why)> Inclusive { get; } = new();
    public List<(string Base, string Past, string Participle)> Irregular { get; } = new();
    public Dictionary<string, string[]> Synonyms { get; } = new(StringComparer.OrdinalIgnoreCase);
    public int SkippedRules { get; private set; }

    static RuleData? shared;
    public static RuleData Shared => shared ??= Load();

    public static RuleData Load()
    {
        var asm = typeof(RuleData).Assembly;
        using var s = asm.GetManifestResourceStream("JustTypeIt.rules.json")
            ?? throw new InvalidOperationException("rules.json is missing from the build.");
        using var doc = JsonDocument.Parse(s);
        return FromJson(doc.RootElement);
    }

    public static RuleData FromJson(JsonElement root)
    {
        var d = new RuleData();
        foreach (var r in root.GetProperty("grammar").EnumerateArray())
        {
            var pattern = IcuToNet(r.GetProperty("pattern").GetString()!);
            var options = RegexOptions.CultureInvariant | (r.GetProperty("caseInsensitive").GetBoolean() ? RegexOptions.IgnoreCase : RegexOptions.None);
            Regex re;
            try { re = new Regex(pattern, options, TimeSpan.FromMilliseconds(250)); }
            catch (ArgumentException) { d.SkippedRules++; continue; }
            d.Grammar.Add(new PatternRule(re, r.GetProperty("replacement").GetString()!, IssueGroups.Parse(r.GetProperty("group").GetString()!),
                r.GetProperty("kind").GetString()!, r.GetProperty("title").GetString()!, r.GetProperty("explanation").GetString()!));
        }
        static List<(string, string)> Pairs(JsonElement e) =>
            e.EnumerateArray().Select(p => (p[0].GetString()!, p[1].GetString()!)).ToList();
        d.Wordy.AddRange(Pairs(root.GetProperty("wordy")));
        d.Redundant.AddRange(Pairs(root.GetProperty("redundant")));
        d.Informal.AddRange(Pairs(root.GetProperty("informal")));
        d.UsToUK.AddRange(Pairs(root.GetProperty("usToUK")));
        d.Hedges.AddRange(root.GetProperty("hedges").EnumerateArray().Select(x => x.GetString()!));
        foreach (var p in root.GetProperty("weakWords").EnumerateObject())
            d.WeakWords[p.Name] = p.Value.EnumerateArray().Select(x => x.GetString()!).ToArray();
        foreach (var x in root.GetProperty("inclusive").EnumerateArray())
            d.Inclusive.Add((x.GetProperty("term").GetString()!, x.GetProperty("alternatives").EnumerateArray().Select(a => a.GetString()!).ToArray(), x.GetProperty("why").GetString()!));
        foreach (var x in root.GetProperty("irregular").EnumerateArray())
            d.Irregular.Add((x[0].GetString()!, x[1].GetString()!, x[2].GetString()!));
        if (root.TryGetProperty("synonyms", out var syn))
            foreach (var p in syn.EnumerateObject()) d.Synonyms[p.Name] = p.Value.EnumerateArray().Select(x => x.GetString()!).ToArray();
        return d;
    }

    /// The Mac rules use ICU regex syntax. The few differences from .NET are translated here.
    public static string IcuToNet(string p) =>
        p.Replace("\\p{L}", "\\p{L}"); // identical today; kept as the single place to adapt syntax
}
