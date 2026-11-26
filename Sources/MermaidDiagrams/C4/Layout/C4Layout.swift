/**
 * File: C4Layout.swift
 * --------------------
 * Layer: Core
 * Description: A C4 diagram laid out on a page whose y runs down, kept as flat records its scene reads once: its
 *              boundaries with their headings' lines, its shapes with their texts, its relations' lines, arrowheads and
 *              labels, every text a measured text of one list of lines over the diagram's bytes; the value types with
 *              text blocks made only when read.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

import CoreGraphics

/// A C4 diagram laid out on a page whose origin is the top left corner and whose y runs down, in points, as Pele lays
/// it out on Mermaid's grid. Its texts are measured texts of `lines`, ranges of the diagram's text or of the lines' own
/// derived bytes; its relations' lines are ranges of `segments`. `title`, `boundaries`, `shapes` and `relations` make
/// the value types, with their text blocks, each time they are read; two layouts are equal when those are.
public struct C4Layout: Equatable, Sendable {
    public let size: CGSize
    /// The font names, headings and the title were measured in (bold); the rest is at thirteen sixteenths of its size, a
    /// shape's kind a point smaller.
    public let font: DiagramFont
    let lines: DiagramMeasuredLines
    /// The diagram's text and its derived bytes, which the lines and the records' aliases index.
    let source: [UInt8]
    let derived: [UInt8]
    let titleText: DiagramMeasuredText?
    let boundaryRecords: [C4LaidOutBoundary]
    /// The boundaries' heading lines, each placed by its left end, side by side for each boundary.
    let headingLines: [DiagramMeasuredText]
    let shapeRecords: [C4LaidOutShape]
    let relationRecords: [C4LaidOutRelation]
    let segments: [DiagramPathSegment]

    public var title: DiagramTextBlock? { titleText.map(block(of:)) }

    /// The boundaries drawn, parents before children; the unnamed top level is not one of them.
    public var boundaries: [C4LayoutBoundary] {
        boundaryRecords.map { record in
            C4LayoutBoundary(alias: string(record.alias), frame: record.frame, isDeploymentNode: record.isDeploymentNode,
                             name: blocks(of: record.nameLines), type: blocks(of: record.typeLines), description: blocks(of: record.descriptionLines),
                             look: record.look)
        }
    }

    /// The shapes, boundary by boundary in that order.
    public var shapes: [C4LayoutShape] {
        shapeRecords.map { record in
            C4LayoutShape(alias: string(record.alias), kind: record.kind, form: record.form, frame: record.frame, type: record.type.map(block(of:)),
                          name: record.name.map(block(of:)), technology: record.technology.map(block(of:)),
                          description: record.description.map(block(of:)), look: record.look)
        }
    }

    /// The relations in the order written.
    public var relations: [C4LayoutRelation] {
        relationRecords.map { record in
            var corners: [CGPoint] = []
            corners.reserveCapacity(record.corners.count / 2)
            for index in stride(from: 0, to: record.corners.count, by: 2) { corners.append(CGPoint(x: record.corners[index], y: record.corners[index + 1])) }
            return C4LayoutRelation(from: string(record.from), to: string(record.to), path: path(of: record), corners: corners,
                                    startMark: record.startMark, endMark: record.endMark, labelFrame: record.labelFrame, label: record.label.map(block(of:)),
                                    technology: record.technology.map(block(of:)), lineColor: record.lineColor, textColor: record.textColor,
                                    isCased: record.isCased)
        }
    }

    public static func == (left: C4Layout, right: C4Layout) -> Bool {
        left.size == right.size && left.font == right.font && left.title == right.title && left.boundaries == right.boundaries
            && left.shapes == right.shapes && left.relations == right.relations
    }

    /// The relation's line as a path.
    func path(of relation: C4LaidOutRelation) -> DiagramPath {
        DiagramPath(start: relation.pathStart, segments: Array(segments[relation.segments]))
    }

    /// The layout with relation `index`'s line replaced by `path`, for the tests of a scene's limits.
    func replacingPath(ofRelation index: Int, with path: DiagramPath) -> C4Layout {
        var relations = relationRecords
        var segments = segments
        relations[index].pathStart = path.start
        relations[index].segments = segments.count..<(segments.count + path.segments.count)
        segments += path.segments
        return C4Layout(size: size, font: font, lines: lines, source: source, derived: derived, titleText: titleText, boundaryRecords: boundaryRecords,
                        headingLines: headingLines, shapeRecords: shapeRecords, relationRecords: relations, segments: segments)
    }

    // MARK: - Texts

    /// Calls `body` with the bytes the lines index: the diagram's text.
    func withSource<Result>(_ body: (UnsafeBufferPointer<UInt8>) throws -> Result) rethrows -> Result {
        try source.withUnsafeBufferPointer(body)
    }

    private func block(of text: DiagramMeasuredText) -> DiagramTextBlock {
        withSource { source in DiagramTextBlock(text, of: lines, source: source) }
    }

    private func blocks(of range: Range<Int>) -> [DiagramTextBlock] {
        range.map { index in block(of: headingLines[index]) }
    }

    /// A text of the diagram, an alias or a relation's end, as a String.
    private func string(_ text: C4Text) -> String {
        guard !text.isNone else { return "" }
        let bytes = text.isDerived ? derived : source
        let start = Int(text.isDerived ? text.start - C4Text.derivedOffset : text.start)
        precondition(start >= 0 && start + text.count <= bytes.count, "text outside the diagram's bytes")
        return String(decoding: bytes[start..<(start + text.count)], as: UTF8.self)
    }
}

/// A boundary laid out: its alias, frame and kind, its heading's lines (ranges of the layout's heading lines) and its look.
struct C4LaidOutBoundary {
    let alias: C4Text
    let frame: CGRect
    let isDeploymentNode: Bool
    let nameLines: Range<Int>
    let typeLines: Range<Int>
    let descriptionLines: Range<Int>
    let look: C4ElementLook
}

/// A shape laid out: its alias, kind, form and frame, its texts centered in it, and its look.
struct C4LaidOutShape {
    let alias: C4Text
    let kind: C4ShapeKind
    let form: C4ShapeForm
    let frame: CGRect
    let type: DiagramMeasuredText?
    let name: DiagramMeasuredText?
    let technology: DiagramMeasuredText?
    let description: DiagramMeasuredText?
    let look: C4ElementLook

    /// Drawn hollow, with a dashed border.
    var isExternal: Bool { kind.isExternal }
}

/// A relation laid out: its ends, its line (its start and a range of the layout's segments), its corners as x, y pairs,
/// its arrowheads, its label's patch and texts, and how it is painted.
struct C4LaidOutRelation {
    let from: C4Text
    let to: C4Text
    var pathStart: CGPoint
    var segments: Range<Int>
    let corners: C4Numbers
    let startMark: DiagramEdgeMark?
    let endMark: DiagramEdgeMark?
    let labelFrame: CGRect?
    let label: DiagramMeasuredText?
    let technology: DiagramMeasuredText?
    let lineColor: DiagramColor?
    let textColor: DiagramColor?
    let isCased: Bool
}
