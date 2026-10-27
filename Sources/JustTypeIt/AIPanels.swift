// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import SwiftUI

/// Shows a generated result with insert / replace / copy actions.
struct ResultBox: View {
    let text: String
    @ObservedObject var model: EditorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(minHeight: 80, maxHeight: 320)
            HStack {
                Button("Insert") { model.insertAtCursor(text) }
                Button("Replace") { model.replaceSelectionOrAll(text) }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }.controlSize(.small)
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.07)))
    }
}

struct AIUnavailableNote: View {
    var body: some View {
        if !AIEngine.available {
            Label(AIEngine.unavailableReason, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        }
    }
}

// MARK: Generative AI

struct GeneratePanel: View {
    @ObservedObject var model: EditorModel
    @VState private var prompt = ""
    @VState private var result = ""
    @VState private var working = false
    @VState private var chat: [(Bool, String)] = []
    @VState private var chatInput = ""

    struct Action: Identifiable { var id: String { name }; let name: String; let icon: String; let instruction: String; let usesDoc: Bool }

    let quick: [Action] = [
        Action(name: "Improve it", icon: "wand.and.stars", instruction: "Improve the text: fix all errors and make it clearer and more engaging while keeping the meaning.", usesDoc: true),
        Action(name: "Shorten it", icon: "arrow.down.right.and.arrow.up.left", instruction: "Make the text significantly shorter and more concise, keeping every key point.", usesDoc: true),
        Action(name: "Expand it", icon: "arrow.up.left.and.arrow.down.right", instruction: "Expand the text with more detail and complete sentences without inventing facts.", usesDoc: true),
        Action(name: "Simplify it", icon: "text.badge.minus", instruction: "Rewrite the text in simple, plain English that anyone can understand.", usesDoc: true),
        Action(name: "Summarize", icon: "list.bullet.rectangle", instruction: "Summarize the text in 3–5 short bullet points.", usesDoc: true),
        Action(name: "Make an outline", icon: "list.number", instruction: "Create a clear, structured outline (headings and bullet points) for the text or topic.", usesDoc: true),
        Action(name: "Brainstorm ideas", icon: "lightbulb", instruction: "Brainstorm 8 fresh, specific ideas or angles related to the text or topic, as a numbered list.", usesDoc: true),
        Action(name: "Write a reply", icon: "arrowshape.turn.up.left", instruction: "The text is a message the user received. Write a helpful, polite reply in the user's voice (first person).", usesDoc: true),
        Action(name: "Continue writing", icon: "text.append", instruction: "Continue writing from where the text ends, in the same style, for one or two paragraphs. Output only the continuation.", usesDoc: true),
        Action(name: "Write a title", icon: "textformat.size", instruction: "Suggest 5 strong titles or subject lines for the text, one per line.", usesDoc: true),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AIUnavailableNote()
                Text("Draft anything").font(.headline)
                TextField("e.g. Write an email asking my manager for Friday off", text: $prompt, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Write draft") {
                        run(instruction: "Write the content the user asks for. \(AIEngine.goalsLine(model.goals, brand: Store.shared.prefs.brandTone))", input: prompt)
                    }.buttonStyle(.borderedProminent).disabled(prompt.isEmpty || working)
                    Button("Email draft") {
                        run(instruction: "Write a complete, ready-to-send email (with a subject line on the first line, prefixed 'Subject:') for the user's request.", input: prompt)
                    }.disabled(prompt.isEmpty || working)
                }
                Text("Quick actions (selection or whole document)").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(quick) { a in
                        Button { run(instruction: a.instruction, input: model.selectedOrAllText) } label: {
                            Label(a.name, systemImage: a.icon).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered).disabled(working || model.text.isEmpty)
                    }
                }
                if working { ProgressView("Writing on-device…").controlSize(.small) }
                if !result.isEmpty { ResultBox(text: result, model: model) }
                Divider()
                Text("Chat about your document").font(.headline)
                ForEach(Array(chat.enumerated()), id: \.offset) { _, m in
                    Text(m.1).textSelection(.enabled).padding(8)
                        .frame(maxWidth: .infinity, alignment: m.0 ? .trailing : .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(m.0 ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05)))
                }
                HStack {
                    TextField("Ask anything…", text: $chatInput).textFieldStyle(.roundedBorder).onSubmit(sendChat)
                    Button("Send", action: sendChat).disabled(chatInput.isEmpty || working)
                }
            }
            .padding(16)
        }
    }

    private func run(instruction: String, input: String) {
        working = true
        result = ""
        Task {
            result = await AIEngine.generate(instruction, input.isEmpty ? "(no text)" : "TEXT:\n<<<\n\(input.prefix(6000))\n>>>") ?? "Sorry, the on-device model couldn't complete this. Try a shorter text."
            working = false
        }
    }

    private func sendChat() {
        let q = chatInput.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        chat.append((true, q))
        chatInput = ""
        working = true
        let history = chat.suffix(6).map { ($0.0 ? "User: " : "Assistant: ") + $0.1 }.joined(separator: "\n")
        Task {
            let ins = "You are a helpful writing assistant. Answer briefly. The user's current document is below.\nDOCUMENT:\n\(model.text.prefix(3000))"
            let a = await AIEngine.generate(ins, history) ?? "Sorry, I couldn't answer that."
            chat.append((false, a))
            working = false
        }
    }
}

// MARK: Agents

struct AgentsPanel: View {
    @ObservedObject var model: EditorModel
    @VState private var agent = "Proofreader"
    @VState private var result = ""
    @VState private var working = false
    @VState private var rubric = ""
    @VState private var paraMode = "Standard"

    let agents: [(String, String, String)] = [
        ("Proofreader", "checkmark.circle", "Fixes every error and polishes the whole text in one pass."),
        ("Paraphraser", "arrow.triangle.2.circlepath", "Rewords the text in a new way, in the mode you pick."),
        ("Reader Reactions", "person.wave.2", "Predicts what your audience will take away and ask."),
        ("AI Grader", "graduationcap", "Grades your writing against a rubric with feedback."),
        ("Humanizer", "person.crop.circle.badge.checkmark", "Makes AI-sounding text read naturally and personally."),
        ("Expert Review", "brain.head.profile", "Feedback from a subject-matter expert on substance and logic."),
    ]
    let modes = ["Standard", "Fluent", "Formal", "Simple", "Creative", "Shorten", "Expand", "Academic"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AIUnavailableNote()
                ForEach(agents, id: \.0) { a in
                    Button { agent = a.0; result = "" } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: a.1).font(.title3).frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.0).font(.headline)
                                Text(a.2).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 9).fill(agent == a.0 ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.04)))
                    }.buttonStyle(.plain)
                }
                if agent == "Paraphraser" {
                    Picker("Mode", selection: $paraMode) { ForEach(modes, id: \.self) { Text($0) } }
                }
                if agent == "AI Grader" {
                    Text("Rubric or assignment (optional)").font(.caption)
                    TextEditor(text: $rubric).frame(height: 70).border(Color.primary.opacity(0.1))
                }
                Button { runAgent() } label: { Label("Run \(agent)", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).disabled(working || model.text.isEmpty || !AIEngine.available)
                if working { ProgressView("\(agent) is working…").controlSize(.small) }
                if !result.isEmpty { ResultBox(text: result, model: model) }
            }
            .padding(16)
        }
    }

    private func runAgent() {
        let src = model.selectedOrAllText
        let g = model.goals
        let brand = Store.shared.prefs.brandTone
        working = true
        result = ""
        Task {
            var out: String?
            switch agent {
            case "Proofreader":
                out = await AIEngine.transform(src, "Proofread the text: correct all spelling, grammar, punctuation and word-choice errors and smooth awkward phrasing. Change as little as needed.", goals: g, brand: brand)
            case "Paraphraser":
                out = await AIEngine.transform(src, "Paraphrase the text in \(paraMode.lowercased()) mode: express the same meaning with different wording and sentence structure.", goals: g, brand: brand)
            case "Reader Reactions":
                out = await AIEngine.readerReactions(src, audience: g.audience)
            case "AI Grader":
                out = await AIEngine.grade(src, rubric: rubric)
            case "Humanizer":
                out = await AIEngine.transform(src, "Rewrite the text so it sounds natural and human: vary sentence length, use plain everyday words and contractions, remove clichés and stock phrases like 'delve', 'moreover', 'in today's fast-paced world'. Keep every fact.", goals: g, brand: brand)
            default:
                out = await AIEngine.generate("You are an expert in the \(g.domain.label.lowercased()) domain reviewing the text. Give specific feedback on accuracy, logic, missing points and structure, as bullet points.", "TEXT:\n<<<\n\(src.prefix(6000))\n>>>")
            }
            result = out ?? "The on-device model couldn't complete this. Try a shorter selection."
            working = false
        }
    }
}
