// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System.Runtime.InteropServices;

namespace JustTypeIt;

/// Windows' built-in spell checker (the one Office and Edge use), through the
/// ISpellCheckerFactory COM API. Offline, no downloads.
public sealed class WindowsSpellChecker : ISpellChecker
{
    public static readonly WindowsSpellChecker Shared = new();
    readonly Dictionary<string, ISpellCheckerCom?> checkers = new();

    static string Tag(Dialect d) => d switch
    {
        Dialect.British => "en-GB", Dialect.Canadian => "en-CA", Dialect.Australian => "en-AU", Dialect.Indian => "en-IN", _ => "en-US",
    };

    ISpellCheckerCom? Get(Dialect d)
    {
        var tag = Tag(d);
        lock (checkers)
        {
            if (checkers.TryGetValue(tag, out var c)) return c;
            try
            {
                var factory = (ISpellCheckerFactory)new SpellCheckerFactoryClass();
                if (factory.IsSupported(tag) == 0) tag = "en-US";
                c = factory.CreateSpellChecker(tag);
            }
            catch { c = null; }
            checkers[Tag(d)] = c;
            return c;
        }
    }

    public IEnumerable<(int start, int length, IReadOnlyList<string> suggestions)> Check(string text, Dialect dialect)
    {
        var checker = Get(dialect);
        if (checker == null || text.Length == 0) return Array.Empty<(int, int, IReadOnlyList<string>)>();
        var results = new List<(int, int, IReadOnlyList<string>)>();
        try
        {
            var errors = checker.ComprehensiveCheck(text);
            while (errors.Next(out var e) == 0 && e != null)
            {
                int start = (int)e.StartIndex, length = (int)e.Length;
                if (start < 0 || length <= 0 || start + length > text.Length) continue;
                var word = text.Substring(start, length);
                var suggestions = new List<string>();
                if (e.CorrectiveAction == CorrectiveAction.Replace && !string.IsNullOrEmpty(e.Replacement)) suggestions.Add(e.Replacement);
                else if (e.CorrectiveAction == CorrectiveAction.GetSuggestions)
                {
                    var list = checker.Suggest(word);
                    while (suggestions.Count < 4 && list.Next(1, out var s, IntPtr.Zero) == 0) suggestions.Add(s);
                }
                else if (e.CorrectiveAction == CorrectiveAction.Delete) suggestions.Add("");
                results.Add((start, length, suggestions));
            }
        }
        catch { }
        return results;
    }

    // COM interop for spellcheck.h (Windows 8+).
    enum CorrectiveAction { None = 0, GetSuggestions = 1, Replace = 2, Delete = 3 }

    [ComImport, Guid("7AB36653-1796-484B-BDFA-E74F1DB7C1DC"), ClassInterface(ClassInterfaceType.None)]
    class SpellCheckerFactoryClass { }

    [ComImport, Guid("8E018A9D-2415-4677-BF08-794EA61F94BB"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISpellCheckerFactory
    {
        IEnumString SupportedLanguages { get; }
        int IsSupported([MarshalAs(UnmanagedType.LPWStr)] string languageTag);
        ISpellCheckerCom CreateSpellChecker([MarshalAs(UnmanagedType.LPWStr)] string languageTag);
    }

    [ComImport, Guid("B6FD0B71-E2BC-4653-8D05-F197E412770B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISpellCheckerCom
    {
        string LanguageTag { [return: MarshalAs(UnmanagedType.LPWStr)] get; }
        IEnumSpellingError Check([MarshalAs(UnmanagedType.LPWStr)] string text);
        IEnumString Suggest([MarshalAs(UnmanagedType.LPWStr)] string word);
        void Add([MarshalAs(UnmanagedType.LPWStr)] string word);
        void Ignore([MarshalAs(UnmanagedType.LPWStr)] string word);
        void AutoCorrect([MarshalAs(UnmanagedType.LPWStr)] string from, [MarshalAs(UnmanagedType.LPWStr)] string to);
        byte GetOptionValue([MarshalAs(UnmanagedType.LPWStr)] string optionId);
        IEnumString OptionIds { get; }
        string Id { [return: MarshalAs(UnmanagedType.LPWStr)] get; }
        string LocalizedName { [return: MarshalAs(UnmanagedType.LPWStr)] get; }
        uint add_SpellCheckerChanged(IntPtr handler);
        void remove_SpellCheckerChanged(uint eventCookie);
        IntPtr GetOptionDescription([MarshalAs(UnmanagedType.LPWStr)] string optionId);
        IEnumSpellingError ComprehensiveCheck([MarshalAs(UnmanagedType.LPWStr)] string text);
    }

    [ComImport, Guid("803E3BD4-2828-4410-8290-418D1D73C762"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IEnumSpellingError
    {
        [PreserveSig] int Next(out ISpellingError? value);
    }

    [ComImport, Guid("B7C82D61-FBE8-4B47-9B27-6C0D2E0DE0A3"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISpellingError
    {
        uint StartIndex { get; }
        uint Length { get; }
        CorrectiveAction CorrectiveAction { get; }
        string Replacement { [return: MarshalAs(UnmanagedType.LPWStr)] get; }
    }

    [ComImport, Guid("00000101-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IEnumString
    {
        [PreserveSig] int Next(int celt, [MarshalAs(UnmanagedType.LPWStr)] out string rgelt, IntPtr pceltFetched);
        [PreserveSig] int Skip(int celt);
        void Reset();
        void Clone(out IEnumString ppenum);
    }
}
