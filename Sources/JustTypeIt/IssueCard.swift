// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import SwiftUI

/// One suggestion: what's wrong, why, and one-click fixes.
struct IssueCard: View {
    let issue: Issue
    @ObservedObject var model: EditorModel
    var compact = false
    var onDone: () -> Void = {}
    @VState private var expanded = false
    @VState private var rewrites: [String] = []
    @VState private var loadingRewrites = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(issue.group.color).frame(width: 8, height: 8)
                Text(issue.group.label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                Text(issue.title).font(.caption.weight(.semibold))
                if issue.source == .ai { Image(systemName: "sparkles").font(.caption2).foregroundStyle(.purple) }
                Spacer()
            }
            if !issue.replacements.isEmpty {
                fixRow
            } else if issue.range.length <= 60 {
                Text(issue.original).font(.callout).strikethrough(false).foregroundStyle(.primary).lineLimit(2)
            }
            if compact || expanded || model.selectedIssueID == issue.id {
                Text(issue.explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if issue.replacements.isEmpty, issue.range.length > 20, AIEngine.available { rewriteBlock }
                actions
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.selectedIssueID == issue.id ? issue.group.color.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { if !compact { expanded.toggle(); model.select(issue) } }
    }

    private var fixRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if issue.range.length <= 80 {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(issue.original).strikethrough().foregroundStyle(.secondary).lineLimit(3)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                }
            }
            FlowButtons(options: issue.replacements, color: issue.group.color) { rep in
                model.accept(issue, replacement: rep)
                onDone()
            }
        }
    }

    private var rewriteBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if rewrites.isEmpty {
                Button {
                    loadingRewrites = true
                    Task {
                        rewrites = await AIEngine.rewriteSentence(issue.original, goals: model.goals, brand: Store.shared.prefs.brandTone)
                        loadingRewrites = false
                    }
                } label: {
                    Label(loadingRewrites ? "Writing…" : "Suggest rewrites", systemImage: "sparkles")
                }
                .disabled(loadingRewrites)
            }
            ForEach(rewrites, id: \.self) { r in
                Button { model.accept(issue, replacement: r); onDone() } label: {
                    Text(r).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(issue.group.color.opacity(0.1)))
                }.buttonStyle(.plain)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 14) {
            Button { model.dismiss(issue); onDone() } label: { Label("Dismiss", systemImage: "trash") }
            if issue.kind.hasPrefix("Spelling") {
                Button { model.addToDictionary(issue); onDone() } label: { Label("Add to dictionary", systemImage: "book") }
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct FlowButtons: View {
    let options: [String]
    let color: Color
    let action: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(options.prefix(4).enumerated()), id: \.offset) { _, o in
                Button { action(o) } label: {
                    Text(o.isEmpty ? "Remove" : o)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(color))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
