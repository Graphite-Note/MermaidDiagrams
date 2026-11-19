/**
 * File: FlowchartNode.swift
 * -------------------------
 * Layer: Core
 * Description: A node of a flowchart and the shapes it is drawn in.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

/// A node of a flowchart: the identifier edges name it by, the text drawn in it and its shape.
public struct FlowchartNode: Equatable, Sendable {
    public let identifier: String
    /// The node's text; its identifier when the diagram gives none.
    public internal(set) var label: DiagramLabel
    public internal(set) var shape: FlowchartNodeShape
    /// What `classDef`, `class`, `:::` and `style` set for the node's colors, or nil when they set none.
    public internal(set) var style: DiagramElementStyle?

    init(identifier: String, label: DiagramLabel, shape: FlowchartNodeShape = .rectangle, style: DiagramElementStyle? = nil) {
        self.identifier = identifier
        self.label = label
        self.shape = shape
        self.style = style
    }
}

/// The shapes a flowchart node is drawn in, Pele's catalogue (`svg/shapes.ts`): Mermaid's classic shapes, written with
/// brackets around the text (`A[text]`, `A{text}`) or by name (`A@{ shape: diam }`), and the shapes written by name
/// only (`A@{ shape: cloud }`), each named by Mermaid's documented names (`documentedNames`).
public enum FlowchartNodeShape: Equatable, Sendable, CaseIterable {
    /// `[text]`.
    case rectangle
    /// `(text)`.
    case roundedRectangle
    /// `([text])`.
    case stadium
    /// `[[text]]`, a rectangle with a line inside each end.
    case subroutine
    /// `[(text)]`, a database.
    case cylinder
    /// `((text))`.
    case circle
    /// `(((text)))`.
    case doubleCircle
    /// `>text]`, a flag notched on its left.
    case asymmetric
    /// `{text}`, a decision.
    case diamond
    /// `{{text}}`.
    case hexagon
    /// `[/text/]`, a parallelogram leaning right.
    case leanRight
    /// `[\text\]`, a parallelogram leaning left.
    case leanLeft
    /// `[/text\]`, wider at the bottom.
    case trapezoid
    /// `[\text/]`, wider at the top.
    case invertedTrapezoid
    /// `@{ shape: text }`: the text alone, without an outline.
    case text
    /// `(-text-)`.
    case ellipse
    /// `datastore`: a box open at its ends, a line along its top and its bottom.
    case dataStore
    /// `folder`: a box with a tab along the left of its top.
    case folder
    /// `bucket`: a pail, wider at its rim.
    case bucket
    /// `console`: a window with a prompt in its title bar.
    case console
    /// `browser`: a window with three dots in its title bar.
    case browser
    /// `person`: a head above a rounded body.
    case person
    /// `bang`: a burst of fourteen spikes.
    case bang
    /// `cloud`.
    case cloud
    /// `notch-rect`, a card: a rectangle with its top left corner cut.
    case card
    /// `lin-rect`: a rectangle with a line inside its left end.
    case linedRectangle
    /// `sm-circ`, a start: a small circle without text.
    case smallCircle
    /// `fr-circ`, a stop: a small circle around a filled one, without text.
    case framedCircle
    /// `fork`, a fork or join: a filled bar without text.
    case forkJoin
    /// `hourglass`, a collate: two triangles point to point, without text.
    case hourglass
    /// `brace`, a comment: the text with a curly brace on its left.
    case leftBrace
    /// `brace-r`: the text with a curly brace on its right.
    case rightBrace
    /// `braces`: the text between two curly braces.
    case braces
    /// `bolt`, a communication link: a lightning bolt without text.
    case lightningBolt
    /// `doc`: a sheet whose bottom edge waves.
    case document
    /// `delay`: a rectangle rounded on its right end.
    case delay
    /// `h-cyl`, direct access storage: a cylinder lying on its side.
    case horizontalCylinder
    /// `lin-cyl`, a disk: a cylinder with a second rim under its top.
    case linedCylinder
    /// `curv-trap`, a display: pointed on the left, rounded on the right.
    case curvedTrapezoid
    /// `div-rect`, a divided process: a rectangle with a band along its top.
    case dividedRectangle
    /// `tri`, an extract: a triangle pointing up.
    case triangle
    /// `win-pane`, internal storage: a rectangle with a band along its top and its left.
    case windowPane
    /// `f-circ`, a junction: a small filled circle without text.
    case filledCircle
    /// `notch-pent`, a loop limit: a rectangle with both top corners cut.
    case notchedPentagon
    /// `flip-tri`, a manual file: a triangle pointing down.
    case flippedTriangle
    /// `sl-rect`, a manual input: a rectangle whose top slopes up to the right.
    case slopedRectangle
    /// `docs`: three documents stacked.
    case stackedDocument
    /// `st-rect`: three rectangles stacked.
    case stackedRectangle
    /// `bow-rect`, stored data: concave on the right, convex on the left.
    case bowTieRectangle
    /// `cross-circ`, a summary: a circle crossed by its diagonals, without text.
    case crossedCircle
    /// `tag-doc`: a document with a mark across its lower right corner.
    case taggedDocument
    /// `tag-rect`: a rectangle with a mark across its lower right corner.
    case taggedRectangle
    /// `flag`, a paper tape: a band whose top and bottom wave.
    case paperTape
    /// `lin-doc`: a document with a line inside its left end.
    case linedDocument
    /// A collapsed group drawn as one node (`group@{ view: collapsed }`): two boxes, one behind the other.
    case collapsedGroup

    /// The shape a `shape:` attribute names, by Mermaid's documented short name or any of its aliases, as Pele writes
    /// them (`squareRect`, `stateStart`), or nil for a name that is none of them.
    public init?(shapeName: String) {
        guard let shape = Self.shapesByName[shapeName] else { return nil }
        self = shape
    }

    /// Mermaid's names for the shape (the short name first), as Mermaid 12.1.0 documents them; none for an ellipse,
    /// written in brackets only, and for a collapsed group.
    var mermaidNames: [String] {
        Self.documentedNamesByShape[self] ?? []
    }

    /// Whether the shape holds its node's text: a start, a stop, a fork, a junction, a collate, a bolt and a summary
    /// are drawn without it, at their fixed sizes.
    var holdsText: Bool {
        switch self {
        case .smallCircle, .framedCircle, .forkJoin, .hourglass, .lightningBolt, .filledCircle, .crossedCircle: false
        default: true
        }
    }

    private static let documentedNamesByShape: [FlowchartNodeShape: [String]] = Dictionary(uniqueKeysWithValues: documentedNames)

    private static let shapesByName: [String: FlowchartNodeShape] = {
        var shapesByName: [String: FlowchartNodeShape] = [:]
        for (shape, names) in documentedNames {
            for name in names { shapesByName[name] = shape }
        }
        return shapesByName
    }()
}
