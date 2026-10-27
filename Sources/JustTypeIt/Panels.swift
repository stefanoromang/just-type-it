// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import SwiftUI

struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 64
    var color: Color {
        score >= 85 ? .green : score >= 65 ? .orange : .red
    }
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: size * 0.1)
            Circle().trim(from: 0, to: CGFloat(score) / 100).stroke(color, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)").font(.system(size: size * 0.34, weight: .bold, design: .rounded)).monospacedDigit()
        }
        .frame(width: size, height: size)
        .animation(.easeOut, value: score)
    }
}

// MARK: Suggestions

struct SuggestionsPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ScoreRing(score: model.metrics.overall, size: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Overall score").font(.headline)
                    Text(model.issues.isEmpty ? "No suggestions — nice work!" : "\(model.issues.count) suggestion\(model.issues.count == 1 ? "" : "s")")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if model.issues.contains(where: { !$0.replacements.isEmpty }) {
                    Button("Accept all") { model.acceptAll(in: model.filter) }.controlSize(.small)
                }
            }
            .padding(14)
            HStack(spacing: 6) {
                chip(nil, "All", model.issues.count, .accentColor)
                ForEach(IssueGroup.allCases) { g in chip(g, g.label, model.metrics.groupCounts[g] ?? 0, g.color) }
            }
            .padding(.horizontal, 10).padding(.bottom, 10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if model.visibleIssues.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundStyle(.green)
                                Text(model.text.isEmpty ? "Start writing to see suggestions." : "Nothing to fix here.").foregroundStyle(.secondary)
                            }.padding(.top, 50)
                        }
                        ForEach(model.visibleIssues) { i in IssueCard(issue: i, model: model).id(i.id) }
                    }
                    .padding(12)
                }
                .onChange(of: model.selectedIssueID) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }
    }

    private func chip(_ g: IssueGroup?, _ label: String, _ n: Int, _ color: Color) -> some View {
        Button { model.filter = g; model.applyHighlights() } label: {
            VStack(spacing: 1) {
                Text("\(n)").font(.system(size: 13, weight: .bold)).monospacedDigit()
                Text(label).font(.system(size: 9)).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(model.filter == g ? color.opacity(0.2) : Color.primary.opacity(0.04)))
            .overlay(alignment: .bottom) { Rectangle().fill(color).frame(height: 2).padding(.horizontal, 8) }
            .foregroundStyle(model.filter == g ? color : .primary)
        }.buttonStyle(.plain)
    }
}

// MARK: Tone

struct TonePanel: View {
    @ObservedObject var model: EditorModel
    @VState private var target = "Confident"
    @VState private var working = false
    let targets = ["Confident", "Friendly", "Formal", "Diplomatic", "Persuasive", "Empathetic", "Concise", "Casual", "Enthusiastic", "Professional"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How your text sounds").font(.headline)
                ForEach(model.metrics.tones) { t in
                    HStack {
                        Text(t.emoji).font(.title2)
                        Text(t.name)
                        Spacer()
                        ProgressView(value: t.strength).frame(width: 110)
                    }
                }
                Divider()
                meter("Formality", model.metrics.formalityScore, "Casual", "Formal")
                meter("Sentiment", (model.metrics.sentiment + 1) / 2, "Negative", "Positive")
                Divider()
                Text("Adjust tone").font(.headline)
                Text("Rewrite the selection (or the whole document) to sound different, using on-device AI.").font(.callout).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    ForEach(targets, id: \.self) { t in
                        Button(t) { target = t; adjust() }.buttonStyle(.bordered).disabled(working || !AIEngine.available)
                    }
                }
                if working { ProgressView("Rewriting as \(target.lowercased())…").controlSize(.small) }
                if !AIEngine.available { Text(AIEngine.unavailableReason).font(.caption).foregroundStyle(.orange) }
                if !Store.shared.prefs.brandTone.isEmpty {
                    Divider()
                    Label("Brand tone: \(Store.shared.prefs.brandTone)", systemImage: "building.2").font(.callout)
                    Button("Match brand tone") { target = "brand"; adjust() }.disabled(working || !AIEngine.available)
                }
            }
            .padding(16)
        }
    }

    private func meter(_ title: String, _ v: Double, _ lo: String, _ hi: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [.orange.opacity(0.4), .blue.opacity(0.4)], startPoint: .leading, endPoint: .trailing)).frame(height: 6)
                    Circle().fill(.white).shadow(radius: 1).frame(width: 14).offset(x: max(0, min(g.size.width - 14, g.size.width * v - 7)))
                }
            }.frame(height: 14)
            HStack { Text(lo); Spacer(); Text(hi) }.font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func adjust() {
        let src = model.selectedOrAllText
        guard !src.isEmpty else { return }
        working = true
        let instr = target == "brand"
            ? "Rewrite the text to match this brand voice: \(Store.shared.prefs.brandTone)."
            : "Rewrite the text so it sounds \(target.lowercased()), keeping every point and fact."
        Task {
            if let r = await AIEngine.transform(src, instr, goals: model.goals, brand: Store.shared.prefs.brandTone) { model.replaceSelectionOrAll(r) }
            working = false
        }
    }
}

// MARK: Scores

struct ScoresPanel: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var store = Store.shared

    var body: some View {
        let m = model.metrics
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ScoreRing(score: m.overall, size: 80)
                    VStack(alignment: .leading) {
                        Text("Performance").font(.title3.bold())
                        Text("Based on suggestions per 100 words and your goals.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(IssueGroup.allCases) { g in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle().fill(g.color).frame(width: 8)
                            Text(g.label).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(m.groupScores[g] ?? 100)").monospacedDigit().bold()
                        }
                        ProgressView(value: Double(m.groupScores[g] ?? 100), total: 100).tint(g.color)
                        Text(g.blurb).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text("Readability").font(.headline)
                grid([
                    ("Readability score", "\(Int(m.readability))", m.readabilityLabel),
                    ("Grade level", String(format: "%.1f", m.gradeLevel), "Flesch–Kincaid"),
                    ("Avg. sentence", String(format: "%.1f words", m.avgSentenceLength), m.avgSentenceLength > 22 ? "Try shorter sentences" : "Good"),
                    ("Avg. word", String(format: "%.1f letters", m.avgWordLength), ""),
                ])
                Text("Vocabulary").font(.headline)
                grid([
                    ("Unique words", String(format: "%.0f%%", m.uniqueWords), "Variety"),
                    ("Rare words", String(format: "%.0f%%", m.rareWords), "Long, uncommon words"),
                ])
                Text("Counts").font(.headline)
                grid([
                    ("Words", "\(m.words)", ""), ("Characters", "\(m.characters)", ""),
                    ("Sentences", "\(m.sentences)", ""), ("Paragraphs", "\(m.paragraphs)", ""),
                    ("Reading time", formatTime(m.readingTime), ""), ("Speaking time", formatTime(m.speakingTime), ""),
                ])
                Divider()
                Text("Your progress").font(.headline)
                grid([
                    ("Fixes accepted", "\(store.stats.suggestionsAccepted)", "All time"),
                    ("Dismissed", "\(store.stats.suggestionsDismissed)", ""),
                ])
                if !store.stats.mistakesByKind.isEmpty {
                    Text("Your most common fixes").font(.subheadline.weight(.semibold))
                    ForEach(store.stats.mistakesByKind.sorted { $0.value > $1.value }.prefix(5), id: \.key) { k, v in
                        HStack { Text(k); Spacer(); Text("\(v)").monospacedDigit().foregroundStyle(.secondary) }.font(.callout)
                    }
                }
            }
            .padding(16)
        }
    }

    private func formatTime(_ minutes: Double) -> String {
        let s = Int(minutes * 60)
        return s < 60 ? "\(s) sec" : "\(s / 60) min \(s % 60) sec"
    }

    private func grid(_ items: [(String, String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
            ForEach(items, id: \.0) { t, v, sub in
                VStack(alignment: .leading, spacing: 2) {
                    Text(t).font(.caption).foregroundStyle(.secondary)
                    Text(v).font(.title3.weight(.semibold)).monospacedDigit()
                    if !sub.isEmpty { Text(sub).font(.caption2).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }
        }
    }
}
