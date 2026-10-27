// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation

enum StyleData {

    /// Wordy phrase → concise alternative.
    static let wordy: [(String, String)] = [
        ("in order to", "to"), ("due to the fact that", "because"), ("owing to the fact that", "because"),
        ("in spite of the fact that", "although"), ("despite the fact that", "although"),
        ("at this point in time", "now"), ("at the present time", "now"), ("at this moment in time", "now"),
        ("in the event that", "if"), ("for the purpose of", "to"), ("with regard to", "about"),
        ("with respect to", "about"), ("in regard to", "about"), ("in reference to", "about"),
        ("in the near future", "soon"), ("a large number of", "many"), ("a majority of", "most"),
        ("the majority of", "most"), ("is able to", "can"), ("are able to", "can"), ("has the ability to", "can"),
        ("have the ability to", "can"), ("in close proximity to", "near"), ("on a daily basis", "daily"),
        ("on a regular basis", "regularly"), ("on a weekly basis", "weekly"), ("make a decision", "decide"),
        ("made a decision", "decided"), ("come to a conclusion", "conclude"), ("give consideration to", "consider"),
        ("take into consideration", "consider"), ("conduct an investigation", "investigate"),
        ("it is important to note that", ""), ("it should be noted that", ""), ("needless to say", ""),
        ("first and foremost", "first"), ("each and every", "every"), ("whether or not", "whether"),
        ("until such time as", "until"), ("prior to", "before"), ("subsequent to", "after"),
        ("in addition to", "besides"), ("as a matter of fact", "in fact"), ("for all intents and purposes", "essentially"),
        ("in light of the fact that", "because"), ("the reason why is that", "because"), ("the reason is because", "because"),
        ("in a timely manner", "promptly"), ("at all times", "always"), ("by means of", "by"),
        ("a sufficient number of", "enough"), ("in the process of", ""), ("during the course of", "during"),
        ("has been shown to be", "is"), ("there is no doubt that", "clearly"), ("so as to", "to"),
    ]

    /// Redundant phrase → trimmed form (tautologies).
    static let redundant: [(String, String)] = [
        ("absolutely essential", "essential"), ("advance planning", "planning"), ("added bonus", "bonus"),
        ("basic fundamentals", "fundamentals"), ("close proximity", "proximity"), ("completely finished", "finished"),
        ("end result", "result"), ("final outcome", "outcome"), ("free gift", "gift"), ("future plans", "plans"),
        ("past history", "history"), ("past experience", "experience"), ("repeat again", "repeat"),
        ("revert back", "revert"), ("return back", "return"), ("unexpected surprise", "surprise"),
        ("true facts", "facts"), ("join together", "join"), ("merge together", "merge"), ("collaborate together", "collaborate"),
        ("each individual", "each"), ("brief summary", "summary"), ("ATM machine", "ATM"), ("PIN number", "PIN"),
        ("general consensus", "consensus"), ("new innovation", "innovation"), ("still remains", "remains"),
        ("plan ahead", "plan"), ("over exaggerate", "exaggerate"), ("very unique", "unique"), ("most unique", "unique"),
        ("first began", "began"), ("may possibly", "may"), ("might possibly", "might"), ("circle around", "circle"),
        ("refer back", "refer"), ("estimated at about", "estimated at"), ("in actual fact", "in fact"),
        ("sum total", "total"), ("exact same", "same"), ("both of them together", "both"),
    ]

    /// Hedging / low-confidence language.
    static let hedges: [String] = [
        "I think maybe", "I think", "I believe", "I feel like", "I guess", "I suppose", "maybe", "perhaps",
        "sort of", "kind of", "somewhat", "probably", "just wanted to", "I'm not sure but", "I'm no expert but",
        "it seems like", "it seems that", "hopefully", "if that makes sense", "does that make sense",
        "I was wondering if", "sorry to bother you", "a little bit", "fairly", "possibly",
    ]

    /// Intensifiers and vague words (engagement).
    static let weakWords: [String: [String]] = [
        "very good": ["excellent", "great", "superb"], "very bad": ["terrible", "awful", "dreadful"],
        "very big": ["huge", "enormous", "massive"], "very small": ["tiny", "minute", "minuscule"],
        "very important": ["crucial", "essential", "vital"], "very happy": ["delighted", "thrilled", "overjoyed"],
        "very sad": ["heartbroken", "miserable", "devastated"], "very tired": ["exhausted", "drained", "worn out"],
        "very hard": ["difficult", "challenging", "arduous"], "very easy": ["effortless", "simple", "straightforward"],
        "very fast": ["rapid", "swift", "quick"], "very old": ["ancient", "aged", "antique"], "very angry": ["furious", "livid", "irate"],
        "very interesting": ["fascinating", "compelling", "intriguing"], "very beautiful": ["stunning", "gorgeous", "exquisite"],
        "very clear": ["obvious", "evident", "apparent"], "very scared": ["terrified", "petrified", "frightened"],
        "really good": ["excellent", "outstanding", "great"], "really bad": ["terrible", "awful", "poor"],
        "really important": ["crucial", "essential", "critical"], "really big": ["huge", "enormous", "vast"],
        "a lot of": ["many", "much", "plenty of"], "lots of": ["many", "plenty of", "numerous"],
        "good": ["great", "solid", "excellent"], "bad": ["poor", "weak", "harmful"], "nice": ["pleasant", "lovely", "kind"],
        "thing": ["item", "aspect", "detail"], "things": ["items", "aspects", "details"], "stuff": ["material", "items", "belongings"],
        "get": ["obtain", "receive", "earn"], "got": ["received", "obtained", "earned"], "big": ["large", "major", "significant"],
        "interesting": ["fascinating", "compelling", "intriguing"], "amazing": ["remarkable", "impressive", "astonishing"],
        "awesome": ["impressive", "outstanding", "excellent"], "basically": ["essentially", "fundamentally", ""],
        "actually": ["in fact", "", "really"], "literally": ["", "truly", "actually"], "really": ["truly", "", "genuinely"],
        "very": ["", "extremely", "highly"],
    ]

    /// Non-inclusive term → inclusive alternatives.
    static let inclusive: [(String, [String], String)] = [
        ("chairman", ["chair", "chairperson"], "Gender-neutral titles include everyone."),
        ("chairwoman", ["chair", "chairperson"], "Gender-neutral titles include everyone."),
        ("mankind", ["humankind", "humanity"], "“Humankind” includes everyone."),
        ("manpower", ["workforce", "staff"], "Gender-neutral alternatives are more inclusive."),
        ("man-hours", ["work hours", "person-hours"], "Gender-neutral alternatives are more inclusive."),
        ("policeman", ["police officer"], "Gender-neutral job titles include everyone."),
        ("policemen", ["police officers"], "Gender-neutral job titles include everyone."),
        ("fireman", ["firefighter"], "Gender-neutral job titles include everyone."),
        ("firemen", ["firefighters"], "Gender-neutral job titles include everyone."),
        ("businessman", ["businessperson", "executive"], "Gender-neutral job titles include everyone."),
        ("businessmen", ["businesspeople", "executives"], "Gender-neutral job titles include everyone."),
        ("salesman", ["salesperson", "sales representative"], "Gender-neutral job titles include everyone."),
        ("stewardess", ["flight attendant"], "Gender-neutral job titles include everyone."),
        ("mailman", ["mail carrier"], "Gender-neutral job titles include everyone."),
        ("spokesman", ["spokesperson"], "Gender-neutral job titles include everyone."),
        ("congressman", ["member of Congress", "legislator"], "Gender-neutral job titles include everyone."),
        ("freshman", ["first-year student"], "A gender-neutral alternative."),
        ("man-made", ["artificial", "synthetic"], "Gender-neutral alternatives are more inclusive."),
        ("guys", ["everyone", "folks", "team"], "When addressing a group, a neutral word includes everyone."),
        ("blacklist", ["blocklist", "denylist"], "Neutral terms avoid associating color with negativity."),
        ("whitelist", ["allowlist", "safelist"], "Neutral terms avoid associating color with value."),
        ("master branch", ["main branch"], "A more neutral technical term."),
        ("slave", ["replica", "secondary"], "In technical writing, “replica” or “secondary” is more neutral."),
        ("handicapped", ["disabled", "people with disabilities"], "Outdated term; prefer person-first or identity-first language."),
        ("crippled", ["disabled"], "This term is considered offensive."),
        ("wheelchair-bound", ["wheelchair user", "uses a wheelchair"], "Describes the person, not a limitation."),
        ("confined to a wheelchair", ["uses a wheelchair"], "Describes the person, not a limitation."),
        ("the elderly", ["older adults", "older people"], "Less stereotyping alternatives."),
        ("crazy", ["wild", "surprising", "unbelievable"], "Avoid mental-health terms used as casual descriptors."),
        ("insane", ["incredible", "extreme", "outrageous"], "Avoid mental-health terms used as casual descriptors."),
        ("lame", ["weak", "disappointing"], "This word can be ableist."),
        ("tone-deaf", ["insensitive", "oblivious"], "Avoids a disability metaphor."),
        ("illegal alien", ["undocumented immigrant"], "A more respectful term."),
        ("illegals", ["undocumented immigrants"], "A more respectful term."),
        ("third world", ["developing", "low-income"], "Outdated and hierarchical."),
        ("grandfathered", ["legacy", "exempt"], "Has discriminatory historical roots."),
        ("he or she", ["they"], "Singular “they” is inclusive and concise."),
        ("his or her", ["their"], "Singular “their” is inclusive and concise."),
    ]

    /// Informal words to flag in formal writing.
    static let informal: [(String, String)] = [
        ("gonna", "going to"), ("wanna", "want to"), ("gotta", "have to"), ("kinda", "kind of"), ("sorta", "sort of"),
        ("yeah", "yes"), ("yep", "yes"), ("nope", "no"), ("ok", "okay"), ("okay", "acceptable"), ("thanks", "thank you"),
        ("thx", "thank you"), ("pls", "please"), ("plz", "please"), ("btw", "by the way"), ("fyi", "for your information"),
        ("asap", "as soon as possible"), ("lol", ""), ("tbh", "to be honest"), ("imo", "in my opinion"), ("awesome", "excellent"),
        ("cool", "good"), ("stuff", "materials"), ("kids", "children"), ("hey", "hello"), ("hi there", "hello"),
        ("a bunch of", "many"), ("get rid of", "remove"), ("figure out", "determine"), ("check out", "review"),
    ]

    /// US spelling → British/Commonwealth spelling.
    static let usToUK: [(String, String)] = [
        ("color", "colour"), ("colors", "colours"), ("favorite", "favourite"), ("favorites", "favourites"),
        ("honor", "honour"), ("humor", "humour"), ("labor", "labour"), ("neighbor", "neighbour"), ("neighbors", "neighbours"),
        ("behavior", "behaviour"), ("flavor", "flavour"), ("rumor", "rumour"), ("center", "centre"), ("centers", "centres"),
        ("theater", "theatre"), ("meter", "metre"), ("liter", "litre"), ("fiber", "fibre"), ("organize", "organise"),
        ("organized", "organised"), ("organization", "organisation"), ("realize", "realise"), ("realized", "realised"),
        ("recognize", "recognise"), ("recognized", "recognised"), ("apologize", "apologise"), ("analyze", "analyse"),
        ("analyzed", "analysed"), ("criticize", "criticise"), ("prioritize", "prioritise"), ("optimize", "optimise"),
        ("customize", "customise"), ("emphasize", "emphasise"), ("summarize", "summarise"), ("catalog", "catalogue"),
        ("dialog", "dialogue"), ("traveled", "travelled"), ("traveling", "travelling"), ("canceled", "cancelled"),
        ("canceling", "cancelling"), ("modeling", "modelling"), ("labeled", "labelled"), ("defense", "defence"),
        ("offense", "offence"), ("gray", "grey"), ("jewelry", "jewellery"), ("aluminum", "aluminium"),
    ]
}
