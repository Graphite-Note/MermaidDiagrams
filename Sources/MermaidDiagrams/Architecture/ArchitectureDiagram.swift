/**
 * File: ArchitectureDiagram.swift
 * -------------------------------
 * Layer: Core
 * Description: An architecture diagram read from Mermaid text: its services and junctions, its groups nested in one
 *              another, its edges between sides, its alignments and its options, as Pele's architecture database keeps them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// An architecture diagram (`architecture-beta`), as Pele's `ArchitectureDb` holds it once its statements are checked:
/// every group, then the services, then the junctions, then the edges and alignments, each naming the others by place.
public struct ArchitectureDiagram: Equatable, Sendable {
    public internal(set) var title: String?
    public internal(set) var accessibilityTitle: String?
    public internal(set) var accessibilityDescription: String?
    /// The services in the order written, then the junctions in the order written, as Pele's map of nodes holds them.
    public internal(set) var nodes: [ArchitectureNode] = []
    /// The groups in the order written; a group's parent comes before it.
    public internal(set) var groups: [ArchitectureGroup] = []
    public internal(set) var edges: [ArchitectureEdge] = []
    public internal(set) var alignments: [ArchitectureAlignment] = []
    public internal(set) var options = ArchitectureOptions()
}

/// A service (an icon in a square with its title below) or a junction (a dot edges meet at).
public struct ArchitectureNode: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case service
        case junction
    }

    public let identifier: String
    public let kind: Kind
    /// The icon's name (`server`, `logos:aws-ec2`); nil for none.
    public let icon: String?
    /// The text written in quotation marks in place of an icon (`service a "DB"`).
    public let iconText: String?
    public let title: String?
    /// The group it is in, by its place in the diagram's groups.
    public let groupIndex: Int?
}

/// A group: a box round the services, junctions and groups in it.
public struct ArchitectureGroup: Equatable, Sendable {
    public let identifier: String
    public let icon: String?
    public let title: String?
    /// The group it is in, by its place, which comes before its own.
    public let parentIndex: Int?
}

/// A side of a service or a junction, by Mermaid's letter.
public enum ArchitectureSide: Int, Equatable, Sendable {
    case left = 0
    case right = 1
    case top = 2
    case bottom = 3

    /// The unit step out of the side, x to the right and y down.
    var step: (dx: Int, dy: Int) {
        switch self {
        case .left: (-1, 0)
        case .right: (1, 0)
        case .top: (0, -1)
        case .bottom: (0, 1)
        }
    }
}

/// An edge from a side of one node to a side of another (`a:R --> L:b`).
public struct ArchitectureEdge: Equatable, Sendable {
    public let sourceIndex: Int
    public let sourceSide: ArchitectureSide
    /// `<` before the line: an arrow at the source.
    public let hasSourceArrow: Bool
    /// `{group}` after the source: the edge leaves from the border of the source's group.
    public let leavesSourceGroup: Bool
    public let targetIndex: Int
    public let targetSide: ArchitectureSide
    public let hasTargetArrow: Bool
    public let entersTargetGroup: Bool
    /// The text written between `-[` and `]-`.
    public let title: String?
}

/// `align row a b c` or `align column a b c`: nodes put beside each other or under each other.
public struct ArchitectureAlignment: Equatable, Sendable {
    public let isRow: Bool
    public let memberIndices: [Int]
}

/// The front matter's and directives' `architecture:` options Pele reads, each within its bounds.
public struct ArchitectureOptions: Equatable, Sendable {
    /// `iconSize`, 8 to 512: a service's square.
    public internal(set) var iconSize: CGFloat = 48
    /// `fontSize`, 4 to 128, or nil for the diagram's.
    public internal(set) var fontSize: CGFloat?
    /// `padding`, 0 to 256: room round a group's content.
    public internal(set) var padding: CGFloat = 20

    public init() {}

    init(_ options: MermaidConfigurationOptions) {
        iconSize = CGFloat(options.boundedNumber("iconSize", fallback: 48, least: -.infinity, largest: 512).clamped(least: 8))
        if case .number(let size) = options.values["fontSize"], size.isFinite { fontSize = CGFloat(min(128, max(4, size))) }
        padding = CGFloat(options.boundedNumber("padding", fallback: 20, least: -.infinity, largest: 256).clamped(least: 0))
    }
}

extension Double {
    /// The number, or `least` when it is below it.
    fileprivate func clamped(least: Double) -> Double {
        Swift.max(self, least)
    }
}

/// What broke an architecture diagram's syntax, or a statement its database refuses, by the identifier it names.
public enum ArchitectureSyntaxProblem: Equatable, Sendable {
    /// The text does not start with `architecture-beta`.
    case expectedKeyword
    /// A group, a service, a junction, an edge, an alignment, a title or a line break was expected.
    case expectedStatement
    /// A line break or the end of the text was expected after a statement.
    case expectedLineEnd
    case expectedIdentifier
    case expectedColon
    /// A side (`L`, `R`, `T` or `B`) was expected.
    case expectedSide
    /// `--`, or `-` and a title, was expected between an edge's sides.
    case expectedLine
    /// A title in brackets after `-`, or the `-` after it.
    case expectedEdgeTitle
    /// `row` or `column` after `align`.
    case expectedRowOrColumn
    case identifierInUse(String)
    case parentMissing(String)
    case placedInItself(String)
    case parentNotAGroup(String)
    /// An edge names an identifier not declared before it.
    case edgeEndMissing(String)
    /// An edge names a group, where Mermaid fails with a TypeError.
    case edgeEndIsAGroup(String)
    /// `{group}` on an edge between two nodes of one group.
    case groupModifierWithinOneGroup(String)
    /// An alignment names something that is not a service or a junction.
    case alignmentMemberNotANode(String)
    case alignmentMemberRepeated(String)
}
