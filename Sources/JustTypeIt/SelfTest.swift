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
            "spanish": SpanishRules.all.map(rule),
            "languages": Language.all.map { ["code": $0.code, "name": $0.name, "native": $0.native] },
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              (try? d.write(to: URL(fileURLWithPath: path))) != nil else { return 1 }
        print("Exported \((RuleData.grammar + GrammarRules.all).count) grammar rules, \(SpanishRules.all.count) Spanish rules and \(Language.all.count) languages to \(path)")
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
            let translations: [(String, RewriteMode, String, String)] = [
                ("Please send the invoice for 1250 euros by Friday. Order A729.", .spanish, "es", "A729"),
                ("Por favor, envía la factura de 1250 euros antes del viernes. Pedido A729.", .english, "en", "A729"),
                ("Stefano will deliver 24 boxes on 12/11/2026. Details: https://example.com/order/729", .spanish, "es", "https://example.com/order/729"),
                ("Stefano entregará 24 cajas el 12/11/2026. Detalles: https://example.com/order/729", .english, "en", "https://example.com/order/729"),
            ]
            for (input, mode, language, protected) in translations {
                let start = Date()
                let output = await Rewriter.versions(of: input, mode: mode, count: 1).first ?? ""
                let detected = Language.detect(output, among: ["en", "es"])
                let inputNumbers = TextUtil.matches("[0-9]+", in: input).map { TextUtil.substring(input, $0.range) }
                let outputNumbers = TextUtil.matches("[0-9]+", in: output).map { TextUtil.substring(output, $0.range) }
                let ok = !output.isEmpty && detected == language && output.contains(protected) && inputNumbers == outputNumbers
                if !ok { fails += 1 }
                print(ok ? "PASS" : "FAIL", "translation", mode.label, String(format: "%.2fs", Date().timeIntervalSince(start)), "→", output)
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
            ("He did good on the exam.", ["did well"]),
        ]
        var fails = 0
        // Every grammar rule must compile; a broken pattern would silently disable it.
        let broken = (RuleData.grammar + GrammarRules.all + SpanishRules.all).filter { TextUtil.regex($0.pattern, caseInsensitive: $0.caseInsensitive) == nil }
        for b in broken { print("FAIL | rule does not compile:", b.title, b.pattern.prefix(80)) }
        if !broken.isEmpty { fails += 1 } else { print("PASS | all \(RuleData.grammar.count + GrammarRules.all.count) grammar rules compile") }
        var o = CheckOptions()
        o.goals = Goals()
        o.languages = ["en", "es"]
        let quick = RewriteMode.primary
        let quickOK = quick.count == 7 && Set(quick).count == 7 && quick.contains(.spanish) && quick.contains(.english)
        let preferences = try? JSONDecoder().decode(Prefs.self, from: Data("{\"quickActions\":[\"casual\",\"unknown\"]}".utf8))
        let migrated = preferences.map { $0.quickActions.count == 7 && $0.quickActions.first == .casual && $0.languages == Language.defaults } ?? false
        let roundTrip = (try? JSONEncoder().encode(preferences ?? Prefs())).flatMap { try? JSONDecoder().decode(Prefs.self, from: $0) }
        if !quickOK || !migrated || roundTrip?.quickActions != preferences?.quickActions { fails += 1 }
        print(quickOK && migrated && roundTrip?.quickActions == preferences?.quickActions ? "PASS" : "FAIL", "| seven configurable Quick Actions and preference migration")
        let safe = AccessibilityEdit.expectedText("Keep 😀 this unchanged", range: NSRange(location: 8, length: 4), original: "this", replacement: "that") == "Keep 😀 that unchanged"
            && AccessibilityEdit.expectedText("Short", range: NSRange(location: 100, length: 1), original: "x", replacement: "y") == nil
            && AccessibilityEdit.expectedText("Old text", range: NSRange(location: 0, length: 3), original: "New", replacement: "Next") == nil
        if !safe { fails += 1 }
        print(safe ? "PASS" : "FAIL", "| replacement boundaries, emoji and stale text")
        let detailsSafe = Rewriter.translationPreservesDetails("Order 729: 24 boxes https://example.com/729", "Pedido 729: 24 cajas https://example.com/729")
            && !Rewriter.translationPreservesDetails("Order 729: 24 boxes", "Pedido 729: 25 cajas")
            && !Rewriter.translationPreservesDetails("Email me at sam@example.com", "Escribe a sam@wrong.com")
        if !detailsSafe { fails += 1 }
        print(detailsSafe ? "PASS" : "FAIL", "| translation rejects changed amounts and addresses")
        let spanishSafe = !SpanishRules.all.contains { rule in
            !TextUtil.matches(rule.pattern, in: "Estoy asiendo la cuerda. No hay lo que necesitamos.", caseInsensitive: rule.caseInsensitive).isEmpty
        }
        if !spanishSafe { fails += 1 }
        print(spanishSafe ? "PASS" : "FAIL", "| Spanish rules preserve valid verbs and “hay lo que”")
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
            ("I feel ill ", nil), ("I wont ", nil), ("visit www.teh ", nil), ("that is, i.", nil), ("i.e. ", nil),
        ]
        for (input, expected) in acCases {
            let got = ac(input)
            let ok = got == expected
            if !ok { fails += 1 }
            print(ok ? "PASS" : "FAIL", "| autocorrect", "“\(input)” →", got.map { "“\($0)”" } ?? "no change")
        }
        for (t, want) in [("Their going to the store tomorow.", "en"), ("Habían muchas personas en la reunión.", "es"),
                          ("Hi Sam,", "en"), ("Te mando el deck mañana.", "es"), ("Grazie per il tuo aiuto con il progetto.", "it")] {
            let got = Language.detect(t, among: ["en", "es", "it"])
            if got != want { fails += 1 }
            print(got == want ? "PASS" : "FAIL", "| language of “\(t)” → \(got)")
        }
        let mixed = RuleEngine.check("Their going to the store.\n¿Que piensas del informe?", options: o)
        let mixedOK = mixed.contains { $0.replacements.first == "They're going" } && mixed.contains { $0.replacements.first == "¿Qué" }
        if !mixedOK { fails += 1 }
        print(mixedOK ? "PASS" : "FAIL", "| English and Spanish in one text:", mixed.map { "\($0.original)→\($0.replacements.first ?? "-")" })
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
            // Correct writing must never get a grammar or spelling error (style hints are fine).
            let errors = found.filter { $0.group == .correctness }
            if !errors.isEmpty { fails += 1; print("FAIL: \(errors.count) correctness flags on correct writing") }
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
            if caught < lines.count { fails += 1 }
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
