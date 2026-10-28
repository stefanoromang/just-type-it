// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation

/// Word-level diff used to turn an AI-corrected sentence into individual, clickable suggestions.
enum WordDiff {

    struct Change {
        var range: NSRange      // in the original string (UTF-16)
        var replacement: String
    }

    struct Token {
        var text: String
        var range: NSRange
    }

    /// Words and punctuation marks as separate tokens.
    static func tokens(_ s: String) -> [Token] {
        TextUtil.matches("[\\p{L}\\p{N}'’-]+|[^\\s\\p{L}\\p{N}]", in: s, caseInsensitive: false).map {
            Token(text: TextUtil.substring(s, $0.range), range: $0.range)
        }
    }

    static func changes(from a: String, to b: String, merged: Bool = true) -> [Change] {
        let ta = tokens(a), tb = tokens(b)
        let n = ta.count, m = tb.count
        guard n > 0, m > 0, n * m < 250_000 else { return [] }
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = ta[i].text == tb[j].text ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        // Walk the table, collecting runs of removed (from a) and inserted (from b) tokens.
        var out: [Change] = []
        var i = 0, j = 0
        var delA: [Int] = [], insB: [Int] = []
        func flush() {
            guard !delA.isEmpty || !insB.isEmpty else { return }
            let rep = insB.isEmpty ? "" : (b as NSString).substring(with: NSRange(location: tb[insB.first!].range.location,
                                                                                    length: NSMaxRange(tb[insB.last!].range) - tb[insB.first!].range.location))
            var range: NSRange
            var replacement = rep
            if delA.isEmpty {
                // Pure insertion: attach to the previous token so the user sees context.
                let anchor = max(0, i - 1)
                guard anchor < ta.count else { delA = []; insB = []; return }
                range = ta[anchor].range
                let isPunct = rep.first.map { !$0.isLetter && !$0.isNumber } ?? false
                replacement = ta[anchor].text + (isPunct ? "" : " ") + rep
                if i == 0 { range = ta[0].range; replacement = rep + " " + ta[0].text }
            } else {
                range = NSRange(location: ta[delA.first!].range.location, length: NSMaxRange(ta[delA.last!].range) - ta[delA.first!].range.location)
                if insB.isEmpty {
                    // Deletion: include one adjacent space.
                    if range.location > 0, (a as NSString).substring(with: NSRange(location: range.location - 1, length: 1)) == " " {
                        range = NSRange(location: range.location - 1, length: range.length + 1)
                    }
                }
            }
            out.append(Change(range: range, replacement: replacement))
            delA = []; insB = []
        }
        while i < n || j < m {
            if i < n, j < m, ta[i].text == tb[j].text {
                flush(); i += 1; j += 1
            } else if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
                insB.append(j); j += 1
            } else {
                delA.append(i); i += 1
            }
        }
        flush()
        return merged ? merge(out, in: a) : out
    }

    /// Joins edits separated by one or two short words so a list fix reads as one suggestion
    /// ("colors and your size and address" → "colors, your size, and address").
    static func merge(_ changes: [Change], in a: String) -> [Change] {
        guard changes.count > 1 else { return changes }
        let ns = a as NSString
        var out: [Change] = [changes[0]]
        for c in changes.dropFirst() {
            let prev = out[out.count - 1]
            let gapStart = NSMaxRange(prev.range)
            guard c.range.location >= gapStart else { out.append(c); continue }
            let gap = ns.substring(with: NSRange(location: gapStart, length: c.range.location - gapStart))
            let gapWords = gap.split(whereSeparator: { $0.isWhitespace }).count
            if gapWords <= 3, !gap.contains(where: { ".!?\n".contains($0) }) {
                let range = NSRange(location: prev.range.location, length: NSMaxRange(c.range) - prev.range.location)
                out[out.count - 1] = Change(range: range, replacement: prev.replacement + gap + c.replacement)
            } else {
                out.append(c)
            }
        }
        return out
    }
}
