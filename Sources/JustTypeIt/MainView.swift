// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SidePanel: String, CaseIterable, Identifiable {
    case suggestions, tone, scores, generate, agents, integrity
    var id: String { rawValue }
    var label: String {
        switch self {
        case .suggestions: "Suggestions"
        case .tone: "Tone"
        case .scores: "Scores"
        case .generate: "AI Write"
        case .agents: "Agents"
        case .integrity: "Integrity"
        }
    }
    var icon: String {
        switch self {
        case .suggestions: "checkmark.bubble"
        case .tone: "face.smiling"
        case .scores: "chart.bar.xaxis"
        case .generate: "sparkles"
        case .agents: "person.2.wave.2"
        case .integrity: "doc.text.magnifyingglass"
        }
    }
}

struct MainView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var store: Store
    @VState private var panel: SidePanel = .suggestions
    @VState private var showGoals = false
    @VState private var search = ""

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            HSplitView {
                editor.frame(minWidth: 460)
                rightPanel.frame(minWidth: 330, idealWidth: 370, maxWidth: 460)
            }
        }
        .onAppear {
            if model.docID == nil, let d = store.documents.sorted(by: { $0.modified > $1.modified }).first { model.load(d) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newDocument)) { _ in newDoc() }
        .onReceive(NotificationCenter.default.publisher(for: .openDocument)) { _ in openFile() }
        .onReceive(NotificationCenter.default.publisher(for: .exportDocument)) { _ in exportFile() }
        .sheet(isPresented: $showGoals) { GoalsSheet(model: model) }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { model.docID }, set: { id in
                if let id, let d = store.documents.first(where: { $0.id == id }) { model.load(d) }
            })) {
                Section("Documents") {
                    ForEach(filteredDocs) { d in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.displayTitle).lineLimit(1)
                            Text("\(TextUtil.wordCount(d.text)) words · \(d.modified.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(d.id)
                        .contextMenu {
                            Button("Duplicate") { var c = d; c.id = UUID(); c.title = d.displayTitle + " copy"; store.documents.insert(c, at: 0) }
                            Button("Delete", role: .destructive) { delete(d) }
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search documents")
            Divider()
            HStack {
                Button { newDoc() } label: { Label("New", systemImage: "plus") }
                Button { openFile() } label: { Label("Open", systemImage: "folder") }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.help("Settings")
            }
            .buttonStyle(.borderless).padding(10)
        }
    }

    private var filteredDocs: [Document] {
        let docs = store.documents.sorted { $0.modified > $1.modified }
        guard !search.isEmpty else { return docs }
        return docs.filter { $0.displayTitle.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) }
    }

    // MARK: Editor

    private var editor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Title", text: Binding(get: {
                    store.documents.first { $0.id == model.docID }?.title ?? ""
                }, set: { v in
                    if let i = store.documents.firstIndex(where: { $0.id == model.docID }) { store.documents[i].title = v }
                }), prompt: Text("Untitled document"))
                .textFieldStyle(.plain).font(.title2.weight(.semibold))
                Spacer()
                Button { showGoals = true } label: { Label("Goals", systemImage: "target") }
                    .help("Set intent, audience, formality and domain")
                Menu {
                    ForEach(Dialect.allCases) { d in
                        Button { store.prefs.dialect = d; model.recheck(immediate: true) } label: {
                            if store.prefs.dialect == d { Label(d.label, systemImage: "checkmark") } else { Text(d.label) }
                        }
                    }
                } label: { Text(store.prefs.dialect.label.replacingOccurrences(of: " English", with: "")) }
                .fixedSize()
                Button { exportFile() } label: { Image(systemName: "square.and.arrow.up") }.help("Export")
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            TextEditorView(model: model)
            Divider()
            HStack(spacing: 16) {
                Text("\(model.metrics.words) words").monospacedDigit()
                Text("\(model.metrics.characters) characters").monospacedDigit()
                Text("\(max(1, Int(model.metrics.readingTime.rounded(.up)))) min read")
                Spacer()
                if model.aiChecking {
                    ProgressView().controlSize(.small)
                    Text("AI is reviewing…")
                } else if !AIEngine.available {
                    Text(AIEngine.unavailableReason).lineLimit(1).help(AIEngine.unavailableReason)
                }
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 7)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Right panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(SidePanel.allCases) { p in
                    Button { panel = p } label: {
                        VStack(spacing: 3) {
                            Image(systemName: p.icon).font(.system(size: 15))
                            Text(p.label).font(.system(size: 10))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(panel == p ? Color.accentColor.opacity(0.15) : .clear))
                        .foregroundStyle(panel == p ? Color.accentColor : .secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(8)
            Divider()
            Group {
                switch panel {
                case .suggestions: SuggestionsPanel(model: model)
                case .tone: TonePanel(model: model)
                case .scores: ScoresPanel(model: model)
                case .generate: GeneratePanel(model: model)
                case .agents: AgentsPanel(model: model)
                case .integrity: IntegrityPanel(model: model)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Files

    private func newDoc() {
        let d = Document(title: "", text: "", goals: store.prefs.defaultGoals)
        store.documents.insert(d, at: 0)
        model.load(d)
    }

    private func delete(_ d: Document) {
        store.documents.removeAll { $0.id == d.id }
        if store.documents.isEmpty { store.documents = [Document(title: "", text: "")] }
        if model.docID == d.id, let first = store.documents.first { model.load(first) }
    }

    private func openFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.plainText, .rtf, .rtfd, .html, UTType(filenameExtension: "md") ?? .plainText,
                                 UTType(filenameExtension: "docx") ?? .data, UTType(filenameExtension: "odt") ?? .data, .data]
        p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let url = p.url else { return }
        let text: String
        if let a = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
            text = a.string
        } else {
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        let d = Document(title: url.deletingPathExtension().lastPathComponent, text: text, goals: store.prefs.defaultGoals)
        store.documents.insert(d, at: 0)
        model.load(d)
    }

    private func exportFile() {
        let p = NSSavePanel()
        let title = store.documents.first { $0.id == model.docID }?.displayTitle ?? "Document"
        p.nameFieldStringValue = title
        p.allowedContentTypes = [.plainText, .rtf, UTType(filenameExtension: "docx") ?? .data, UTType(filenameExtension: "md") ?? .plainText]
        p.isExtensionHidden = false
        guard p.runModal() == .OK, let url = p.url else { return }
        let attr = NSAttributedString(string: model.text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        switch url.pathExtension.lowercased() {
        case "rtf":
            if let d = attr.rtf(from: NSRange(location: 0, length: attr.length), documentAttributes: [:]) { try? d.write(to: url) }
        case "docx":
            if let d = try? attr.data(from: NSRange(location: 0, length: attr.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]) { try? d.write(to: url) }
        default:
            try? model.text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct GoalsSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set goals").font(.title2.bold())
            Text("Get tailored suggestions based on your writing goals and audience.").foregroundStyle(.secondary)
            picker("Intent", selection: $model.goals.intent)
            picker("Audience", selection: $model.goals.audience)
            picker("Formality", selection: $model.goals.formality)
            picker("Domain", selection: $model.goals.domain)
            HStack {
                Button("Make these my defaults") { Store.shared.prefs.defaultGoals = model.goals }
                Spacer()
                Button("Done") { model.persist(); model.recheck(immediate: true); dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 520)
    }

    private func picker<T: Hashable & Identifiable & CaseIterable>(_ title: String, selection: Binding<T>) -> some View where T.AllCases: RandomAccessCollection, T: RawRepresentable, T.RawValue == String {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Picker(title, selection: selection) {
                ForEach(T.allCases) { v in Text(label(v)).tag(v) }
            }
            .pickerStyle(.segmented).labelsHidden()
        }
    }

    private func label<T>(_ v: T) -> String {
        switch v {
        case let x as Intent: x.label
        case let x as Audience: x.label
        case let x as Formality: x.label
        case let x as Domain: x.label
        default: "\(v)"
        }
    }
}
