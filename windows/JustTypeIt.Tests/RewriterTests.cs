// Just Type It for Windows – created by Stefano Roman Gunness · MIT License

using JustTypeIt;
using Xunit.Abstractions;

public class RewriterTests
{
    readonly ITestOutputHelper log;
    public RewriterTests(ITestOutputHelper log) => this.log = log;

    const string Messy = "hey so i think maybe we should move the meeting to thursday because alot of people cant make it on tuesday, let me know what u think";

    string Run(RewriteMode m)
    {
        var r = Rewriter.Offline(Messy, m);
        log.WriteLine($"{m.Label()}: {r}");
        Assert.NotNull(r);
        return r!;
    }

    [Fact]
    public void GrammarOnlyFixesMistakesAndKeepsWords()
    {
        var r = Run(RewriteMode.GrammarOnly);
        Assert.Contains("a lot", r);
        Assert.Contains("can't", r);
        Assert.StartsWith("Hey so I think", r);
        Assert.Contains("Thursday", r);
    }

    [Fact]
    public void ConfidentRemovesHedging()
    {
        var r = Run(RewriteMode.Confident);
        Assert.DoesNotContain("I think maybe", r);
        Assert.Contains("a lot", r);
    }

    [Fact]
    public void ProfessionalRemovesSlang()
    {
        var r = Run(RewriteMode.Professional);
        Assert.StartsWith("Hello", r);
        Assert.DoesNotContain(" u ", " " + r + " ");
        Assert.Contains("you think", r);
        Assert.DoesNotContain("I think maybe", r);
    }

    [Fact]
    public void FormalExpandsContractions()
    {
        var r = Rewriter.Offline("I can't come and it's late, thanks.", RewriteMode.Formal)!;
        log.WriteLine(r);
        Assert.Contains("cannot", r);
        Assert.Contains("it is", r);
        Assert.Contains("thank you", r);
    }

    [Fact]
    public void CasualContracts()
    {
        var r = Rewriter.Offline("Dear Sam, I am not able to attend. I will send the notes. Kind regards", RewriteMode.Casual)!;
        log.WriteLine(r);
        Assert.StartsWith("Hi", r);
        Assert.Contains("I'm", r);
        Assert.Contains("I'll", r);
    }

    [Fact]
    public void ShorterRemovesWordiness()
    {
        var r = Rewriter.Offline("In order to make a decision, we really need to look at the end result very carefully.", RewriteMode.Shorter)!;
        log.WriteLine(r);
        Assert.True(r.Length < 80);
        Assert.Contains("decide", r);
    }

    [Fact]
    public void CleanTextNeedsNoGrammarRewrite() =>
        Assert.Null(Rewriter.Offline("Thanks for the update. I will send the report on Friday.", RewriteMode.GrammarOnly));

    [Fact]
    public async Task WithoutAIEveryOfflineModeStillReturnsAVersion()
    {
        Rewriter.OllamaUrl = "http://127.0.0.1:9"; // nothing listens here
        foreach (var m in Enum.GetValues<RewriteMode>().Where(m => m.WorksOffline()))
        {
            var v = await Rewriter.Versions(Messy, m);
            log.WriteLine($"{m.Label()}: {v.FirstOrDefault()}");
            Assert.NotEmpty(v);
        }
        Assert.Empty(await Rewriter.Versions(Messy, RewriteMode.Enthusiastic)); // needs AI
    }
}
