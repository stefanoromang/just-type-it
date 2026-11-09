// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System;
using System.Collections.Generic;
using System.Linq;

namespace JustTypeIt;

/// Proactive help shared with the Mac app: safe autocorrect, pre-send warnings, tone at a glance.
public static class Proactive
{
    public static readonly Dictionary<string, string> Autocorrections = new(StringComparer.Ordinal)
    {
        ["teh"] = "the", ["adn"] = "and", ["taht"] = "that", ["thier"] = "their", ["recieve"] = "receive", ["recieved"] = "received",
        ["definately"] = "definitely", ["seperate"] = "separate", ["occured"] = "occurred", ["untill"] = "until", ["wich"] = "which",
        ["tommorow"] = "tomorrow", ["tomorow"] = "tomorrow", ["accomodate"] = "accommodate", ["acheive"] = "achieve", ["beleive"] = "believe",
        ["calender"] = "calendar", ["collegue"] = "colleague", ["enviroment"] = "environment", ["goverment"] = "government",
        ["immediatly"] = "immediately", ["independant"] = "independent", ["knowlege"] = "knowledge", ["neccessary"] = "necessary",
        ["occassion"] = "occasion", ["publically"] = "publicly", ["recomend"] = "recommend", ["sincerly"] = "sincerely",
        ["succesful"] = "successful", ["suprise"] = "surprise", ["truely"] = "truly", ["wierd"] = "weird", ["buisness"] = "business",
        ["managment"] = "management", ["alot"] = "a lot", ["becuase"] = "because", ["freind"] = "friend", ["goign"] = "going",
        ["hte"] = "the", ["jsut"] = "just", ["knwo"] = "know", ["realy"] = "really", ["thanx"] = "thanks", ["waht"] = "what", ["yuor"] = "your",
        ["dont"] = "don't", ["didnt"] = "didn't", ["doesnt"] = "doesn't", ["isnt"] = "isn't", ["wasnt"] = "wasn't", ["arent"] = "aren't",
        ["werent"] = "weren't", ["shouldnt"] = "shouldn't", ["couldnt"] = "couldn't", ["wouldnt"] = "wouldn't", ["havent"] = "haven't",
        ["hasnt"] = "hasn't", ["youre"] = "you're", ["theyre"] = "they're", ["thats"] = "that's", ["whats"] = "what's", ["im"] = "I'm", ["i"] = "I",
    };

    public sealed record Correction(int Start, int Length, string Original, string Replacement);

    /// The word just finished before `caret`; only unambiguous typos (real words like "ill" or "wont" are never changed).
    public static Correction? Autocorrect(string text, int caret, ISet<string>? dictionary = null)
    {
        if (caret < 2 || caret > text.Length) return null;
        char trigger = text[caret - 1];
        if (trigger != ' ' && ",.;:!?\n".IndexOf(trigger) < 0) return null;
        int start = caret - 1;
        while (start > 0 && (char.IsLetter(text[start - 1]) || text[start - 1] == '\'')) start--;
        int len = caret - 1 - start;
        if (len <= 0) return null;
        var word = text.Substring(start, len);
        var lower = word.ToLowerInvariant();
        // Abbreviations: "i.e.", "e.g.", "U.S." are left alone.
        if (start > 0 && text[start - 1] == '.') return null;
        if (trigger == '.' && (word.Length == 1 || (caret < text.Length && char.IsLetter(text[caret])))) return null;
        if (dictionary != null && dictionary.Contains(lower)) return null;
        if (!Autocorrections.TryGetValue(lower, out var fix)) return null;
        if (start > 0 && "@#/\\._-`".IndexOf(text[start - 1]) >= 0) return null;
        if (word == "I" || fix == word) return null;
        var rep = fix == "I" || fix.StartsWith("I'") ? fix : TextUtil.MatchCase(fix, word);
        return new Correction(start, len, word, rep);
    }

    public sealed record SendWarning(string Title, string Detail);

    public static List<SendWarning> PreSendWarnings(string text, IReadOnlyList<Issue> issues)
    {
        var outList = new List<SendWarning>();
        int errors = issues.Count(i => i.Group == IssueGroup.Correctness);
        if (errors > 0) outList.Add(new($"{errors} correctness issue{(errors == 1 ? "" : "s")}", "Spelling, grammar or punctuation mistakes are still in this message."));
        var lower = text.ToLowerInvariant();
        if (TextUtil.Matches(@"\b(attached|attachment|i've attached|please find attached|see attached|enclosed)\b", lower).Any())
            outList.Add(new("Mentions an attachment", "Make sure the file is actually attached before sending."));
        var harsh = new[] { "unacceptable", "ridiculous", "stupid", "incompetent", "useless", "as i already said", "per my last email", "obviously", "for the last time", "i told you" };
        var h = harsh.FirstOrDefault(lower.Contains);
        if (h != null) outList.Add(new("Tone may come across as harsh", $"“{h}” can read as frustrated or blunt. Consider a softer phrasing."));
        var acronyms = new HashSet<string> { "ASAP", "FYI", "HTML", "JSON", "NASA", "UNICEF", "COVID" };
        if (TextUtil.Matches(@"\b[A-Z]{4,}\b", text, false).Count(m => !acronyms.Contains(m.Value)) >= 2)
            outList.Add(new("Several words in capitals", "Words in all capitals can read like shouting."));
        if (TextUtil.WordCount(text) > 250) outList.Add(new("Long message", "This is over 250 words. Consider leading with the key point or using bullets."));
        return outList;
    }

    public static string? ToneEmoji(string text)
    {
        if (TextUtil.WordCount(text) < 12) return null;
        var top = Metrics.Compute(text, Array.Empty<Issue>()).Tones.FirstOrDefault();
        return top.name switch
        {
            "Confident" => "🤝", "Friendly" => "😀", "Formal" => "🎩", "Optimistic" => "🌤️", "Assertive" => "📣",
            "Worried" => "😟", "Unassuming" => "🙂", "Informal" => "😎", _ => "😐",
        };
    }
}
