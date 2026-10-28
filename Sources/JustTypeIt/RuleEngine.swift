// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import AppKit
import NaturalLanguage

/// Fast, fully on-device checker. Combines macOS's spelling and grammar engine with
/// hand-written rules for grammar, clarity, engagement and delivery.
@MainActor
enum RuleEngine {

    static func check(_ text: String, options o: CheckOptions) -> [Issue] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var issues: [Issue] = []
        issues += systemCheck(text, o)
        issues += patternRules(text, o)
        issues += mechanics(text)
        issues += structure(text)
        issues += StyleChecks.run(text, o)
        return dedupe(issues, text: text, o: o)
    }

    // MARK: macOS spelling & grammar

    static func systemCheck(_ text: String, _ o: CheckOptions) -> [Issue] {
        let sc = NSSpellChecker.shared
        let lang = o.dialect.spellLanguage
        var orth: NSOrthography?
        var wc = 0
        let types = NSTextCheckingResult.CheckingType.spelling.rawValue | NSTextCheckingResult.CheckingType.grammar.rawValue
        let opts: [NSSpellChecker.OptionKey: Any] = [.orthography: NSOrthography.defaultOrthography(forLanguage: lang)]
        let results = sc.check(text, range: NSRange(location: 0, length: (text as NSString).length),
                               types: NSTextCheckingTypes(types), options: opts,
                               inSpellDocumentWithTag: 0, orthography: &orth, wordCount: &wc)
        var out: [Issue] = []
        for r in results {
            let word = TextUtil.substring(text, r.range)
            if r.resultType == .spelling {
                if o.dictionary.contains(word.lowercased()) { continue }
                if word.contains(where: \.isNumber) || word.hasPrefix("http") || word.contains("@") { continue }
                // Tech names like Node.js, macOS, iPhone, GitHub, camelCase identifiers.
                let ns = text as NSString
                let end = NSMaxRange(r.range)
                let dotted = end + 1 < ns.length && ns.substring(with: NSRange(location: end, length: 1)) == "." && ns.substring(with: NSRange(location: end + 1, length: 1)).first?.isLetter == true
                let before = r.range.location >= 1 ? ns.substring(with: NSRange(location: r.range.location - 1, length: 1)) : ""
                if dotted || before == "." || word.dropLast().contains(".") || word.dropFirst().contains(where: \.isUppercase) { continue }
                let guesses = sc.guesses(forWordRange: r.range, in: text, language: lang, inSpellDocumentWithTag: 0) ?? []
                let missingApostrophe = guesses.first.map { $0.replacingOccurrences(of: "'", with: "").lowercased() == word.lowercased() } ?? false
                out.append(Issue(range: r.range, original: word, replacements: Array(guesses.prefix(4)),
                                 group: .correctness, kind: missingApostrophe ? "Punctuation/Apostrophe" : "Spelling/Misspelled",
                                 title: missingApostrophe ? "Missing apostrophe" : "Spelling",
                                 explanation: missingApostrophe
                                    ? "Contractions need an apostrophe where letters are left out."
                                    : "“\(word)” isn't in the \(o.dialect.label) dictionary. If it's a name or term you use, add it to your dictionary.",
                                 source: .system))
            } else if r.resultType == .grammar {
                for d in r.grammarDetails ?? [] {
                    guard let rv = d["NSGrammarRange"] as? NSValue else { continue }
                    let local = rv.rangeValue
                    let range = NSRange(location: r.range.location + local.location, length: local.length)
                    let corr = (d["NSGrammarCorrections"] as? [String]) ?? []
                    let desc = (d["NSGrammarUserDescription"] as? String) ?? "Possible grammar issue."
                    let cat = (d["NSGrammarUserCategory"] as? String) ?? "Grammar"
                    out.append(Issue(range: range, original: TextUtil.substring(text, range), replacements: corr,
                                     group: .correctness, kind: "Grammar/\(cat.replacingOccurrences(of: " ", with: ""))",
                                     title: cat, explanation: desc, source: .system))
                }
            }
        }
        return out
    }

    // MARK: Pattern rules (grammar, confused words, agreement, articles, prepositions)

    static func patternRules(_ text: String, _ o: CheckOptions) -> [Issue] {
        var out: [Issue] = []
        for rule in RuleData.grammar + GrammarRules.all {
            for m in TextUtil.matches(rule.pattern, in: text, caseInsensitive: rule.caseInsensitive) {
                let orig = TextUtil.substring(text, m.range)
                if o.dictionary.contains(orig.lowercased()) { continue }
                var reps: [String] = []
                if !rule.replacement.isEmpty, let re = try? NSRegularExpression(pattern: rule.pattern, options: rule.caseInsensitive ? [.caseInsensitive] : []) {
                    var rep = Morph.resolve(re.replacementString(for: m, in: text, offset: 0, template: rule.replacement))
                    rep = TextUtil.matchCase(rep, like: orig)
                    if rep != orig { reps = [rep] } else { continue }
                } else {
                    reps = fallbackFix(rule.kind, orig)
                }
                if rule.kind == "Grammar/SubjectVerbAgreement", orig.lowercased().hasPrefix("i was") { continue }
                reps = reps.map(fixThirdPerson)
                out.append(Issue(range: m.range, original: orig, replacements: reps, group: rule.group,
                                 kind: rule.kind, title: rule.title, explanation: rule.explanation))
            }
        }
        return out
    }

    static let pastTense: [String: String] = [
        "go": "went", "eat": "ate", "see": "saw", "come": "came", "run": "ran", "buy": "bought", "write": "wrote",
        "take": "took", "give": "gave", "make": "made", "do": "did",
    ]
    static let baseForm: [String: String] = [
        "went": "go", "gone": "go", "ate": "eat", "wrote": "write", "took": "take", "gave": "give", "saw": "see",
        "did": "do", "was": "be", "has": "have",
    ]
    static let contractions: [String: String] = [
        "dont": "don't", "cant": "can't", "wont": "won't", "didnt": "didn't", "doesnt": "doesn't", "isnt": "isn't",
        "wasnt": "wasn't", "arent": "aren't", "werent": "weren't", "shouldnt": "shouldn't", "couldnt": "couldn't",
        "wouldnt": "wouldn't", "havent": "haven't", "hasnt": "hasn't", "im": "I'm", "ive": "I've", "youre": "you're",
        "theyre": "they're", "thats": "that's", "whats": "what's", "lets go": "let's go",
    ]

    /// "she gos" → "she goes", "he trys" → "he tries".
    static func fixThirdPerson(_ s: String) -> String {
        let fixes = ["gos": "goes", "dos": "does", "trys": "tries", "haves": "has"]
        var out = s
        for (k, v) in fixes { out = out.replacingOccurrences(of: "\\b\(k)\\b", with: v, options: .regularExpression) }
        return out
    }

    static func fallbackFix(_ kind: String, _ orig: String) -> [String] {
        switch kind {
        case "Punctuation/Apostrophe":
            if let c = contractions[orig.lowercased()] { return [c == "I'm" || c == "I've" ? c : TextUtil.matchCase(c, like: orig)] }
        case "Grammar/VerbTense" where TextUtil.matches("^(am|is|are) \\w+ing\\b", in: orig).count > 0:
            let aux = orig.split(separator: " ")[0].lowercased()
            return [(aux == "is" ? "has been" : "have been") + orig.dropFirst(aux.count)]
        case "Grammar/VerbTense":
            var s = orig
            for (base, past) in pastTense {
                let p = "\\b(he|she|it|i|we|they|you) \(base)\\b"
                if let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive) {
                    s = re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "$1 \(past)")
                }
            }
            return s == orig ? [] : [s]
        case "Grammar/SubjectVerbAgreement", "Grammar/CollectiveNoun":
            let parts = orig.split(separator: " ").map(String.init)
            guard let last = parts.last else { return [] }
            let lw = last.lowercased()
            if let first = parts.first?.lowercased(), first == "me" || first == "my", parts.count >= 4 {
                // "Me and my brother likes" / "My brother and I likes" → "My brother and I like"
                let person = first == "me" ? parts[3] : parts[1]
                let verb = ["likes": "like", "loves": "love", "wants": "want", "needs": "need", "has": "have", "is": "are", "was": "were", "goes": "go", "does": "do"][lw] ?? lw
                let s = "My \(person) and I \(verb)"
                return [orig.first?.isUppercase == true ? s : s.prefix(1).lowercased() + s.dropFirst()]
            }
            let sing = ["are": "is", "were": "was", "have": "has", "do": "does"]
            if let r = sing[lw] { return [parts.dropLast().joined(separator: " ") + " " + r] }
            return []
        case "Grammar/UncountableNoun":
            let parts = orig.split(separator: " ").map(String.init)
            if let f = parts.first?.lowercased(), f == "a" || f == "an" {
                let rest = parts.dropFirst().joined(separator: " ")
                return [rest, "some " + rest, "a piece of " + rest].map { TextUtil.matchCase($0, like: orig) }
            }
            return []
        case "Grammar/AdverbAdjective":
            return [orig.replacingOccurrences(of: "\\bgood$", with: "well", options: .regularExpression)]
        case "Grammar/PronounCase":
            let subj = ["me": "I", "him": "he", "her": "she", "them": "they"]
            let parts = orig.split(separator: " ").map(String.init)
            guard parts.count == 4 else { return [] }
            let a = subj[parts[0].lowercased()] ?? parts[0], b = subj[parts[2].lowercased()] ?? parts[2]
            let other = a == "I" ? b : a
            var verb = parts[3]
            if verb.lowercased() == "was" { verb = "were" }
            return [other.prefix(1).uppercased() + other.dropFirst() + " and I " + verb].map { orig.first?.isUppercase == true ? $0 : $0.prefix(1).lowercased() + $0.dropFirst() }
        case "Grammar/VerbForm":
            let parts = orig.split(separator: " ")
            if parts.count == 2, let b = baseForm[parts[1].lowercased()] { return ["\(parts[0]) \(b)"] }
        default: break
        }
        return []
    }

    // MARK: Mechanics: spacing, punctuation, capitalization, repeated words

    static func mechanics(_ text: String) -> [Issue] {
        var out: [Issue] = []
        func add(_ p: String, _ rep: (String) -> String, _ kind: String, _ title: String, _ why: String, ci: Bool = true, group: IssueGroup = .correctness) {
            for m in TextUtil.matches(p, in: text, caseInsensitive: ci) {
                let o = TextUtil.substring(text, m.range)
                out.append(Issue(range: m.range, original: o, replacements: [rep(o)], group: group, kind: kind, title: title, explanation: why))
            }
        }
        add("\\b(\\w+) \\1\\b", { String($0.split(separator: " ")[0]) }, "Grammar/RepeatedWord", "Repeated word",
            "The same word appears twice in a row.")
        add("(?<=\\S)  +(?=\\S)", { _ in " " }, "Punctuation/Spacing", "Extra space", "Use a single space between words.")
        add("\\s+([,.;:!?])(?!\\d)", { $0.trimmingCharacters(in: .whitespaces) }, "Punctuation/Spacing", "Space before punctuation",
            "Punctuation attaches to the word before it.")
        add("(?<=[a-z])([,;:])(?=[A-Za-z])", { $0 + " " }, "Punctuation/Spacing", "Missing space",
            "Add a space after a comma, semicolon or colon.", ci: false)
        add("(?<=[a-z]{2})([.!?])(?=[A-Z][a-z])", { $0 + " " }, "Punctuation/Spacing", "Missing space",
            "Add a space after the end of a sentence.", ci: false)
        add(",,+", { _ in "," }, "Punctuation/Comma", "Double comma", "Use a single comma.")
        add("(?<![.])\\.\\.(?![.])", { _ in "." }, "Punctuation/Period", "Double period", "Use one period, or three for an ellipsis.")
        add("!{2,}|\\?{2,}", { String($0.prefix(1)) }, "Punctuation/Exclamation", "Repeated punctuation",
            "One mark is enough in most writing.", group: .delivery)
        add("\\b(however|therefore|moreover|furthermore|nevertheless|consequently) (?=[a-z])", { $0.trimmingCharacters(in: .whitespaces) + ", " },
            "Punctuation/Comma", "Missing comma", "Introductory transition words are usually followed by a comma.")
        add("(?<=[a-z]), (however|therefore|moreover|consequently), (?=[a-z])", { "; " + $0.dropFirst(2) }, "Punctuation/CommaSplice", "Comma splice",
            "When a transition word joins two complete sentences, use a semicolon before it.", ci: false)
        add("\\b(\\w+)'s(?= (are|were|have)\\b)", { String($0.dropLast(2)) + "s" }, "Punctuation/Apostrophe", "Plural, not possessive",
            "Plurals don't take an apostrophe.")
        add("\\b(self|ex|all) (?=[a-z]+)(aware|employed|confident|esteem|wife|husband|boyfriend|girlfriend|inclusive|important)\\b",
            { $0.replacingOccurrences(of: " ", with: "-") }, "Spelling/Misspelled/MissingHyphenInPrefixes", "Missing hyphen",
            "This prefix is joined with a hyphen.")
        add("\\b(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety) (one|two|three|four|five|six|seven|eight|nine)\\b",
            { $0.replacingOccurrences(of: " ", with: "-") }, "Spelling/Misspelled/MissingHyphenInNumbers", "Missing hyphen",
            "Compound numbers from 21 to 99 are hyphenated.")
        add("\\b(well|long|high|full|short|part|full) (known|term|quality|time|lived|written|paid)\\b(?= [a-z]+)",
            { $0.replacingOccurrences(of: " ", with: "-") }, "Spelling/Misspelled/MissingHyphen", "Compound adjective",
            "Compound adjectives before a noun are usually hyphenated.")
        add("(?<=[a-z]) - (?=[a-z])", { _ in " — " }, "Punctuation/Dash", "Dash", "Use an em dash (—) to set off a phrase.", group: .delivery)

        // Common words capitalized in the middle of a sentence ("this email Is our time").
        let common = "is|are|was|were|the|and|or|but|our|your|their|my|it|this|that|we|you|to|of|for|with|in|on|at|a|an|be|have|has|will|can|please|thank|thanks"
        for m in TextUtil.matches("(?<=[a-z,] )(" + common.split(separator: "|").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "|") + ")\\b", in: text, caseInsensitive: false) {
            let o = TextUtil.substring(text, m.range)
            out.append(Issue(range: m.range, original: o, replacements: [o.lowercased()], group: .correctness,
                             kind: "Grammar/Capitalization", title: "Capitalization",
                             explanation: "Only capitalize the first word of a sentence and proper nouns."))
        }
        // Ordinary words written in all capitals (not acronyms).
        let shouty: Set<String> = ["DATA", "PLEASE", "THANKS", "IMPORTANT", "URGENT", "VERY", "REALLY", "NOW", "TODAY", "EVERYONE", "ALL", "NEVER", "ALWAYS", "MUST", "NOTE", "FREE", "SOON", "ASAP"]
        for m in TextUtil.matches("\\b[A-Z]{3,}\\b", in: text, caseInsensitive: false) {
            let o = TextUtil.substring(text, m.range)
            guard shouty.contains(o), o != "ASAP" else { continue }
            // Skip lines written entirely in capitals (headings).
            let line = (text as NSString).lineRange(for: m.range)
            let lt = TextUtil.substring(text, line)
            if lt == lt.uppercased() { continue }
            out.append(Issue(range: m.range, original: o, replacements: [o.lowercased()], group: .delivery,
                             kind: "Style/Formatting/AllCaps", title: "All capitals",
                             explanation: "Words in all capitals read like shouting. Use bold or rephrase for emphasis."))
        }
        // Greeting without a comma ("Hi Team" on its own line).
        for m in TextUtil.matches("(?m)^(Hi|Hello|Hey|Dear|Good morning|Good afternoon|Good evening)( [A-Z][\\w.]*(?: [A-Z][\\w.]*){0,3})?(?=[ \\t]*$)", in: text, caseInsensitive: false) {
            let o = TextUtil.substring(text, m.range)
            out.append(Issue(range: m.range, original: o, replacements: [o + ","], group: .correctness,
                             kind: "Punctuation/GreetingComma", title: "Missing comma",
                             explanation: "Put a comma after a greeting: “Hi Team,”."))
        }
        // Sentence capitalization and closing punctuation.
        for s in TextUtil.sentences(text) {
            guard let first = s.text.first(where: { $0.isLetter }) else { continue }
            let prefix = s.text.prefix(while: { !$0.isLetter })
            if first.isLowercase, !prefix.contains("\""), !s.text.hasPrefix("http") {
                let loc = s.range.location + (String(prefix) as NSString).length
                let r = NSRange(location: loc, length: 1)
                out.append(Issue(range: r, original: String(first), replacements: [first.uppercased()], group: .correctness,
                                 kind: "Style/Formatting/LowerCaseSentenceStart", title: "Capitalization",
                                 explanation: "Start every sentence with a capital letter."))
            }
            if let last = s.text.last, last.isLetter || last.isNumber, s.text.split(separator: " ").count >= 4,
               NSMaxRange(s.range) >= (text as NSString).length || TextUtil.substring(text, NSRange(location: NSMaxRange(s.range), length: 1)).first?.isNewline == true {
                let w = TextUtil.words(s.text).last?.text ?? String(last)
                let r = NSRange(location: NSMaxRange(s.range) - (w as NSString).length, length: (w as NSString).length)
                let isQ = ["who", "what", "when", "where", "why", "how", "do", "does", "did", "can", "could", "would", "will", "is", "are", "should"]
                    .contains(s.text.split(separator: " ").first.map { $0.lowercased() } ?? "")
                out.append(Issue(range: r, original: w, replacements: [w + (isQ ? "?" : ".")], group: .correctness,
                                 kind: "Punctuation/MissingEnd", title: "Missing end punctuation",
                                 explanation: isQ ? "This looks like a question; end it with a question mark." : "End the sentence with a period."))
            }
        }
        return out
    }

    // MARK: Sentence structure: run-ons, comma splices, fragments, modifiers

    static func structure(_ text: String) -> [Issue] {
        var out: [Issue] = []
        let subj = "(i|you|he|she|it|we|they|this|that|there)"
        for s in TextUtil.sentences(text) {
            let words = s.text.split(whereSeparator: { $0.isWhitespace })
            // Comma splice: ", <pronoun> <verb>" joining two clauses.
            for m in TextUtil.matches("(?<=\\w), " + subj + " ([a-z']+)\\b", in: s.text) {
                let lead = TextUtil.substring(s.text, NSRange(location: 0, length: m.range.location)).lowercased()
                let verb = TextUtil.substring(s.text, m.range(at: 2))
                guard isVerb(verb, in: s.text, at: m.range(at: 2).location), hasVerb(lead) else { continue }
                if ["if ", "when ", "because ", "although ", "while ", "since ", "after ", "before ", "though ", "unless ", "as "].contains(where: { lead.hasPrefix($0) || lead.contains(" " + $0) }) { continue }
                if lead.contains(" and ") || lead.contains(" but ") || lead.split(separator: " ").count < 3 { continue }
                // Introductory phrases ("Running late this morning, I…", "Regardless of the cost, we…") aren't clauses.
                let clause = lead.components(separatedBy: ", ").last ?? lead
                let firstWord = clause.split(separator: " ").first.map(String.init) ?? ""
                let intro: Set<String> = ["in", "on", "at", "by", "for", "with", "without", "after", "before", "during", "despite", "regardless", "irregardless", "according", "unlike", "like", "as", "to", "from", "since", "until", "upon", "of", "thanks", "due", "given", "once", "even", "although", "though", "whether", "having", "being"]
                if intro.contains(firstWord) || firstWord.hasSuffix("ing") || firstWord.hasSuffix("ly") || firstWord.hasSuffix("ed") { continue }
                guard TextUtil.matches("\\b(i|you|he|she|it|we|they|this|that|there|[a-z]+s?) (am|is|are|was|were|have|has|had|will|can|could|would|should|did|do|does|[a-z]+ed|[a-z]+s)\\b", in: clause).count > 0 else { continue }
                let r = NSRange(location: s.range.location + m.range.location, length: 2)
                let next = TextUtil.substring(s.text, NSRange(location: m.range.location + 2, length: m.range.length - 2))
                out.append(Issue(range: NSRange(location: r.location, length: m.range.length), original: ", " + next,
                                 replacements: [". " + (next.lowercased().hasPrefix("i ") ? next : next.prefix(1).uppercased() + next.dropFirst()), "; " + next, ", and " + next],
                                 group: .correctness, kind: "Punctuation/CommaSplice", title: "Comma splice",
                                 explanation: "Two complete sentences are joined only by a comma. Use a period, a semicolon, or add a conjunction."))
            }
            // Run-on: long sentence with little punctuation.
            let commas = s.text.filter { ",;:—".contains($0) }.count
            if words.count >= 35, commas <= 1 {
                out.append(Issue(range: s.range, original: s.text, replacements: [], group: .correctness,
                                 kind: "Grammar/RunOn", title: "Run-on sentence",
                                 explanation: "This sentence is \(words.count) words long with almost no punctuation. Split it into shorter sentences, or use AI Rewrite."))
            } else if words.count >= 30 {
                out.append(Issue(range: s.range, original: s.text, replacements: [], group: .clarity,
                                 kind: "Style/Clarity/LongSentence", title: "Long sentence",
                                 explanation: "Sentences over 30 words are hard to follow. Try splitting this one."))
            }
            // Fragment: no verb.
            let greeting = TextUtil.matches("^(hi|hey|hello|dear|thanks|thank you|cheers|best|regards|sincerely|good (morning|afternoon|evening)|congrats|congratulations|welcome|great job|well done|happy \\w+|ok|okay|yes|no|sure)\\b", in: s.text).count > 0
            if words.count >= 2, words.count <= 12, !greeting, !s.text.hasSuffix("!"), !hasVerb(s.text),
               !words.dropFirst().contains(where: { let w = $0.lowercased().trimmingCharacters(in: .punctuationCharacters); return w.hasSuffix("ed") || w.hasSuffix("es") || ["is", "are", "was", "were", "has", "had", "am"].contains(w) }), !s.text.hasSuffix(":"), !s.text.hasSuffix("?"),
               !s.text.hasPrefix("-"), !s.text.hasPrefix("•"), s.text.last.map({ ".!".contains($0) }) == true {
                out.append(Issue(range: s.range, original: s.text, replacements: [], group: .correctness,
                                 kind: "Grammar/Fragment", title: "Sentence fragment",
                                 explanation: "This sentence seems to be missing a verb. Join it to the sentence before, or complete it."))
            }
            if words.count >= 3, let f = words.first?.lowercased(),
               ["because", "although", "since", "unless", "whereas", "while"].contains(f), !s.text.contains(","), words.count < 9 {
                out.append(Issue(range: s.range, original: s.text, replacements: [], group: .correctness,
                                 kind: "Grammar/Fragment", title: "Sentence fragment",
                                 explanation: "A sentence that starts with “\(f)” needs a main clause. Connect it to the sentence before or after."))
            }
            // Dangling modifier: "Walking to the store, the rain ..." – introductory -ing/-ed phrase followed by a non-person subject.
            if let m = TextUtil.matches("^((?:after |while |when )?[A-Za-z]+(?:ing|ed)\\b[^,]{2,60}), (the|a|an|it|there|my|his|her|our|their) ([a-z]+)", in: s.text).first {
                let noun = TextUtil.substring(s.text, m.range(at: 3)).lowercased()
                let people: Set<String> = ["man", "woman", "boy", "girl", "teacher", "student", "team", "manager", "dog", "cat", "kids", "people", "doctor", "driver", "author", "writer", "user", "customer", "child", "family", "group", "staff", "players"]
                if !people.contains(noun) {
                    out.append(Issue(range: s.range, original: s.text, replacements: [], group: .clarity,
                                     kind: "Grammar/DanglingModifier", title: "Possible dangling modifier",
                                     explanation: "The opening phrase should describe the subject that comes right after the comma (“\(noun)”). Make sure the right person or thing is doing the action."))
                }
            }
            for m in TextUtil.matches("\\b(only) (\\w+ed|said|had|ate|got|saw)\\b", in: s.text) {
                let r = NSRange(location: s.range.location + m.range.location, length: m.range.length)
                out.append(Issue(range: r, original: TextUtil.substring(text, r), replacements: [], group: .clarity,
                                 kind: "Grammar/MisplacedModifier", title: "Misplaced modifier",
                                 explanation: "“Only” modifies the word right after it. Place it directly before the word it limits (e.g., “ate only two” rather than “only ate two”)."))
            }
        }
        return out
    }

    static func isVerb(_ word: String, in sentence: String, at utf16Offset: Int) -> Bool {
        let common: Set<String> = ["am", "is", "are", "was", "were", "have", "has", "had", "will", "can", "did", "do", "does", "should", "would", "could", "might", "must"]
        if common.contains(word.lowercased()) { return true }
        let t = NLTagger(tagSchemes: [.lexicalClass])
        t.string = sentence
        guard let r = Range(NSRange(location: utf16Offset, length: 0), in: sentence) else { return false }
        let (tag, _) = t.tag(at: r.lowerBound, unit: .word, scheme: .lexicalClass)
        return tag == .verb
    }

    static func hasVerb(_ sentence: String) -> Bool {
        let t = NLTagger(tagSchemes: [.lexicalClass])
        t.string = sentence
        var found = false
        t.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, _ in
            if tag == .verb { found = true; return false }
            return true
        }
        return found
    }

    // MARK: De-duplication

    /// Email addresses, URLs, @mentions, #tags, file paths and code are never checked.
    static func protectedRanges(_ text: String) -> [NSRange] {
        let patterns = [
            "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
            "\\b(?:https?://|www\\.)[^\\s<>\"]+",
            "\\b[A-Za-z0-9-]+\\.(?:com|org|net|io|ai|co|dev|app|edu|gov|us|uk|ca|de|fr|me|info|biz)(?:/[^\\s]*)?\\b",
            "(?<![\\w])[@#][A-Za-z0-9_.-]+",
            "`[^`\\n]+`",
            "(?:~|\\.{1,2})?/[A-Za-z0-9._/-]+",
        ]
        return patterns.flatMap { TextUtil.matches($0, in: text).map(\.range) }
    }

    static func dedupe(_ issues: [Issue], text: String, o: CheckOptions) -> [Issue] {
        let protected = protectedRanges(text)
        let issues = issues.filter { i in i.range.length > 40 || !protected.contains { NSIntersectionRange($0, i.range).length > 0 } }
        let priority: [IssueGroup: Int] = [.correctness: 0, .clarity: 1, .delivery: 2, .engagement: 3]
        let sorted = issues.sorted {
            if priority[$0.group]! != priority[$1.group]! { return priority[$0.group]! < priority[$1.group]! }
            if ($0.source == .system) != ($1.source == .system) { return $0.source != .system }
            return $0.range.length < $1.range.length
        }
        var kept: [Issue] = []
        for i in sorted {
            guard i.range.length > 0, NSMaxRange(i.range) <= (text as NSString).length else { continue }
            if i.replacements.first == i.original { continue }
            // Keep sentence-level hints even when they contain smaller issues.
            let wide = i.range.length > 40
            let clash = kept.contains { k in
                let kWide = k.range.length > 40
                if wide != kWide { return false }
                return NSIntersectionRange(k.range, i.range).length > 0
            }
            if !clash { kept.append(i) }
        }
        return kept.sorted { $0.range.location < $1.range.location }
    }
}
