// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation

// MARK: Originality (plagiarism) check

struct OriginalityMatch: Identifiable, Hashable {
    var id = UUID()
    var range: NSRange
    var passage: String
    var source: String
    var similarity: Double
}

struct OriginalityReport {
    var matches: [OriginalityMatch] = []
    var originalPercent = 100.0
    var checkedSources = 0
    var notes: [String] = []
}

enum Originality {

    static func shingles(_ text: String, n: Int = 5) -> Set<String> {
        let w = text.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init)
        guard w.count >= n else { return w.isEmpty ? [] : [w.joined(separator: " ")] }
        return Set((0...(w.count - n)).map { w[$0..<($0 + n)].joined(separator: " ") })
    }

    /// Compares each sentence of `text` with every source (pasted text, fetched web pages, other documents).
    static func compare(_ text: String, sources: [(name: String, text: String)]) -> OriginalityReport {
        var rep = OriginalityReport()
        rep.checkedSources = sources.count
        let srcShingles = sources.map { ($0.name, shingles($0.text)) }
        var flaggedWords = 0
        let total = max(1, TextUtil.wordCount(text))
        for s in TextUtil.sentences(text) where TextUtil.wordCount(s.text) >= 6 {
            let sh = shingles(s.text)
            guard !sh.isEmpty else { continue }
            var best: (String, Double)?
            for (name, ss) in srcShingles {
                let sim = Double(sh.intersection(ss).count) / Double(sh.count)
                if sim > (best?.1 ?? 0) { best = (name, sim) }
            }
            if let best, best.1 >= 0.35 {
                rep.matches.append(OriginalityMatch(range: s.range, passage: s.text, source: best.0, similarity: best.1))
                flaggedWords += TextUtil.wordCount(s.text)
            }
        }
        rep.originalPercent = max(0, 100 - Double(flaggedWords) / Double(total) * 100)
        return rep
    }

    /// Downloads a web page and returns its visible text.
    static func fetchText(_ url: URL) async -> String? {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req), let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        return htmlToText(html)
    }

    static func htmlToText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "(?is)<(script|style|noscript|svg|head)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>|</h\\d>|</li>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: "&#(\\d+);", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n\\s*\\n+", with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Searches the web for exact sentences (DuckDuckGo HTML results) and compares the text with the pages found.
    static func webCheck(_ text: String, maxQueries: Int = 6, progress: @escaping (String) -> Void) async -> OriginalityReport {
        let candidates = TextUtil.sentences(text)
            .map(\.text)
            .filter { TextUtil.wordCount($0) >= 8 }
            .sorted { $0.count > $1.count }
            .prefix(maxQueries)
        var urls: [URL] = []
        var notes: [String] = []
        for (i, s) in candidates.enumerated() {
            progress("Searching the web (\(i + 1)/\(candidates.count))…")
            let q = "\"" + String(s.prefix(150)) + "\""
            var comps = URLComponents(string: "https://html.duckduckgo.com/html/")!
            comps.queryItems = [URLQueryItem(name: "q", value: q)]
            guard let u = comps.url, let html = await rawFetch(u) else { notes.append("A web search failed; check your connection."); continue }
            for m in TextUtil.matches("uddg=([^&\"]+)", in: html) {
                let enc = TextUtil.substring(html, m.range(at: 1))
                if let dec = enc.removingPercentEncoding, let url = URL(string: dec), url.scheme?.hasPrefix("http") == true,
                   !urls.contains(url), !(url.host ?? "").contains("duckduckgo") {
                    urls.append(url)
                    if urls.count >= 12 { break }
                }
            }
        }
        var sources: [(String, String)] = []
        for (i, u) in urls.prefix(10).enumerated() {
            progress("Comparing with sources (\(i + 1)/\(min(urls.count, 10)))…")
            if let t = await fetchText(u), t.count > 200 { sources.append((u.absoluteString, t)) }
        }
        var rep = compare(text, sources: sources)
        if candidates.isEmpty { notes.append("The text is too short for a web search. Write a few longer sentences.") }
        if urls.isEmpty, !candidates.isEmpty { notes.append("No matching pages were found on the web.") }
        rep.notes = notes
        return rep
    }

    static func rawFetch(_ url: URL) async -> String? {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (d, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

// MARK: AI-text detection (statistical signals)

struct AIDetection {
    var score: Double           // 0 = human-like, 1 = AI-like
    var signals: [String]

    var label: String {
        switch score {
        case ..<0.35: "Likely human-written"
        case 0.35..<0.6: "Mixed signals"
        default: "Likely AI-generated"
        }
    }

    static let stockPhrases = [
        "delve", "in today's fast-paced", "it is important to note", "in conclusion", "furthermore", "moreover",
        "a testament to", "navigate the complexities", "tapestry", "in the realm of", "unlock the potential",
        "plays a crucial role", "it's worth noting", "seamless", "leverage", "robust", "ever-evolving", "embark",
        "holistic", "game-changer", "foster", "paramount", "multifaceted", "pivotal", "in summary", "overall,",
        "whether you're", "elevate", "harness", "landscape", "underscore", "intricate",
    ]

    static func analyze(_ text: String) -> AIDetection {
        let sents = TextUtil.sentences(text).map { Double(TextUtil.wordCount($0.text)) }.filter { $0 > 0 }
        var signals: [String] = []
        guard sents.count >= 3 else { return AIDetection(score: 0, signals: ["Write at least three sentences for a meaningful estimate."]) }
        let mean = sents.reduce(0, +) / Double(sents.count)
        let sd = sqrt(sents.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(sents.count))
        let burst = sd / max(1, mean)
        var score = 0.0
        if burst < 0.3 { score += 0.35; signals.append("Sentence lengths are very uniform (low “burstiness”).") }
        else if burst < 0.45 { score += 0.15; signals.append("Sentence lengths are fairly uniform.") }
        else { signals.append("Sentence lengths vary naturally, like human writing.") }
        let lower = text.lowercased()
        let hits = stockPhrases.filter { lower.contains($0) }
        let words = Double(max(1, TextUtil.wordCount(text)))
        let density = Double(hits.count) / (words / 100)
        if density > 1.5 { score += 0.35 } else if density > 0.6 { score += 0.2 }
        if !hits.isEmpty { signals.append("Common AI phrasing: " + hits.prefix(6).map { "“\($0)”" }.joined(separator: ", ") + ".") }
        let personal = TextUtil.matches("\\b(I|my|me|we|our)\\b", in: text, caseInsensitive: false).count
        if personal == 0 { score += 0.1; signals.append("No personal voice (no I/my/we).") } else { signals.append("Uses a personal voice.") }
        let contractions = TextUtil.matches("\\b\\w+'(t|s|re|ll|ve|d|m)\\b", in: text).count
        if contractions == 0, words > 80 { score += 0.1; signals.append("No contractions in a long text.") }
        let digits = TextUtil.matches("\\d", in: text).count
        if digits == 0, words > 120 { score += 0.05; signals.append("No concrete numbers or specifics.") }
        let typos = text.contains("  ") || TextUtil.matches("\\bi\\b", in: text, caseInsensitive: false).count > 0
        if typos { score -= 0.1; signals.append("Small human quirks (spacing, casing).") }
        return AIDetection(score: max(0, min(1, score)), signals: signals)
    }
}

// MARK: Citations

enum CitationStyle: String, CaseIterable, Identifiable {
    case apa = "APA 7", mla = "MLA 9", chicago = "Chicago"
    var id: String { rawValue }
}

struct CitationSource {
    var authors = ""        // "Jane Doe; John Smith"
    var title = ""
    var container = ""      // website / journal / publisher
    var year = ""
    var month = ""
    var day = ""
    var url = ""
    var accessed = Date()

    var authorList: [(first: String, last: String)] {
        authors.components(separatedBy: CharacterSet(charactersIn: ";\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { full in
                if full.contains(",") {
                    let p = full.components(separatedBy: ",")
                    return (p.dropFirst().joined(separator: ",").trimmingCharacters(in: .whitespaces), p[0].trimmingCharacters(in: .whitespaces))
                }
                let p = full.split(separator: " ")
                return (p.dropLast().joined(separator: " "), String(p.last ?? ""))
            }
    }

    func format(_ style: CitationStyle) -> String {
        let a = authorList
        let df = DateFormatter()
        df.dateFormat = "d MMM. yyyy"
        let accessed = df.string(from: self.accessed)
        let t = title.isEmpty ? "Untitled" : title
        let y = year.isEmpty ? "n.d." : year
        switch style {
        case .apa:
            let names: String = {
                let f = a.map { n in "\(n.last), " + n.first.split(separator: " ").map { "\($0.prefix(1))." }.joined(separator: " ") }
                switch f.count {
                case 0: return ""
                case 1: return f[0]
                case 2: return "\(f[0]), & \(f[1])"
                default: return f.dropLast().joined(separator: ", ") + ", & " + f.last!
                }
            }()
            let date = [y, month, day].filter { !$0.isEmpty }.joined(separator: ", ")
            var s = names.isEmpty ? "\(t). (\(date))." : "\(names) (\(date)). \(t)."
            if !container.isEmpty { s += " \(container)." }
            if !url.isEmpty { s += " \(url)" }
            return s
        case .mla:
            var names = ""
            if a.count == 1 { names = "\(a[0].last), \(a[0].first). " }
            else if a.count == 2 { names = "\(a[0].last), \(a[0].first), and \(a[1].first) \(a[1].last). " }
            else if a.count > 2 { names = "\(a[0].last), \(a[0].first), et al. " }
            var s = names + "“\(t).” "
            if !container.isEmpty { s += "*\(container)*, " }
            let date = [day, month, year].filter { !$0.isEmpty }.joined(separator: " ")
            if !date.isEmpty { s += "\(date), " }
            if !url.isEmpty { s += url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "") + ". " }
            s += "Accessed \(accessed)."
            return s.replacingOccurrences(of: ", Accessed", with: ". Accessed")
        case .chicago:
            var names = ""
            if a.count == 1 { names = "\(a[0].last), \(a[0].first). " }
            else if a.count >= 2 {
                names = "\(a[0].last), \(a[0].first), " + a.dropFirst().dropLast().map { "\($0.first) \($0.last), " }.joined() + "and \(a.last!.first) \(a.last!.last). "
            }
            var s = names + "“\(t).” "
            if !container.isEmpty { s += "\(container). " }
            let date = [month, day].filter { !$0.isEmpty }.joined(separator: " ")
            s += date.isEmpty ? "\(y). " : "\(date), \(y). "
            if !url.isEmpty { s += "\(url)." }
            return s.trimmingCharacters(in: .whitespaces)
        }
    }

    func inText(_ style: CitationStyle) -> String {
        let a = authorList
        let lead: String = {
            switch a.count {
            case 0: return "“\(title.prefix(30))”"
            case 1: return a[0].last
            case 2: return style == .apa ? "\(a[0].last) & \(a[1].last)" : "\(a[0].last) and \(a[1].last)"
            default: return "\(a[0].last) et al."
            }
        }()
        switch style {
        case .apa: return "(\(lead), \(year.isEmpty ? "n.d." : year))"
        case .mla: return "(\(lead))"
        case .chicago: return "(\(lead) \(year.isEmpty ? "n.d." : year))"
        }
    }

    /// Fills fields from a web page's metadata.
    static func fromURL(_ url: URL) async -> CitationSource {
        var c = CitationSource(url: url.absoluteString)
        guard let html = await Originality.rawFetch(url) else { return c }
        func meta(_ names: [String]) -> String? {
            for n in names {
                for p in ["<meta[^>]+(?:name|property)=[\"']\(n)[\"'][^>]+content=[\"']([^\"']+)[\"']",
                          "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:name|property)=[\"']\(n)[\"']"] {
                    if let m = TextUtil.matches(p, in: html).first { return Originality.htmlToText(TextUtil.substring(html, m.range(at: 1))) }
                }
            }
            return nil
        }
        c.title = meta(["og:title", "citation_title", "twitter:title", "dc.title"])
            ?? TextUtil.matches("<title[^>]*>([^<]+)</title>", in: html).first.map { Originality.htmlToText(TextUtil.substring(html, $0.range(at: 1))) } ?? ""
        c.container = meta(["og:site_name", "citation_journal_title", "application-name"]) ?? (url.host ?? "").replacingOccurrences(of: "www.", with: "")
        c.authors = meta(["citation_author", "author", "article:author", "dc.creator"]) ?? ""
        if c.authors.hasPrefix("http") { c.authors = "" }
        if let d = meta(["citation_publication_date", "article:published_time", "date", "dc.date", "citation_date"]) {
            let parts = d.prefix(10).split(separator: "-")
            if let y = parts.first, y.count == 4 { c.year = String(y) }
            if parts.count >= 2, let mi = Int(parts[1]), (1...12).contains(mi) { c.month = DateFormatter().monthSymbols[mi - 1] }
            if parts.count >= 3, let di = Int(parts[2]) { c.day = String(di) }
        }
        return c
    }
}
