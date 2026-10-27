// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation
import CoreServices

/// Small built-in thesaurus with a fallback to the macOS thesaurus (Dictionary Services).
enum Synonyms {

    static let table: [String: [String]] = [
        "important": ["crucial", "essential", "significant"], "help": ["assist", "support", "aid"],
        "use": ["employ", "apply", "utilize"], "show": ["demonstrate", "reveal", "display"],
        "make": ["create", "produce", "build"], "think": ["believe", "consider", "suppose"],
        "need": ["require", "must have", "depend on"], "want": ["wish", "desire", "hope"],
        "change": ["alter", "modify", "adjust"], "start": ["begin", "launch", "initiate"],
        "end": ["finish", "conclude", "close"], "improve": ["enhance", "refine", "strengthen"],
        "problem": ["issue", "challenge", "difficulty"], "result": ["outcome", "effect", "consequence"],
        "idea": ["concept", "notion", "proposal"], "people": ["individuals", "everyone", "the public"],
        "great": ["excellent", "outstanding", "remarkable"], "work": ["effort", "labor", "task"],
        "team": ["group", "crew", "squad"], "project": ["initiative", "undertaking", "venture"],
        "provide": ["supply", "offer", "deliver"], "create": ["build", "develop", "produce"],
        "different": ["distinct", "varied", "diverse"], "new": ["fresh", "novel", "recent"],
        "many": ["numerous", "several", "countless"], "also": ["additionally", "too", "as well"],
        "however": ["yet", "still", "nevertheless"], "because": ["since", "as", "given that"],
        "said": ["stated", "explained", "noted"], "says": ["states", "explains", "notes"],
        "really": ["truly", "genuinely", "very"], "best": ["finest", "top", "ideal"],
        "customer": ["client", "buyer", "user"], "customers": ["clients", "buyers", "users"],
        "time": ["period", "moment", "while"], "way": ["method", "approach", "means"],
        "data": ["information", "figures", "details"], "process": ["procedure", "method", "workflow"],
        "system": ["platform", "framework", "setup"], "goal": ["aim", "objective", "target"],
        "plan": ["strategy", "scheme", "proposal"], "happy": ["glad", "pleased", "delighted"],
        "sad": ["unhappy", "sorrowful", "downcast"], "quickly": ["rapidly", "swiftly", "promptly"],
        "easy": ["simple", "effortless", "straightforward"], "hard": ["difficult", "tough", "demanding"],
        "beautiful": ["lovely", "gorgeous", "stunning"], "write": ["compose", "draft", "author"],
        "writing": ["prose", "composition", "text"], "small": ["little", "compact", "minor"],
        "large": ["big", "sizable", "substantial"], "fast": ["quick", "rapid", "speedy"],
        "look": ["appear", "seem", "glance"], "feel": ["sense", "experience", "perceive"],
        "know": ["understand", "recognize", "realize"], "find": ["discover", "locate", "identify"],
        "give": ["offer", "provide", "grant"], "keep": ["retain", "maintain", "hold"],
        "try": ["attempt", "aim", "strive"], "learn": ["discover", "master", "pick up"],
        "company": ["business", "firm", "organization"], "product": ["offering", "item", "solution"],
        "user": ["customer", "person", "member"], "users": ["customers", "people", "members"],
        "feature": ["capability", "function", "tool"], "features": ["capabilities", "functions", "tools"],
        "suggest": ["recommend", "propose", "advise"], "develop": ["build", "create", "grow"],
        "support": ["help", "back", "assist"], "allow": ["let", "enable", "permit"],
    ]

    static func lookup(_ word: String) -> [String] {
        let w = word.lowercased()
        if let s = table[w] { return s }
        return systemThesaurus(w)
    }

    /// Reads synonyms from the macOS thesaurus when available.
    static func systemThesaurus(_ word: String) -> [String] {
        let ns = word as NSString
        guard let raw = DCSCopyTextDefinition(nil, ns, CFRange(location: 0, length: ns.length))?.takeRetainedValue() as String? else {
            return []
        }
        // Thesaurus entries look like "word | noun | syn1, syn2, ..."; dictionary entries rarely contain long comma lists.
        let candidates = raw.components(separatedBy: CharacterSet(charactersIn: "|:;"))
            .filter { $0.components(separatedBy: ",").count >= 3 }
        guard let best = candidates.first else { return [] }
        return best.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty && $0.split(separator: " ").count <= 2 && $0.lowercased() != word && $0.allSatisfy { $0.isLetter || $0 == " " || $0 == "-" } }
            .prefix(3).map { $0 }
    }
}
