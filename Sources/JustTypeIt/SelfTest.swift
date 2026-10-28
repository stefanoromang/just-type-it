// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation

/// `JustTypeIt --self-test` runs the checker on sample sentences and prints the results.
@MainActor
enum SelfTest {
    static func run() -> Int32 {
        let samples: [(String, [String])] = [
            ("Their going to the store tomorow.", ["They're going", "tomorrow"]),
            ("He dont care about the affect it has.", ["He doesn't", "effect"]),
            ("Me and him was very very happy.", ["He and I were"]),
            ("I has a apple and she go to school.", ["I have", "an apple", "she goes"]),
            ("In order to make a decision, we met.", ["To", "decide"]),
            ("The report was written by the manager.", ["the manager wrote"]),
            ("I think maybe we should of sent it.", ["should have"]),
            ("The chairman spoke to mankind.", ["chair", "humankind"]),
            ("It was raining, we stayed inside all day long.", ["Comma splice"]),
            ("The team discussed about it alot.", ["discussed", "a lot"]),
            ("This is better then that.", ["better than"]),
            ("i went home.", ["I"]),
        ]
        var fails = 0
        var o = CheckOptions()
        o.goals = Goals()
        for (s, expect) in samples {
            let issues = RuleEngine.check(s, options: o)
            let flat = issues.map { "\($0.original)→\($0.replacements.first ?? "-") [\($0.title)]" }
            let blob = issues.map { ($0.replacements.joined(separator: "|") + " " + $0.title).lowercased() }.joined(separator: " ")
            let missing = expect.filter { !blob.contains($0.lowercased()) }
            if !missing.isEmpty { fails += 1 }
            print(missing.isEmpty ? "PASS" : "FAIL missing \(missing)", "|", s)
            for f in flat { print("    ", f) }
        }
        let contact = "E: stefano.roman@buyersedgeplatform.com www.buyersedgeplatform.com @stefanoromang"
        let contactIssues = RuleEngine.check(contact, options: o)
        print("contact-line issues:", contactIssues.count, contactIssues.map(\.original))
        if !contactIssues.isEmpty { fails += 1 }
        let clean = "Thank you for meeting with us yesterday. We reviewed the proposal and agree with most of it. Our team will send the revised budget on Friday, and we look forward to working together. She makes great coffee. He helps the students every morning. The results surprised everyone. Let him know when it starts."
        let cleanIssues = RuleEngine.check(clean, options: o)
        print("clean-text false positives:", cleanIssues.count)
        for i in cleanIssues { print("    FP:", i.original, "→", i.replacements.first ?? "-", "[\(i.title)]") }
        if let i = CommandLine.arguments.firstIndex(of: "--corpus"), i + 1 < CommandLine.arguments.count,
           let corpus = try? String(contentsOfFile: CommandLine.arguments[i + 1], encoding: .utf8) {
            let found = RuleEngine.check(corpus, options: o).filter { $0.group == .correctness || $0.group == .clarity }
            print("corpus correctness/clarity flags:", found.count)
            for f in found { print("    CORPUS:", f.original.prefix(60), "→", f.replacements.first ?? "-", "[\(f.title)]") }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--errors"), i + 1 < CommandLine.arguments.count,
           let corpus = try? String(contentsOfFile: CommandLine.arguments[i + 1], encoding: .utf8) {
            var caught = 0
            let lines = corpus.split(separator: "\n").map(String.init)
            for l in lines {
                let f = RuleEngine.check(l, options: o).filter { $0.group == .correctness }
                if f.isEmpty { print("    MISSED:", l) } else { caught += 1; print("    caught:", l, "=>", f.map { "\($0.original)→\($0.replacements.first ?? "-")" }.joined(separator: "; ")) }
            }
            print("error recall: \(caught)/\(lines.count)")
        }
        if let i = CommandLine.arguments.firstIndex(of: "--sample"), i + 1 < CommandLine.arguments.count,
           let t = try? String(contentsOfFile: CommandLine.arguments[i + 1], encoding: .utf8) {
            for f in RuleEngine.check(t, options: o) { print("    RULE:", f.original.prefix(50), "→", f.replacements.first ?? "-", "[\(f.title)]") }
            if CommandLine.arguments.contains("--ai") {
                let sema = DispatchSemaphore(value: 0)
                Task { @MainActor in
                    let rules = RuleEngine.check(t, options: o)
                    for f in await AIEngine.deepCheck(t, goals: Goals(), dialect: .american, brand: "", existing: rules) {
                        print("    AI:", f.original.prefix(50), "→", f.replacements.first ?? "-", "[\(f.title)]")
                    }
                    sema.signal()
                }
                while sema.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            }
        }
        let m = Metrics.compute(Store.welcomeText, issues: RuleEngine.check(Store.welcomeText, options: o))
        print("welcome score:", m.overall, m.groupScores.map { "\($0.key.rawValue)=\($0.value)" }, "tones:", m.tones.map(\.name))
        print("AI available:", AIEngine.available)
        if CommandLine.arguments.contains("--ai"), !CommandLine.arguments.contains("--sample") {
            let sema = DispatchSemaphore(value: 0)
            Task { @MainActor in
                let t = "Me and my friend goes to the libary every weeks. Irregardless, we was always learning alot of new thing."
                AIEngine.debug = true
                let found = await AIEngine.deepCheck(t, goals: Goals(), dialect: .american, brand: "", existing: [])
                for f in found { print("    AI:", f.original, "→", f.replacements.first ?? "-", "|", f.explanation) }
                let rw = await AIEngine.rewriteSentence("The thing that I want to say is that the meeting, which was long, was not very productive for us.", goals: Goals(), brand: "")
                print("    rewrites:", rw)
                sema.signal()
            }
            while sema.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
        return fails == 0 ? 0 : 1
    }
}
