// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation

/// English verb and noun forms used to build grammar fixes.
enum Morph {

    // base, past, past participle
    static let irregular: [(String, String, String)] = [
        ("be", "was", "been"), ("go", "went", "gone"), ("eat", "ate", "eaten"), ("write", "wrote", "written"),
        ("take", "took", "taken"), ("give", "gave", "given"), ("run", "ran", "run"), ("begin", "began", "begun"),
        ("drink", "drank", "drunk"), ("sing", "sang", "sung"), ("swim", "swam", "swum"), ("come", "came", "come"),
        ("do", "did", "done"), ("see", "saw", "seen"), ("speak", "spoke", "spoken"), ("break", "broke", "broken"),
        ("choose", "chose", "chosen"), ("drive", "drove", "driven"), ("fly", "flew", "flown"), ("forget", "forgot", "forgotten"),
        ("freeze", "froze", "frozen"), ("grow", "grew", "grown"), ("know", "knew", "known"), ("ride", "rode", "ridden"),
        ("rise", "rose", "risen"), ("shake", "shook", "shaken"), ("steal", "stole", "stolen"), ("throw", "threw", "thrown"),
        ("wake", "woke", "woken"), ("wear", "wore", "worn"), ("make", "made", "made"), ("say", "said", "said"),
        ("get", "got", "gotten"), ("buy", "bought", "bought"), ("think", "thought", "thought"), ("tell", "told", "told"),
        ("find", "found", "found"), ("bring", "brought", "brought"), ("teach", "taught", "taught"), ("catch", "caught", "caught"),
        ("feel", "felt", "felt"), ("keep", "kept", "kept"), ("leave", "left", "left"), ("meet", "met", "met"),
        ("pay", "paid", "paid"), ("send", "sent", "sent"), ("spend", "spent", "spent"), ("build", "built", "built"),
        ("lose", "lost", "lost"), ("hold", "held", "held"), ("stand", "stood", "stood"), ("understand", "understood", "understood"),
        ("sell", "sold", "sold"), ("sit", "sat", "sat"), ("sleep", "slept", "slept"), ("win", "won", "won"),
        ("put", "put", "put"), ("set", "set", "set"), ("cut", "cut", "cut"), ("hit", "hit", "hit"), ("read", "read", "read"),
        ("lead", "led", "led"), ("hear", "heard", "heard"), ("mean", "meant", "meant"), ("fall", "fell", "fallen"),
        ("have", "had", "had"), ("hide", "hid", "hidden"), ("bite", "bit", "bitten"), ("draw", "drew", "drawn"),
        ("show", "showed", "shown"), ("lie", "lay", "lain"), ("lay", "laid", "laid"), ("light", "lit", "lit"),
    ]

    static func participle(_ past: String) -> String {
        let l = past.lowercased()
        return irregular.first { $0.1 == l }?.2 ?? l
    }

    static func base(_ w: String) -> String {
        let l = w.lowercased()
        if let e = irregular.first(where: { $0.1 == l || $0.2 == l }) { return e.0 }
        if l.hasSuffix("ied") { return String(l.dropLast(3)) + "y" }
        if l.hasSuffix("ed") {
            let stem = String(l.dropLast(2))
            if let a = stem.last, let b = stem.dropLast().last, a == b, !"lsz".contains(a) { return String(stem.dropLast()) }
            if stem.hasSuffix("at") || stem.hasSuffix("iz") || stem.hasSuffix("us") || stem.hasSuffix("v") || stem.hasSuffix("c") || stem.hasSuffix("dg") || stem.hasSuffix("ag") || stem.hasSuffix("ur") || stem.hasSuffix("as") || stem.hasSuffix("os") || stem.hasSuffix("rs") || stem.hasSuffix("ns") || stem.hasSuffix("ok") || stem.hasSuffix("ir") || stem.hasSuffix("ar") && !stem.hasSuffix("ear") {
                return stem + "e"
            }
            return stem
        }
        return l
    }

    static func ing(_ w: String) -> String {
        let l = w.lowercased()
        let special = ["see": "seeing", "be": "being", "lie": "lying", "die": "dying"]
        if let s = special[l] { return s }
        if l.hasSuffix("ie") { return String(l.dropLast(2)) + "ying" }
        if l.hasSuffix("e"), !l.hasSuffix("ee") { return String(l.dropLast()) + "ing" }
        let cvc = ["meet": false, "get": true, "run": true, "sit": true, "stop": true, "chat": true, "plan": true, "swim": true, "begin": true]
        if cvc[l] == true { return l + String(l.last!) + "ing" }
        return l + "ing"
    }

    static func thirdPerson(_ w: String) -> String {
        let l = w.lowercased()
        let special = ["have": "has", "do": "does", "go": "goes", "are": "is", "were": "was", "don't": "doesn't", "be": "is"]
        if let s = special[l] { return s }
        if l.hasSuffix("y"), let p = l.dropLast().last, !"aeiou".contains(p) { return String(l.dropLast()) + "ies" }
        if ["s", "sh", "ch", "x", "z", "o"].contains(where: l.hasSuffix) { return l + "es" }
        return l + "s"
    }

    static func subjectPronoun(_ w: String) -> String {
        ["me": "I", "him": "he", "her": "she", "us": "we", "them": "they"][w.lowercased()] ?? w
    }

    static func plural(_ w: String) -> String {
        ["is": "are", "was": "were", "has": "have", "does": "do", "doesn't": "don't"][w.lowercased()] ?? w
    }

    static func edAdjective(_ w: String) -> String {
        let l = w.lowercased()
        let map = ["boring": "bored", "interesting": "interested", "exciting": "excited", "confusing": "confused", "tiring": "tired",
                   "annoying": "annoyed", "frustrating": "frustrated", "disappointing": "disappointed", "surprising": "surprised",
                   "amazing": "amazed", "terrifying": "terrified", "embarrassing": "embarrassed"]
        return map[l] ?? l
    }

    static func singularNoun(_ w: String) -> String {
        let l = w.lowercased()
        if l.hasSuffix("ies") { return String(l.dropLast(3)) + "y" }
        if l == "news's" { return "news" }
        if l.hasSuffix("es"), ["progresses", "accommodations"].contains(l) == false, l.hasSuffix("ches") || l.hasSuffix("shes") { return String(l.dropLast(2)) }
        return l.hasSuffix("s") ? String(l.dropLast()) : l
    }

    /// Applies directive tokens in a rule replacement, e.g. "has PP:went" → "has gone".
    static func resolve(_ s: String) -> String {
        var out = s
        let ops: [(String, (String) -> String)] = [
            ("PP", participle), ("BASE", base), ("ING", ing), ("SING", thirdPerson), ("PLUR", plural),
            ("ED", edAdjective), ("SINGNOUN", singularNoun), ("OBJ", subjectPronoun),
        ]
        for (tag, f) in ops {
            for m in TextUtil.matches("\\b\(tag):([\\w']+)", in: out, caseInsensitive: false).reversed() {
                let w = TextUtil.substring(out, m.range(at: 1))
                out = (out as NSString).replacingCharacters(in: m.range, with: f(w))
            }
        }
        return out
    }
}
