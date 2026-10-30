// Just Type It for Windows – created by Stefano Roman Gunness · MIT License
// Same expectations as the Mac self-test, so both apps behave the same.

using JustTypeIt;
using Xunit.Abstractions;

public class EngineTests
{
    readonly ITestOutputHelper log;
    public EngineTests(ITestOutputHelper log) => this.log = log;

    static List<Issue> Check(string s) => RuleEngine.Check(s, new CheckOptions());

    [Fact]
    public void AllSharedRulesCompile() => Assert.Equal(0, RuleData.Shared.SkippedRules);

    [Theory]
    [InlineData("Their going to the store.", "They're going")]
    [InlineData("He dont care about the affect it has.", "He doesn't")]
    [InlineData("He dont care about the affect it has.", "the effect")]
    [InlineData("Me and him was very happy.", "He and I were")]
    [InlineData("I has a apple and she go to school.", "I have")]
    [InlineData("I has a apple and she go to school.", "an apple")]
    [InlineData("I has a apple and she go to school.", "she goes")]
    [InlineData("In order to make a decision, we met.", "To")]
    [InlineData("The report was written by the manager.", "the manager wrote")]
    [InlineData("I think we should of sent it.", "should have")]
    [InlineData("The chairman spoke to mankind.", "humankind")]
    [InlineData("This is better then that.", "better than")]
    [InlineData("He has went home already.", "has gone")]
    [InlineData("Did you saw that?", "Did you see")]
    [InlineData("I look forward to meet you.", "look forward to meeting")]
    [InlineData("She suggested me to go.", "suggested that I go")]
    [InlineData("She plays the piano very good.", "very well")]
    [InlineData("Hi Team\n\nThanks for coming.", "Hi Team,")]
    [InlineData("this email Is our time to collect it.", "is")]
    [InlineData("We need the 4 difference colors now.", "different colors")]
    public void FindsAndFixes(string text, string expected)
    {
        var found = Check(text);
        foreach (var i in found) log.WriteLine(i.ToString());
        Assert.Contains(found, i => i.Replacements.Any(r => r.Contains(expected)));
    }

    [Fact]
    public void ErrorCorpusRecall()
    {
        var lines = File.ReadAllLines("error-corpus.txt").Where(l => l.Trim().Length > 0).ToList();
        var missed = lines.Where(l => !Check(l).Any(i => i.Group == IssueGroup.Correctness)).ToList();
        foreach (var m in missed) log.WriteLine("MISSED: " + m);
        log.WriteLine($"recall {lines.Count - missed.Count}/{lines.Count}");
        // Without a dictionary-based spell checker (that's Windows' job at runtime), only a
        // handful of pure misspellings can be missed.
        Assert.True(missed.Count <= 5, $"missed {missed.Count}: {string.Join(" | ", missed)}");
    }

    [Fact]
    public void NoGrammarFalseAlarmsOnCleanWriting()
    {
        var text = File.ReadAllText("clean-corpus.txt");
        var flags = Check(text).Where(i => i.Group == IssueGroup.Correctness).ToList();
        foreach (var f in flags) log.WriteLine("FLAG: " + f);
        Assert.True(flags.Count <= 2, string.Join(" | ", flags));
    }

    [Fact]
    public void ContactDetailsAreNeverFlagged()
    {
        Assert.Empty(Check("E: stefano.roman@buyersedgeplatform.com www.buyersedgeplatform.com @stefanoromang C:\\Users\\Stefano\\file.txt"));
    }

    [Fact]
    public void ApplyingEveryFixKeepsOtherTextIntact()
    {
        var text = "Their going to the store tomorrow and he dont care. Best, Stefano";
        var issues = Check(text).Where(i => i.Replacements.Count > 0).OrderByDescending(i => i.Start).ToList();
        var result = text;
        foreach (var i in issues) result = result.Remove(i.Start, i.Length).Insert(i.Start, i.Replacements[0]);
        Assert.Contains("They're going", result);
        Assert.Contains("he doesn't", result);
        Assert.EndsWith("Best, Stefano", result);
    }

    [Fact]
    public void DialectSpellings()
    {
        var uk = RuleEngine.Check("My favorite color is blue.", new CheckOptions { Dialect = Dialect.British });
        Assert.Contains(uk, i => i.Replacements.Contains("colour"));
        var us = RuleEngine.Check("My favourite colour is blue.", new CheckOptions { Dialect = Dialect.American });
        Assert.Contains(us, i => i.Replacements.Contains("color"));
    }

    [Fact]
    public void ScoresAndReadability()
    {
        var text = "Their going to the store. I has a apple.";
        var m = Metrics.Compute(text, Check(text));
        Assert.True(m.Overall < 100);
        Assert.True(m.GroupCounts[IssueGroup.Correctness] >= 2);
        Assert.InRange(m.Readability, 0, 100);
    }
}
