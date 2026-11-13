// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import AppKit
import SwiftUI

/// State for the open document: text, live suggestions, scores.
@MainActor
final class EditorModel: ObservableObject {
    @Published var text: String = ""
    @Published var issues: [Issue] = []
    @Published var metrics = Metrics()
    @Published var selectedIssueID: UUID?
    @Published var filter: IssueGroup?
    @Published var aiChecking = false
    @Published var docID: UUID?
    @Published var goals = Goals()
    @Published var status: String = ""

    weak var textView: NSTextView?
    private let store = Store.shared
    private var checkTask: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    private var ignored: Set<String> = []
    private var aiIssues: [Issue] = []
    private var lastAIText = ""

    var visibleIssues: [Issue] {
        guard let filter else { return issues }
        return issues.filter { $0.group == filter }
    }

    func load(_ doc: Document) {
        store.saveNow()
        docID = doc.id
        text = doc.text
        goals = doc.goals
        ignored = doc.ignoredKeys
        aiIssues = []
        lastAIText = ""
        selectedIssueID = nil
        textView?.string = doc.text
        recheck(immediate: true)
    }

    func textChanged(_ new: String) {
        guard new != text else { return }
        let delta = (new as NSString).length - (text as NSString).length
        text = new
        // Shift suggestions after an edit so underlines stay on the right words until the next check.
        if let tv = textView {
            let caret = tv.selectedRange().location
            let shift: (Issue) -> Issue? = { i in
                var i = i
                if i.range.location >= caret - max(0, delta) { i.range.location += delta }
                return TextUtil.substring(new, i.range) == i.original ? i : nil
            }
            aiIssues = aiIssues.compactMap(shift)
            issues = issues.compactMap(shift)
            applyHighlights()
        }
        persist()
        recheck(immediate: false)
    }

    func persist() {
        guard let id = docID, let idx = store.documents.firstIndex(where: { $0.id == id }) else { return }
        store.documents[idx].text = text
        store.documents[idx].goals = goals
        store.documents[idx].ignoredKeys = ignored
        store.documents[idx].modified = Date()
    }

    func recheck(immediate: Bool) {
        checkTask?.cancel()
        checkTask = Task {
            if !immediate { try? await Task.sleep(nanoseconds: 350_000_000) }
            guard !Task.isCancelled else { return }
            runRules()
            scheduleAI()
        }
    }

    private func key(_ i: Issue) -> String { "\(i.kind)|\(i.original.lowercased())" }

    private func runRules() {
        let opts = CheckOptions.from(store.prefs, goals: goals)
        var found = RuleEngine.check(text, options: opts)
        let ruleRanges = found
        for a in aiIssues where !ruleRanges.contains(where: { NSIntersectionRange($0.range, a.range).length > 0 }) {
            found.append(a)
        }
        issues = found.filter { !ignored.contains(key($0)) }.sorted { $0.range.location < $1.range.location }
        scheduleMetrics()
        if let sel = selectedIssueID, !issues.contains(where: { $0.id == sel }) { selectedIssueID = nil }
        applyHighlights()
    }

    private var metricsTask: Task<Void, Never>?

    /// Scores, readability and tone cover the whole document; they're refreshed after typing pauses.
    private func scheduleMetrics() {
        metricsTask?.cancel()
        let quick = (text as NSString).length < 20_000
        metricsTask = Task { @MainActor [weak self] in
            if !quick { try? await Task.sleep(nanoseconds: 900_000_000) }
            guard let self, !Task.isCancelled else { return }
            self.metrics = Metrics.compute(self.text, issues: self.issues)
        }
    }

    private func scheduleAI() {
        guard store.prefs.aiChecks, AIEngine.available else { return }
        aiTask?.cancel()
        aiTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, text != lastAIText, TextUtil.wordCount(text) >= 4 else { return }
            await runAI()
        }
    }

    func runAI() async {
        let snapshot = text
        aiChecking = true
        defer { aiChecking = false }
        let found = await AIEngine.deepCheck(snapshot, goals: goals, dialect: store.prefs.dialect, brand: store.prefs.brandTone,
                                             existing: issues.filter { $0.source != .ai })
        guard snapshot == text else { return }
        lastAIText = snapshot
        aiIssues = found
        runRules()
    }

    // MARK: Actions

    func accept(_ issue: Issue, replacement: String? = nil) {
        let rep = replacement ?? issue.replacements.first ?? ""
        guard TextUtil.substring(text, issue.range) == issue.original else { recheck(immediate: true); return }
        var finalRep = rep
        // Removing a phrase at a sentence start: capitalize what follows.
        if rep.isEmpty, issue.range.location == 0 || TextUtil.substring(text, NSRange(location: max(0, issue.range.location - 2), length: min(2, issue.range.location))).contains(where: { ".!?\n".contains($0) }) {
            let next = NSRange(location: NSMaxRange(issue.range), length: 1)
            if NSMaxRange(next) <= (text as NSString).length {
                let ch = TextUtil.substring(text, next)
                replace(NSRange(location: issue.range.location, length: issue.range.length + 1), with: ch.uppercased())
                store.recordAccept(issue)
                return
            }
        }
        if rep.isEmpty, issue.range.location > 0, TextUtil.substring(text, NSRange(location: issue.range.location - 1, length: 1)) == " ",
           NSMaxRange(issue.range) < (text as NSString).length, TextUtil.substring(text, NSRange(location: NSMaxRange(issue.range), length: 1)).first.map({ ",.;:!?".contains($0) }) == true {
            replace(NSRange(location: issue.range.location - 1, length: issue.range.length + 1), with: "")
            store.recordAccept(issue)
            return
        }
        if finalRep.isEmpty == false, issue.original.first?.isUppercase == true, finalRep.first?.isLowercase == true, issue.range.location == 0 {
            finalRep = finalRep.prefix(1).uppercased() + finalRep.dropFirst()
        }
        replace(issue.range, with: finalRep)
        store.recordAccept(issue)
    }

    func replace(_ range: NSRange, with s: String) {
        guard range.location >= 0, range.length >= 0, range.location <= text.utf16.count,
              range.length <= text.utf16.count - range.location, Range(range, in: text) != nil else { return }
        if let tv = textView, tv.shouldChangeText(in: range, replacementString: s) {
            tv.textStorage?.replaceCharacters(in: range, with: s)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: range.location + (s as NSString).length, length: 0))
        } else {
            guard textView == nil else { return }
            textChanged((text as NSString).replacingCharacters(in: range, with: s))
        }
    }

    func dismiss(_ issue: Issue) {
        ignored.insert(key(issue))
        aiIssues.removeAll { $0.id == issue.id }
        store.stats.suggestionsDismissed += 1
        persist()
        runRules()
    }

    func addToDictionary(_ issue: Issue) {
        store.addToDictionary(issue.original)
        runRules()
    }

    func acceptAll(in group: IssueGroup? = nil) {
        // Apply from the end so earlier ranges stay valid.
        let list = (group == nil ? issues : issues.filter { $0.group == group })
            .filter { !$0.replacements.isEmpty && $0.range.length < 60 }
            .sorted { $0.range.location > $1.range.location }
        var lastStart = Int.max
        textView?.undoManager?.beginUndoGrouping()
        for i in list where NSMaxRange(i.range) <= lastStart {
            accept(i)
            lastStart = i.range.location
        }
        textView?.undoManager?.endUndoGrouping()
    }

    func select(_ issue: Issue) {
        guard TextUtil.substring(text, issue.range) == issue.original else { return }
        selectedIssueID = issue.id
        textView?.scrollRangeToVisible(issue.range)
        textView?.showFindIndicator(for: issue.range)
    }

    func setText(_ s: String) {
        let full = NSRange(location: 0, length: (text as NSString).length)
        replace(full, with: s)
    }

    func replaceSelectionOrAll(_ s: String) {
        guard let tv = textView else { setText(s); return }
        let r = tv.selectedRange()
        if r.length > 0 { replace(r, with: s) } else { setText(s) }
    }

    var selectedOrAllText: String {
        if let tv = textView, tv.selectedRange().length > 0 { return TextUtil.substring(text, tv.selectedRange()) }
        return text
    }

    func insertAtCursor(_ s: String) {
        guard let tv = textView else { setText(text + s); return }
        replace(tv.selectedRange(), with: s)
    }

    // MARK: Underlines

    func applyHighlights() {
        guard let tv = textView, let lm = tv.layoutManager else { return }
        let full = NSRange(location: 0, length: (tv.string as NSString).length)
        lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)
        lm.removeTemporaryAttribute(.underlineColor, forCharacterRange: full)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        for i in issues where NSMaxRange(i.range) <= full.length {
            if filter != nil, i.group != filter { continue }
            let style: NSUnderlineStyle = i.range.length > 40 ? [.single, .patternDot] : [.thick, .single]
            lm.addTemporaryAttributes([.underlineStyle: style.rawValue, .underlineColor: i.group.nsColor], forCharacterRange: i.range)
            if i.id == selectedIssueID {
                lm.addTemporaryAttribute(.backgroundColor, value: i.group.nsColor.withAlphaComponent(0.18), forCharacterRange: i.range)
            }
        }
    }

    func issue(at index: Int) -> Issue? {
        issues.filter { NSLocationInRange(index, $0.range) }.min { $0.range.length < $1.range.length }
    }
}
