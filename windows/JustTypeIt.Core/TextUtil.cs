// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace JustTypeIt;

public readonly record struct Span(int Start, int Length, string Text)
{
    public int End => Start + Length;
}

public static class TextUtil
{
    static readonly TimeSpan Timeout = TimeSpan.FromMilliseconds(250);
    static readonly Dictionary<(string, bool), Regex> cache = new();

    public static Regex Re(string pattern, bool ignoreCase = true)
    {
        lock (cache)
        {
            if (!cache.TryGetValue((pattern, ignoreCase), out var re))
            {
                re = new Regex(pattern, RegexOptions.CultureInvariant | (ignoreCase ? RegexOptions.IgnoreCase : RegexOptions.None), Timeout);
                cache[(pattern, ignoreCase)] = re;
            }
            return re;
        }
    }

    public static IEnumerable<Match> Matches(string pattern, string text, bool ignoreCase = true)
    {
        MatchCollection ms;
        try { ms = Re(pattern, ignoreCase).Matches(text); _ = ms.Count; }
        catch (RegexMatchTimeoutException) { yield break; }
        foreach (Match m in ms) yield return m;
    }

    public static string Sub(string text, int start, int length) =>
        start < 0 || length < 0 || start + length > text.Length ? "" : text.Substring(start, length);

    public static string MatchCase(string target, string source)
    {
        if (target.Length == 0 || source.Length == 0) return target;
        if (source.Length > 1 && source == source.ToUpperInvariant() && source != source.ToLowerInvariant()) return target.ToUpperInvariant();
        if (char.IsUpper(source[0])) return char.ToUpperInvariant(target[0]) + target[1..];
        return target;
    }

    public static IEnumerable<Span> Words(string text)
    {
        foreach (Match m in Re(@"[\p{L}\p{N}][\p{L}\p{N}'’\-]*").Matches(text))
            yield return new Span(m.Index, m.Length, m.Value);
    }

    public static int WordCount(string text) => Words(text).Count();

    /// Sentences, splitting on . ! ? and line breaks (abbreviations like "Mr." and "e.g." are kept together).
    public static List<Span> Sentences(string text)
    {
        var outList = new List<Span>();
        int start = 0;
        void Add(int end)
        {
            var raw = text[start..end];
            int lead = raw.Length - raw.TrimStart().Length;
            var core = raw.Trim();
            if (core.Length > 0) outList.Add(new Span(start + lead, core.Length, core));
            start = end;
        }
        var abbr = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "e.g", "i.e", "inc", "ltd", "co", "no", "p.m", "a.m" };
        for (int i = 0; i < text.Length; i++)
        {
            char c = text[i];
            if (c == '\n') { Add(i); continue; }
            if (c is '.' or '!' or '?')
            {
                int j = i + 1;
                while (j < text.Length && (text[j] is '.' or '!' or '?' or '"' or '”' or ')' or '\'')) j++;
                if (j < text.Length && !char.IsWhiteSpace(text[j])) { i = j - 1; continue; }
                if (c == '.')
                {
                    int w = i - 1;
                    while (w >= 0 && (char.IsLetter(text[w]) || text[w] == '.')) w--;
                    var word = text[(w + 1)..i];
                    if (abbr.Contains(word) || (word.Length == 1 && char.IsUpper(word[0]))) continue;
                }
                Add(j);
                i = j - 1;
            }
        }
        if (start < text.Length) Add(text.Length);
        return outList;
    }

    public static List<Span> Paragraphs(string text)
    {
        var outList = new List<Span>();
        int pos = 0;
        foreach (var part in text.Split('\n'))
        {
            var core = part.TrimEnd('\r');
            int lead = core.Length - core.TrimStart().Length;
            var t = core.Trim();
            if (t.Length > 0) outList.Add(new Span(pos + lead, t.Length, t));
            pos += part.Length + 1;
        }
        return outList;
    }

    public static int Syllables(string word)
    {
        var w = new string(word.ToLowerInvariant().Where(char.IsLetter).ToArray());
        if (w.Length == 0) return 0;
        if (w.Length <= 3) return 1;
        int count = 0; bool prev = false;
        foreach (var ch in w)
        {
            bool v = "aeiouy".Contains(ch);
            if (v && !prev) count++;
            prev = v;
        }
        if (w.EndsWith("e") && !w.EndsWith("le") && count > 1) count--;
        if ((w.EndsWith("es") || w.EndsWith("ed")) && count > 1 && !w.EndsWith("ted") && !w.EndsWith("ded")) count--;
        return Math.Max(1, count);
    }

    public static readonly HashSet<string> Stopwords = new(StringComparer.OrdinalIgnoreCase)
    {
        "the","a","an","and","or","but","if","of","to","in","on","at","for","with","by","from","as","is","are","was","were","be","been",
        "being","it","its","this","that","these","those","i","you","he","she","we","they","me","him","her","us","them","my","your","his",
        "our","their","not","no","so","do","does","did","have","has","had","will","would","can","could","should","may","might","must",
        "there","here","what","which","who","whom","when","where","why","how","all","any","some","than","then","also","just","about",
        "into","over","after","before","up","out","more","most",
    };

    /// Simple verb detection used for fragment and comma-splice checks.
    static readonly HashSet<string> CommonVerbs = new(StringComparer.OrdinalIgnoreCase)
    {
        "am","is","are","was","were","be","been","have","has","had","do","does","did","will","would","can","could","should","may","might",
        "must","go","goes","went","get","gets","got","make","makes","made","know","knew","think","thought","take","took","see","saw","come",
        "came","want","wants","look","looks","use","uses","find","found","give","gave","tell","told","work","works","call","try","ask",
        "need","needs","feel","felt","become","leave","left","put","mean","keep","let","begin","seem","help","show","hear","play","run",
        "move","live","believe","bring","happen","write","sit","stand","lose","pay","meet","include","continue","set","learn","change",
        "lead","understand","watch","follow","stop","create","speak","read","spend","grow","open","walk","win","offer","remember","love",
        "consider","appear","buy","wait","serve","die","send","expect","build","stay","fall","cut","reach","kill","remain","suggest",
        "raise","pass","sell","require","report","decide","pull","like","likes","says","said","agree","surprised","sent","review",
        "built","argue","test","collect","celebrate","seems","suits","plays","attend","bring","share","confirm","join","finish",
        "spoke","spoken","ran","began","drove","flew","wrote","ate","drank","sang","swam","chose","broke","wore","threw","grew","drew",
        "taught","bought","brought","caught","fought","kept","slept","met","led","paid","sold","held","stood","won","lost","heard",
    };

    static readonly HashSet<string> Subjects = new(StringComparer.OrdinalIgnoreCase)
    { "i", "you", "we", "they", "he", "she", "it", "let's", "lets", "who", "that", "which", "there" };

    /// Conservative verb detection (no part-of-speech tagger on Windows): known verbs,
    /// -ed/-ing forms, contractions, any word after a subject pronoun, and a third-person -s
    /// word that follows a noun phrase.
    public static bool HasVerb(string sentence)
    {
        var ws = Words(sentence).Select(w => w.Text).ToList();
        for (int i = 0; i < ws.Count; i++)
        {
            var l = ws[i].ToLowerInvariant().Replace('’', '\'');
            if (CommonVerbs.Contains(l)) return true;
            if (l.Length > 3 && (l.EndsWith("ed") || l.EndsWith("ing"))) return true;
            if (l.Contains('\'') && !l.EndsWith("'s") || l.EndsWith("n't") || l == "let's" || l == "it's" || l == "that's" || l == "there's") return true;
            if (i > 0 && Subjects.Contains(ws[i - 1]) && !Stopwords.Contains(l)) return true;
            if (i > 0 && l.Length > 3 && l.EndsWith("s") && !l.EndsWith("ss") && !Stopwords.Contains(ws[i - 1])) return true;
        }
        return false;
    }

    public static bool LooksLikeVerb(string word)
    {
        var l = word.ToLowerInvariant();
        return CommonVerbs.Contains(l) || (l.Length > 3 && l.EndsWith("ed")) || l.EndsWith("n't");
    }
}
