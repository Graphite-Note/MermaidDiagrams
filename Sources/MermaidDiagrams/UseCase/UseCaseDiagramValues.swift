/**
 * File: UseCaseDiagramValues.swift
 * --------------------------------
 * Layer: Core
 * Description: What a use case diagram's model gives to read: its actors, use cases, system boundaries, relationships,
 *              notes, JSON tables and class definitions as values made when read, and the kinds they are of.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

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
