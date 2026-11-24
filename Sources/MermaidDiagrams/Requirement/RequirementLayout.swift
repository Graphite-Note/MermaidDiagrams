/**
 * File: RequirementLayout.swift
 * -----------------------------
 * Layer: Core
 * Description: A requirement diagram laid out on a page: its boxes with their texts, its relations with their marks and
 *              texts, and its title, and why a layout is refused.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// A requirement diagram laid out on a page whose origin is the top left corner and whose y runs down, in points.
public struct RequirementLayout: Equatable, Sendable {
    public let size: CGSize
    public let font: DiagramFont
    /// The requirements, then the elements, in the order the diagram declares them.
    public let boxes: [RequirementLayoutBox]
    /// The relations between two boxes drawn, in the order written; a relation naming nothing declared is not drawn.
    public let relations: [RequirementLayoutRelation]
    public let title: DiagramTextBlock?
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
        let movedMark: RequirementRelationMark = switch mark {
        case .containment(let point, let towardBox): .containment(point: point.translated(by: offset), towardBox: towardBox)
        case .arrow(let tip, let direction): .arrow(tip: tip.translated(by: offset), direction: direction)
        }
        return RequirementLayoutRelation(kind: kind, path: path.translated(by: offset), mark: movedMark, text: text.translated(by: offset))
    }

    /// Moved by `offset` where it stands, each point as `translated(by:)` moves it: its path's points in their own list.
    mutating func translate(by offset: CGVector) {
        path.translate(by: offset)
        mark = switch mark {
        case .containment(let point, let towardBox): .containment(point: point.translated(by: offset), towardBox: towardBox)
        case .arrow(let tip, let direction): .arrow(tip: tip.translated(by: offset), direction: direction)
        }
        text = text.translated(by: offset)
    }
}
