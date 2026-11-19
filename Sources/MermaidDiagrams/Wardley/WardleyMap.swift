/**
 * File: WardleyMap.swift
 * ----------------------
 * Layer: Core
 * Description: A Mermaid Wardley map (`wardley-beta`) as Mermaid's builder holds it: its components and anchors with
 *              their coordinates in percent, links, evolutions, pipelines, annotations, notes, forces, stages and size.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A Mermaid Wardley map as Mermaid's builder holds it. Coordinates are percentages: x is evolution, from left to right,
/// and y is visibility, from bottom to top.
public struct WardleyMap: Equatable, Sendable {
    /// `title …`, else `title:` in the front matter.
    public internal(set) var title: String?
    public internal(set) var accessibilityTitle: String?
    public internal(set) var accessibilityDescription: String?
    /// Anchors, components and pipeline components, in the order first added.
    public internal(set) var nodes: [WardleyMapNode] = []
    public internal(set) var links: [WardleyMapLink] = []
    /// Where components are heading, one per component, a later one replacing an earlier where it stood.
    public internal(set) var trends: [WardleyMapTrend] = []
    public internal(set) var pipelines: [WardleyMapPipeline] = []
    public internal(set) var annotations: [WardleyMapAnnotation] = []
    public internal(set) var notes: [WardleyMapNote] = []
    public internal(set) var accelerators: [WardleyMapForce] = []
    public internal(set) var deaccelerators: [WardleyMapForce] = []
    /// Where the list of annotations goes, in percent, or nil for under the map.
    public internal(set) var annotationsBox: WardleyMapPoint?
    /// The evolution stages' names, or nil for Mermaid's four.
    public internal(set) var stages: [String]?
    /// The right edge of each stage from 0 to 1, when every stage gives one (`Genesis@0.2`).
    public internal(set) var stageBoundaries: [Double]?
    /// `size [width, height]`, the canvas in points.
    public internal(set) var size: WardleyMapSize?
    public internal(set) var options: WardleyMapOptions = WardleyMapOptions()

    init() {}
}

/// A point of the map in percent: x is evolution, y is visibility.
public struct WardleyMapPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
}

/// `size [width, height]`.
public struct WardleyMapSize: Equatable, Sendable {
    public let width: Double
    public let height: Double
}

/// An anchor, a component or a pipeline's component.
public struct WardleyMapNode: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case anchor
        case component
        case pipelineComponent
    }

    /// Its name, or `Parent_Name` for a pipeline's component.
    public let identifier: String
    public internal(set) var label: String
    public internal(set) var point: WardleyMapPoint
    public internal(set) var kind: Kind
    /// `label [x, y]`: where its text starts, in points from its center; nil where the map gives none.
    public internal(set) var labelOffsetX: Double?
    public internal(set) var labelOffsetY: Double?
    public internal(set) var isInPipeline = false
    public internal(set) var isPipelineParent = false
    public internal(set) var hasInertia = false
    public internal(set) var sourcing: WardleyMapSourcing?
}

/// How a component is sourced: `(build)`, `(buy)`, `(outsource)` or `(market)`.
public enum WardleyMapSourcing: String, Equatable, Sendable {
    case build, buy, outsource, market
}

/// How a link flows, from its ports or its arrow.
public enum WardleyMapFlow: Equatable, Sendable {
    case forward, backward, bidirectional
}

public struct WardleyMapLink: Equatable, Sendable {
    /// The nodes' identifiers, a name resolved to the first node that has it as its label when no node has it as its
    /// identifier; a name no node has stays as written and the link is not drawn.
    public let source: String
    public let target: String
    public let isDashed: Bool
    public let label: String?
    public let flow: WardleyMapFlow?
}

/// `evolve Component 0.8`: where a component is heading, in percent.
public struct WardleyMapTrend: Equatable, Sendable {
    public let nodeIdentifier: String
    public let target: WardleyMapPoint
}

/// A pipeline: its parent's identifier and its components' identifiers.
public struct WardleyMapPipeline: Equatable, Sendable {
    public let nodeIdentifier: String
    public internal(set) var componentIdentifiers: [String]
}

/// A numbered annotation, its circle at a point, and its text in the list.
public struct WardleyMapAnnotation: Equatable, Sendable {
    /// As JavaScript's `parseInt` reads the digits written: infinite past the largest double.
    public let number: Double
    public let point: WardleyMapPoint
    public let text: String?
}

public struct WardleyMapNote: Equatable, Sendable {
    public let text: String
    public let point: WardleyMapPoint
}

/// An accelerator or a deaccelerator: a wide arrow at a point with its name.
public struct WardleyMapForce: Equatable, Sendable {
    public let name: String
    public let point: WardleyMapPoint
}

/// The options of Wardley maps the front matter (`config:`, then `wardley-beta:`) and directives set.
public struct WardleyMapOptions: Equatable, Sendable {
    /// `width` and `height`, 1 to 1,000,000: the canvas when the map gives no size; Pele's 900 by 600 otherwise.
    public internal(set) var width: Double?
    public internal(set) var height: Double?
    /// `showGrid`: dashed lines at each quarter of the plot.
    public internal(set) var showsGrid = false

    public init() {}

    init(_ options: MermaidConfigurationOptions) {
        if case .number(let width) = options.values["width"], (1...1_000_000).contains(width) { self.width = width }
        if case .number(let height) = options.values["height"], (1...1_000_000).contains(height) { self.height = height }
        if case .boolean(true) = options.values["showGrid"] { showsGrid = true }
    }
}

/// What broke a Wardley map's syntax, or a statement its builder cannot take.
public enum WardleyMapSyntaxProblem: Equatable, Sendable {
    /// A statement was expected: a keyword, a title, an accessibility statement, a link or a line break.
    case expectedStatement
    /// A name was expected: plain, with spaces, or quoted.
    case expectedName
    /// A token of another kind was expected, by Pele's name for it (`'['`, `WARDLEY_NUMBER`, `INT`, `STRING`, `->`, `}`).
    case expectedToken(String)
    /// A line break or the end of the text was expected after a statement.
    case expectedLineEnd
    /// A coordinate, an evolution or a size is not from 0 to 1 or from 0 to 100, by the value written.
    case coordinateOutOfRange(Double)
    /// A pipeline names no component placed before it, by its name.
    case pipelineWithoutComponent(String)
}
