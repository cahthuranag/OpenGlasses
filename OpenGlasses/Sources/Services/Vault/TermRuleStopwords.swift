import Foundation

/// The function words [[TermRule]] leaves out, one short list per language (Plan JY P0).
///
/// Written for this plan, not taken from a published list: the articles, pronouns, prepositions,
/// conjunctions, auxiliaries and question words a question is phrased with, and nothing a manual
/// would name a part or a value by. Words under three letters are dropped by length anyway, so
/// the lists carry the longer ones. Lowercase; Arabic is compared after `normalisedArabic`.
/// Provisional: Plan JY P3 measures them with each language group.
enum TermRuleStopwords {

    static func words(for language: TermRule.StemLanguage) -> Set<String> {
        switch language {
        case .german: return german
        case .spanish: return spanish
        case .french: return french
        case .hungarian: return hungarian
        case .italian: return italian
        case .dutch: return dutch
        case .polish: return polish
        case .portuguese: return portuguese
        case .ukrainian: return ukrainian
        case .russian: return russian
        case .urdu: return urdu
        case .cyrillic: return cyrillic
        }
    }

    static let german: Set<String> = [
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einer", "eines", "einem", "einen",
        "und", "oder", "aber", "auch", "als", "auf", "aus", "bei", "bis", "durch", "für", "gegen",
        "mit", "nach", "ohne", "über", "unter", "von", "vor", "zum", "zur", "zwischen", "beim", "vom",
        "ist", "sind", "war", "waren", "wird", "werden", "wurde", "wurden", "hat", "haben", "hatte",
        "kann", "können", "muss", "müssen", "soll", "sollte", "darf", "nicht", "kein", "keine",
        "wie", "was", "wer", "wann", "warum", "welche", "welcher", "welches", "wieviel", "wo",
        "dieser", "diese", "dieses", "sich", "ihr", "ihre", "sie", "wir", "ich", "man", "noch",
        "nur", "schon", "sehr", "dann", "denn", "wenn", "dass", "hier", "dort", "alle", "mehr",
    ]

    static let spanish: Set<String> = [
        "los", "las", "del", "una", "unos", "unas", "que", "por", "para", "con", "sin", "sobre",
        "entre", "desde", "hasta", "como", "cómo", "cuál", "cuáles", "cuándo", "dónde", "qué",
        "quién", "cuánto", "cuánta", "cuántos", "son", "está", "están", "ser", "fue", "era", "hay",
        "tiene", "tienen", "debe", "deben", "puede", "pueden", "este", "esta", "estos", "estas",
        "ese", "esa", "eso", "esos", "esas", "muy", "más", "menos", "también", "pero", "porque",
        "cuando", "donde", "sus", "nos", "les", "todo", "todos", "toda", "todas", "cada", "otro",
    ]

    static let french: Set<String> = [
        "les", "des", "une", "est", "sont", "dans", "pour", "par", "avec", "sans", "sur", "sous",
        "entre", "vers", "chez", "que", "qui", "quoi", "quel", "quelle", "quels", "quelles",
        "comment", "quand", "pourquoi", "combien", "leur", "leurs", "son", "ses", "nos", "vos",
        "ont", "avoir", "être", "était", "sera", "fait", "faut", "peut", "doit", "doivent",
        "cette", "ces", "cet", "aux", "mais", "donc", "car", "pas", "plus", "moins", "très",
        "aussi", "tout", "tous", "toute", "toutes", "elle", "elles", "ils", "nous", "vous",
    ]

    static let hungarian: Set<String> = [
        "egy", "azt", "ezt", "van", "vannak", "volt", "lesz", "kell", "lehet", "nem", "igen",
        "hogy", "mint", "amely", "amelyik", "ami", "aki", "mit", "mikor", "hol", "hogyan", "miért",
        "melyik", "mennyi", "milyen", "mekkora", "vagy", "meg", "még", "már", "csak", "után", "előtt",
        "alatt", "felett", "között", "által", "számára", "minden", "ennek", "annak", "ezek",
        "azok", "itt", "ott", "is", "sem", "pedig", "mert", "majd",
    ]

    static let italian: Set<String> = [
        "gli", "una", "uno", "del", "della", "dei", "delle", "degli", "dal", "dalla", "che", "chi",
        "cosa", "come", "quando", "dove", "perché", "qual", "quale", "quali", "quanto", "quanta", "per",
        "con", "senza", "tra", "fra", "sul", "sulla", "nel", "nella", "alla", "allo", "agli",
        "alle", "non", "più", "meno", "molto", "anche", "sono", "essere", "stato", "deve",
        "devono", "può", "possono", "questo", "questa", "questi", "queste", "quello", "quella",
        "suo", "sua", "loro", "tutto", "tutti",
    ]

    static let dutch: Set<String> = [
        "het", "een", "van", "voor", "met", "door", "naar", "over", "onder", "tussen", "bij", "uit",
        "tot", "als", "dat", "die", "dit", "deze", "wat", "wie", "waar", "wanneer", "waarom", "hoe",
        "hoeveel", "welke", "welk", "zijn", "was", "waren", "wordt", "worden", "werd", "heeft",
        "hebben", "had", "kan", "kunnen", "moet", "moeten", "mag", "niet", "geen", "ook", "maar",
        "dan", "nog", "wel", "zeer", "meer", "alle", "hun", "zich", "ons", "onze",
    ]

    static let polish: Set<String> = [
        "jest", "są", "był", "była", "było", "być", "się", "nie", "tak", "jak", "jaka", "jaki",
        "jakie", "jakiej", "który", "która", "które", "których", "gdzie", "kiedy", "dlaczego",
        "ile", "czy", "dla", "bez", "przez", "przed", "pod", "nad", "między", "przy", "oraz",
        "lub", "ale", "też", "także", "tylko", "jego", "jej", "ich", "ten", "tej", "tego", "tym",
        "tych", "może", "można", "należy", "musi", "jeśli", "gdy",
    ]

    static let portuguese: Set<String> = [
        "uma", "uns", "umas", "dos", "das", "que", "por", "para", "com", "sem", "sobre", "entre",
        "desde", "até", "como", "qual", "quais", "quando", "onde", "quem", "quanto", "quanta",
        "são", "está", "estão", "ser", "foi", "era", "tem", "têm", "deve", "devem", "pode",
        "podem", "este", "esta", "estes", "estas", "esse", "essa", "isso", "muito", "mais",
        "menos", "também", "mas", "porque", "seu", "sua", "seus", "suas", "todo", "todos",
        "toda", "todas", "cada", "outro", "nos", "nas", "pelo", "pela",
    ]

    static let ukrainian: Set<String> = [
        "яка", "який", "яке", "які", "якої", "якого", "хто", "коли", "чому", "скільки", "для",
        "без", "через", "перед", "під", "над", "між", "при", "після", "від", "або", "але",
        "також", "тільки", "його", "її", "їх", "цей", "ця", "це", "ці", "той", "та", "те", "ті",
        "бути", "був", "була", "було", "були", "має", "мають", "може", "можна", "треба", "слід",
        "потрібно", "якщо", "вже", "ще", "дуже", "так", "про", "щоб", "чи",
    ]

    static let russian: Set<String> = [
        "какая", "какой", "какое", "какие", "каков", "какова", "каково", "что", "кто", "где", "когда", "почему", "сколько",
        "для", "без", "через", "перед", "под", "над", "между", "при", "после", "или", "также",
        "только", "его", "её", "их", "этот", "эта", "это", "эти", "тот", "быть", "был", "была",
        "было", "были", "есть", "имеет", "может", "можно", "нужно", "надо", "следует", "если",
        "уже", "ещё", "очень", "так", "как", "чтобы", "про",
    ]

    /// Cyrillic text whose language was not settled.
    static let cyrillic: Set<String> = ukrainian.union(russian)

    static let urdu: Set<String> = [
        "کیا", "ہیں", "تھا", "تھی", "تھے", "لیے", "لئے", "ایک", "کرنا", "کرتے", "کرتا", "ہوتا",
        "ہوتی", "ہوتے", "نہیں", "کتنا", "کتنی", "کتنے", "کہاں", "کیوں", "کیسے", "والا", "والی",
        "والے", "اور", "بھی", "سکتا", "سکتی", "سکتے", "چاہیے", "کون", "جب", "تک", "پھر", "یہاں",
    ]

    static let arabic: Set<String> = Set([
        "هي", "هو", "هذا", "هذه", "ذلك", "تلك", "التي", "الذي", "الذين", "على", "إلى", "عن", "مع",
        "بعد", "قبل", "عند", "حتى", "أو", "ثم", "لم", "لن", "هل", "كيف", "متى", "أين", "لماذا",
        "كم", "أي", "كان", "كانت", "يكون", "تكون", "يجب", "يمكن", "ليس", "بين", "كل", "بعض",
        "غير", "أن", "إن", "ألا", "إلا", "ماذا", "فيه", "فيها", "منه", "منها",
    ].map(TermRule.normalisedArabic))

    // MARK: - Endings (Plan JY P3)

    /// The case and verb endings a word in a heavily inflected language may carry, longest first:
    /// stripped from a word before its prefix is kept, so a word shorter than the prefix length
    /// meets its other forms ("жінка", "жінкою" → "жінк"). Written for this plan; one ending is
    /// stripped, only when at least `TermRule.minimumStemAfterEnding` letters are left.
    static func endings(for group: TermRule.Group) -> [String] {
        switch group {
        case .cyrillic: return cyrillicEndings
        case .latinHeavy: return latinHeavyEndings
        case .latinLight: return latinLightEndings
        default: return []
        }
    }

    static let cyrillicEndings: [String] = [
        "ьтеся", "ться", "ются", "ются", "ется", "ится", "ішся", "ешся",
        "ами", "ями", "ові", "еві", "єві", "ого", "его", "ому", "ему", "ими", "іми", "ыми", "ях", "ах", "иях",
        "ів", "їв", "ов", "ев", "ою", "ею", "єю", "ий", "ій", "ый", "ой", "ей", "им", "ім", "ым", "их", "іх", "ых",
        "ом", "ем", "ам", "ям", "ая", "яя", "ое", "ее", "ую", "юю", "ть", "ти", "ла", "ли", "ло", "ся", "сь",
        "ут", "ют", "ать", "ять", "ить", "ити", "ати",
        "а", "я", "у", "ю", "ы", "и", "і", "ї", "е", "є", "о", "ь", "й",
    ].sorted { $0.count > $1.count }

    static let latinHeavyEndings: [String] = [
        // German
        "ungen", "ern", "en", "er", "es", "em", "e", "n", "s",
        // Polish
        "ami", "ach", "owi", "ego", "emu", "ych", "ich", "ymi", "imi", "ów", "om", "ie", "ia", "iu", "ą", "ę",
        "y", "a", "u", "o", "i",
        // Hungarian
        "ban", "ben", "nak", "nek", "val", "vel", "ból", "ből", "hoz", "hez", "höz", "ról", "ről", "nál", "nél",
        "ra", "re", "ba", "be", "on", "en", "ön", "at", "et", "ot", "öt", "ok", "ek", "ök", "ak", "t", "k",
    ].reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.sorted { $0.count > $1.count }

    static let latinLightEndings: [String] = [
        "mente", "ções", "ción", "zione", "ciones", "zioni", "ões", "es", "os", "as", "is", "ns", "en",
        "e", "a", "o", "s", "i",
    ].sorted { $0.count > $1.count }

    /// Pieces a question is phrased with: question words, demonstratives, and the polite and verb
    /// endings that attach to everything ("です", "합니다").
    static let bigrams: Set<String> = [
        // Chinese (Simplified; Traditional text is folded first)
        "什么", "这篇", "这个", "那个", "这些", "那些", "哪些", "哪个", "怎么", "怎样", "如何", "为什",
        "请问", "一下", "我们", "你们", "他们", "是否", "可以", "多少", "是什",
        // Japanese
        "です", "すか", "ます", "でし", "まし", "ませ", "した", "して", "いる", "てい", "ある", "られ",
        "れる", "する", "され", "ので", "から", "まで", "など", "この", "その", "あの", "どの", "どう",
        "なに", "何で",
        // Korean
        "어떤", "무엇", "어떻", "떻게", "합니", "니다", "니까", "습니", "입니", "있습", "됩니", "하는",
    ]

    /// The particles a Korean word may end in, longest first (P3).
    static let koreanParticles: [String] = [
        "에서는", "으로는", "에게서", "까지", "부터", "에서", "으로", "에게", "한테", "보다", "처럼", "하고", "이나",
        "은", "는", "이", "가", "을", "를", "의", "에", "도", "로", "와", "과", "만",
    ].sorted { $0.count > $1.count }

    /// One-character runs that are particles, not terms.
    static let singleCharacters: Set<String> = [
        "的", "了", "是", "在", "和", "与", "及", "或", "吗", "呢",
        "の", "は", "を", "に", "が", "で", "と", "も", "か", "へ",
        "은", "는", "이", "가", "을", "를", "의", "에", "도",
    ]
}
