// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation

/// `JustTypeIt --self-test` runs the checker on sample sentences and prints the results.
@MainActor
enum SelfTest {
    /// Writes the shared rule data used by the Windows app (windows/JustTypeIt.Core/rules.json).
    static func exportRules(_ path: String) -> Int32 {
        func rule(_ r: PatternRule) -> [String: Any] {
            ["pattern": r.pattern, "replacement": r.replacement, "group": r.group.rawValue, "kind": r.kind,
             "title": r.title, "explanation": r.explanation, "caseInsensitive": r.caseInsensitive]
        }
        let pairs: ([(String, String)]) -> [[String]] = { $0.map { [$0.0, $0.1] } }
        let json: [String: Any] = [
            "grammar": (RuleData.grammar + GrammarRules.all).map(rule),
            "wordy": pairs(StyleData.wordy), "redundant": pairs(StyleData.redundant),
            "informal": pairs(StyleData.informal), "usToUK": pairs(StyleData.usToUK),
            "hedges": StyleData.hedges,
            "weakWords": StyleData.weakWords,
            "inclusive": StyleData.inclusive.map { ["term": $0.0, "alternatives": $0.1, "why": $0.2] as [String: Any] },
            "irregular": Morph.irregular.map { [$0.0, $0.1, $0.2] },
            "synonyms": Synonyms.table,
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              (try? d.write(to: URL(fileURLWithPath: path))) != nil else { return 1 }
        print("Exported \((RuleData.grammar + GrammarRules.all).count) grammar rules to \(path)")
        return 0
    }

    static func benchmark() -> Int32 {
        let base = (try? String(contentsOfFile: "Tests/clean-corpus.txt", encoding: .utf8)) ?? Store.welcomeText
        var o = CheckOptions(); o.goals = Goals()
        for (label, text) in [("email (120 words)", String(base.prefix(700))), ("page (700 words)", base), ("long doc (2,800 words)", String(repeating: base + "\n\n", count: 4))] {
            _ = RuleEngine.check(text, options: o)
            let t0 = Date()
            for _ in 0..<3 { _ = RuleEngine.check(text, options: o) }
            print(String(format: "%@: %.0f ms per check", label, Date().timeIntervalSince(t0) * 1000 / 3))
        }
        do {
            var doc = String(repeating: base + "\n\n", count: 4)
            _ = RuleEngine.check(doc, options: o)
            let t0 = Date()
            for k in 0..<10 { doc += " word\(k)"; _ = RuleEngine.check(doc, options: o) }
            print(String(format: "typing into a 2,800-word doc: %.0f ms per keystroke pause", Date().timeIntervalSince(t0) * 100))
            func t(_ n: String, _ f: () -> Void) { let a = Date(); f(); print(String(format: "    %@ %.0f ms", n, Date().timeIntervalSince(a) * 1000)) }
            t("docwide") { _ = StyleChecks.documentWide(doc, o) }
            t("repetition") { _ = StyleChecks.repetition(doc, o) }
            t("consistency") { _ = StyleChecks.consistency(doc) }
            t("paragraphs (NL)") { _ = TextUtil.paragraphs(doc) }
            t("words") { _ = TextUtil.words(doc) }
            t("dedupe") { _ = RuleEngine.dedupe(RuleEngine.check(doc, options: o), text: doc, o: o) }
            t("paragraph split") { _ = RuleEngine.lineParagraphs(doc) }
        }
        let text = base
        func time(_ name: String, _ f: () -> Void) { let t = Date(); for _ in 0..<3 { f() }; print(String(format: "  %@: %.0f ms", name, Date().timeIntervalSince(t) * 1000 / 3)) }
        time("system spelling") { _ = RuleEngine.systemCheck(text, o) }
        time("pattern rules") { _ = RuleEngine.patternRules(text, o) }
        time("mechanics") { _ = RuleEngine.mechanics(text) }
        time("structure") { _ = RuleEngine.structure(text) }
        time("style") { _ = StyleChecks.run(text, o) }
        time("style: engagement") { _ = StyleChecks.engagement(text, o) }
        time("style: dialect") { _ = StyleChecks.dialect(text, .american) }
        time("style: consistency") { _ = StyleChecks.consistency(text) }
        return 0
    }

    /// Tests every rewrite style with Apple Intelligence (and the offline fallback).
    static func rewriteTest() -> Int32 {
        let text = "hey so i think maybe we should probably move the meeting to thursday because alot of people cant make it on tuesday, let me know what u think"
        var fails = 0
        let sema = DispatchSemaphore(value: 0)
        Task { @MainActor in
            for mode in RewriteMode.allCases {
                let t0 = Date()
                let v = await Rewriter.versions(of: text, mode: mode, count: mode == .professional ? 3 : 1)
                let ok = !v.isEmpty && v.allSatisfy { !$0.isEmpty && $0 != text && !$0.contains("[") }
                if !ok { fails += 1 }
                print(ok ? "PASS" : "FAIL", String(format: "%-18@ %.1fs  versions=%d  → %@", mode.label as NSString, Date().timeIntervalSince(t0), v.count, (v.first ?? "-").replacingOccurrences(of: "\n", with: " ⏎ ").prefix(150) as CVarArg))
            }
            for mode in [RewriteMode.grammarOnly, .shorter, .confident] {
                let r = Rewriter.offline(text, mode: mode) ?? ""
                let ok = !r.isEmpty && r.contains("a lot") && r.contains("can't")
                if !ok { fails += 1 }
                print(ok ? "PASS" : "FAIL", "offline", mode.label, "→", r.prefix(140))
            }
            let custom = await Rewriter.versions(of: text, mode: .improve, custom: "make it sound like a pirate", count: 1)
            if custom.isEmpty { fails += 1 }
            print(custom.isEmpty ? "FAIL" : "PASS", "custom instruction →", custom.first?.prefix(140) ?? "-")
            sema.signal()
        }
        while sema.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        print(fails == 0 ? "REWRITE: ALL PASS" : "REWRITE: \(fails) FAILED")
        return fails == 0 ? 0 : 1
    }

    static func run() -> Int32 {
        if CommandLine.arguments.contains("--rewrite") { return rewriteTest() }
        if CommandLine.arguments.contains("--benchmark") { return benchmark() }
        if let i = CommandLine.arguments.firstIndex(of: "--export-rules"), i + 1 < CommandLine.arguments.count {
            return exportRules(CommandLine.arguments[i + 1])
        }
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
        // Proactive features
        func ac(_ t: String) -> String? {
            guard let f = Proactive.autocorrect(t, caret: (t as NSString).length) else { return nil }
            return (t as NSString).replacingCharacters(in: f.range, with: f.replacement)
        }
        let acCases: [(String, String?)] = [
            ("I think teh ", "I think the "), ("Teh ", "The "), ("we dont ", "we don't "), ("recieved,", "received,"),
            ("i ", "I "), ("He said im ", "He said I'm "), ("email me@teh ", nil), ("the ", nil), ("Ill ", nil),
            ("I feel ill ", nil), ("I wont ", nil), ("visit www.teh ", nil),
        ]
        for (input, expected) in acCases {
            let got = ac(input)
            let ok = got == expected
            if !ok { fails += 1 }
            print(ok ? "PASS" : "FAIL", "| autocorrect", "“\(input)” →", got.map { "“\($0)”" } ?? "no change")
        }
        let send = Proactive.preSendWarnings("Hi Sam, please see attached. This is unacceptable.", issues: [])
        let sendOK = send.contains { $0.title.contains("attachment") } && send.contains { $0.title.contains("harsh") }
        if !sendOK { fails += 1 }
        print(sendOK ? "PASS" : "FAIL", "| pre-send check:", send.map(\.title))
        let cleanSend = Proactive.preSendWarnings("Hi Sam, thanks for the update. See you Monday.", issues: [])
        if !cleanSend.isEmpty { fails += 1 }
        print(cleanSend.isEmpty ? "PASS" : "FAIL", "| pre-send check on a clean message:", cleanSend.map(\.title))
        let tone = Proactive.toneEmoji("Thank you so much for your help, I really appreciate it and I'm glad we could finish this together.")
        if tone == nil { fails += 1 }
        print(tone != nil ? "PASS" : "FAIL", "| tone:", tone.map { "\($0.emoji) \($0.label)" } ?? "none")
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
