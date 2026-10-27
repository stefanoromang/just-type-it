// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import SwiftUI

struct IntegrityPanel: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var store = Store.shared
    @VState private var report: OriginalityReport?
    @VState private var progress = ""
    @VState private var checking = false
    @VState private var pasted = ""
    @VState private var detection: AIDetection?
    @VState private var aiOpinion = ""
    @VState private var style: CitationStyle = .apa
    @VState private var src = CitationSource()
    @VState private var urlField = ""
    @VState private var finding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                plagiarism
                Divider()
                aiDetect
                Divider()
                citations
            }
            .padding(16)
        }
    }

    // MARK: Plagiarism

    private var plagiarism: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Plagiarism check", systemImage: "doc.on.doc").font(.headline)
            Text("Searches the web for your longest sentences and compares your text with the pages found, your other documents, and any source you paste below.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Compare with a specific source (optional)") {
                TextEditor(text: $pasted).frame(height: 70).border(Color.primary.opacity(0.1))
            }.font(.callout)
            HStack {
                Button { check(web: true) } label: { Label("Check web + documents", systemImage: "globe") }
                    .buttonStyle(.borderedProminent).disabled(checking || model.text.isEmpty)
                Button("Offline only") { check(web: false) }.disabled(checking || model.text.isEmpty)
            }
            if checking { ProgressView(progress).controlSize(.small) }
            if let r = report {
                HStack {
                    ScoreRing(score: Int(r.originalPercent), size: 48)
                    VStack(alignment: .leading) {
                        Text("\(Int(r.originalPercent))% original").font(.headline)
                        Text("\(r.matches.count) matching passage\(r.matches.count == 1 ? "" : "s") · \(r.checkedSources) sources compared").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(r.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                ForEach(r.matches) { m in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("“\(m.passage)”").font(.callout).lineLimit(4)
                        HStack {
                            Text("\(Int(m.similarity * 100))% match").font(.caption.bold()).foregroundStyle(.red)
                            if let u = URL(string: m.source), u.scheme != nil { Link(u.host ?? m.source, destination: u).font(.caption).lineLimit(1) }
                            else { Text(m.source).font(.caption).lineLimit(1) }
                        }
                        HStack {
                            Button("Show") {
                                model.textView?.scrollRangeToVisible(m.range)
                                model.textView?.showFindIndicator(for: m.range)
                            }
                            Button("Add quotes") { quote(m) }
                            if m.source.hasPrefix("http") { Button("Cite") { urlField = m.source; findCitation() } }
                        }.controlSize(.small)
                    }
                    .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.06)))
                }
            }
        }
    }

    private func check(web: Bool) {
        checking = true
        progress = "Comparing…"
        let text = model.text
        var sources: [(name: String, text: String)] = store.documents.filter { $0.id != model.docID && !$0.text.isEmpty }
            .map { ("Your document: \($0.displayTitle)", $0.text) }
        if !pasted.trimmingCharacters(in: .whitespaces).isEmpty { sources.append(("Pasted source", pasted)) }
        Task {
            var r = Originality.compare(text, sources: sources)
            if web {
                let w = await Originality.webCheck(text) { p in Task { @MainActor in progress = p } }
                let merged = w.matches + r.matches.filter { m in !w.matches.contains { NSIntersectionRange($0.range, m.range).length > 0 } }
                let flagged = merged.reduce(0) { $0 + TextUtil.wordCount($1.passage) }
                r = OriginalityReport(matches: merged.sorted { $0.range.location < $1.range.location },
                                      originalPercent: max(0, 100 - Double(flagged) / Double(max(1, TextUtil.wordCount(text))) * 100),
                                      checkedSources: r.checkedSources + w.checkedSources, notes: w.notes)
            }
            report = r
            checking = false
        }
    }

    private func quote(_ m: OriginalityMatch) {
        guard TextUtil.substring(model.text, m.range) == m.passage else { return }
        var p = m.passage
        var tail = ""
        if let l = p.last, ".!?".contains(l) { tail = String(l); p.removeLast() }
        model.replace(m.range, with: "“\(p)”" + tail)
    }

    // MARK: AI detection

    private var aiDetect: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI content detector", systemImage: "cpu").font(.headline)
            Text("Estimates how much the text reads like AI-generated writing. No detector is perfect; treat this as a signal, not proof.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Analyze") {
                detection = AIDetection.analyze(model.text)
                aiOpinion = ""
                if AIEngine.available {
                    Task { aiOpinion = await AIEngine.aiOpinion(model.text) ?? "" }
                }
            }.disabled(model.text.isEmpty)
            if let d = detection {
                HStack {
                    ProgressView(value: d.score).tint(d.score > 0.6 ? .red : d.score > 0.35 ? .orange : .green)
                    Text("\(Int(d.score * 100))%").monospacedDigit()
                }
                Text(d.label).font(.subheadline.bold())
                ForEach(d.signals, id: \.self) { Text("• " + $0).font(.caption) }
                if !aiOpinion.isEmpty { Text(aiOpinion).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    // MARK: Citations

    private var citations: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Citation generator", systemImage: "quote.opening").font(.headline)
            Picker("Style", selection: $style) { ForEach(CitationStyle.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            HStack {
                TextField("Paste a URL to auto-fill", text: $urlField).textFieldStyle(.roundedBorder).onSubmit(findCitation)
                Button(finding ? "…" : "Fetch", action: findCitation).disabled(urlField.isEmpty || finding)
            }
            Group {
                TextField("Authors (First Last; First Last)", text: $src.authors)
                TextField("Title", text: $src.title)
                TextField("Website / journal / publisher", text: $src.container)
                HStack {
                    TextField("Year", text: $src.year)
                    TextField("Month", text: $src.month)
                    TextField("Day", text: $src.day)
                }
                TextField("URL", text: $src.url)
            }.textFieldStyle(.roundedBorder)
            if !src.title.isEmpty || !src.url.isEmpty {
                let full = src.format(style)
                let inText = src.inText(style)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reference").font(.caption.bold())
                    Text(full).textSelection(.enabled).font(.callout)
                    Text("In-text").font(.caption.bold())
                    Text(inText).textSelection(.enabled).font(.callout)
                    HStack {
                        Button("Insert in-text") { model.insertAtCursor(" " + inText) }
                        Button("Add to references") {
                            let heading = style == .mla ? "Works Cited" : style == .apa ? "References" : "Bibliography"
                            let base = model.text.contains("\n\(heading)\n") ? model.text : model.text + "\n\n\(heading)\n"
                            model.setText(base + full.replacingOccurrences(of: "*", with: "") + "\n")
                        }
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(full.replacingOccurrences(of: "*", with: ""), forType: .string)
                        }
                    }.controlSize(.small)
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }
        }
    }

    private func findCitation() {
        var s = urlField.trimmingCharacters(in: .whitespaces)
        if !s.hasPrefix("http") { s = "https://" + s }
        guard let u = URL(string: s) else { return }
        finding = true
        Task {
            src = await CitationSource.fromURL(u)
            finding = false
        }
    }
}
