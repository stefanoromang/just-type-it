// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: Store

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            dictionary.tabItem { Label("Dictionary", systemImage: "book") }
            styleGuide.tabItem { Label("Style Guide", systemImage: "building.2") }
            snippets.tabItem { Label("Snippets", systemImage: "text.badge.plus") }
            everywhere.tabItem { Label("Everywhere", systemImage: "macwindow.on.rectangle") }
        }
        .frame(width: 600, height: 460)
    }

    private var general: some View {
        Form {
            Picker("English dialect", selection: $store.prefs.dialect) {
                ForEach(Dialect.allCases) { Text($0.label).tag($0) }
            }
            Section("Checks") {
                Toggle("AI full-sentence suggestions (Apple Intelligence, on-device)", isOn: $store.prefs.aiChecks)
                Toggle("Passive voice", isOn: $store.prefs.checkPassive)
                Toggle("Hedging and confidence", isOn: $store.prefs.checkHedging)
                Toggle("Inclusive language", isOn: $store.prefs.checkInclusive)
                Toggle("Consistency (spelling, numbers, dates, commas)", isOn: $store.prefs.checkConsistency)
            }
            Section("Default goals for new documents") {
                Picker("Intent", selection: $store.prefs.defaultGoals.intent) { ForEach(Intent.allCases) { Text($0.label).tag($0) } }
                Picker("Audience", selection: $store.prefs.defaultGoals.audience) { ForEach(Audience.allCases) { Text($0.label).tag($0) } }
                Picker("Formality", selection: $store.prefs.defaultGoals.formality) { ForEach(Formality.allCases) { Text($0.label).tag($0) } }
                Picker("Domain", selection: $store.prefs.defaultGoals.domain) { ForEach(Domain.allCases) { Text($0.label).tag($0) } }
            }
            if !AIEngine.available { Text(AIEngine.unavailableReason).foregroundStyle(.orange) }
        }
        .formStyle(.grouped)
    }

    @VState private var newWord = ""
    private var dictionary: some View {
        VStack(alignment: .leading) {
            Text("Words here are never flagged: names, brands, jargon.").foregroundStyle(.secondary)
            HStack {
                TextField("Add a word", text: $newWord).onSubmit { store.addToDictionary(newWord); newWord = "" }
                Button("Add") { store.addToDictionary(newWord); newWord = "" }.disabled(newWord.isEmpty)
            }
            List {
                ForEach(store.prefs.dictionary.sorted(), id: \.self) { w in
                    HStack { Text(w); Spacer(); Button { store.removeFromDictionary(w) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless) }
                }
            }
        }.padding()
    }

    private var styleGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Brand tone").font(.headline)
            TextField("e.g. Warm, confident and jargon-free. Use “we”, not “the company”.", text: $store.prefs.brandTone, axis: .vertical)
                .lineLimit(2...3)
            Text("Style rules").font(.headline)
            Text("Flag a term and suggest your team's preferred wording.").font(.caption).foregroundStyle(.secondary)
            List {
                ForEach($store.prefs.styleRules) { $r in
                    HStack {
                        TextField("Avoid", text: $r.avoid)
                        Image(systemName: "arrow.right")
                        TextField("Use", text: $r.use)
                        TextField("Note (optional)", text: $r.note)
                        Button { store.prefs.styleRules.removeAll { $0.id == r.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
            }
            Button("Add rule") { store.prefs.styleRules.append(StyleRule(avoid: "", use: "", note: "")) }
        }.padding()
    }

    private var snippets: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type a trigger in the editor and it expands into the full text.").foregroundStyle(.secondary)
            List {
                ForEach($store.prefs.snippets) { $s in
                    HStack(alignment: .top) {
                        TextField("Trigger", text: $s.trigger).frame(width: 90)
                        TextField("Text", text: $s.text, axis: .vertical).lineLimit(1...4)
                        Button { store.prefs.snippets.removeAll { $0.id == s.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
            }
            Button("Add snippet") { store.prefs.snippets.append(Snippet(trigger: ";new", text: "")) }
        }.padding()
    }

    private var everywhere: some View {
        Form {
            Section("Use Just Type It in any app") {
                Text("1. Select text in any app: Mail, Slack, Notion, Word, Pages, Chrome, Safari…")
                Text("2. Press ⌃⌥G (Control-Option-G).")
                Text("3. Fix suggestions in the panel and click **Replace in app**.")
                Text("You can also right-click selected text → Services → **Check with Just Type It**.")
            }
            Section("Permissions") {
                HStack {
                    Image(systemName: AXIsProcessTrusted() ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(AXIsProcessTrusted() ? .green : .orange)
                    Text("Accessibility (to read and replace selected text)")
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
        }.formStyle(.grouped)
    }
}
