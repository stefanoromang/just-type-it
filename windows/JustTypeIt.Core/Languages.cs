// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace JustTypeIt;

public sealed record Language(string Code, string Name, string Native)
{
    public string MenuLabel => Name == Native ? Name : $"{Name} ({Native})";
}

/// Writing languages (the same list as the Mac app, from rules.json) and a small offline language detector.
public static class Languages
{
    public static readonly string[] Defaults = { "en", "es" };
    public static IReadOnlyList<Language> All => RuleData.Shared.Languages;
    public static Language Named(string code) => All.FirstOrDefault(l => l.Code == code) ?? All[0];

    public static string Summary(IReadOnlyList<string> codes)
    {
        var names = All.Where(l => codes.Contains(l.Code)).Select(l => l.Name).ToList();
        return names.Count <= 2 ? string.Join(", ", names) : $"{names[0]} + {names.Count - 1}";
    }

    /// Windows spell checker language tag.
    public static string SpellTag(string code, Dialect d) => code switch
    {
        "en" => d switch { Dialect.British => "en-GB", Dialect.Canadian => "en-CA", Dialect.Australian => "en-AU", Dialect.Indian => "en-IN", _ => "en-US" },
        "es" => "es-ES", "it" => "it-IT", "pt-BR" => "pt-BR", "pt-PT" => "pt-PT", "fr" => "fr-FR", "de" => "de-DE", "nl" => "nl-NL",
        "sv" => "sv-SE", "da" => "da-DK", "nb" => "nb-NO", "fi" => "fi-FI", "pl" => "pl-PL", "cs" => "cs-CZ", "ro" => "ro-RO",
        "hu" => "hu-HU", "el" => "el-GR", "tr" => "tr-TR", "ru" => "ru-RU", "uk" => "uk-UA", "bg" => "bg-BG", "id" => "id-ID",
        "vi" => "vi-VN", "hi" => "hi-IN", "ar" => "ar-SA", "he" => "he-IL", "ko" => "ko-KR", _ => code,
    };

    static readonly Dictionary<string, string[]> CommonWords = new()
    {
        ["en"] = "the and is are you to of in that it for with this was have be we not on your will can please thanks hi i my our".Split(' '),
        ["es"] = "el la los las de que y en es un una por con para no se lo del al está son mi tu muy pero como más gracias hola qué cómo vez cada buena buen nos te me le les hay está están también todo pedido mañana hoy ayer".Split(' '),
        ["it"] = "il lo la gli le di che e è un una per con non sono del della mi ti ma come più grazie ciao anche questo".Split(' '),
        ["pt"] = "o a os as de que e em é um uma por com para não se do da dos no na mais obrigado olá você muito também".Split(' '),
        ["fr"] = "le la les de des que et est un une pour avec ne pas je vous nous du au il elle merci bonjour très mais".Split(' '),
        ["de"] = "der die das und ist nicht ich sie es ein eine zu mit für auf den dem wir ihr danke hallo auch aber sehr".Split(' '),
        ["nl"] = "de het een en is niet ik je we van op met voor dat zijn aan ook maar dank hallo heel".Split(' '),
        ["sv"] = "och är det att jag en ett på med för inte vi du som av till men tack hej mycket".Split(' '),
        ["da"] = "og er det at jeg en et på med for ikke vi du som af til men tak hej meget".Split(' '),
        ["nb"] = "og er det at jeg en et på med for ikke vi du som av til men takk hei veldig".Split(' '),
        ["fi"] = "ja on ei se että olen olet hän me te he kiitos hei mutta myös tämä".Split(' '),
        ["pl"] = "i w nie to jest się na że z do jak ale dziękuję cześć bardzo jestem".Split(' '),
        ["cs"] = "a v je to se na že s do jak ale děkuji ahoj velmi jsem není".Split(' '),
        ["ro"] = "și în este nu o un de la cu pentru că mulțumesc bună foarte dar".Split(' '),
        ["hu"] = "a az és hogy nem van egy is de köszönöm szia nagyon meg".Split(' '),
        ["tr"] = "ve bir bu da de için ile çok ama teşekkürler merhaba değil ben sen".Split(' '),
        ["id"] = "dan yang di ini itu dengan untuk tidak saya anda kami terima kasih halo juga".Split(' '),
        ["vi"] = "và là của có không tôi bạn cho với này được cảm ơn xin chào rất".Split(' '),
    };

    /// The language of a paragraph, among the user's languages; English (or the first) when unclear.
    public static string Detect(string text, IReadOnlyList<string> codes)
    {
        var fallback = codes.Contains("en") ? "en" : codes.FirstOrDefault() ?? "en";
        if (codes.Count < 2 || !text.Any(char.IsLetter)) return fallback;
        // Scripts first (Greek, Cyrillic, Arabic, Hebrew, Devanagari, Hangul).
        (string re, string[] langs)[] scripts =
        {
            (@"\p{IsGreek}", new[] { "el" }), (@"\p{IsCyrillic}", new[] { "uk", "bg", "ru" }), (@"\p{IsArabic}", new[] { "ar" }),
            (@"\p{IsHebrew}", new[] { "he" }), (@"\p{IsDevanagari}", new[] { "hi" }), (@"\p{IsHangulSyllables}", new[] { "ko" }),
        };
        foreach (var (re, langs) in scripts)
            if (Regex.IsMatch(text, re))
            {
                if (langs.Length > 1 && codes.Contains("uk") && Regex.IsMatch(text, "[іїєґ]", RegexOptions.IgnoreCase)) return "uk";
                var hit = langs.FirstOrDefault(codes.Contains);
                if (hit != null) return hit;
            }
        var words = Regex.Matches(text.ToLowerInvariant(), @"\p{L}+").Select(m => m.Value).ToList();
        string best = fallback; double bestScore = 0, enScore = 0;
        foreach (var code in codes)
        {
            var key = code.StartsWith("pt") ? "pt" : code;
            if (!CommonWords.TryGetValue(key, out var list)) continue;
            double score = words.Count(list.Contains);
            if (key == "es" && Regex.IsMatch(text, "[ñ¿¡]")) score += 2;
            if (key == "es" && Regex.IsMatch(text, "[áéíóú]") && !Regex.IsMatch(text, "[àèìòùâêôãõç]")) score += 1;
            if (key == "pt" && Regex.IsMatch(text, "[ãõç]")) score += 2;
            if (key == "de" && Regex.IsMatch(text, "[ß]")) score += 2;
            if (code == "en") enScore = score;
            if (score > bestScore) { bestScore = score; best = code; }
        }
        // Choose another language only with clear evidence over English.
        if (best != "en" && codes.Contains("en") && bestScore <= enScore) return "en";
        return bestScore >= 1 ? best : fallback;
    }
}
