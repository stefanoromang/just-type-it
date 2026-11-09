// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import AppKit
import SwiftUI

/// NSTextView wrapper with colored underlines and a click-to-fix popover.
struct TextEditorView: NSViewRepresentable {
    @ObservedObject var model: EditorModel

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: 16)
        tv.textContainerInset = NSSize(width: 36, height: 28)
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 5
        tv.defaultParagraphStyle = para
        tv.typingAttributes = [.font: NSFont.systemFont(ofSize: 16), .paragraphStyle: para, .foregroundColor: NSColor.textColor]
        tv.string = model.text
        scroll.drawsBackground = false
        tv.drawsBackground = false
        model.textView = tv
        context.coordinator.textView = tv
        let double = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleClicked(_:)))
        double.numberOfClicksRequired = 2
        double.delaysPrimaryMouseButtonEvents = false
        tv.addGestureRecognizer(double)
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        click.delaysPrimaryMouseButtonEvents = false
        tv.addGestureRecognizer(click)
        DispatchQueue.main.async { model.applyHighlights() }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.model = model
        model.applyHighlights()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var model: EditorModel
        weak var textView: NSTextView?
        private var popover: NSPopover?

        init(_ m: EditorModel) { model = m }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            expandSnippets(tv)
            autocorrect(tv)
            model.textChanged(tv.string)
        }

        /// Replaces a typed snippet trigger (e.g. ";sig") with its text.
        private func expandSnippets(_ tv: NSTextView) {
            let caret = tv.selectedRange().location
            let s = tv.string as NSString
            for sn in Store.shared.prefs.snippets where !sn.trigger.isEmpty {
                let len = (sn.trigger as NSString).length
                guard caret >= len else { continue }
                let r = NSRange(location: caret - len, length: len)
                if s.substring(with: r) == sn.trigger, tv.shouldChangeText(in: r, replacementString: sn.text) {
                    tv.textStorage?.replaceCharacters(in: r, with: sn.text)
                    tv.didChangeText()
                    tv.setSelectedRange(NSRange(location: r.location + (sn.text as NSString).length, length: 0))
                    return
                }
            }
        }

        private var lastLength = 0

        /// Fixes obvious typos the moment a word is finished. ⌘Z undoes it.
        private func autocorrect(_ tv: NSTextView) {
            let len = (tv.string as NSString).length
            defer { lastLength = (tv.string as NSString).length }
            guard Store.shared.prefs.autocorrect, len == lastLength + 1 else { return }
            let caret = tv.selectedRange().location
            guard let fix = Proactive.autocorrect(tv.string, caret: caret, dictionary: Set(Store.shared.prefs.dictionary.map { $0.lowercased() })),
                  tv.shouldChangeText(in: fix.range, replacementString: fix.replacement) else { return }
            tv.textStorage?.replaceCharacters(in: fix.range, with: fix.replacement)
            tv.didChangeText()
            tv.undoManager?.setActionName("Autocorrect")
            tv.setSelectedRange(NSRange(location: fix.range.location + (fix.replacement as NSString).length + 1, length: 0))
            Store.shared.stats.autocorrections += 1
        }

        /// Double-click a word to see synonyms and replace it with one click.
        @objc func doubleClicked(_ g: NSClickGestureRecognizer) {
            guard let tv = textView else { return }
            let idx = tv.characterIndexForInsertion(at: g.location(in: tv))
            let ns = tv.string as NSString
            guard idx < ns.length else { return }
            let range = tv.selectionRange(forProposedRange: NSRange(location: idx, length: 0), granularity: .selectByWord)
            let word = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard word.count >= 3, word.allSatisfy(\.isLetter) else { return }
            let syns = Synonyms.lookup(word).filter { !$0.isEmpty }
            guard !syns.isEmpty else { return }
            popover?.close()
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            var rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: tc)
            rect.origin.x += tv.textContainerOrigin.x
            rect.origin.y += tv.textContainerOrigin.y
            let pop = NSPopover()
            pop.behavior = .transient
            pop.contentViewController = NSHostingController(rootView: SynonymCard(word: word, synonyms: syns) { [weak self, weak pop] s in
                pop?.close()
                guard let tv = self?.textView, NSMaxRange(range) <= (tv.string as NSString).length,
                      (tv.string as NSString).substring(with: range).trimmingCharacters(in: .whitespaces) == word else { return }
                let rep = TextUtil.matchCase(s, like: word)
                if tv.shouldChangeText(in: range, replacementString: rep) {
                    tv.textStorage?.replaceCharacters(in: range, with: rep)
                    tv.didChangeText()
                }
            }.padding(10))
            pop.show(relativeTo: rect, of: tv, preferredEdge: .maxY)
            popover = pop
        }

        @objc func clicked(_ g: NSClickGestureRecognizer) {
            guard let tv = textView else { return }
            let p = g.location(in: tv)
            let idx = tv.characterIndexForInsertion(at: p)
            guard let issue = model.issue(at: idx) ?? model.issue(at: max(0, idx - 1)) else { popover?.close(); return }
            model.select(issue)
            show(issue, in: tv)
        }

        func show(_ issue: Issue, in tv: NSTextView) {
            popover?.close()
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            let glyphs = lm.glyphRange(forCharacterRange: issue.range, actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
            rect.origin.x += tv.textContainerOrigin.x
            rect.origin.y += tv.textContainerOrigin.y
            if rect.width > 300 { rect.size.width = 40 }
            let pop = NSPopover()
            pop.behavior = .transient
            pop.contentViewController = NSHostingController(rootView: IssueCard(issue: issue, model: model, compact: true) { [weak pop] in pop?.close() }
                .frame(width: 340).padding(4))
            pop.show(relativeTo: rect, of: tv, preferredEdge: .maxY)
            popover = pop
        }
    }
}

struct SynonymCard: View {
    let word: String
    let synonyms: [String]
    let pick: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Synonyms for “\(word)”").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(synonyms.prefix(6), id: \.self) { s in
                Button(s) { pick(s) }.buttonStyle(.borderless)
            }
        }
        .frame(minWidth: 180, alignment: .leading)
    }
}
