// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation

/// Extra grammar rules: verb forms, comparatives, uncountable nouns, tense, pronouns.
enum GrammarRules {

    static func r(_ p: String, _ rep: String, _ kind: String, _ title: String, _ why: String) -> PatternRule {
        PatternRule(pattern: p, replacement: rep, group: .correctness, kind: kind, title: title, explanation: why)
    }

    static let all: [PatternRule] = verbForms + agreement + comparatives + nouns + idioms

    static let verbForms: [PatternRule] = [
        r("\\b(I|you|we|they|he|she|it) seen\\b", "$1 saw", "Grammar/VerbForm", "Verb form",
          "“Seen” needs a helper verb (have seen). On its own, use the past tense “saw”."),
        r("\\b(has|have|had) (went|ate|wrote|took|gave|ran|began|drank|sang|swam|came|did|saw|spoke|broke|chose|drove|flew|forgot|froze|grew|knew|rode|rose|shook|stole|threw|woke|wore)\\b", "$1 PP:$2",
          "Grammar/VerbForm", "Verb form", "After has/have/had, use the past participle (e.g., “gone”, not “went”)."),
        r("\\b(didn't|did not|doesn't|does not|don't|do not|did|does|didnt|doesnt) (\\w+ed|went|saw|ate|took|gave|came|made|wrote|said|got|knew|ran|bought|thought|told|found)\\b(?<!\\b(?:did|does|didn't|doesn't|don't|do not|did not|does not|didnt|doesnt) (?:need|feed|speed|seed|bleed|breed|heed|proceed|succeed|exceed|bed|red|shed|wed|led|fed))",
          "$1 BASE:$2", "Grammar/VerbForm", "Verb form", "After do, does or did, use the base form of the verb (e.g., “did go”)."),
        r("\\b(can|could|will|would|shall|should|may|might|must) (\\w+?)(s|es)\\b(?<!\\b(?:can|could|will|would|shall|should|may|might|must) (?:is|has|was|does|goes|focus|access|process|discuss|address|express|pass|miss|guess|bless|cross|dress|press|stress|toss|kiss|less|this|thus|plus|bus|gas|yes|us|chaos|canvas|always|perhaps|series|news|class|glass|grass|mess|boss|loss|progress|success|business|harass|bias|cus|ics))",
          "$1 $2", "Grammar/VerbForm", "Verb form", "After a modal verb (can, will, should…), use the base form without -s."),
        r("\\b(did|does|do|didn't|doesn't|don't) (you|he|she|it|we|they|I) (saw|went|ate|took|gave|came|made|wrote|said|got|knew|ran|bought|thought|told|found|\\w+ed)\\b(?<! (?:need|feed|speed|seed|bleed|breed|heed|proceed|succeed|exceed|bed|red|shed|wed|led|fed))", "$1 $2 BASE:$3",
          "Grammar/VerbForm", "Verb form", "In questions with do/does/did, the main verb stays in the base form: “Did you see…?”"),
        r("\\b(look|looking|looked|looks) forward to (meet|see|hear|work|speak|talk|receive|discuss|join|connect|help|chat)\\b", "$1 forward to ING:$2",
          "Grammar/VerbForm", "Verb form", "“Look forward to” is followed by an -ing form: “look forward to meeting you”."),
        r("\\b(suggest|suggested|suggests|recommend|recommended|recommends) (me|him|her|us|them) to (\\w+)\\b", "$1 that OBJ:$2 $3",
          "Grammar/VerbForm", "Verb pattern", "“Suggest” and “recommend” don't take “someone to do”. Use “suggested that I go” or “suggested going”."),
        r("\\b(you|we|they) am\\b|\\b(you|we|they) is\\b", "", "Grammar/SubjectVerbAgreement", "Subject-verb agreement", "The verb “be” must match its subject."),
        r("\\b(am|is|are) agree\\b", "agree", "Grammar/VerbForm", "Verb form", "“Agree” is a verb by itself: say “I agree”, not “I am agree”."),
        r("\\b(will|shall) call you when (I|you|we|they|he|she) will\\b", "will call you when $2", "Grammar/VerbTense", "Verb tense",
          "In time clauses (when, after, before, as soon as) use the present tense for the future: “when I arrive”."),
        r("\\b(when|after|before|as soon as|until|once) (I|you|we|they|he|she|it) will (\\w+)\\b", "$1 $2 $3", "Grammar/VerbTense", "Verb tense",
          "In time clauses about the future, use the present tense (“when I arrive”), not “will”."),
        r("\\b(am|is|are) (living|working|studying|staying|waiting|teaching|using|learning) (here |there |in [A-Z]\\w+ |at \\w+ )?(since|for (?:\\w+ )?(?:years|months|weeks|days|hours|a long time|ages))\\b", "",
          "Grammar/VerbTense", "Verb tense", "With “since” or “for + period”, use the present perfect continuous: “I have been living here since 2010”."),
        r("\\b(I|you|we|they|he|she) (am|is|are) waiting you\\b", "$1 $2 waiting for you", "Grammar/Preposition", "Missing preposition", "“Wait” needs “for” before the person or thing: “waiting for you”."),
        r("\\b(borrow|borrowed) (me|you|him|her|us|them) (my|your|his|her|our|their|a|the)\\b", "lend $2 $3", "Spelling/AccidentallyConfused", "Borrow vs. lend",
          "You borrow something from someone; you lend something to someone."),
        r("\\b(could|couldn't) care less\\b(?<=could care less)", "couldn't care less", "Grammar/Idiom", "Idiom",
          "The standard idiom is “couldn't care less” (meaning you don't care at all)."),
        r("\\b(I|you|we|they|he|she) wish (I|he|she|it) was\\b", "$1 wish $2 were", "Grammar/Subjunctive", "Subjunctive mood",
          "After “wish”, formal English uses “were” for unreal situations: “I wish I were taller”."),
        r("\\bif I was (you|him|her|rich|taller|younger|there)\\b", "if I were $1", "Grammar/Subjunctive", "Subjunctive mood",
          "For imaginary situations, use “were”: “if I were you”."),
        r("\\b(I|we|you|they) (am|is|are) (boring|interesting|exciting|confusing|tiring|annoying|frustrating|disappointing|surprising|amazing|terrifying|embarrassing) (in|with|by|about)\\b", "$1 $2 ED:$3 $4",
          "Grammar/Participle", "-ed vs. -ing adjective", "Use -ed for how you feel (“I am bored”) and -ing for what causes the feeling (“the class is boring”)."),
        r("\\b(I|we|you|they|he|she) (am|is|are|was|were) interesting in\\b", "$1 $2 interested in", "Grammar/Participle", "-ed vs. -ing adjective",
          "Use “interested” for how you feel; “interesting” describes the thing."),
    ]

    static let agreement: [PatternRule] = [
        r("\\b(everyone|everybody|someone|somebody|anyone|anybody|no one|nobody|each|every one|either|neither) (have|are|were|do|don't|go|want|need|like|know|think)\\b", "$1 SING:$2",
          "Grammar/SubjectVerbAgreement", "Subject-verb agreement", "Words like everyone, each and neither are singular and take a singular verb."),
        r("\\b(each|either|neither|one|none) of (the|these|those|my|our|your|their|them|us)( \\w+)? (are|have|were|do)\\b", "",
          "Grammar/SubjectVerbAgreement", "Subject-verb agreement", "The subject is “each/neither/one”, which is singular: use “is”, “has” or “was”."),
        r("\\b(the|a|this|that) (list|number of|group|set|collection|series|box|bag|team|pair|quality|cost|price|purpose|goal|result|majority) of (\\w+s) (are|were|have)\\b", "",
          "Grammar/SubjectVerbAgreement", "Subject-verb agreement", "The verb agrees with the main noun (“the list”), not with the plural noun after “of”."),
        r("\\b(this) (are|were|have)\\b", "$1 SING:$2", "Grammar/SubjectVerbAgreement", "Subject-verb agreement", "“This” is singular. Use “these” with plural nouns."),
        r("\\b(those|these) (is|was|has)\\b", "$1 PLUR:$2", "Grammar/SubjectVerbAgreement", "Subject-verb agreement", "“Those” and “these” are plural and take a plural verb."),
        r("\\b(me and my (brother|sister|friend|wife|husband|mom|dad|mother|father|son|daughter|boss|team|family|partner)|my (brother|sister|friend|wife|husband) and I) (likes|loves|wants|needs|has|is|was|goes|does)\\b", "",
          "Grammar/SubjectVerbAgreement", "Subject-verb agreement", "Two people joined by “and” make a plural subject. Also use “My brother and I” as the subject."),
        r("\\b(him and me|me and him|her and me|me and her|him and I|her and I) (are|were|went|have|had|will|like|love|did|can)\\b", "",
          "Grammar/PronounCase", "Pronoun case", "Use subject pronouns as the subject: “He and I are friends.”"),
        r("\\b(to|for|with|from|between|about|at|by|like) (\\w+) and I\\b(?! (am|was|have|had|will|would|can|could|went|think|did|do))", "$1 $2 and me",
          "Grammar/PronounCase", "Pronoun case", "After a preposition, use the object pronoun “me”: “to John and me”."),
        r("\\b(it's) (tail|own|name|color|colour|size|purpose|way|place|value|goal|owner|wheels|leaves|head|shape|price|power)\\b", "its $2",
          "Spelling/AccidentallyConfused", "Its vs. it's", "“Its” (no apostrophe) is possessive; “it's” means “it is”."),
    ]

    static let comparatives: [PatternRule] = [
        r("\\b(more|less) (\\w+er)\\b(?<!\\b(?:more|less) (?:other|over|under|never|ever|either|after|water|paper|power|number|order|offer|matter|member|player|user|computer|customer|answer|letter|together|whether|rather|later|further|cover|enter|consider|remember|deliver|discover|manager|teacher|worker|partner|weather|leader|winter|summer|dinner|corner|border|center|meter|cancer|career|lower|faster))", "$2",
          "Grammar/Comparative", "Double comparative", "Don't use “more” with an -er adjective. Say “taller”, not “more taller”."),
        r("\\b(most) (\\w+est)\\b", "the $2", "Grammar/Comparative", "Double superlative", "Don't use “most” with an -est adjective. Say “the easiest”, not “the most easiest”."),
        r("\\bthe most (best|worst)\\b", "the $1", "Grammar/Comparative", "Double superlative", "“Best” and “worst” are already superlatives."),
        r("\\b(plays|play|played|did|does|do|sings|sang|works|worked|speaks|spoke|writes|wrote|runs|ran|went|goes|performed|performs|cooks|cooked|dances|danced|drives|drove) (\\w+ ){0,2}(very |really |so )?good\\b(?<!\\bgoes good|\\bwent good)", "",
          "Grammar/AdverbAdjective", "Adjective vs. adverb", "To describe how someone does something, use the adverb “well”, not “good”."),
        r("\\b(feel|feels|felt) badly\\b", "$1 bad", "Grammar/AdverbAdjective", "Adjective vs. adverb", "After linking verbs like “feel”, use the adjective: “I feel bad”."),
        r("\\b(less) (friends|people|items|cars|books|mistakes|errors|calories|words|hours|days|students|employees|problems|questions|options|emails|meetings|customers|things|cases|issues|bugs|steps)\\b", "fewer $2",
          "Grammar/FewerLess", "Fewer vs. less", "Use “fewer” for things you can count."),
    ]

    static let nouns: [PatternRule] = [
        r("\\b(informations|advices|furnitures|equipments|knowledges|feedbacks|researches|homeworks|luggages|baggages|softwares|evidences|staffs|traffics|progresses|accommodations|stuffs|news's)\\b", "SINGNOUN:$1",
          "Grammar/UncountableNoun", "Uncountable noun", "This noun is uncountable in English, so it has no plural form."),
        r("\\b(datas)\\b", "data", "Grammar/UncountableNoun", "Uncountable noun", "“Data” is already plural (or uncountable); “datas” isn't a word."),
        r("\\b(a|an) (good |great |bad |important |useful )?(news|advice|information|furniture|equipment|feedback|research|homework|luggage|software|evidence|progress|knowledge|work|traffic)\\b", "",
          "Grammar/UncountableNoun", "Uncountable noun", "Uncountable nouns don't take “a/an”. Use “some”, “a piece of”, or no article."),
        r("\\b(informations|information|advice|feedback) (are|were)\\b", "$1 SING:$2", "Grammar/UncountableNoun", "Uncountable noun", "Uncountable nouns take a singular verb."),
    ]

    static let idioms: [PatternRule] = [
        r("\\b(went|go|going|goes|came|come|coming) to (store|office|airport|bank|hospital|station|gym|library|supermarket|mall|park|beach|doctor|dentist|cinema|theater|theatre|meeting)\\b", "$1 to the $2",
          "Grammar/Articles", "Missing article", "This place usually needs “the”: “went to the store”."),
        r("\\b(go|going|went|come|came|coming|get|got|getting) to (the|my) home\\b", "$1 home", "Grammar/Articles", "Unnecessary words",
          "With verbs of movement, “home” doesn't need “to the”: “go home”."),
        r("\\b(irregardless)\\b", "regardless", "Spelling/Nonstandard", "Nonstandard word", "“Irregardless” is nonstandard. Use “regardless”."),
        r("\\bbecause of (the|a|my|our|his|her|their) (\\w+) (is|was|are|were|has|had)\\b", "because $1 $2 $3", "Grammar/Conjunction", "Because vs. because of",
          "Use “because” before a full clause (subject + verb); “because of” goes before a noun."),
        r("\\b(the team|the staff|the committee|the board|the company|the family|the government|the audience|the class) (are|were|have)\\b(?! (all|both|each))", "",
          "Grammar/CollectiveNoun", "Collective noun", "In American English, collective nouns usually take a singular verb (“the team is”). British English allows either."),
        r("\\b(\\w+), please (let|send|find|contact|feel|call|reply|confirm|see|review|advise)\\b(?<!\\b(?:hi|hello|thanks|yes|no|okay|ok|sure|so|now|again|also|first|then|and|but|or|first|finally),)", "$1. Please $2",
          "Punctuation/CommaSplice", "Comma splice", "This joins two sentences with a comma. Start a new sentence with “Please”."),
        r("\\b(alright)\\b", "all right", "Spelling/Nonstandard", "Informal spelling", "In formal writing, “all right” is the standard spelling."),
        r("\\b(supposably)\\b", "supposedly", "Spelling/Misspelled", "Misused word", "The word is “supposedly”."),
        r("\\bfor all intensive purposes\\b", "for all intents and purposes", "Grammar/Idiom", "Idiom", "The idiom is “for all intents and purposes”."),
        r("\\b(case and point)\\b", "case in point", "Grammar/Idiom", "Idiom", "The idiom is “case in point”."),
        r("\\b(nip it in the butt)\\b", "nip it in the bud", "Grammar/Idiom", "Idiom", "The idiom is “nip it in the bud”."),
        r("\\b(one in the same)\\b", "one and the same", "Grammar/Idiom", "Idiom", "The idiom is “one and the same”."),
        r("\\b(peaked|piqued|peeked) (my|your|his|her|their|our) (interest|curiosity)\\b(?<!piqued \\w{2,5} (?:interest|curiosity))", "piqued $2 $3",
          "Spelling/AccidentallyConfused", "Confused word", "Interest is “piqued” (stimulated), not “peaked” or “peeked”."),
        r("\\b(complement|complements|complemented) (on|you on)\\b", "compliment $2", "Spelling/AccidentallyConfused", "Complement vs. compliment",
          "A “compliment” is praise; a “complement” completes something."),
        r("\\b(principle) (reason|cause|investigator|goal|concern|author|source)\\b", "principal $2", "Spelling/AccidentallyConfused", "Principal vs. principle",
          "“Principal” means main or most important; a “principle” is a rule or belief."),
        r("\\b(accept) (for|that one)\\b(?<=accept for)", "except $2", "Spelling/AccidentallyConfused", "Accept vs. except",
          "“Except” means excluding; “accept” means to receive or agree."),
        r("\\b(advice) (you|him|her|them|us|me)\\b", "advise $2", "Spelling/AccidentallyConfused", "Advice vs. advise",
          "“Advise” is the verb; “advice” is the noun."),
        r("\\b(weather) (or not|to go|you|he|she|they|we|it is)\\b", "whether $2", "Spelling/AccidentallyConfused", "Weather vs. whether",
          "“Whether” introduces alternatives; “weather” is rain, sun and so on."),
        r("\\b(breath) (in|out|deeply)\\b", "breathe $2", "Spelling/AccidentallyConfused", "Breath vs. breathe", "“Breathe” is the verb; “breath” is the noun."),
        r("\\b(loose) (weight|my|your|his|her|the game|money|track|sleep)\\b", "lose $2", "Spelling/AccidentallyConfused", "Lose vs. loose",
          "“Lose” means to misplace or fail to keep; “loose” means not tight."),
        r("\\b(further) (away|down the road|north|south|east|west|from here)\\b(?<!further from here)", "farther $2", "Spelling/AccidentallyConfused", "Farther vs. further",
          "Use “farther” for physical distance and “further” for degree or extent."),
        r("\\b(t shirt|tshirt|t-shirt|tee shirt)(s?)\\b", "T-shirt$2", "Spelling/Misspelled/MissingHyphen", "Spelling", "The standard spelling is “T-shirt”."),
        r("\\b(e mail|e-mail)\\b", "email", "Spelling/Variant", "Spelling", "“Email” (no hyphen) is now the standard spelling."),
        r("\\b(difference) (colors|colours|types|sizes|options|kinds|ways|styles|models|versions|languages|countries|people|places|things|designs|flavors|products|teams|reasons)\\b", "different $2",
          "Spelling/AccidentallyConfused", "Word choice", "“Different” (adjective) describes the noun; “difference” is a noun."),
        r("\\b(alot of|a lot off)\\b", "a lot of", "Spelling/Misspelled", "Spelling", "“A lot” is two words."),
        r("\\b(every one|everyone) (of|of the)\\b(?<=everyone of|everyone of the)", "every one $2", "Spelling/AccidentallyConfused", "Every one vs. everyone",
          "Use “every one of” (two words) when you mean each single one."),
        r("\\b(i\\.e|e\\.g)\\.? (?=\\w)", "$1., ", "Punctuation/Comma", "Missing comma", "In American English, “i.e.” and “e.g.” are followed by a comma."),
    ]
}
