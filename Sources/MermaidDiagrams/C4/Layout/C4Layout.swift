/**
 * File: C4Layout.swift
 * --------------------
 * Layer: Core
 * Description: A C4 diagram laid out on a page whose y runs down: its boundaries with their headings, its shapes with
 *              their texts, its relations' lines, arrowheads and labels, and the colors its styles set.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

/// A C4 diagram laid out on a page whose origin is the top left corner and whose y runs down, in points, as Pele lays
/// it out on Mermaid's grid.
public struct C4Layout: Equatable, Sendable {
    public let size: CGSize
    /// The font names, headings and the title were measured in (bold); the rest is at thirteen sixteenths of its size, a
    /// shape's kind a point smaller.
    public let font: DiagramFont
    public let title: DiagramTextBlock?
    /// The boundaries drawn, parents before children; the unnamed top level is not one of them.
    public let boundaries: [C4LayoutBoundary]
    /// The shapes, boundary by boundary in that order.
    public let shapes: [C4LayoutShape]
    /// The relations in the order written.
    public let relations: [C4LayoutRelation]
}

/// A boundary: its frame, dashed unless it is a deployment node, and its heading, each line placed by its left end.
public struct C4LayoutBoundary: Equatable, Sendable {
    public let alias: String
    public let frame: CGRect
    public let isDeploymentNode: Bool
    /// The name in bold, `[type]` and the description, line by line, each empty where it has none.
    public let name: [DiagramTextBlock]
    public let type: [DiagramTextBlock]
    public let description: [DiagramTextBlock]
    public let look: C4ElementLook
}

/// A shape: its frame, the form it is drawn as, and its texts centered in it.
public struct C4LayoutShape: Equatable, Sendable {
    public let alias: String
    public let kind: C4ShapeKind
    public let form: C4ShapeForm
    public let frame: CGRect
    /// `«kind»`, the name in bold, `[technology]` and the description, each nil where it has none.
    public let type: DiagramTextBlock?
    public let name: DiagramTextBlock?
    public let technology: DiagramTextBlock?
    public let description: DiagramTextBlock?
    public let look: C4ElementLook

    /// Drawn hollow, with a dashed border.
    public var isExternal: Bool { kind.isExternal }
}

/// A relation: its line, the arrowheads at the ends it points at, its label and technology on a patch of the page's
/// color, and how it is painted.
public struct C4LayoutRelation: Equatable, Sendable {
    public let from: String
    public let to: String
    public let path: DiagramPath
    /// The line's ends and corners before its corners are rounded and its ends trimmed for arrowheads; none for a loop.
    public let corners: [CGPoint]
    public let startMark: DiagramEdgeMark?
    public let endMark: DiagramEdgeMark?
    /// The patch behind the label and the technology, nil when the relation has neither.
    public let labelFrame: CGRect?
    public let label: DiagramTextBlock?
    /// `[technology]`, in italic.
    public let technology: DiagramTextBlock?
    /// The line's color: its `$lineColor`, else the text color picked over the boundary fill it lies on, else nil for
    /// the line color.
    public let lineColor: DiagramColor?
    public let textColor: DiagramColor?
    /// Whether the line is drawn over a wider line of the page's color, as Pele cases a line that crosses the border of
    /// a filled boundary.
    public let isCased: Bool
}

/// The colors a C4 element's style sets (`$bgColor`, `$borderColor`, `$fontColor`) as Pele resolves them, and the text
/// color Pele's ink picks over its fill for text that sets none.
public struct C4ElementLook: Equatable, Sendable {
    public let fill: DiagramColor?
    public let stroke: DiagramColor?
    public let textColor: DiagramColor?
    public let ink: DiagramColor?
    /// Whether the fill paints anything (Pele's `paints`): written, not `none` or `transparent`, not fully clear; a value
    /// not read as a color counts as opaque.
    let paintsFill: Bool

    init(backgroundColor: String?, borderColor: String?, fontColor: String?) {
        func declaration(_ property: String, _ value: String?) -> [VennStyleDeclaration] {
            guard let value, !value.isEmpty else { return [] }
            return [VennStyleDeclaration(property: property, value: value)]
        }
        let shape = VennAppearance(declaration("fill", backgroundColor) + declaration("stroke", borderColor))
        let text = VennAppearance(declaration("color", fontColor))
        fill = shape.fill
        stroke = shape.stroke
        textColor = text.textColor
        ink = shape.ink(forTextOf: text)
        paintsFill = Self.paints(backgroundColor, read: shape.fill)
        inkForLines = shape.ink(forTextOf: VennAppearance())
    }

    /// The color Pele's ink picks over the fill for a line that sets none.
    let inkForLines: DiagramColor?

    /// The look of an element whose style writes no color, worked out once: most elements set none.
    static let unstyled = C4ElementLook(backgroundColor: nil, borderColor: nil, fontColor: nil)


    /// The color a style value writes, nil when none is read.
    static func color(_ value: String?, property: String) -> DiagramColor? {
        guard let value, !value.isEmpty else { return nil }
        let look = VennAppearance([VennStyleDeclaration(property: property, value: value)])
        return property == "color" ? look.textColor : look.stroke
    }

    /// Whether a value is written that Pele's `resolveStyle` keeps: not empty and none of the values it leaves out.
    static func isWritten(_ value: String?) -> Bool {
        guard let value else { return false }
        let trimmed = C4Characters.trimmed(MermaidByte.withoutImportance(value))
        return !trimmed.isEmpty && !VennAppearance.isUnsafe(trimmed)
    }

    private static func paints(_ value: String?, read: DiagramColor?) -> Bool {
        guard isWritten(value), let value else { return false }
        let lowered = C4Characters.trimmed(value).lowercased()
        guard lowered != "none", lowered != "transparent" else { return false }
        return (read?.alpha ?? 1) > 0
    }
}

extension C4Diagram {
    /// The look an element's colors give, as `C4ElementLook(backgroundColor:borderColor:fontColor:)` makes it from them;
    /// `C4ElementLook.unstyled`, made once, when it writes none.
    func look(of element: C4ElementRecord) -> C4ElementLook {
        guard !element.backgroundColor.isNoneOrEmpty || !element.borderColor.isNoneOrEmpty || !element.fontColor.isNoneOrEmpty else {
            return C4ElementLook.unstyled
        }
        return C4ElementLook(backgroundColor: string(element.backgroundColor), borderColor: string(element.borderColor), fontColor: string(element.fontColor))
    }
}
