/**
 * File: RequirementLayout.swift
 * -----------------------------
 * Layer: Core
 * Description: A requirement diagram laid out on a page: its boxes with their texts, its relations with their marks and
 *              texts, and its title, kept as placed records of measured texts over one list of lines that the scene reads
 *              directly, with the boxes, relations and title as blocks made when a host asks; and why a layout is refused.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// A requirement diagram laid out on a page whose origin is the top left corner and whose y runs down, in points.
///
/// Its texts are measured texts of one list of lines (`DiagramMeasuredText`), which the scene draws from directly;
/// `boxes`, `relations` and `title` make the same texts as `DiagramTextBlock`s each time they are read.
public struct RequirementLayout: Sendable {
    public let size: CGSize
    public let font: DiagramFont
    /// The lines of every text below, all of them derived bytes.
    let lines: DiagramMeasuredLines
    /// The requirements, then the elements, in the order the diagram declares them.
    let placedBoxes: [RequirementPlacedBox]
    /// The lines of the boxes' fields' names and values, each placed: a box's are its ranges of it.
    let fieldTexts: [DiagramMeasuredText]
    /// The relations between two boxes drawn, in the order written.
    let placedRelations: [RequirementPlacedRelation]
    /// The title placed, or nil without one or for a title of no line.
    let placedTitle: DiagramMeasuredText?
    /// The diagram's `unappliedStatementCount`, which its measuring counted.
    var unappliedStatementCount = 0

    /// The requirements, then the elements, in the order the diagram declares them, made when read.
    public var boxes: [RequirementLayoutBox] {
        placedBoxes.map { box in
            RequirementLayoutBox(frame: box.frame, isRequirement: box.isRequirement, stereotype: block(of: box.stereotype), name: block(of: box.name),
                                 dividerY: box.dividerY, fieldNames: fieldTexts[box.fieldNames].map(block(of:)),
                                 fieldValues: fieldTexts[box.fieldValues].map(block(of:)), style: box.style)
        }
    }

    /// The relations between two boxes drawn, in the order written; a relation naming nothing declared is not drawn. Made
    /// when read.
    public var relations: [RequirementLayoutRelation] {
        placedRelations.map { relation in
            RequirementLayoutRelation(kind: relation.kind, path: relation.path, mark: relation.mark, text: block(of: relation.text))
        }
    }

    public var title: DiagramTextBlock? { placedTitle.map(block(of:)) }

    /// `text`, a text of this layout's lines, as a block.
    func block(of text: DiagramMeasuredText) -> DiagramTextBlock {
        DiagramTextBlock(text, of: lines, source: DiagramMeasuredLines.noSource)
    }
}

extension RequirementLayout: Equatable {
    /// The same size, font, boxes, relations and title.
    public static func == (left: RequirementLayout, right: RequirementLayout) -> Bool {
        left.size == right.size && left.font == right.font && left.boxes == right.boxes && left.relations == right.relations && left.title == right.title
    }
}

/// A box placed: its frame, its stereotype and name, its divider, its fields' lines as ranges of the layout's
/// `fieldTexts`, and its style.
struct RequirementPlacedBox: Sendable {
    let frame: CGRect
    let isRequirement: Bool
    let stereotype: DiagramMeasuredText
    let name: DiagramMeasuredText
    let dividerY: CGFloat?
    let fieldNames: Range<Int>
    let fieldValues: Range<Int>
    let style: DiagramElementStyle?
}

/// A relation placed, its text a measured text of the layout's lines.
struct RequirementPlacedRelation: Sendable {
    let kind: RequirementRelationKind
    var path: DiagramPath
    var mark: RequirementRelationMark
    var text: DiagramMeasuredText

    /// Moved by `offset` where it stands, each point as `RequirementLayoutRelation.translate(by:)` moves it.
    mutating func translate(by offset: CGVector) {
        path.translate(by: offset)
        mark = mark.translated(by: offset)
        text = text.translated(by: offset)
    }
}

/// A requirement's or an element's box: its stereotype (`«Requirement»`, `«Element»`) and bold name centered in its head,
/// then, under a divider, a row per field written, its name muted at the left and its value after the widest name.
public struct RequirementLayoutBox: Equatable, Sendable {
    public let frame: CGRect
    public let isRequirement: Bool
    public let stereotype: DiagramTextBlock
    public let name: DiagramTextBlock
    /// Where the divider under the head runs across the box, or nil for a box without fields.
    public let dividerY: CGFloat?
    /// The fields' names and values, a block per line, each starting at its column's left.
    public let fieldNames: [DiagramTextBlock]
    public let fieldValues: [DiagramTextBlock]
    /// The colors the diagram's `style`, `classDef` and `class` statements give the box, or nil for the usual look.
    public let style: DiagramElementStyle?
}

/// A relation: its line, solid for `contains` and dashed otherwise, its mark, and its text, `«kind»`, on a patch.
public struct RequirementLayoutRelation: Equatable, Sendable {
    public let kind: RequirementRelationKind
    /// The line, which starts past a containment mark.
    public internal(set) var path: DiagramPath
    /// A containment's circled plus at its source, or the open arrowhead at its target.
    public internal(set) var mark: RequirementRelationMark
    public internal(set) var text: DiagramTextBlock
}

/// The mark at a relation's end.
public enum RequirementRelationMark: Equatable, Sendable {
    /// A circled plus whose rim touches `point`, the source's side, `towardBox` pointing into the source.
    case containment(point: CGPoint, towardBox: CGVector)
    /// An open arrowhead with its tip at `tip`, pointing along `direction`.
    case arrow(tip: CGPoint, direction: CGVector)

    func translated(by offset: CGVector) -> RequirementRelationMark {
        switch self {
        case .containment(let point, let towardBox): .containment(point: point.translated(by: offset), towardBox: towardBox)
        case .arrow(let tip, let direction): .arrow(tip: tip.translated(by: offset), direction: direction)
        }
    }
}

/// Why a requirement diagram was not laid out.
public enum RequirementLayoutError: Error, Equatable, Sendable {
    /// The layout needs more nodes and passing points than `MermaidDiagramLimits.maximumLayoutPointCount`.
    case tooManyLayoutPoints(limit: Int)
}

extension RequirementLayoutBox {
    func translated(by offset: CGVector) -> RequirementLayoutBox {
        RequirementLayoutBox(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), isRequirement: isRequirement,
                             stereotype: stereotype.translated(by: offset), name: name.translated(by: offset), dividerY: dividerY.map { y in y + offset.dy },
                             fieldNames: fieldNames.map { text in text.translated(by: offset) }, fieldValues: fieldValues.map { text in text.translated(by: offset) },
                             style: style)
    }
}

extension RequirementLayoutRelation {
    func translated(by offset: CGVector) -> RequirementLayoutRelation {
        RequirementLayoutRelation(kind: kind, path: path.translated(by: offset), mark: mark.translated(by: offset), text: text.translated(by: offset))
    }

    /// Moved by `offset` where it stands, each point as `translated(by:)` moves it: its path's points in their own list.
    mutating func translate(by offset: CGVector) {
        path.translate(by: offset)
        mark = mark.translated(by: offset)
        text = text.translated(by: offset)
    }
}
