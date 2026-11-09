// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation
import NaturalLanguage
import SwiftUI

/// A writing language the user can turn on. English has the full rule set; every language gets
/// spelling and grammar from macOS, punctuation checks and AI suggestions; Spanish adds its own rules.
struct Language: Identifiable, Hashable {
    let code: String       // also used in prefs and in rules.json
    let name: String       // English name
    let native: String     // name in the language itself
    let spell: String      // NSSpellChecker language
    var id: String { code }
    var menuLabel: String { name == native ? name : "\(name) (\(native))" }

    static let all: [Language] = [
        .init(code: "en", name: "English", native: "English", spell: "en_US"),
        .init(code: "es", name: "Spanish", native: "Español", spell: "es"),
        .init(code: "it", name: "Italian", native: "Italiano", spell: "it"),
        .init(code: "pt-BR", name: "Portuguese (Brazil)", native: "Português (Brasil)", spell: "pt_BR"),
        .init(code: "pt-PT", name: "Portuguese (Portugal)", native: "Português (Portugal)", spell: "pt_PT"),
        .init(code: "fr", name: "French", native: "Français", spell: "fr"),
        .init(code: "de", name: "German", native: "Deutsch", spell: "de"),
        .init(code: "nl", name: "Dutch", native: "Nederlands", spell: "nl"),
        .init(code: "sv", name: "Swedish", native: "Svenska", spell: "sv"),
        .init(code: "da", name: "Danish", native: "Dansk", spell: "da"),
        .init(code: "nb", name: "Norwegian", native: "Norsk", spell: "nb"),
        .init(code: "fi", name: "Finnish", native: "Suomi", spell: "fi"),
        .init(code: "pl", name: "Polish", native: "Polski", spell: "pl"),
        .init(code: "cs", name: "Czech", native: "Čeština", spell: "cs"),
        .init(code: "ro", name: "Romanian", native: "Română", spell: "ro"),
        .init(code: "hu", name: "Hungarian", native: "Magyar", spell: "hu"),
        .init(code: "el", name: "Greek", native: "Ελληνικά", spell: "el"),
        .init(code: "tr", name: "Turkish", native: "Türkçe", spell: "tr"),
        .init(code: "ru", name: "Russian", native: "Русский", spell: "ru"),
        .init(code: "uk", name: "Ukrainian", native: "Українська", spell: "uk"),
        .init(code: "bg", name: "Bulgarian", native: "Български", spell: "bg"),
        .init(code: "id", name: "Indonesian", native: "Bahasa Indonesia", spell: "id"),
        .init(code: "vi", name: "Vietnamese", native: "Tiếng Việt", spell: "vi"),
        .init(code: "hi", name: "Hindi", native: "हिन्दी", spell: "hi"),
        .init(code: "ar", name: "Arabic", native: "العربية", spell: "ar"),
        .init(code: "he", name: "Hebrew", native: "עברית", spell: "he"),
        .init(code: "ko", name: "Korean", native: "한국어", spell: "ko"),
    ]

    static let defaults = ["en", "es"]

    static func named(_ code: String) -> Language { all.first { $0.code == code } ?? all[0] }

    /// Short summary for menus: "English, Spanish" or "English + 3".
    static func summary(_ codes: [String]) -> String {
        let names = all.filter { codes.contains($0.code) }.map(\.name)
        return names.count <= 2 ? names.joined(separator: ", ") : "\(names[0]) + \(names.count - 1)"
    }

    /// The language of a paragraph, chosen only among the user's languages. English (or the first
    /// language) when the text is too short or unclear.
    static func detect(_ text: String, among codes: [String]) -> String {
        let fallback = codes.contains("en") ? "en" : (codes.first ?? "en")
        guard codes.count > 1, text.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return fallback }
        let nl: (String) -> NLLanguage = { NLLanguage(rawValue: $0.hasPrefix("pt") ? "pt" : $0) }
        let r = NLLanguageRecognizer()
        r.languageConstraints = codes.map(nl)
        r.processString(text)
        guard let (top, p) = r.languageHypotheses(withMaximum: 1).first, p >= 0.7 else { return fallback }
        return codes.first { nl($0) == top } ?? fallback
    }
}

/// Menu to turn writing languages on and off (at least one stays on). English and Spanish are on by default.
struct LanguageMenu: View {
    @ObservedObject var store: Store
    var changed: () -> Void = {}

    var body: some View {
        Menu("Languages: \(Language.summary(store.prefs.languages))") {
            Text("Checks each paragraph in its own language")
            Divider()
            ForEach(Language.all) { l in
                Button { toggle(l.code) } label: {
                    if store.prefs.languages.contains(l.code) { Label(l.menuLabel, systemImage: "checkmark") } else { Text(l.menuLabel) }
                }
            }
            Divider()
            Menu("English Variety: \(store.prefs.dialect.label.replacingOccurrences(of: " English", with: ""))") {
                ForEach(Dialect.allCases) { d in
                    Button { store.prefs.dialect = d; changed() } label: { if store.prefs.dialect == d { Label(d.label, systemImage: "checkmark") } else { Text(d.label) } }
                }
            }
            Button("Reset to English + Spanish") { store.prefs.languages = Language.defaults; changed() }
        }
    }

    private func toggle(_ code: String) {
        if let i = store.prefs.languages.firstIndex(of: code) {
            guard store.prefs.languages.count > 1 else { return }
            store.prefs.languages.remove(at: i)
        } else {
            store.prefs.languages.append(code)
        }
        changed()
    }
}
