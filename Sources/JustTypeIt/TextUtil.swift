// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation
import NaturalLanguage

struct Span {
    var range: NSRange
    var text: String
}

enum TextUtil {

    static func sentences(_ text: String) -> [Span] {
        spans(text, unit: .sentence)
    }

    static func paragraphs(_ text: String) -> [Span] {
        spans(text, unit: .paragraph)
    }

    static func words(_ text: String) -> [Span] {
        spans(text, unit: .word)
    }

    private static func spans(_ text: String, unit: NLTokenUnit) -> [Span] {
        let tok = NLTokenizer(unit: unit)
        tok.string = text
        var out: [Span] = []
        tok.enumerateTokens(in: text.startIndex..<text.endIndex) { r, _ in
            let ns = NSRange(r, in: text)
            let s = String(text[r])
            // Trim trailing whitespace/newlines from the span.
            let trimmed = s.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            let lead = s.count - s.drop(while: { $0.isWhitespace }).count
            let core = String(trimmed.dropFirst(lead))
            if !core.isEmpty {
                let start = ns.location + (s.prefix(lead) as Substring).utf16.count
                out.append(Span(range: NSRange(location: start, length: core.utf16.count), text: core))
            }
            return true
        }
        return out
    }

    /// Regex matches (case-insensitive by default) with capture groups.
    static func matches(_ pattern: String, in text: String, caseInsensitive: Bool = true) -> [NSTextCheckingResult] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else {
            return []
        }
        return re.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    static func substring(_ text: String, _ r: NSRange) -> String {
        guard r.location != NSNotFound, NSMaxRange(r) <= (text as NSString).length else { return "" }
        return (text as NSString).substring(with: r)
    }

    /// Copies the capitalization pattern of `source` onto `target`.
    static func matchCase(_ target: String, like source: String) -> String {
        guard let f = source.first, !target.isEmpty else { return target }
        if source.count > 1, source == source.uppercased(), source != source.lowercased() { return target.uppercased() }
        if f.isUppercase { return target.prefix(1).uppercased() + target.dropFirst() }
        return target
    }

    static func wordCount(_ text: String) -> Int {
        var n = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in n += 1 }
        return n
    }

    static func syllables(_ word: String) -> Int {
        let w = word.lowercased().filter(\.isLetter)
        guard !w.isEmpty else { return 0 }
        if w.count <= 3 { return 1 }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var count = 0
        var prevVowel = false
        for ch in w {
            let v = vowels.contains(ch)
            if v && !prevVowel { count += 1 }
            prevVowel = v
        }
        if w.hasSuffix("e"), !w.hasSuffix("le"), count > 1 { count -= 1 }
        if w.hasSuffix("es") || w.hasSuffix("ed"), count > 1, !w.hasSuffix("ted"), !w.hasSuffix("ded") { count -= 1 }
        return max(1, count)
    }

    static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "if", "of", "to", "in", "on", "at", "for", "with", "by", "from", "as",
        "is", "are", "was", "were", "be", "been", "being", "it", "its", "this", "that", "these", "those", "i", "you",
        "he", "she", "we", "they", "me", "him", "her", "us", "them", "my", "your", "his", "our", "their", "not", "no",
        "so", "do", "does", "did", "have", "has", "had", "will", "would", "can", "could", "should", "may", "might",
        "must", "there", "here", "what", "which", "who", "whom", "when", "where", "why", "how", "all", "any", "some",
        "than", "then", "also", "just", "about", "into", "over", "after", "before", "up", "out", "more", "most",
    ]
}
