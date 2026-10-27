// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation
import NaturalLanguage

/// Clarity, engagement, delivery and consistency checks.
@MainActor
enum StyleChecks {

    static func run(_ text: String, _ o: CheckOptions) -> [Issue] {
        var out: [Issue] = []
        out += phraseList(text, StyleData.wordy, group: .clarity, kind: "Style/Wordiness/InflatedPhrases", title: "Wordy phrase") {
            $1.isEmpty ? "“\($0)” adds words without meaning. Remove it." : "“\($1)” says the same thing in fewer words."
        }
        out += phraseList(text, StyleData.redundant, group: .clarity, kind: "Style/Wordiness/Tautology", title: "Redundancy") {
            "“\($0)” repeats itself. “\($1)” is enough."
        }
        if o.passive { out += passive(text) }
        if o.hedging { out += hedging(text) }
        if o.inclusive { out += inclusive(text) }
        out += engagement(text, o)
        if o.goals.formality == .formal || o.goals.domain == .academic || o.goals.domain == .business {
            out += phraseList(text, StyleData.informal, group: .delivery, kind: "Style/Formality/Informal", title: "Informal language") {
                $1.isEmpty ? "“\($0)” is too casual for formal writing." : "“\($0)” is informal. In formal writing use “\($1)”."
            }
            for m in TextUtil.matches("\\b(don't|can't|won't|isn't|aren't|wasn't|doesn't|didn't|it's|I'm|we're|they're|you're)\\b", in: text) {
                let o2 = TextUtil.substring(text, m.range)
                if let full = expand[o2.lowercased()] {
                    out.append(Issue(range: m.range, original: o2, replacements: [TextUtil.matchCase(full, like: o2)], group: .delivery,
                                     kind: "Style/Formality/Contraction", title: "Contraction",
                                     explanation: "Formal and academic writing usually avoids contractions."))
                }
            }
        }
        if o.goals.domain == .academic {
            for m in TextUtil.matches("\\b(I|me|my|we|our|you)\\b", in: text, caseInsensitive: false) where m.range.location > 0 {
                out.append(Issue(range: m.range, original: TextUtil.substring(text, m.range), replacements: [], group: .delivery,
                                 kind: "Style/Academic/Person", title: "Personal pronoun",
                                 explanation: "Many academic styles prefer an impersonal voice. Consider rephrasing without first or second person."))
            }
        }
        out += dialect(text, o.dialect)
        if o.consistency { out += consistency(text) }
        out += styleGuide(text, o.styleRules)
        return out
    }

    static let expand: [String: String] = [
        "don't": "do not", "can't": "cannot", "won't": "will not", "isn't": "is not", "aren't": "are not",
        "wasn't": "was not", "doesn't": "does not", "didn't": "did not", "it's": "it is", "i'm": "I am",
        "we're": "we are", "they're": "they are", "you're": "you are",
    ]

    static func phraseList(_ text: String, _ list: [(String, String)], group: IssueGroup, kind: String, title: String,
                           why: (String, String) -> String) -> [Issue] {
        var out: [Issue] = []
        for (p, r) in list {
            for m in TextUtil.matches("\\b" + NSRegularExpression.escapedPattern(for: p) + "\\b", in: text) {
                let o = TextUtil.substring(text, m.range)
                var range = m.range
                var rep = TextUtil.matchCase(r, like: o)
                if r.isEmpty {
                    // Swallow a following comma/space when deleting a phrase.
                    let after = TextUtil.substring(text, NSRange(location: NSMaxRange(range), length: min(2, (text as NSString).length - NSMaxRange(range))))
                    if after.hasPrefix(", ") { range.length += 2 } else if after.hasPrefix(" ") { range.length += 1 }
                    rep = ""
                }
                out.append(Issue(range: range, original: TextUtil.substring(text, range), replacements: [rep], group: group,
                                 kind: kind, title: title, explanation: why(o, r)))
            }
        }
        return out
    }

    // MARK: Passive voice

    static let irregularParticiples: Set<String> = [
        "done", "made", "given", "taken", "written", "seen", "known", "shown", "found", "built", "sent", "told", "held",
        "brought", "bought", "caught", "taught", "thought", "chosen", "driven", "eaten", "forgotten", "hidden", "broken",
        "spoken", "stolen", "frozen", "beaten", "bitten", "drawn", "grown", "thrown", "worn", "torn", "sold", "paid",
        "left", "lost", "kept", "led", "met", "put", "read", "set", "cut", "hit", "run", "won", "begun", "sung", "drunk",
    ]

    static func passive(_ text: String) -> [Issue] {
        var out: [Issue] = []
        let pattern = "\\b(am|is|are|was|were|be|been|being|get|gets|got)\\s+(?:(?:not|also|already|often|always|never|being|just|then)\\s+)?([a-z]+ed|[a-z]+en|" + irregularParticiples.joined(separator: "|") + ")\\b(\\s+by\\s+((?:the|a|an|my|our|your|his|her|their)\\s+)?([a-z]+))?"
        let adjectives: Set<String> = ["interested", "excited", "tired", "bored", "married", "worried", "pleased", "surprised", "scared", "located", "supposed", "used", "concerned", "involved", "based", "related", "qualified", "satisfied", "prepared", "dedicated", "committed", "experienced", "allowed", "open", "often", "seen", "even", "ten", "kitten", "garden", "happen", "listen", "chicken", "golden", "sudden", "hidden", "children", "oxen", "eleven", "seven", "heaven", "linen", "women", "men", "given"]
        for m in TextUtil.matches(pattern, in: text) {
            let part = TextUtil.substring(text, m.range(at: 2)).lowercased()
            if adjectives.contains(part) && m.range(at: 3).location == NSNotFound { continue }
            let orig = TextUtil.substring(text, m.range)
            var reps: [String] = []
            if m.range(at: 5).location != NSNotFound {
                let det = m.range(at: 4).location != NSNotFound ? TextUtil.substring(text, m.range(at: 4)) : ""
                let agent = det + TextUtil.substring(text, m.range(at: 5))
                let aux = TextUtil.substring(text, m.range(at: 1)).lowercased()
                let verb = ["was", "were", "got"].contains(aux) ? pastFromParticiple(part) : presentFromParticiple(part)
                reps = ["\(agent) \(verb)"]
            }
            out.append(Issue(range: m.range, original: orig, replacements: reps, group: .clarity, kind: "Style/PassiveVoice",
                             title: "Passive voice",
                             explanation: "This sentence appears to be in the passive voice. Active voice is usually clearer and more direct: put the person or thing doing the action first."
                                + (reps.isEmpty ? "" : " Reorder the sentence so “\(reps[0])” leads it.")))
        }
        return out
    }

    static func pastFromParticiple(_ p: String) -> String {
        let map = ["done": "did", "given": "gave", "taken": "took", "written": "wrote", "seen": "saw", "known": "knew", "shown": "showed",
                   "chosen": "chose", "driven": "drove", "eaten": "ate", "forgotten": "forgot", "hidden": "hid", "broken": "broke",
                   "spoken": "spoke", "stolen": "stole", "frozen": "froze", "beaten": "beat", "bitten": "bit", "drawn": "drew",
                   "grown": "grew", "thrown": "threw", "worn": "wore", "torn": "tore", "begun": "began", "sung": "sang", "drunk": "drank"]
        return map[p] ?? p
    }

    static func presentFromParticiple(_ p: String) -> String {
        let past = pastFromParticiple(p)
        if past.hasSuffix("ied") { return String(past.dropLast(3)) + "ies" }
        if past.hasSuffix("ed") {
            let stem = String(past.dropLast(2))
            if stem.hasSuffix("at") || stem.hasSuffix("iz") || stem.hasSuffix("is") || stem.hasSuffix("us") || stem.hasSuffix("v") || stem.hasSuffix("ur") || stem.hasSuffix("ag") || stem.hasSuffix("uc") || stem.hasSuffix("as") { return stem + "es" }
            return stem + "s"
        }
        return past
    }

    // MARK: Confidence

    static func hedging(_ text: String) -> [Issue] {
        var out: [Issue] = []
        var taken: [NSRange] = []
        for h in StyleData.hedges.sorted(by: { $0.count > $1.count }) {
            for m in TextUtil.matches("\\b" + NSRegularExpression.escapedPattern(for: h) + "\\b,?\\s?", in: text) {
                if taken.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { continue }
                taken.append(m.range)
                let o = TextUtil.substring(text, m.range)
                let atStart = m.range.location == 0 || TextUtil.substring(text, NSRange(location: max(0, m.range.location - 2), length: min(2, m.range.location))).contains(where: { ".!?\n".contains($0) })
                out.append(Issue(range: m.range, original: o, replacements: [""], group: .delivery, kind: "Style/Confidence/Hedging",
                                 title: "Hedging language",
                                 explanation: "“\(h)” can make you sound unsure. Removing it makes your point more confident." + (atStart ? " Capitalize the next word after removing it." : "")))
            }
        }
        return out
    }

    // MARK: Inclusive language

    static func inclusive(_ text: String) -> [Issue] {
        var out: [Issue] = []
        for (term, alts, why) in StyleData.inclusive {
            for m in TextUtil.matches("\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b", in: text) {
                let o = TextUtil.substring(text, m.range)
                out.append(Issue(range: m.range, original: o, replacements: alts.map { TextUtil.matchCase($0, like: o) }, group: .delivery,
                                 kind: "Style/Sensitivity/Inclusive", title: "Inclusive language", explanation: why))
            }
        }
        return out
    }

    // MARK: Engagement: weak words, repetition, variety

    static func engagement(_ text: String, _ o: CheckOptions) -> [Issue] {
        var out: [Issue] = []
        var taken: [NSRange] = []
        for (w, alts) in StyleData.weakWords.sorted(by: { $0.key.count > $1.key.count }) {
            let single = !w.contains(" ")
            for m in TextUtil.matches("\\b" + NSRegularExpression.escapedPattern(for: w) + "\\b", in: text) {
                if taken.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { continue }
                taken.append(m.range)
                if single && ["good", "bad", "get", "got", "big", "thing", "things", "nice"].contains(w) && o.goals.formality == .informal { continue }
                let orig = TextUtil.substring(text, m.range)
                var range = m.range
                var reps = alts.map { TextUtil.matchCase($0, like: orig) }
                if reps.contains("") {
                    let after = TextUtil.substring(text, NSRange(location: NSMaxRange(range), length: min(1, (text as NSString).length - NSMaxRange(range))))
                    if after == " " { range.length += 1 }
                }
                reps = reps.map { $0.isEmpty ? "" : $0 }
                out.append(Issue(range: range, original: TextUtil.substring(text, range), replacements: reps, group: .engagement,
                                 kind: w.hasPrefix("very") || w.hasPrefix("really") ? "Engagement/Intensifier" : "Engagement/WeakWord",
                                 title: w.hasPrefix("very ") || w.hasPrefix("really ") ? "Intensifier" : (reps.contains("") ? "Filler word" : "Vague word"),
                                 explanation: reps.contains("")
                                    ? "“\(w)” rarely adds meaning. Consider removing it."
                                    : "“\(w)” is overused and vague. A more precise word makes your writing more engaging."))
            }
        }
        // Repeated content words within a paragraph.
        for p in TextUtil.paragraphs(text) {
            var counts: [String: [NSRange]] = [:]
            let tagger = NLTagger(tagSchemes: [.lemma])
            tagger.string = p.text
            for w in TextUtil.words(p.text) {
                let l = w.text.lowercased()
                guard l.count >= 4, !TextUtil.stopwords.contains(l), !o.dictionary.contains(l), l.allSatisfy(\.isLetter) else { continue }
                counts[l, default: []].append(NSRange(location: p.range.location + w.range.location, length: w.range.length))
            }
            for (word, ranges) in counts where ranges.count >= 3 {
                let syns = Synonyms.lookup(word)
                for r in ranges.dropFirst(2) {
                    let orig = TextUtil.substring(text, r)
                    out.append(Issue(range: r, original: orig, replacements: syns.map { TextUtil.matchCase($0, like: orig) }, group: .engagement,
                                     kind: "Engagement/Repetition", title: "Repetitive word",
                                     explanation: "“\(word)” appears \(ranges.count) times in this paragraph. Varying your words keeps readers interested."))
                }
            }
            // Sentence starts repeated.
            let sents = TextUtil.sentences(p.text)
            if sents.count >= 3 {
                for i in 2..<sents.count {
                    let a = sents[i - 2].text.split(separator: " ").first?.lowercased()
                    let b = sents[i - 1].text.split(separator: " ").first?.lowercased()
                    let c = sents[i].text.split(separator: " ").first?.lowercased()
                    if let a, a == b, b == c {
                        let w = String(sents[i].text.split(separator: " ").first ?? "")
                        let r = NSRange(location: p.range.location + sents[i].range.location, length: (w as NSString).length)
                        out.append(Issue(range: r, original: w, replacements: [], group: .engagement, kind: "Engagement/SentenceVariety",
                                         title: "Monotonous sentence starts",
                                         explanation: "Three sentences in a row start with “\(w)”. Vary how your sentences begin."))
                    }
                }
            }
        }
        return out
    }

    // MARK: Regional spelling

    static func dialect(_ text: String, _ d: Dialect) -> [Issue] {
        var out: [Issue] = []
        for (us, uk) in StyleData.usToUK {
            let (from, to) = d.usesBritishSpelling ? (us, uk) : (uk, us)
            if d == .canadian, ["organise", "organised", "organisation", "realise", "realised", "recognise", "recognised", "apologise", "analyse", "analysed", "criticise", "prioritise", "optimise", "customise", "emphasise", "summarise"].contains(to) { continue }
            for m in TextUtil.matches("\\b" + from + "\\b", in: text) {
                let o = TextUtil.substring(text, m.range)
                out.append(Issue(range: m.range, original: o, replacements: [TextUtil.matchCase(to, like: o)], group: .correctness,
                                 kind: "Spelling/Regional", title: "\(d.label) spelling",
                                 explanation: "In \(d.label), this is spelled “\(to)”. You can change your English dialect in Settings."))
            }
        }
        return out
    }

    // MARK: Consistency

    static func consistency(_ text: String) -> [Issue] {
        var out: [Issue] = []
        // Mixed spellings of the same word (e.g. e-mail / email, Covid / COVID).
        var forms: [String: [String: [NSRange]]] = [:]
        for w in TextUtil.words(text) where w.text.count >= 3 {
            let key = w.text.lowercased().replacingOccurrences(of: "-", with: "")
            forms[key, default: [:]][w.text, default: []].append(w.range)
        }
        for m in TextUtil.matches("\\b[A-Za-z]+-[A-Za-z]+\\b", in: text) {
            let w = TextUtil.substring(text, m.range)
            let key = w.lowercased().replacingOccurrences(of: "-", with: "")
            forms[key, default: [:]][w, default: []].append(m.range)
        }
        for (_, variants) in forms where variants.count >= 2 {
            // Ignore sentence-start capitalization differences.
            let norm = Set(variants.keys.map { $0.prefix(1).lowercased() + $0.dropFirst() })
            guard norm.count >= 2 else { continue }
            let preferred = variants.max { $0.value.count < $1.value.count }!.key
            for (form, ranges) in variants where form != preferred && form.prefix(1).lowercased() + form.dropFirst() != preferred.prefix(1).lowercased() + preferred.dropFirst() {
                for r in ranges {
                    out.append(Issue(range: r, original: form, replacements: [TextUtil.matchCase(preferred, like: form)], group: .correctness,
                                     kind: "Consistency/Spelling", title: "Inconsistent spelling",
                                     explanation: "You also wrote “\(preferred)” in this document. Pick one form and use it throughout."))
                }
            }
        }
        // Numbers: mixed digits and words for small numbers.
        let numWords = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        let words = TextUtil.matches("\\b(" + numWords.joined(separator: "|") + ")\\b(?= [a-z]+s\\b)", in: text)
        let digits = TextUtil.matches("(?<![\\d.,$:/])\\b[1-9]\\b(?![\\d.,:%/])(?= [a-z]+s\\b)", in: text)
        if !words.isEmpty, !digits.isEmpty {
            for m in digits {
                let o = TextUtil.substring(text, m.range)
                out.append(Issue(range: m.range, original: o, replacements: [numWords[Int(o)! - 1]], group: .correctness,
                                 kind: "Style/Formatting/NumberVsWord", title: "Inconsistent numbers",
                                 explanation: "Elsewhere you spell out small numbers. Most style guides spell out one through nine."))
            }
        }
        // Date formats: mixed numeric and written dates.
        let numeric = TextUtil.matches("\\b\\d{1,2}/\\d{1,2}/\\d{2,4}\\b", in: text)
        let written = TextUtil.matches("\\b(January|February|March|April|May|June|July|August|September|October|November|December) \\d{1,2}(st|nd|rd|th)?,? \\d{4}\\b", in: text, caseInsensitive: false)
        if !numeric.isEmpty, !written.isEmpty {
            for m in numeric {
                out.append(Issue(range: m.range, original: TextUtil.substring(text, m.range), replacements: [], group: .correctness,
                                 kind: "Consistency/Dates", title: "Inconsistent date format",
                                 explanation: "This document mixes numeric and written dates. Use one format throughout."))
            }
        }
        // Oxford comma consistency.
        let withOx = TextUtil.matches("\\b\\w+, \\w+, (and|or) \\w+", in: text)
        let withoutOx = TextUtil.matches("\\b\\w+, \\w+ (and|or) \\w+", in: text)
        if !withOx.isEmpty, !withoutOx.isEmpty {
            for m in withoutOx {
                let o = TextUtil.substring(text, m.range)
                let fixed = o.replacingOccurrences(of: " and ", with: ", and ").replacingOccurrences(of: " or ", with: ", or ")
                out.append(Issue(range: m.range, original: o, replacements: [fixed], group: .correctness,
                                 kind: "Consistency/OxfordComma", title: "Inconsistent serial comma",
                                 explanation: "You use the serial (Oxford) comma elsewhere in this document."))
            }
        }
        // Mixed quote styles.
        let straight = text.contains("\"")
        let curly = text.contains("“") || text.contains("”")
        if straight, curly {
            for m in TextUtil.matches("\"", in: text) {
                out.append(Issue(range: m.range, original: "\"", replacements: ["“", "”"], group: .correctness,
                                 kind: "Consistency/Quotes", title: "Inconsistent quotation marks",
                                 explanation: "This document mixes straight and curly quotation marks."))
            }
        }
        return out
    }

    // MARK: Team style guide

    static func styleGuide(_ text: String, _ rules: [StyleRule]) -> [Issue] {
        var out: [Issue] = []
        for r in rules where !r.avoid.isEmpty {
            for m in TextUtil.matches("\\b" + NSRegularExpression.escapedPattern(for: r.avoid) + "\\b", in: text) {
                let o = TextUtil.substring(text, m.range)
                out.append(Issue(range: m.range, original: o, replacements: r.use.isEmpty ? [] : [r.use], group: .delivery,
                                 kind: "StyleGuide/Custom", title: "Style guide",
                                 explanation: r.note.isEmpty ? "Your style guide recommends “\(r.use)” instead of “\(r.avoid)”." : r.note))
            }
        }
        return out
    }
}
