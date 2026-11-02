// Just Type It for Windows – created by Stefano Roman Gunness · MIT License
// Same cases as the Mac self-test.

using JustTypeIt;

public class ProactiveTests
{
    static string? Ac(string t)
    {
        var f = Proactive.Autocorrect(t, t.Length);
        return f == null ? null : t.Remove(f.Start, f.Length).Insert(f.Start, f.Replacement);
    }

    [Theory]
    [InlineData("I think teh ", "I think the ")]
    [InlineData("Teh ", "The ")]
    [InlineData("we dont ", "we don't ")]
    [InlineData("recieved,", "received,")]
    [InlineData("i ", "I ")]
    [InlineData("He said im ", "He said I'm ")]
    [InlineData("email me@teh ", null)]
    [InlineData("the ", null)]
    [InlineData("I feel ill ", null)]
    [InlineData("I wont ", null)]
    [InlineData("visit www.teh ", null)]
    public void Autocorrect(string input, string? expected) => Assert.Equal(expected, Ac(input));

    [Fact]
    public void PreSendWarnings()
    {
        var w = Proactive.PreSendWarnings("Hi Sam, please see attached. This is unacceptable.", Array.Empty<Issue>());
        Assert.Contains(w, x => x.Title.Contains("attachment"));
        Assert.Contains(w, x => x.Title.Contains("harsh"));
        Assert.Empty(Proactive.PreSendWarnings("Hi Sam, thanks for the update. See you Monday.", Array.Empty<Issue>()));
    }

    [Fact]
    public void Tone() => Assert.Equal("😀", Proactive.ToneEmoji("Thank you so much for your help, I really appreciate it and I'm glad we could finish this together."));
}
