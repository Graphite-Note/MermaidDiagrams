/**
 * File: WardleyMapLayout.swift
 * ----------------------------
 * Layer: Core
 * Description: A Wardley map laid out on a page whose y runs down: the plot's frame, stages and axes, the pipelines, the
 *              links and evolutions, the components and anchors with their labels, the annotations, notes and forces.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A Wardley map laid out on a page whose origin is the top left corner and whose y runs down, in points, as Pele lays it
/// out: the plot's axes, evolution from left to right and visibility from bottom to top, the stages' dashed lines and
/// names under it, and everything placed at its coordinates in percent of the plot.
public struct WardleyMapLayout: Equatable, Sendable {
    public internal(set) var size: CGSize
    /// The font the title was measured in (bold); the map's text is in thirteen sixteenths of its size, links' labels and
    /// forces in one point more than eleven sixteenths, annotations' numbers in eleven sixteenths.
    public let font: DiagramFont
    public internal(set) var title: DiagramTextBlock?
    /// The plot: its bottom left corner is evolution 0 and visibility 0.
    public internal(set) var plot: CGRect
    /// The dashed lines between stages, and the grid's when the options show it.
    public internal(set) var stageLines: [DiagramPath] = []
    public internal(set) var gridLines: [DiagramPath] = []
    /// The two axes, up the left side and along the bottom.
    public internal(set) var axes: DiagramPath
    public internal(set) var stageLabels: [DiagramTextBlock] = []
    /// `Evolution` under the stages, and `Visibility` turned a quarter anticlockwise left of the plot; both drawn bold.
    public internal(set) var evolutionTitle: DiagramTextBlock?
    public internal(set) var visibilityTitle: DiagramTextBlock?
    public internal(set) var pipelines: [WardleyMapLayoutPipeline] = []
    public internal(set) var links: [WardleyMapLayoutLink] = []
    public internal(set) var trends: [WardleyMapLayoutTrend] = []
    public internal(set) var nodes: [WardleyMapLayoutNode] = []
    public internal(set) var annotations: [WardleyMapLayoutAnnotation] = []
    /// The numbered list of the annotations' texts, in its box.
    public internal(set) var annotationList: WardleyMapLayoutAnnotationList?
    /// Each note's lines, bold.
    public internal(set) var notes: [[DiagramTextBlock]] = []
    public internal(set) var forces: [WardleyMapLayoutForce] = []
}

/// A pipeline's box around its components, and the dashed line through them when there are several.
public struct WardleyMapLayoutPipeline: Equatable, Sendable {
    public internal(set) var frame: CGRect
    public internal(set) var line: DiagramPath?
}

/// A link: its line, dashed or not, the arrows its flow puts at its ends, and its label beside its middle.
public struct WardleyMapLayoutLink: Equatable, Sendable {
    public internal(set) var line: DiagramPath
    public let isDashed: Bool
    public internal(set) var arrows: [DiagramEdgeMark]
    public internal(set) var label: DiagramTextBlock?
}

/// An evolution: a dashed line in the accent color to where the component is heading, its arrow, and an open circle there.
public struct WardleyMapLayoutTrend: Equatable, Sendable {
    public internal(set) var line: DiagramPath?
    public internal(set) var arrow: DiagramEdgeMark?
    public internal(set) var target: CGPoint
}

/// An anchor (its name alone), a component (a circle), a pipeline's parent (a square), with its sourcing, its inertia bar
/// and its label's lines.
public struct WardleyMapLayoutNode: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        case none
        case circle
        case square
    }

    public internal(set) var center: CGPoint
    public let shape: Shape
    public let sourcing: WardleyMapSourcing?
    /// The bar beside the node that marks inertia, filled in the line color.
    public internal(set) var inertia: CGRect?
    /// The label's lines; an anchor's are bold.
    public internal(set) var label: [DiagramTextBlock]
    public let isAnchor: Bool
}

/// An annotation's numbered circles, one per point.
public struct WardleyMapLayoutAnnotation: Equatable, Sendable {
    public internal(set) var circles: [WardleyMapLayoutCircle]
    public internal(set) var numbers: [DiagramTextBlock]
}

/// A circle of the map: an annotation's.
public struct WardleyMapLayoutCircle: Equatable, Sendable {
    public internal(set) var center: CGPoint
    public let radius: CGFloat
}

/// The annotations' list: its box and its rows, each starting 10 points in.
public struct WardleyMapLayoutAnnotationList: Equatable, Sendable {
    public internal(set) var frame: CGRect
    public internal(set) var rows: [DiagramTextBlock]
}

/// An accelerator, pointing right, or a deaccelerator, pointing left: its wide arrow and its name under it.
public struct WardleyMapLayoutForce: Equatable, Sendable {
    public internal(set) var outline: DiagramPath
    public let isAccelerator: Bool
    public internal(set) var name: DiagramTextBlock?
}
