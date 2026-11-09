// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import Foundation

/// Spanish grammar, accent and spelling rules. Only mistakes that are wrong in every Spanish-speaking
/// country are flagged; everything else (spelling of ordinary words) comes from macOS's Spanish dictionary.
enum SpanishRules {

    static func r(_ p: String, _ rep: String, _ kind: String, _ title: String, _ why: String,
                  group: IssueGroup = .correctness, ci: Bool = true) -> PatternRule {
        PatternRule(pattern: p, replacement: rep, group: group, kind: kind, title: title, explanation: why, caseInsensitive: ci)
    }

    static let all: [PatternRule] = accents + haber + articles + grammar + spelling + capitals

    /// Question words keep their accent in questions: ¿Qué…?, ¿Cómo…?
    static let accents: [PatternRule] = {
        let words = ["que": "qué", "como": "cómo", "donde": "dónde", "cuando": "cuándo", "cual": "cuál", "cuales": "cuáles",
                     "quien": "quién", "quienes": "quiénes", "cuanto": "cuánto", "cuanta": "cuánta", "cuantos": "cuántos", "cuantas": "cuántas",
                     "adonde": "adónde"]
        var out = words.sorted { $0.key < $1.key }.map { w, a in
            r("¿(\\s*)([\(w.prefix(1).uppercased())\(w.prefix(1))])\(w.dropFirst())\\b", "¿$1$2\(a.dropFirst())", "Spanish/Accent", "Tilde",
              "En preguntas, “\(a)” lleva tilde. (Question words take an accent.)", ci: false)
        }
        out += [
            r("¿(\\s*)([Pp])or que\\b", "¿$1$2or qué", "Spanish/Accent", "Tilde", "En preguntas se escribe “por qué”, separado y con tilde.", ci: false),
            r("¿(\\s*)([Pp])orque\\b", "¿$1$2or qué", "Spanish/Accent", "Tilde", "En preguntas se escribe “por qué”, separado y con tilde.", ci: false),
            r("\\b(tu) (eres|tienes|estás|estas|puedes|sabes|quieres|vas|haces|dices|necesitas|crees|piensas|debes|tenías|eras|fuiste)\\b", "tú $2",
              "Spanish/Accent", "Tú / tu", "“Tú” (pronombre) lleva tilde; “tu” sin tilde es posesivo (tu casa)."),
            r("\\b(el) (es|está|tiene|fue|era|dijo|quiere|puede|va|sabe|vino|hizo|tenía|estaba|necesita|cree|piensa|trabaja|vive)\\b", "él $2",
              "Spanish/Accent", "Él / el", "“Él” (pronombre) lleva tilde; “el” sin tilde es artículo (el libro)."),
            r("\\b(para|a|de|por|sin|contra|hacia|según|entre) mi(?=\\s*[.,;:!?)]|\\s*$|\\s+(?:mismo|misma|me|también|tampoco|es|no)\\b)", "$1 mí",
              "Spanish/Accent", "Mí / mi", "Después de una preposición, el pronombre “mí” lleva tilde (para mí, a mí me gusta)."),
            r("\\b(que|claro que|pues|eso|creo que|dijo que|dije que) si(?=\\s*[.,!?]|\\s*$)", "$1 sí",
              "Spanish/Accent", "Sí / si", "“Sí” afirmativo lleva tilde (creo que sí)."),
            r("\\b(esta) (bien|mal|listo|claro|aquí|allí|ahí|seguro|segura|disponible|haciendo|trabajando|esperando|incluido|incluida|terminado|terminada)\\b", "está $2",
              "Spanish/Accent", "Está / esta", "El verbo “está” lleva tilde; “esta” sin tilde es demostrativo (esta casa)."),
            r("\\b(estas) (bien|mal|seguro|segura|seguros|seguras|listo|lista|haciendo|trabajando|ocupado|ocupada)\\b", "estás $2",
              "Spanish/Accent", "Estás / estas", "El verbo “estás” lleva tilde; “estas” sin tilde es demostrativo (estas casas)."),
            r("\\b(cada vez|lo|los|las|mucho|mucha|muchos|muchas|aún|todavía|un poco|algo|nada|mucho|cada día) mas\\b", "$1 más",
              "Spanish/Accent", "Más / mas", "“Más” (cantidad) lleva tilde; “mas” sin tilde significa “pero”."),
            r("\\b(mas) (o menos|de lo|que nada|tarde|temprano|bien|grande|pequeño|importante|fácil|difícil|rápido|información|detalles|tiempo)\\b", "más $2",
              "Spanish/Accent", "Más / mas", "“Más” (cantidad) lleva tilde; “mas” sin tilde significa “pero”."),
        ]
        return out
    }()

    /// "Haber" used impersonally (there is/are) is always singular: "había muchas personas".
    static let haber: [PatternRule] = {
        let qty = "(muchas|muchos|varias|varios|unas|unos|pocas|pocos|algunas|algunos|demasiadas|demasiados|bastantes|dos|tres|cuatro|cinco|diez|cien|problemas|personas|cambios|errores|quejas|dudas|\\d+)"
        let why = "Con el sentido de “existir”, “haber” es impersonal y va en singular: “había muchas personas”, “hubo problemas”."
        var out = [("habían", "había"), ("hubieron", "hubo"), ("habrán", "habrá"), ("habrían", "habría"), ("hayan", "haya")].map { pl, sg in
            r("(?<!\\b(?:se|les|los|las|me|te|nos|que se) )\\b(\(pl)) \(qty)\\b", "\(sg) $2", "Spanish/Haber", "Haber impersonal", why)
        }
        out += [
            r("\\b(va|van|iba|iban) haber\\b", "$1 a haber", "Spanish/Haber", "Va a haber", "Falta la preposición “a”: “va a haber”."),
            r("\\b(vamos|voy|vas) haber\\b", "$1 a ver", "Spanish/Haber", "A ver / haber", "“A ver” (de “ver”) se escribe separado: “vamos a ver”."),
            r("(?<!\\b(?:puede|pueda|podría|debe|debería|tiene que|suele|parece|va a|tiene) )\\bhaber si\\b", "a ver si", "Spanish/Haber", "A ver / haber",
              "“A ver si…” se escribe separado (de “ver”)."),
            r("\\b(a) (sido|tenido|habido|podido|llegado|terminado|recibido|trabajado|hablado|comprado|olvidado|pasado por alto)\\b", "ha $2",
              "Spanish/Haber", "Ha / a", "Con el participio va el verbo “ha” (con h): “ha sido”."),
            r("\\b(he|has|ha|hemos|habéis|han|había|habían|haber) echo\\b", "$1 hecho", "Spanish/Haber", "Hecho / echo",
              "“Hecho” (de “hacer”) se escribe con h: “he hecho”."),
            r("\\b(haiga|haigan)\\b", "haya", "Spanish/Haber", "Haya", "La forma correcta es “haya”."),
            r("\\bahí que (\\w+(?:ar|er|ir))\\b", "hay que $1", "Spanish/Hay", "Hay / ahí", "“Hay que” (verbo haber); “ahí” es un lugar."),
            r("\\b(por|de) hay\\b(?!\\s+(?:que|un|una|mucho|mucha|muchos|muchas|algo|nada|más|menos|varios|varias)\\b)", "$1 ahí",
              "Spanish/Hay", "Ahí / hay", "“Ahí” indica lugar (por ahí, de ahí); “hay” es del verbo haber."),
            r("\\bhay (está|están|estaba|tienes|va|viene|lo|la|los|las)\\b", "ahí $1", "Spanish/Hay", "Ahí / hay",
              "“Ahí” indica lugar (ahí está); “hay” es del verbo haber."),
        ]
        return out
    }()

    /// Article–noun gender for common nouns that look like the other gender.
    static let articles: [PatternRule] = [
        r("\\b(la) (problema|sistema|tema|programa|día|idioma|mapa|clima|dilema|esquema|planeta|programa|correo|mensaje)\\b", "el $2",
          "Spanish/Gender", "Género", "Este sustantivo es masculino: “el problema”, “el sistema”, “el día”."),
        r("\\b(una) (problema|sistema|tema|programa|día|idioma|mapa|dilema|esquema|planeta|correo|mensaje)\\b", "un $2",
          "Spanish/Gender", "Género", "Este sustantivo es masculino: “un problema”, “un día”."),
        r("\\b(el) (mano|foto|moto|gente|calle|noche|tarde|clase|leche|carne|llave|mente|sede|reunión|razón|opción|información|empresa)\\b", "la $2",
          "Spanish/Gender", "Género", "Este sustantivo es femenino: “la mano”, “la foto”, “la reunión”."),
        r("\\b(un) (mano|foto|moto|calle|noche|clase|llave|reunión|razón|opción|empresa)\\b", "una $2",
          "Spanish/Gender", "Género", "Este sustantivo es femenino: “una reunión”, “una foto”."),
        r("\\bde el\\b", "del", "Spanish/Contraction", "Del", "“De” + “el” se contrae en “del” (salvo nombres propios como “El Salvador”).", ci: false),
        r("(?<![\\w¿¡])a el\\b", "al", "Spanish/Contraction", "Al", "“A” + “el” se contrae en “al”.", ci: false),
    ]

    static let grammar: [PatternRule] = [
        // Dequeísmo: "pienso de que" → "pienso que".
        r("\\b(pienso|piensa|piensas|pensamos|piensan|pensaba|creo|crees|cree|creemos|creen|creía|opino|opina|opinamos|dijo|dije|dijeron|dicen|considero|considera|supongo|supone|me parece|le parece|nos parece|parece|espero|esperamos|imagino|resulta|es posible|es necesario|es probable) de que\\b", "$1 que",
          "Spanish/Dequeismo", "Dequeísmo", "Con este verbo no se usa “de que”: “pienso que”, “creo que”."),
        // Queísmo: "me di cuenta que" → "me di cuenta de que".
        r("\\b(me di|te diste|se dio|nos dimos|se dieron|darse|me doy|te das|se da|nos damos|se dan) cuenta que\\b", "$1 cuenta de que",
          "Spanish/Queismo", "Queísmo", "“Darse cuenta” lleva “de”: “me di cuenta de que”."),
        r("\\b(estoy|está|estás|estamos|están|estaba|estábamos|estaban) (seguro|segura|seguros|seguras|convencido|convencida|convencidos|convencidas) que\\b", "$1 $2 de que",
          "Spanish/Queismo", "Queísmo", "“Estar seguro / convencido” lleva “de”: “estoy seguro de que”."),
        r("\\ba pesar que\\b", "a pesar de que", "Spanish/Queismo", "A pesar de que", "La locución es “a pesar de que”."),
        // Old preterite forms with an extra -s: "dijistes" → "dijiste".
        r("\\b(dij|fu|hic|vin|tuv|estuv|pud|quis|com|sal|escrib|recib|lleg|habl|mand|envi|dej|pens|trabaj|termin|pas|olvid|llam|compr)(iste|aste)s\\b", "$1$2",
          "Spanish/Verb", "Forma verbal", "El pretérito de “tú” no lleva -s final: “dijiste”, “llegaste”."),
        r("\\b(en base a)\\b", "con base en", "Spanish/Style", "En base a", "Se recomienda “con base en”, “basándose en” o “a partir de”.", group: .clarity),
        r("\\b(Hola|Buenos días|Buenas tardes|Buenas noches)( [A-ZÁÉÍÓÚÑ][\\wáéíóúñ.]*(?: [A-ZÁÉÍÓÚÑ][\\wáéíóúñ.]*){0,3})(?=[ \\t]*$)", "$1$2,",
          "Punctuation/GreetingComma", "Falta coma", "El saludo va seguido de coma: “Hola Ana,”.", ci: false),
    ]

    static let spelling: [PatternRule] = {
        let pairs: [(String, String)] = [
            ("a la ves", "a la vez"), ("tal ves", "tal vez"), ("otra ves", "otra vez"), ("una ves", "una vez"), ("cada ves", "cada vez"),
            ("talvez", "tal vez"), ("osea", "o sea"), ("aveces", "a veces"), ("enserio", "en serio"), ("porfavor", "por favor"),
            ("apesar", "a pesar"), ("haci", "así"), ("aser", "hacer"), ("asiendo", "haciendo"), ("echo de menos", "echo de menos"),
            ("nose", "no sé"), ("nos vemos mañana", "nos vemos mañana"), ("almenos", "al menos"), ("encambio", "en cambio"),
            ("deacuerdo", "de acuerdo"), ("sinembargo", "sin embargo"), ("hechar", "echar"), ("ubiera", "hubiera"), ("ubo", "hubo"),
            ("nesecito", "necesito"), ("nesesito", "necesito"), ("nececito", "necesito"), ("exelente", "excelente"), ("ecelente", "excelente"),
            ("interezante", "interesante"), ("dijieron", "dijeron"), ("trajieron", "trajeron"), ("conducí", "conduje"),
        ].filter { $0.0 != $0.1 }
        return pairs.map { wrong, right in
            r("\\b\(wrong)\\b", right, "Spanish/Spelling", "Ortografía", "Se escribe “\(right)”.")
        }
    }()

    /// Days, months and languages are lowercase in Spanish.
    static let capitals: [PatternRule] = [
        r("(?<=\\b(?:el|los|este|próximo|cada|del|al|desde el|hasta el) )(Lunes|Martes|Miércoles|Jueves|Viernes|Sábado|Domingo)\\b", "LOWER:$1",
          "Spanish/Capitalization", "Minúscula", "En español, los días de la semana se escriben con minúscula.", ci: false),
        r("(?<=\\b\\d{1,2} de )(Enero|Febrero|Marzo|Abril|Mayo|Junio|Julio|Agosto|Septiembre|Setiembre|Octubre|Noviembre|Diciembre)\\b", "LOWER:$1",
          "Spanish/Capitalization", "Minúscula", "En español, los meses se escriben con minúscula.", ci: false),
        r("(?<=\\b(?:en|el|del|hablo|habla|hablas|hablamos|hablan|idioma|traducir al|traducido al) )(Español|Inglés|Francés|Italiano|Alemán|Portugués|Chino|Japonés)\\b", "LOWER:$1",
          "Spanish/Capitalization", "Minúscula", "En español, los idiomas se escriben con minúscula.", ci: false),
    ]
}
