/**
 * File: UseCaseDiagram.swift
 * --------------------------
 * Layer: Core
 * Description: A Mermaid use case diagram (`usecase-beta`) as Pele's model holds it once read: its actors, use cases,
 *              system boundaries, relationships, notes, JSON tables and class definitions, in the order first mentioned.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A Mermaid use case diagram as Pele's `resolveUsecase` holds it: every actor and use case in the order its id is first
/// mentioned, the system boundaries and JSON tables likewise, the relationships and notes in the order written.
public struct UseCaseDiagram: Equatable, Sendable {
    public internal(set) var actors: [UseCaseActor] = []
    public internal(set) var useCases: [UseCase] = []
    public internal(set) var systemBoundaries: [UseCaseSystemBoundary] = []
    public internal(set) var relationships: [UseCaseRelationship] = []
    public internal(set) var notes: [UseCaseNote] = []
    public internal(set) var jsonNodes: [UseCaseJSONNode] = []
    /// `classDef` statements, each name once in the order first defined, its styles those of its last definition.
    public internal(set) var classDefinitions: [UseCaseClassDefinition] = []
    /// `direction …`, left to right unless written.
    public internal(set) var direction: UseCaseDirection = .leftToRight
    /// The front matter's `title:`; a use case diagram has no title statement.
    public var title: String?
    /// `accTitle: …`, empty unless written.
    public internal(set) var accessibilityTitle = ""
    /// `accDescr: …` or `accDescr { … }`, the indentation of its lines dropped, empty unless written.
    public internal(set) var accessibilityDescription = ""
    /// The options `usecase.nodeSpacing` and `usecase.rankSpacing` of the front matter or a directive, when numbers above
    /// zero (cut to 2,000): the gap between nodes of a rank and between ranks.
    public internal(set) var nodeSpacing: Double?
    public internal(set) var rankSpacing: Double?

    /// The diagram turned to run down, when it runs across (left to right or right to left), as Pele draws it for a
    /// narrow column; nil when it runs down already.
    public var turnedToRunDown: UseCaseDiagram? {
        guard direction == .leftToRight || direction == .rightToLeft else { return nil }
        var turned = self
        turned.direction = .topToBottom
        return turned
    }
}

/// Whether a label is drawn as written or read as Markdown (a string written `"`…`"`).
public enum UseCaseLabelType: String, Equatable, Sendable {
    case text
    case markdown
}

/// How an actor is drawn: a stick figure, its outline, a filled figure, or a box for an icon.
public enum UseCaseActorType: String, Equatable, Sendable {
    case normal
    case hollow
    case awesome
    case icon
}

public struct UseCaseActor: Equatable, Sendable {
    public let identifier: String
    public internal(set) var label: String
    public internal(set) var labelType: UseCaseLabelType
    public internal(set) var type: UseCaseActorType
    /// `icon: …`, which makes the actor's type `icon`.
    public internal(set) var icon: String?
    /// `business: true`, drawn with a slash across its head.
    public internal(set) var isBusiness: Bool
    /// `<<…>>`, without its brackets.
    public internal(set) var stereotype: String?
    /// The system boundary the actor is declared in.
    public internal(set) var parentIdentifier: String?
    public internal(set) var classes: [String]
    /// `style` declarations, in the order written.
    public internal(set) var styles: [String]
}

/// A use case's outline: an ellipse (`Id(…)` or no label), or a rectangle (`Id[…]`).
public enum UseCaseShape: String, Equatable, Sendable {
    case ellipse
    case rectangle = "rect"
}

public struct UseCase: Equatable, Sendable {
    public let identifier: String
    public internal(set) var label: String
    public internal(set) var labelType: UseCaseLabelType
    public internal(set) var shape: UseCaseShape
    public internal(set) var isBusiness: Bool
    public internal(set) var stereotype: String?
    public internal(set) var parentIdentifier: String?
    public internal(set) var classes: [String]
    public internal(set) var styles: [String]
}

/// A system boundary's look: a box, or a box under a tab that holds its title (`type: package`).
public enum UseCaseBoundaryType: String, Equatable, Sendable {
    case rectangle = "rect"
    case package
}

public struct UseCaseSystemBoundary: Equatable, Sendable {
    public let identifier: String
    public internal(set) var label: String
    public internal(set) var labelType: UseCaseLabelType
    public internal(set) var type: UseCaseBoundaryType
    /// The actors and use cases declared in it, in the order written.
    public internal(set) var members: [String]
    public internal(set) var classes: [String]
    public internal(set) var styles: [String]
}

/// What a relationship says: an association, or a use case's `include` or `extend` of another (`..> : include`), or a
/// generalization (`--|>`).
public enum UseCaseRelationshipType: String, Equatable, Sendable {
    case association
    case include
    case extend
    case generalization
}

/// An association's marks, as Mermaid's `ARROW_TYPE` numbers them.
public enum UseCaseArrow: Int, Equatable, Sendable {
    /// `-->`: an arrowhead at the target.
    case solidArrow
    /// `<--`: an arrowhead at the source.
    case backArrow
    /// `--`: no mark.
    case lineSolid
    /// `--o`, `--x`: a circle or a cross at the target.
    case circleArrow
    case crossArrow
    /// `o--`, `x--`: a circle or a cross at the source.
    case circleArrowReversed
    case crossArrowReversed
}

/// How fast Mermaid animates a relationship's dashes; a still drawing keeps the dashes.
public enum UseCaseAnimation: String, Equatable, Sendable {
    case fast
    case slow
}

public struct UseCaseRelationship: Equatable, Sendable {
    /// Its explicit id (`A login@--> B`), else `edge-` and its number among those without one.
    public let identifier: String
    public let hasExplicitIdentifier: Bool
    public let source: String
    public let target: String
    public let type: UseCaseRelationshipType
    public let arrow: UseCaseArrow
    public let label: String?
    public let labelType: UseCaseLabelType?
    /// Each dash beyond the second asks for one more rank between the ends: at least 1.
    public let minimumLength: Int
    public internal(set) var classes: [String]
    public internal(set) var styles: [String]
    public internal(set) var isAnimated: Bool
    public internal(set) var animation: UseCaseAnimation?
}

/// `note for Target text`, its id `note-` and its number.
public struct UseCaseNote: Equatable, Sendable {
    public let identifier: String
    public let target: String
    public let label: String
    public let labelType: UseCaseLabelType
}

/// `json Id@{ … }`: a table of one row per leaf of a JSON object, its keys in the order written.
public struct UseCaseJSONNode: Equatable, Sendable {
    public let identifier: String
    public let value: UseCaseJSONValue
    public internal(set) var classes: [String]
    public internal(set) var styles: [String]
}

public struct UseCaseClassDefinition: Equatable, Sendable {
    public let identifier: String
    public internal(set) var styles: [String]
}

/// The way a use case diagram's ranks follow each other.
public enum UseCaseDirection: String, Equatable, Sendable {
    case topToBottom = "TB"
    case bottomToTop = "BT"
    case leftToRight = "LR"
    case rightToLeft = "RL"
}
