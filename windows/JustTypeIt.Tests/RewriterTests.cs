// Just Type It for Windows – created by Stefano Roman Gunness · MIT License

using JustTypeIt;
using Xunit.Abstractions;

public class RewriterTests
{
    readonly ITestOutputHelper log;
    public RewriterTests(ITestOutputHelper log) => this.log = log;

    const string Messy = "hey so i think maybe we should move the meeting to thursday because alot of people cant make it on tuesday, let me know what u think";

    [Fact]
    public void SevenActionsCanBeCustomizedAndRecovered()
    {
        Assert.Equal(7, RewriteModes.Primary.Length);
        Assert.Equal(7, RewriteModes.Primary.Distinct().Count());
        Assert.Contains(RewriteMode.Spanish, RewriteModes.Primary);
        Assert.Contains(RewriteMode.English, RewriteModes.Primary);
        var actions = RewriteModes.Normalize(new[] { RewriteMode.Casual, (RewriteMode)999 });
        Assert.Equal(7, actions.Length);
        Assert.Equal(RewriteMode.Casual, actions[0]);
        Assert.DoesNotContain((RewriteMode)999, actions);
    }

    [Theory]
    [InlineData(RewriteMode.Spanish, "Spanish")]
    [InlineData(RewriteMode.English, "English")]
    public void TranslationDoesNotUseTheEnglishOnlyFallback(RewriteMode mode, string target)
    {
        Assert.Contains("ONLY in " + target, mode.LanguageInstruction());
        Assert.Null(Rewriter.Offline(Messy, mode));
        Assert.False(mode.WorksOffline());
    }

    [Fact]
    public void StaleOrInvalidFixesNeverAlterText()
    {
        var fixes = new[]
        {
            new Issue { Start = -1, Length = 3, Original = "Old", Replacements = new() { "bad" } },
            new Issue { Start = 0, Length = 3, Original = "Old", Replacements = new() { "bad" } },
            new Issue { Start = 500, Length = 3, Original = "Old", Replacements = new() { "bad" } },
        };
        Assert.Equal("New text", Rewriter.ApplyIssues("New text", fixes));
    }

    [Fact]
    public async Task EmptyOversizedAndCancelledRequestsReturnNothing()
    {
        Assert.Empty(await Rewriter.Versions("", RewriteMode.Spanish));
        Assert.Empty(await Rewriter.Versions(new string('x', 6001), RewriteMode.Spanish));
        Assert.Empty(await Rewriter.Versions(Messy, RewriteMode.Spanish, cancellationToken: new CancellationToken(true)));
        Assert.Empty(await Rewriter.Proofread(new string('x', 6001), new CheckOptions()));
        Assert.Empty(await Rewriter.Proofread(Messy, new CheckOptions(), new CancellationToken(true)));
    }

    [Fact]
    public void SpanishNeverGetsEnglishSlangSubstitutions()
    {
        Assert.Null(Rewriter.Offline("El cliente indicó que no puede asistir a la reunión.", RewriteMode.Professional));
    }

    [Theory]
    [InlineData("Order 729: 24 boxes", "Pedido 729: 24 cajas", true)]
    [InlineData("Order 729: 24 boxes", "Pedido 729: 25 cajas", false)]
    [InlineData("Email sam@example.com", "Escribe a sam@wrong.com", false)]
    [InlineData("See https://example.com/729", "Ver https://example.com/729", true)]
    public void TranslationsProtectDetails(string source, string output, bool safe) =>
        Assert.Equal(safe, Rewriter.TranslationPreservesDetails(source, output));

    [Theory]
    [InlineData(RewriteMode.Spanish, "Please send order A729 for 24 boxes.", "Por favor, envía el pedido A729 de 24 cajas.", "Spanish")]
    [InlineData(RewriteMode.English, "Por favor, envía el pedido A729 de 24 cajas.", "Please send order A729 for 24 boxes.", "English")]
    [InlineData(RewriteMode.GrammarOnly, "The team have sent order A729 yesterday.", "The team sent order A729 yesterday.", "English")]
    public async Task TranslationFlowsThroughLocalAI(RewriteMode mode, string source, string translated, string language)
    {
        var portProbe = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
        portProbe.Start();
        var port = ((System.Net.IPEndPoint)portProbe.LocalEndpoint).Port;
        portProbe.Stop();
        using var server = new System.Net.HttpListener();
        var url = $"http://127.0.0.1:{port}/";
        server.Prefixes.Add(url); server.Start();
        var previous = Rewriter.OllamaUrl;
        Rewriter.OllamaUrl = url.TrimEnd('/');
        string request = "";
        var serve = Task.Run(async () =>
        {
            for (int n = 0; n < 2; n++)
            {
                var context = await server.GetContextAsync().WaitAsync(TimeSpan.FromSeconds(10));
                var payload = "";
                if (context.Request.Url!.AbsolutePath == "/api/tags") payload = "{\"models\":[{\"name\":\"qwen2.5:test\"}]}";
                else
                {
                    using var reader = new StreamReader(context.Request.InputStream);
                    request = await reader.ReadToEndAsync();
                    payload = System.Text.Json.JsonSerializer.Serialize(new { message = new { content = translated } });
                }
                var bytes = System.Text.Encoding.UTF8.GetBytes(payload);
                context.Response.ContentType = "application/json";
                await context.Response.OutputStream.WriteAsync(bytes);
                context.Response.Close();
            }
        });
        try
        {
            var versions = mode == RewriteMode.GrammarOnly
                ? (await Rewriter.Proofread(source, new CheckOptions())).Select(i => i.Replacements[0]).ToList()
                : await Rewriter.Versions(source, mode, count: 1);
            await serve;
            Assert.Equal(translated, Assert.Single(versions));
            using var parsed = System.Text.Json.JsonDocument.Parse(request);
            var instruction = parsed.RootElement.GetProperty("messages")[0].GetProperty("content").GetString()!;
            if (mode == RewriteMode.GrammarOnly)
            {
                Assert.Contains("Proofread this English sentence", instruction);
                Assert.Contains("Never translate", instruction);
            }
            else
            {
                Assert.Contains("ONLY in " + language, instruction);
                Assert.DoesNotContain("never translate", instruction);
            }
        }
        finally { Rewriter.OllamaUrl = previous; server.Stop(); }
    }

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
