// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation
import SwiftUI

/// Saves documents and settings to ~/Library/Application Support/JustTypeIt.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var prefs = Prefs() { didSet { savePrefs() } }
    @Published var documents: [Document] = [] { didSet { scheduleDocSave() } }
    @Published var stats = Stats() { didSet { saveStats() } }

    struct Stats: Codable {
        var suggestionsAccepted = 0
        var suggestionsDismissed = 0
        var wordsChecked = 0
        var acceptedByGroup: [String: Int] = [:]
        var mistakesByKind: [String: Int] = [:]
    }

    private let dir: URL
    private var saveTask: Task<Void, Never>?

    init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JustTypeIt")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: dir.appendingPathComponent("prefs.json")), let p = try? JSONDecoder().decode(Prefs.self, from: d) { prefs = p }
        if let d = try? Data(contentsOf: dir.appendingPathComponent("documents.json")), let docs = try? JSONDecoder().decode([Document].self, from: d) { documents = docs }
        if let d = try? Data(contentsOf: dir.appendingPathComponent("stats.json")), let s = try? JSONDecoder().decode(Stats.self, from: d) { stats = s }
        if documents.isEmpty { documents = [Document(title: "Welcome to Just Type It", text: Store.welcomeText)] }
    }

    static let welcomeText = """
    Welcome to Just Type It! Start typing, paste you're text, or open a file and suggestions will appear on the right.

    Their are a few mistakes in this paragraph so you can see how it work. In order to make a decision, the team have discussed about it alot. The report was written by the manager and it was very very good. I think maybe we should of sent it yesterday, me and him was going to do it.

    Click any underlined word to see why it was flagged and fix it in one click.
    """

    private func savePrefs() {
        if let d = try? JSONEncoder().encode(prefs) { try? d.write(to: dir.appendingPathComponent("prefs.json"), options: .atomic) }
    }

    private func saveStats() {
        if let d = try? JSONEncoder().encode(stats) { try? d.write(to: dir.appendingPathComponent("stats.json"), options: .atomic) }
    }

    private func scheduleDocSave() {
        saveTask?.cancel()
        let docs = documents
        let url = dir.appendingPathComponent("documents.json")
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            if let d = try? JSONEncoder().encode(docs) { try? d.write(to: url, options: .atomic) }
        }
    }

    func saveNow() {
        if let d = try? JSONEncoder().encode(documents) { try? d.write(to: dir.appendingPathComponent("documents.json"), options: .atomic) }
    }

    func addToDictionary(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, !prefs.dictionary.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) else { return }
        prefs.dictionary.append(w)
        NSSpellChecker.shared.learnWord(w)
    }

    func removeFromDictionary(_ word: String) {
        prefs.dictionary.removeAll { $0 == word }
        NSSpellChecker.shared.unlearnWord(word)
    }

    func recordAccept(_ i: Issue) {
        stats.suggestionsAccepted += 1
        stats.acceptedByGroup[i.group.rawValue, default: 0] += 1
        stats.mistakesByKind[i.title, default: 0] += 1
    }
}
