// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System.Text.Json;

namespace JustTypeIt;

public sealed class Prefs
{
    public Dialect Dialect { get; set; } = Dialect.American;
    public Goals DefaultGoals { get; set; } = new();
    public List<string> Dictionary { get; set; } = new();
    public List<StyleRule> StyleRules { get; set; } = new();
    public bool CheckEverywhere { get; set; } = true;
    public bool StartWithWindows { get; set; } = true;
    public bool Passive { get; set; } = true;
    public bool Hedging { get; set; } = true;
    public bool Inclusive { get; set; } = true;
    public List<string> PausedApps { get; set; } = new();
    public int FixesAccepted { get; set; }
    public bool Onboarded { get; set; }
}

/// Settings and documents in %LOCALAPPDATA%\JustTypeIt. Nothing is sent anywhere.
public sealed class Store
{
    public static readonly Store Shared = new();
    public static string Dir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JustTypeIt");
    static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    public Prefs Prefs { get; private set; } = new();
    public string DraftText { get; set; } = "";

    Store()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            var p = Path.Combine(Dir, "prefs.json");
            if (File.Exists(p)) Prefs = JsonSerializer.Deserialize<Prefs>(File.ReadAllText(p)) ?? new();
            var d = Path.Combine(Dir, "draft.txt");
            DraftText = File.Exists(d) ? File.ReadAllText(d) : Welcome;
        }
        catch { Prefs = new(); DraftText = Welcome; }
    }

    public const string Welcome =
        "Welcome to Just Type It! Start typing or paste you're text and suggestions will appear on the right.\r\n\r\n" +
        "Their are a few mistakes in this paragraph so you can see how it work. In order to make a decision, the team have discussed about it alot. " +
        "The report was written by the manager and it was very very good. I think maybe we should of sent it yesterday.\r\n\r\n" +
        "Click any suggestion to fix it in one click. Just Type It also checks what you type in Outlook, Word, Teams, Chrome and other apps.";

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(Path.Combine(Dir, "prefs.json"), JsonSerializer.Serialize(Prefs, Json));
            File.WriteAllText(Path.Combine(Dir, "draft.txt"), DraftText);
        }
        catch { }
    }

    public CheckOptions Options(Goals? goals = null) => new()
    {
        Dialect = Prefs.Dialect,
        Goals = goals ?? Prefs.DefaultGoals,
        Dictionary = new HashSet<string>(Prefs.Dictionary, StringComparer.OrdinalIgnoreCase),
        StyleRules = Prefs.StyleRules,
        Passive = Prefs.Passive,
        Hedging = Prefs.Hedging,
        Inclusive = Prefs.Inclusive,
        Spelling = WindowsSpellChecker.Shared,
    };

    public void AddToDictionary(string word)
    {
        word = word.Trim();
        if (word.Length == 0 || Prefs.Dictionary.Contains(word, StringComparer.OrdinalIgnoreCase)) return;
        Prefs.Dictionary.Add(word);
        Save();
    }
}
