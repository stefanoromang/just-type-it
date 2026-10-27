// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation
import NaturalLanguage

struct ToneReading: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var emoji: String
    var strength: Double
}

struct Metrics {
    var words = 0
    var characters = 0
    var sentences = 0
    var paragraphs = 0
    var readingTime = 0.0   // minutes
    var speakingTime = 0.0  // minutes
    var avgWordLength = 0.0
    var avgSentenceLength = 0.0
    var readability = 0.0   // Flesch reading ease 0–100
    var gradeLevel = 0.0    // Flesch–Kincaid grade
    var uniqueWords = 0.0   // vocabulary variety %
    var rareWords = 0.0     // % of long words
    var overall = 100
    var groupScores: [IssueGroup: Int] = [:]
    var groupCounts: [IssueGroup: Int] = [:]
    var tones: [ToneReading] = []
    var sentiment = 0.0
    var formalityScore = 0.5

    var readabilityLabel: String {
        switch readability {
        case 90...: "Very easy"
        case 70..<90: "Easy"
        case 60..<70: "Plain English"
        case 50..<60: "Fairly difficult"
        case 30..<50: "Difficult"
        default: "Very difficult"
        }
    }

    static func compute(_ text: String, issues: [Issue]) -> Metrics {
        var m = Metrics()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return m }
        let words = TextUtil.words(text).map(\.text).filter { $0.contains(where: \.isLetter) }
        let sents = TextUtil.sentences(text)
        m.words = words.count
        m.characters = text.count
        m.sentences = max(1, sents.count)
        m.paragraphs = TextUtil.paragraphs(text).count
        m.readingTime = Double(m.words) / 238.0
        m.speakingTime = Double(m.words) / 150.0
        m.avgWordLength = words.isEmpty ? 0 : Double(words.reduce(0) { $0 + $1.count }) / Double(words.count)
        m.avgSentenceLength = Double(m.words) / Double(m.sentences)
        let syl = words.reduce(0) { $0 + TextUtil.syllables($1) }
        if m.words > 0 {
            let spw = Double(syl) / Double(m.words)
            m.readability = max(0, min(100, 206.835 - 1.015 * m.avgSentenceLength - 84.6 * spw))
            m.gradeLevel = max(0, 0.39 * m.avgSentenceLength + 11.8 * spw - 15.59)
            m.uniqueWords = Double(Set(words.map { $0.lowercased() }).count) / Double(m.words) * 100
            m.rareWords = Double(words.filter { $0.count >= 9 }.count) / Double(m.words) * 100
        }
        // Scores: penalty per issue relative to length.
        let per100 = max(1.0, Double(m.words) / 100.0)
        let weights: [IssueGroup: Double] = [.correctness: 9, .clarity: 6, .engagement: 4, .delivery: 5]
        var overallPenalty = 0.0
        for g in IssueGroup.allCases {
            let n = issues.filter { $0.group == g }.count
            m.groupCounts[g] = n
            let p = Double(n) * weights[g]! / per100
            m.groupScores[g] = max(0, Int((100 - p).rounded()))
            overallPenalty += p * (g == .correctness ? 0.5 : 0.25)
        }
        m.overall = max(0, min(100, Int((100 - overallPenalty).rounded())))
        (m.tones, m.sentiment, m.formalityScore) = detectTone(text)
        return m
    }

    // MARK: Tone detection

    static let toneLexicon: [(String, String, [String])] = [
        ("Confident", "🤝", ["will", "definitely", "certainly", "sure", "confident", "guarantee", "clearly", "absolutely", "committed", "ensure", "proven"]),
        ("Friendly", "😀", ["thanks", "thank", "glad", "happy", "great", "love", "hope", "welcome", "cheers", "appreciate", "wonderful", "awesome", "!"]),
        ("Formal", "🎩", ["therefore", "furthermore", "regards", "sincerely", "accordingly", "pursuant", "hereby", "kindly", "respectfully", "consequently", "dear"]),
        ("Optimistic", "🌤️", ["excited", "looking forward", "opportunity", "progress", "improve", "success", "positive", "bright", "promising", "growth"]),
        ("Assertive", "📣", ["must", "need to", "required", "immediately", "expect", "insist", "should", "now", "deadline", "important"]),
        ("Appreciative", "🙏", ["thank you", "grateful", "appreciate", "thanks", "gratitude", "kind of you"]),
        ("Worried", "😟", ["worried", "concern", "concerned", "afraid", "unfortunately", "risk", "problem", "issue", "anxious", "fear"]),
        ("Unassuming", "🙂", ["just", "maybe", "perhaps", "I think", "I guess", "sort of", "kind of", "possibly", "a bit", "a little", "sorry"]),
        ("Direct", "🎯", ["please", "send", "do", "need", "let me know", "by", "today", "confirm"]),
        ("Informal", "😎", ["hey", "gonna", "wanna", "lol", "yeah", "cool", "stuff", "kinda", "btw", "guys"]),
        ("Disapproving", "😒", ["disappointed", "unacceptable", "frustrated", "annoyed", "poor", "failed", "wrong", "never", "terrible", "bad"]),
        ("Curious", "🤔", ["?", "wonder", "curious", "how", "why", "interested", "explore"]),
    ]

    static func detectTone(_ text: String) -> ([ToneReading], Double, Double) {
        let lower = " " + text.lowercased() + " "
        let words = max(1, TextUtil.wordCount(text))
        var readings: [ToneReading] = []
        for (name, emoji, cues) in toneLexicon {
            var hits = 0
            for c in cues {
                if c == "!" || c == "?" { hits += lower.filter { String($0) == c }.count; continue }
                hits += TextUtil.matches("\\b" + NSRegularExpression.escapedPattern(for: c) + "\\b", in: lower).count
            }
            if hits > 0 {
                readings.append(ToneReading(name: name, emoji: emoji, strength: min(1, Double(hits) / (Double(words) / 25.0 + 1))))
            }
        }
        // Sentiment from NaturalLanguage.
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        var total = 0.0
        var n = 0.0
        for p in TextUtil.paragraphs(text) {
            let s = (p.text as NSString)
            tagger.string = p.text
            let (tag, _) = tagger.tag(at: p.text.startIndex, unit: .paragraph, scheme: .sentimentScore)
            if let v = tag.flatMap({ Double($0.rawValue) }) { total += v * Double(s.length); n += Double(s.length) }
        }
        let sentiment = n > 0 ? total / n : 0
        if sentiment > 0.3, !readings.contains(where: { $0.name == "Optimistic" }) {
            readings.append(ToneReading(name: "Optimistic", emoji: "🌤️", strength: sentiment * 0.8))
        }
        if sentiment < -0.3, !readings.contains(where: { $0.name == "Disapproving" || $0.name == "Worried" }) {
            readings.append(ToneReading(name: "Concerned", emoji: "😟", strength: -sentiment * 0.8))
        }
        if readings.isEmpty { readings.append(ToneReading(name: "Neutral", emoji: "😐", strength: 0.5)) }
        let formal = readings.first { $0.name == "Formal" }?.strength ?? 0
        let informal = readings.first { $0.name == "Informal" }?.strength ?? 0
        let contractions = Double(TextUtil.matches("\\b\\w+'(t|s|re|ll|ve|d|m)\\b", in: text).count) / Double(words)
        let formality = max(0, min(1, 0.55 + formal * 0.4 - informal * 0.5 - contractions * 3))
        return (Array(readings.sorted { $0.strength > $1.strength }.prefix(4)), sentiment, formality)
    }
}
