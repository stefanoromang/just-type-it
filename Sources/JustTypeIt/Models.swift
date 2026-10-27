// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation
import SwiftUI

/// The four suggestion groups, mirroring how writing feedback is usually organized.
enum IssueGroup: String, Codable, CaseIterable, Identifiable {
    case correctness, clarity, engagement, delivery
    var id: String { rawValue }
    var label: String {
        switch self {
        case .correctness: "Correctness"
        case .clarity: "Clarity"
        case .engagement: "Engagement"
        case .delivery: "Delivery"
        }
    }
    var color: Color {
        switch self {
        case .correctness: Color(red: 0.89, green: 0.25, blue: 0.30)
        case .clarity: Color(red: 0.16, green: 0.48, blue: 0.95)
        case .engagement: Color(red: 0.13, green: 0.66, blue: 0.42)
        case .delivery: Color(red: 0.55, green: 0.33, blue: 0.92)
        }
    }
    var nsColor: NSColor { NSColor(color) }
    var blurb: String {
        switch self {
        case .correctness: "Spelling, grammar and punctuation"
        case .clarity: "Wordiness, passive voice, hard sentences"
        case .engagement: "Vivid words, variety, repetition"
        case .delivery: "Tone, confidence, formality, inclusivity"
        }
    }
}

/// A single suggestion in the text.
struct Issue: Identifiable, Hashable {
    var id = UUID()
    var range: NSRange
    var original: String
    var replacements: [String]
    var group: IssueGroup
    /// Short machine-readable kind, e.g. "Spelling/Misspelled".
    var kind: String
    var title: String
    var explanation: String
    var source: Source = .rules

    enum Source: String { case rules, system, ai }

    var isRewrite: Bool { original.split(separator: " ").count > 6 }
}

enum Dialect: String, Codable, CaseIterable, Identifiable {
    case american, british, canadian, australian, indian
    var id: String { rawValue }
    var label: String {
        switch self {
        case .american: "American English"
        case .british: "British English"
        case .canadian: "Canadian English"
        case .australian: "Australian English"
        case .indian: "Indian English"
        }
    }
    var spellLanguage: String {
        switch self {
        case .american: "en_US"
        case .british: "en_GB"
        case .canadian: "en_CA"
        case .australian: "en_AU"
        case .indian: "en_IN"
        }
    }
    /// Uses British-style -our / -ise / -re spellings.
    var usesBritishSpelling: Bool { self != .american }
}

enum Intent: String, Codable, CaseIterable, Identifiable {
    case inform, describe, convince, tellStory
    var id: String { rawValue }
    var label: String {
        switch self {
        case .inform: "Inform"
        case .describe: "Describe"
        case .convince: "Convince"
        case .tellStory: "Tell a story"
        }
    }
}

enum Audience: String, Codable, CaseIterable, Identifiable {
    case general, knowledgeable, expert
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum Formality: String, Codable, CaseIterable, Identifiable {
    case informal, neutral, formal
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum Domain: String, Codable, CaseIterable, Identifiable {
    case general, academic, business, technical, creative, casual, email
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct Goals: Codable, Hashable {
    var intent: Intent = .inform
    var audience: Audience = .knowledgeable
    var formality: Formality = .neutral
    var domain: Domain = .general

    var summary: String {
        "intent: \(intent.label), audience: \(audience.label), formality: \(formality.label), domain: \(domain.label)"
    }
}

struct Document: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var text: String
    var goals = Goals()
    var modified = Date()
    var ignoredKeys: Set<String> = []

    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return first.isEmpty ? "Untitled document" : String(first.prefix(40))
    }
}

/// A team style-guide rule: flag a term and recommend another.
struct StyleRule: Codable, Identifiable, Hashable {
    var id = UUID()
    var avoid: String
    var use: String
    var note: String
}

struct Snippet: Codable, Identifiable, Hashable {
    var id = UUID()
    var trigger: String
    var text: String
}

struct Prefs: Codable {
    var dialect: Dialect = .american
    var defaultGoals = Goals()
    var dictionary: [String] = []
    var styleRules: [StyleRule] = []
    var brandTone: String = ""
    var snippets: [Snippet] = [
        Snippet(trigger: ";sig", text: "Best regards,\nStefano"),
        Snippet(trigger: ";thx", text: "Thank you for your time and consideration."),
    ]
    var aiChecks = true
    var checkPassive = true
    var checkInclusive = true
    var checkHedging = true
    var checkConsistency = true
    var onlineOriginality = false
    var checkEverywhere = true
    var launchAtLogin = true
    var excludedApps: [String] = []

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = Prefs()
        dialect = (try? c.decode(Dialect.self, forKey: .dialect)) ?? def.dialect
        defaultGoals = (try? c.decode(Goals.self, forKey: .defaultGoals)) ?? def.defaultGoals
        dictionary = (try? c.decode([String].self, forKey: .dictionary)) ?? def.dictionary
        styleRules = (try? c.decode([StyleRule].self, forKey: .styleRules)) ?? def.styleRules
        brandTone = (try? c.decode(String.self, forKey: .brandTone)) ?? def.brandTone
        snippets = (try? c.decode([Snippet].self, forKey: .snippets)) ?? def.snippets
        aiChecks = (try? c.decode(Bool.self, forKey: .aiChecks)) ?? def.aiChecks
        checkPassive = (try? c.decode(Bool.self, forKey: .checkPassive)) ?? def.checkPassive
        checkInclusive = (try? c.decode(Bool.self, forKey: .checkInclusive)) ?? def.checkInclusive
        checkHedging = (try? c.decode(Bool.self, forKey: .checkHedging)) ?? def.checkHedging
        checkConsistency = (try? c.decode(Bool.self, forKey: .checkConsistency)) ?? def.checkConsistency
        onlineOriginality = (try? c.decode(Bool.self, forKey: .onlineOriginality)) ?? def.onlineOriginality
        checkEverywhere = (try? c.decode(Bool.self, forKey: .checkEverywhere)) ?? def.checkEverywhere
        launchAtLogin = (try? c.decode(Bool.self, forKey: .launchAtLogin)) ?? def.launchAtLogin
        excludedApps = (try? c.decode([String].self, forKey: .excludedApps)) ?? def.excludedApps
    }
}

/// Options that shape a check run.
struct CheckOptions {
    var dialect: Dialect = .american
    var goals = Goals()
    var dictionary: Set<String> = []
    var styleRules: [StyleRule] = []
    var passive = true
    var inclusive = true
    var hedging = true
    var consistency = true

    @MainActor static func from(_ p: Prefs, goals: Goals) -> CheckOptions {
        CheckOptions(dialect: p.dialect, goals: goals, dictionary: Set(p.dictionary.map { $0.lowercased() }),
                     styleRules: p.styleRules, passive: p.checkPassive, inclusive: p.checkInclusive,
                     hedging: p.checkHedging, consistency: p.checkConsistency)
    }
}

/// SwiftUI's `@State` resolves to a macro that needs Xcode's plugin; this alias uses the
/// property wrapper directly so the app builds with only the Command Line Tools.
typealias VState<V> = SwiftUI.State<V>
