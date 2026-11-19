/**
 * File: RailroadDiagram.swift
 * ---------------------------
 * Layer: Core
 * Description: A Mermaid railroad diagram as its grammar describes it, whichever of the four notations it is written
 *              in: its rules, each a tree of sequences, choices, optionals and repetitions of terminals and names.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A Mermaid railroad diagram (`railroad-beta`, `railroad-ebnf-beta`, `railroad-abnf-beta` or `railroad-peg-beta`): the
/// rules of a grammar in the order they are written, each drawn as a track, and the options its front matter or
/// directives give.
public struct RailroadDiagram: Equatable, Sendable {
    /// The notation its keyword names.
    public internal(set) var notation: RailroadNotation
    /// `title …` before the first rule (without its quotation marks), else `title:` in the front matter, else nil.
    public internal(set) var title: String?
    public internal(set) var accessibilityTitle: String?
    public internal(set) var accessibilityDescription: String?
    /// Every rule in the order it is written: a name defined twice is drawn twice.
    public internal(set) var rules: [RailroadRule]
    public internal(set) var options: RailroadOptions

    init(notation: RailroadNotation, title: String? = nil, accessibilityTitle: String? = nil, accessibilityDescription: String? = nil,
         rules: [RailroadRule] = [], options: RailroadOptions = RailroadOptions()) {
        self.notation = notation
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.rules = rules
        self.options = options
    }

    /// The rule a name refers to: the last one defined with it, as Mermaid's database looks it up.
    public func rule(named name: String) -> RailroadRule? {
        rules.last { rule in rule.name == name }
    }
}

/// Which of Mermaid's four railroad grammars a diagram is written in.
public enum RailroadNotation: String, Equatable, Sendable, CaseIterable {
    /// `railroad-beta`: Mermaid's own, a constructor call per part (`sequence(terminal("a"), nonterminal("b"))`).
    case railroad
    /// `railroad-ebnf-beta`: EBNF in the W3C and ISO 14977 styles (`rule = a | "b" , [ c ] , { d } ;`).
    case extendedBackusNaurForm = "ebnf"
    /// `railroad-abnf-beta`: ABNF as in RFC 5234, each rule closed by a semicolon (`rule = a / *b [c] %x41-5A ;`).
    case augmentedBackusNaurForm = "abnf"
    /// `railroad-peg-beta`: a parsing expression grammar (`Rule <- a / b* !c ;`).
    case parsingExpressionGrammar = "peg"

    /// The keyword that declares the notation.
    public var keyword: String {
        self == .railroad ? "railroad-beta" : "railroad-\(rawValue)-beta"
    }

    /// The notation whose keyword starts `typeKeyword` without regard to case, as Mermaid's detectors find it; nil for
    /// any other keyword. The keyword itself is read in its own case afterwards, so `RAILROAD-BETA` is a railroad
    /// diagram whose syntax is broken.
    init?(typeKeyword: String) {
        let lowercased = typeKeyword.lowercased()
        guard let notation = Self.allCases.first(where: { notation in lowercased.hasPrefix(notation.keyword) }) else { return nil }
        self = notation
    }
}

/// A rule of a railroad diagram: its name and what it stands for.
public struct RailroadRule: Equatable, Sendable {
    public let name: String
    public let definition: RailroadExpression
}

/// A part of a rule, as the four notations reduce to one tree: a sequence or a choice of one part is that part.
public indirect enum RailroadExpression: Equatable, Sendable {
    /// Text written as it is matched: drawn in a rounded box, as written.
    case terminal(String)
    /// A name of another rule: drawn in a box.
    case nonterminal(String)
    /// Text that describes what is matched (EBNF's `? … ?`, a PEG's `.` and its predicates): drawn in a dashed box.
    case special(String)
    case sequence([RailroadExpression])
    case choice([RailroadExpression])
    case optional(RailroadExpression)
    /// The part at least `minimum` and at most `maximum` times; `maximum` is infinite when it has no bound, and either
    /// is infinite for a count too large for a double, as JavaScript's `parseInt` reads it.
    case repetition(RailroadExpression, minimum: Double, maximum: Double)

    /// The most levels a rule's tree, or its brackets, nest: deeper, the rule is refused
    /// (`MermaidDiagramReadError.nestingTooDeep`), so that reading, comparing, freeing and laying it out stay well within
    /// the stack of a secondary thread (512 KiB). Sixty-four levels are far past what a drawing shows legibly.
    public static let maximumNestingDepth = 64
}

/// The options of the front matter's `config: railroad:` and of `%%{init: …}%%` directives, as written; Pele's
/// defaults and bounds are applied where the diagram is laid out.
public struct RailroadOptions: Equatable, Sendable {
    /// The size of the text in the boxes; zero for seven eighths of the font's.
    public internal(set) var fontSize: Double?
    /// The room on either side of a box's text.
    public internal(set) var padding: Double?
    /// Between the parts of a sequence, and between branches stacked one below the other.
    public internal(set) var horizontalSeparation: Double?
    public internal(set) var verticalSeparation: Double?
    /// The radius of the track's turns.
    public internal(set) var arcRadius: Double?
    /// `showMarkers: false` leaves out the dots at a track's ends.
    public internal(set) var showsMarkers: Bool = true
    public internal(set) var markerRadius: Double?
    public internal(set) var strokeWidth: Double?

    init() {}

    init(_ options: MermaidConfigurationOptions) {
        func number(_ key: String) -> Double? {
            guard case .number(let value) = options.values[key] else { return nil }
            return value
        }
        fontSize = number("fontSize")
        padding = number("padding")
        horizontalSeparation = number("horizontalSeparation")
        verticalSeparation = number("verticalSeparation")
        arcRadius = number("arcRadius")
        showsMarkers = options.values["showMarkers"] != .boolean(false)
        markerRadius = number("markerRadius")
        strokeWidth = number("strokeWidth")
    }
}

extension RailroadDiagram: TitledMermaidDiagram {}
