// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation
import NaturalLanguage

/// Proactive help: safe autocorrect as you type, tone at a glance, and a pre-send check.
enum Proactive {

    // MARK: Autocorrect

    /// Only unambiguous typos are fixed automatically; anything that could be intentional stays a suggestion.
    static let autocorrections: [String: String] = [
        "teh": "the", "adn": "and", "taht": "that", "thier": "their", "recieve": "receive", "recieved": "received",
        "definately": "definitely", "seperate": "separate", "occured": "occurred", "untill": "until", "wich": "which",
        "tommorow": "tomorrow", "tomorow": "tomorrow", "accomodate": "accommodate", "acheive": "achieve", "beleive": "believe",
        "calender": "calendar", "collegue": "colleague", "enviroment": "environment", "goverment": "government",
        "immediatly": "immediately", "independant": "independent", "knowlege": "knowledge", "neccessary": "necessary",
        "occassion": "occasion", "publically": "publicly", "recomend": "recommend", "sincerly": "sincerely",
        "succesful": "successful", "suprise": "surprise", "truely": "truly", "wierd": "weird", "buisness": "business",
        "managment": "management", "alot": "a lot", "becuase": "because", "freind": "friend", "goign": "going",
        "hte": "the", "jsut": "just", "knwo": "know", "realy": "really", "thanx": "thanks", "waht": "what", "yuor": "your",
        "dont": "don't", "didnt": "didn't", "doesnt": "doesn't", "isnt": "isn't",
        "wasnt": "wasn't", "arent": "aren't", "werent": "weren't", "shouldnt": "shouldn't", "couldnt": "couldn't",
        "wouldnt": "wouldn't", "havent": "haven't", "hasnt": "hasn't", "youre": "you're", "theyre": "they're",
        "thats": "that's", "whats": "what's", "im": "I'm", "i": "I",
    ]

    /// Real words that look like typos ("ill", "wont", "cant", "id", "ive") are never auto-changed;
    /// they're left to the grammar checker, which shows a suggestion instead.
    static let ambiguous: Set<String> = []

    struct Correction: Equatable {
        var range: NSRange
        var original: String
        var replacement: String
    }

    /// Looks at the word just finished before `caret` (the user typed a space or punctuation).
    /// Returns a correction only for unambiguous typos, preserving capitalization.
    static func autocorrect(_ text: String, caret: Int, dictionary: Set<String> = []) -> Correction? {
        let ns = text as NSString
        guard caret > 1, caret <= ns.length else { return nil }
        let trigger = ns.substring(with: NSRange(location: caret - 1, length: 1))
        guard trigger == " " || ",.;:!?\n".contains(trigger) else { return nil }
        var start = caret - 1
        while start > 0 {
            let ch = ns.substring(with: NSRange(location: start - 1, length: 1))
            if ch.rangeOfCharacter(from: .letters) == nil && ch != "'" { break }
            start -= 1
        }
        let range = NSRange(location: start, length: caret - 1 - start)
        guard range.length > 0 else { return nil }
        let word = ns.substring(with: range)
        let lower = word.lowercased()
        // Abbreviations: "i.e.", "e.g.", "U.S." — a letter right before or after a period isn't a word end.
        if start > 0, ns.substring(with: NSRange(location: start - 1, length: 1)) == "." { return nil }
        if trigger == ".", caret < ns.length, ns.substring(with: NSRange(location: caret, length: 1)).rangeOfCharacter(from: .letters) != nil { return nil }
        if trigger == ".", word.count == 1 { return nil }
        guard !dictionary.contains(lower), let fix = autocorrections[lower] else { return nil }
        // Skip words inside URLs, emails, @mentions, file paths and code.
        if start > 0 {
            let before = ns.substring(with: NSRange(location: start - 1, length: 1))
            if "@#/\\._-`".contains(before) { return nil }
        }
        if ambiguous.contains(lower) {
            // "Ill" at the start of a sentence or "wont" capitalized might be intentional; only fix lowercase forms mid-sentence.
            guard word == lower, start > 0 else { return nil }
        }
        if word == "I" || fix == word { return nil }
        let replacement = fix == "I" || fix.hasPrefix("I'") ? fix : TextUtil.matchCase(fix, like: word)
        return Correction(range: range, original: word, replacement: replacement)
    }

    // MARK: Tone at a glance

    static func toneEmoji(_ text: String) -> (emoji: String, label: String)? {
        guard TextUtil.wordCount(text) >= 12 else { return nil }
        // Tone word lists are English.
        if let l = NLLanguageRecognizer.dominantLanguage(for: text), l != .english { return nil }
        let tones = Metrics.detectTone(text).0
        guard let top = tones.first else { return nil }
        return (top.emoji, top.name)
    }

    // MARK: Before you send

    struct SendWarning: Equatable {
        var title: String
        var detail: String
    }

    /// Checks a message before it goes out: unfixed errors, missing attachment, harsh tone, missing greeting/sign-off.
    static func preSendWarnings(_ text: String, issues: [Issue]) -> [SendWarning] {
        var out: [SendWarning] = []
        let errors = issues.filter { $0.group == .correctness }.count
        if errors > 0 {
            out.append(SendWarning(title: "\(errors) correctness issue\(errors == 1 ? "" : "s")", detail: "Spelling, grammar or punctuation mistakes are still in this message."))
        }
        let lower = text.lowercased()
        if TextUtil.matches("\\b(attached|attachment|i've attached|please find attached|see attached|enclosed)\\b", in: lower).count > 0 {
            out.append(SendWarning(title: "Mentions an attachment", detail: "Make sure the file is actually attached before sending."))
        }
        let harsh = ["unacceptable", "ridiculous", "stupid", "incompetent", "useless", "as i already said", "per my last email", "obviously", "for the last time", "i told you"]
        if let h = harsh.first(where: { lower.contains($0) }) {
            out.append(SendWarning(title: "Tone may come across as harsh", detail: "“\(h)” can read as frustrated or blunt. Consider a softer phrasing."))
        }
        let shouting = TextUtil.matches("\\b[A-Z]{4,}\\b", in: text, caseInsensitive: false).filter {
            !["ASAP", "FYI", "HTML", "JSON", "NASA", "UNICEF", "COVID"].contains(TextUtil.substring(text, $0.range))
        }.count
        if shouting >= 2 {
            out.append(SendWarning(title: "Several words in capitals", detail: "Words in all capitals can read like shouting."))
        }
        if TextUtil.wordCount(text) > 250 {
            out.append(SendWarning(title: "Long message", detail: "This is over 250 words. Consider leading with the key point or using bullets."))
        }
        return out
    }
}
