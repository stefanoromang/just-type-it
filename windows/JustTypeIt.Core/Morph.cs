// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace JustTypeIt;

/// English verb and noun forms used to build grammar fixes (same logic as Morphology.swift).
public static class Morph
{
    static List<(string Base, string Past, string Participle)> Irregular => RuleData.Shared.Irregular;

    public static string Participle(string past)
    {
        var l = past.ToLowerInvariant();
        return Irregular.FirstOrDefault(e => e.Past == l).Participle ?? l;
    }

    public static string Base(string w)
    {
        var l = w.ToLowerInvariant();
        var e = Irregular.FirstOrDefault(x => x.Past == l || x.Participle == l);
        if (e.Base != null) return e.Base;
        if (l.EndsWith("ied")) return l[..^3] + "y";
        if (l.EndsWith("ed"))
        {
            var stem = l[..^2];
            if (stem.Length >= 2 && stem[^1] == stem[^2] && !"lsz".Contains(stem[^1])) return stem[..^1];
            string[] eEnd = { "at", "iz", "us", "v", "c", "dg", "ag", "ur", "as", "os", "rs", "ns", "ok", "ir" };
            if (eEnd.Any(stem.EndsWith) || (stem.EndsWith("ar") && !stem.EndsWith("ear"))) return stem + "e";
            return stem;
        }
        return l;
    }

    public static string Ing(string w)
    {
        var l = w.ToLowerInvariant();
        var special = new Dictionary<string, string> { ["see"] = "seeing", ["be"] = "being", ["lie"] = "lying", ["die"] = "dying" };
        if (special.TryGetValue(l, out var s)) return s;
        if (l.EndsWith("ie")) return l[..^2] + "ying";
        if (l.EndsWith("e") && !l.EndsWith("ee")) return l[..^1] + "ing";
        if (new[] { "get", "run", "sit", "stop", "chat", "plan", "swim", "begin" }.Contains(l)) return l + l[^1] + "ing";
        return l + "ing";
    }

    public static string ThirdPerson(string w)
    {
        var l = w.ToLowerInvariant();
        var special = new Dictionary<string, string> { ["have"] = "has", ["do"] = "does", ["go"] = "goes", ["are"] = "is", ["were"] = "was", ["don't"] = "doesn't", ["be"] = "is" };
        if (special.TryGetValue(l, out var s)) return s;
        if (l.EndsWith("y") && l.Length > 1 && !"aeiou".Contains(l[^2])) return l[..^1] + "ies";
        if (new[] { "s", "sh", "ch", "x", "z", "o" }.Any(l.EndsWith)) return l + "es";
        return l + "s";
    }

    public static string Plural(string w) => w.ToLowerInvariant() switch
    {
        "is" => "are", "was" => "were", "has" => "have", "does" => "do", "doesn't" => "don't", _ => w,
    };

    public static string EdAdjective(string w) => w.ToLowerInvariant() switch
    {
        "boring" => "bored", "interesting" => "interested", "exciting" => "excited", "confusing" => "confused", "tiring" => "tired",
        "annoying" => "annoyed", "frustrating" => "frustrated", "disappointing" => "disappointed", "surprising" => "surprised",
        "amazing" => "amazed", "terrifying" => "terrified", "embarrassing" => "embarrassed", var x => x,
    };

    public static string SingularNoun(string w)
    {
        var l = w.ToLowerInvariant();
        if (l.EndsWith("ies")) return l[..^3] + "y";
        if (l == "news's") return "news";
        if (l.EndsWith("ches") || l.EndsWith("shes")) return l[..^2];
        return l.EndsWith("s") ? l[..^1] : l;
    }

    public static string SubjectPronoun(string w) => w.ToLowerInvariant() switch
    {
        "me" => "I", "him" => "he", "her" => "she", "us" => "we", "them" => "they", _ => w,
    };

    /// Applies directive tokens in a rule replacement, e.g. "has PP:went" → "has gone".
    public static string Resolve(string s)
    {
        var ops = new (string tag, System.Func<string, string> f)[]
        {
            ("SINGNOUN", SingularNoun), ("PP", Participle), ("BASE", Base), ("ING", Ing), ("SING", ThirdPerson),
            ("PLUR", Plural), ("ED", EdAdjective), ("OBJ", SubjectPronoun),
        };
        var outStr = s;
        foreach (var (tag, f) in ops)
            outStr = Regex.Replace(outStr, $@"\b{tag}:([\w']+)", m => f(m.Groups[1].Value));
        return outStr;
    }
}
