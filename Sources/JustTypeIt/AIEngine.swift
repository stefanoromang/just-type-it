// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation
import FoundationModels
import AppKit

/// Everything powered by Apple's on-device language model (Apple Intelligence).
/// Nothing leaves the Mac.
@MainActor
enum AIEngine {

    static var debug = false

    static var available: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var unavailableReason: String {
        switch SystemLanguageModel.default.availability {
        case .available: return ""
        case .unavailable(let r):
            switch r {
            case .deviceNotEligible: return "This Mac doesn't support Apple Intelligence. Rule-based checks still work."
            case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in System Settings to unlock AI features."
            case .modelNotReady: return "Apple Intelligence is still downloading. AI features will turn on automatically."
            @unknown default: return "Apple Intelligence is unavailable."
            }
        }
    }

    static func run(_ instructions: String, _ prompt: String, temperature: Double? = nil) async -> String? {
        guard available else { return nil }
        let session = LanguageModelSession(model: SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations),
                                           instructions: instructions)
        let opts = temperature.map { GenerationOptions(temperature: $0) } ?? GenerationOptions(temperature: 0)
        do {
            let r = try await session.respond(to: prompt, options: opts)
            let t = clean(r.content)
            return t.isEmpty ? nil : t
        } catch {
            return nil
        }
    }

    static func clean(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for p in ["Here is the rewritten text:", "Here's the rewritten text:", "Rewritten text:", "Here is the revised text:", "Revised text:", "Output:", "Sure! Here", "Here is"] {
            if t.lowercased().hasPrefix(p.lowercased()), let nl = t.firstIndex(of: "\n"), p.hasPrefix("Here") || p.hasPrefix("Sure") {
                if t[..<nl].count < 80 { t = String(t[t.index(after: nl)...]) }
            } else if t.lowercased().hasPrefix(p.lowercased()) {
                t = String(t.dropFirst(p.count))
            }
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count > 2, t.hasPrefix("\""), t.hasSuffix("\""), !t.dropFirst().dropLast().contains("\"") { t = String(t.dropFirst().dropLast()) }
        return t.replacingOccurrences(of: "<<<", with: "").replacingOccurrences(of: ">>>", with: "")
    }

    static func goalsLine(_ g: Goals, brand: String) -> String {
        var s = "Writing goals – \(g.summary)."
        if !brand.isEmpty { s += " Brand voice: \(brand)." }
        return s
    }

    // MARK: Deep check (full-sentence suggestions)

    /// Asks the model to correct each sentence, then diffs word-by-word to produce precise suggestions.
    static func deepCheck(_ text: String, goals: Goals, dialect: Dialect, brand: String, existing: [Issue]) async -> [Issue] {
        guard available else { return [] }
        let ins = """
        You are an expert proofreader for \(dialect.label). Correct the sentence: fix grammar, spelling, punctuation, agreement, verb tense, articles, prepositions and word choice.
        Make the smallest changes needed. Keep the meaning, the words and the style. Do not rephrase correct parts.
        Output ONLY the corrected sentence. If it is already correct, output it unchanged.
        """
        var issues: [Issue] = []
        let sentences = TextUtil.sentences(text).filter { TextUtil.wordCount($0.text) >= 3 && TextUtil.wordCount($0.text) <= 80 }
        for s in sentences.prefix(40) {
            if Task.isCancelled { break }
            guard var fixed = await run(ins, s.text) else { continue }
            fixed = fixed.components(separatedBy: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? fixed
            fixed = stripQuotes(fixed.trimmingCharacters(in: .whitespaces))
            guard fixed != s.text, similarity(fixed, s.text) > 0.5 else { continue }
            // Drop edits that rules already cover, then join nearby edits into one readable suggestion.
            let raw = WordDiff.changes(from: s.text, to: fixed, merged: false).filter { d in
                let range = NSRange(location: s.range.location + d.range.location, length: d.range.length)
                return range.length > 0 && !existing.contains(where: { NSIntersectionRange($0.range, range).length > 0 })
            }
            for d in WordDiff.merge(raw, in: s.text) {
                let range = NSRange(location: s.range.location + d.range.location, length: d.range.length)
                if issues.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) { continue }
                if existing.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) { continue }
                var range2 = range
                // A fix that starts with punctuation attaches to the previous word: "colors and" → "colors,".
                if let f = d.replacement.first, ",.;:!?".contains(f), range2.location > 0,
                   TextUtil.substring(text, NSRange(location: range2.location - 1, length: 1)) == " " {
                    range2 = NSRange(location: range2.location - 1, length: range2.length + 1)
                }
                let orig = TextUtil.substring(text, range2)
                if orig.lowercased() == d.replacement.lowercased(), orig.first?.isUppercase == d.replacement.first?.isUppercase { continue }
                let (group, title, why) = classify(orig.trimmingCharacters(in: .whitespaces), d.replacement)
                issues.append(Issue(range: range2, original: orig, replacements: [d.replacement], group: group,
                                    kind: "AI/\(title)", title: title, explanation: why, source: .ai))
            }
        }
        return issues
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let wa = Set(a.lowercased().split(separator: " ")), wb = Set(b.lowercased().split(separator: " "))
        guard !wa.isEmpty else { return 0 }
        return Double(wa.intersection(wb).count) / Double(max(wa.count, wb.count))
    }

    /// Names the kind of change the AI made so the explanation teaches something.
    static func classify(_ o: String, _ r: String) -> (IssueGroup, String, String) {
        let lo = o.lowercased(), lr = r.lowercased()
        let strip: (String) -> String = { $0.filter { $0.isLetter || $0.isNumber || $0 == " " } }
        if o == r.lowercased() || r == o.lowercased() || lo == lr {
            if o.count > 1, o == o.uppercased() { return (.correctness, "Capitalization", "Don't write ordinary words in all capitals; it reads like shouting. Use “\(r)”.") }
            return (.correctness, "Capitalization", r.first?.isUppercase == true ? "Capitalize this word: “\(r)”." : "This word doesn't need a capital letter here: “\(r)”.")
        }
        if strip(lo) == strip(lr) {
            if r.contains(",") && !o.contains(",") { return (.correctness, "Missing comma", "Add a comma here to separate items or clauses: “\(r)”.") }
            if o.contains(",") && !r.contains(",") { return (.correctness, "Unnecessary comma", "This comma isn't needed: “\(r)”.") }
            if r.contains("-") != o.contains("-") { return (.correctness, "Hyphen", "Use “\(r)” (hyphenation).") }
            if r.contains("'") || r.contains("’") { return (.correctness, "Apostrophe", "Use an apostrophe here: “\(r)”.") }
            return (.correctness, "Punctuation", "The punctuation should be “\(r)”.")
        }
        if lo.replacingOccurrences(of: " ", with: "") == lr.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "") {
            return (.correctness, "Hyphen", "This compound is written “\(r)”.")
        }
        let ow = lo.split(separator: " "), rw = lr.split(separator: " ")
        if ow.count == 1, rw.count == 1 {
            let a = String(ow[0]), b = String(rw[0])
            let edit = levenshtein(a, b)
            if edit <= 2 && !["a", "an", "the"].contains(a) && NSSpellChecker.shared.checkSpelling(of: a, startingAt: 0).location != NSNotFound {
                return (.correctness, "Spelling", "“\(o)” is misspelled; the correct spelling is “\(r)”.")
            }
            let verbs: Set<String> = ["is", "are", "was", "were", "has", "have", "do", "does", "did", "go", "goes", "went"]
            if verbs.contains(a) || verbs.contains(b) || a.hasSuffix("s") != b.hasSuffix("s") && (a.hasPrefix(String(b.prefix(3)))) {
                return (.correctness, "Agreement", "The verb or noun form should agree with its subject or number: use “\(r)”.")
            }
            if ["a", "an", "the"].contains(a) || ["a", "an", "the"].contains(b) {
                return (.correctness, "Article", "Use the article “\(r)” here.")
            }
            if ["in", "on", "at", "to", "for", "of", "with", "by", "from", "about"].contains(a) {
                return (.correctness, "Preposition", "The natural preposition here is “\(r)”.")
            }
            return (.correctness, "Word choice", "“\(r)” is the correct or more precise word in this context.")
        }
        if r.isEmpty { return (.clarity, "Unnecessary words", "“\(o)” can be removed without changing the meaning.") }
        if o.isEmpty { return (.correctness, "Missing word", "A word seems to be missing here: “\(r)”.") }
        return (.correctness, "Grammar", "This phrase reads more correctly as “\(r)”.")
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }

    struct Chunk { var text: String; var offset: Int }

    static func chunks(_ text: String, max: Int) -> [Chunk] {
        var out: [Chunk] = []
        var cur = ""
        var start = 0
        var pos = 0
        for p in text.components(separatedBy: "\n") {
            let len = (p as NSString).length + 1
            if (cur as NSString).length + len > max, !cur.isEmpty {
                out.append(Chunk(text: cur, offset: start))
                cur = ""
                start = pos
            }
            cur += p + "\n"
            pos += len
        }
        if !cur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(Chunk(text: cur, offset: start)) }
        return out
    }

    // MARK: Rewrites

    static func rewriteSentence(_ sentence: String, goals: Goals, brand: String) async -> [String] {
        let ins = """
        Rewrite the user's sentence so it is clear, correct, concise and flows naturally, preserving its meaning.
        \(goalsLine(goals, brand: brand))
        Give exactly three alternative rewrites, one per line, numbered 1., 2., 3. No other text.
        """
        guard let out = await run(ins, sentence, temperature: 0.7) else { return [] }
        return out.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "^\\s*\\d+[.)]\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != sentence }
            .prefix(3).map { stripQuotes($0) }
    }

    static func stripQuotes(_ s: String) -> String {
        var t = s
        if t.count > 2, t.hasPrefix("\""), t.hasSuffix("\"") { t = String(t.dropFirst().dropLast()) }
        return t
    }

    static func transform(_ text: String, _ instruction: String, goals: Goals, brand: String) async -> String? {
        let ins = """
        \(instruction)
        \(goalsLine(goals, brand: brand))
        Keep the original language. Do not invent facts. Output ONLY the resulting text, with no commentary or quotes.
        """
        return await run(ins, "TEXT:\n<<<\n\(text)\n>>>")
    }

    // MARK: Generative features

    static func generate(_ instructions: String, _ prompt: String) async -> String? {
        await run(instructions + "\nOutput only the requested content. Never use placeholders like [Name]; if something is unknown, leave it out.", prompt, temperature: 0.6)
    }

    // MARK: Agents

    static func readerReactions(_ text: String, audience: Audience) async -> String? {
        let ins = """
        You are a sample reader from this audience: \(audience.label). Read the TEXT and report, in short bullet points:
        - Main takeaway: what you understood as the main point (one sentence).
        - What lands: one or two things that work.
        - Questions you'd ask: up to three.
        - Where you got lost or bored: specific spots, if any.
        - Likely reaction: how you'd feel and respond.
        """
        return await run(ins, "TEXT:\n<<<\n\(text.prefix(6000))\n>>>")
    }

    static func grade(_ text: String, rubric: String) async -> String? {
        let ins = """
        You are a fair, demanding teacher grading the student's writing. Use the RUBRIC if provided; otherwise grade on thesis, organization, evidence, style and mechanics.
        Output:
        Grade: <letter grade and score out of 100>
        Strengths: 2–3 bullets
        To improve: 3–5 specific, actionable bullets with examples from the text
        """
        let r = rubric.trimmingCharacters(in: .whitespacesAndNewlines)
        return await run(ins, (r.isEmpty ? "" : "RUBRIC:\n\(r)\n\n") + "TEXT:\n<<<\n\(text.prefix(6000))\n>>>")
    }

    static func aiOpinion(_ text: String) async -> String? {
        let ins = """
        Assess whether the TEXT reads as AI-generated or human-written. Mention concrete signals (generic phrasing, uniform sentence length, lack of specifics, stock transitions, or personal detail and irregular rhythm).
        Answer in two or three sentences. Be honest that this is an estimate.
        """
        return await run(ins, "TEXT:\n<<<\n\(text.prefix(4000))\n>>>")
    }
}
