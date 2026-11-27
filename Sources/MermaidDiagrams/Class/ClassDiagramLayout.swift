/**
 * File: ClassDiagramLayout.swift
 * ------------------------------
 * Layer: Core
 * Description: A class diagram laid out on a page, with its namespaces' boxes, kept as placed records over one list of
 *              measured lines and one list of path segments that the scene reads directly; its classes, notes, edges
 *              and title made as blocks and paths of their own only when a host asks.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

import CoreGraphics

/// A class diagram laid out on a page whose origin is the top left corner and whose y runs down, in points. Drawing
/// it needs only colors: every position, path and text measurement is here.
public struct ClassDiagramLayout: Sendable {
    public let size: CGSize
    /// The font the text was measured in; each text carries its own size.
    public let font: DiagramFont
    /// The lines of every measured text; a line read as written points into `source`, the others into the lines' own bytes.
    let lines: DiagramMeasuredLines
    let source: MermaidSourceText
    /// Every edge's segments.
    let segments: [DiagramPathSegment]
    /// The classes' boxes, in the order of `ClassDiagram.classes`.
    let placedClasses: [ClassDiagramPlacedClass]
    /// The boxes' annotations and members, each box's in a run.
    let placedAnnotations: [DiagramMeasuredText]
    let placedMembers: [ClassDiagramPlacedMember]
    let placedNotes: [ClassDiagramPlacedNote]
    let placedInterfaces: [DiagramMeasuredText]
    let placedRelations: [ClassDiagramPlacedEdge]
    let placedNoteLinks: [ClassDiagramPlacedEdge]
    let placedTitle: DiagramMeasuredText?
    /// The namespaces' boxes, outer ones before the boxes inside them, drawn as a flowchart's groups are; empty for a
    /// diagram without namespaces.
    public internal(set) var namespaces: [FlowchartLayoutCluster] = []

    /// The classes' boxes, in the order of `ClassDiagram.classes`, made from the records.
    public var classes: [ClassDiagramLayoutClass] {
        placedClasses.map { box in
            ClassDiagramLayoutClass(frame: box.frame, dividerYs: box.hasDividers ? [box.dividerYs.title, box.dividerYs.attributes] : [],
                                    annotations: placedAnnotations[box.annotationIndices].map(block(of:)), name: block(of: box.name),
                                    members: placedMembers[box.memberIndices].map { member in
                                        ClassDiagramLayoutMember(text: block(of: member.text), classifier: member.classifier)
                                    })
        }
    }

    /// The notes, in the order of `ClassDiagram.notes`.
    public var notes: [ClassDiagramLayoutNote] { placedNotes.map { note in ClassDiagramLayoutNote(frame: note.frame, text: block(of: note.text)) } }
    /// The names of lollipop interfaces, drawn as text alone.
    public var interfaces: [DiagramTextBlock] { placedInterfaces.map(block(of:)) }
    /// The relations' lines, in the order of `ClassDiagram.relations`.
    public var relations: [ClassDiagramLayoutEdge] { placedRelations.map(edge(of:)) }
    /// The dotted lines from notes to their classes, in the order of the notes that have one.
    public var noteLinks: [ClassDiagramLayoutEdge] { placedNoteLinks.map(edge(of:)) }
    /// The diagram's title above it, drawn bold, or nil.
    public var title: DiagramTextBlock? { placedTitle.map(block(of:)) }

    func block(of text: DiagramMeasuredText) -> DiagramTextBlock {
        source.withBytes { source in DiagramTextBlock(text, of: lines, source: source) }
    }

    private func edge(of placed: ClassDiagramPlacedEdge) -> ClassDiagramLayoutEdge {
        ClassDiagramLayoutEdge(line: placed.line, path: placed.path.path(in: segments), sourceMark: placed.sourceMark, targetMark: placed.targetMark,
                               text: placed.text.map(block(of:)), sourceCardinality: placed.sourceCardinality.map(block(of:)),
                               targetCardinality: placed.targetCardinality.map(block(of:)))
    }
}

extension ClassDiagramLayout: Equatable {
    public static func == (left: ClassDiagramLayout, right: ClassDiagramLayout) -> Bool {
        left.size == right.size && left.font == right.font && left.classes == right.classes && left.notes == right.notes
            && left.interfaces == right.interfaces && left.relations == right.relations && left.noteLinks == right.noteLinks && left.title == right.title
            && left.namespaces == right.namespaces
    }
}

/// A class's box as the layout places it: its frame, the lines under its title and its attributes, its name, and its
/// annotations and members, runs of the layout's lists.
struct ClassDiagramPlacedClass: Sendable {
    let frame: CGRect
    let hasDividers: Bool
    let dividerYs: (title: CGFloat, attributes: CGFloat)
    let annotations: Range<Int32>
    let name: DiagramMeasuredText
    let members: Range<Int32>

    var annotationIndices: Range<Int> { Int(annotations.lowerBound)..<Int(annotations.upperBound) }
    var memberIndices: Range<Int> { Int(members.lowerBound)..<Int(members.upperBound) }
}

struct ClassDiagramPlacedNote: Sendable {
    let frame: CGRect
    let text: DiagramMeasuredText
}

/// A relation or a note's link as the layout places it: its line, a run of the layout's segments, its marks and texts.
struct ClassDiagramPlacedEdge: Sendable {
    let line: ClassDiagramLineStyle
    var path: DiagramSegmentRun
    var sourceMark: ClassDiagramRelationMark?
    var targetMark: ClassDiagramRelationMark?
    var text: DiagramMeasuredText?
    var sourceCardinality: DiagramMeasuredText?
    var targetCardinality: DiagramMeasuredText?

    /// Moved by `offset`, all but its segments, which the layout moves in its list.
    mutating func translate(by offset: CGVector) {
        path.start = path.start.translated(by: offset)
        sourceMark = sourceMark?.translated(by: offset)
        targetMark = targetMark?.translated(by: offset)
        text = text?.translated(by: offset)
        sourceCardinality = sourceCardinality?.translated(by: offset)
        targetCardinality = targetCardinality?.translated(by: offset)
    }
}

/// A class's box: its outline, the lines between its compartments, and its text.
public struct ClassDiagramLayoutClass: Equatable, Sendable {
    public let frame: CGRect
    /// The y of each line drawn across the box: under the title, and under the attributes.
    public let dividerYs: [CGFloat]
    /// `«interface»` and the like, above the name, drawn small in the muted color.
    public let annotations: [DiagramTextBlock]
    /// The name, drawn bold.
    public let name: DiagramTextBlock
    /// The attributes then the methods, each a line of its own starting at the box's left padding.
    public let members: [ClassDiagramLayoutMember]
}

/// A line of a class's attributes or methods.
public struct ClassDiagramLayoutMember: Equatable, Sendable {
    public let text: DiagramTextBlock
    /// Static members are underlined, abstract ones in italics.
    public let classifier: ClassDiagramMemberClassifier
}

/// A note: a box with a folded corner around its text.
public struct ClassDiagramLayoutNote: Equatable, Sendable {
    public let frame: CGRect
    public let text: DiagramTextBlock
}

/// A relation's or a note's line, with its marks and texts.
public struct ClassDiagramLayoutEdge: Equatable, Sendable {
    public let line: ClassDiagramLineStyle
    /// The line, which stops where a mark begins.
    public internal(set) var path: DiagramPath
    public internal(set) var sourceMark: ClassDiagramRelationMark?
    public internal(set) var targetMark: ClassDiagramRelationMark?
    /// The relation's text, drawn on a patch of the background, or nil.
    public internal(set) var text: DiagramTextBlock?
    /// The cardinality beside the source end, drawn small in the muted color, or nil.
    public internal(set) var sourceCardinality: DiagramTextBlock?
    /// The cardinality beside the target end, or nil.
    public internal(set) var targetCardinality: DiagramTextBlock?
}

/// The mark at an end of a relation: its kind, the point it touches what it marks, and the unit direction it points
/// in, toward that point.
public struct ClassDiagramRelationMark: Equatable, Sendable {
    public let end: ClassDiagramRelationEnd
    public let tip: CGPoint
    public let direction: CGVector
}

extension ClassDiagramLayoutClass {
    func translated(by offset: CGVector) -> ClassDiagramLayoutClass {
        ClassDiagramLayoutClass(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), dividerYs: dividerYs.map { y in y + offset.dy },
                                annotations: annotations.map { block in block.translated(by: offset) }, name: name.translated(by: offset),
                                members: members.map { member in
                                    ClassDiagramLayoutMember(text: member.text.translated(by: offset), classifier: member.classifier)
                                })
    }
}

extension ClassDiagramLayoutNote {
    func translated(by offset: CGVector) -> ClassDiagramLayoutNote {
        ClassDiagramLayoutNote(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), text: text.translated(by: offset))
    }
}

extension ClassDiagramLayoutEdge {
    func translated(by offset: CGVector) -> ClassDiagramLayoutEdge {
        ClassDiagramLayoutEdge(line: line, path: path.translated(by: offset), sourceMark: sourceMark?.translated(by: offset),
                               targetMark: targetMark?.translated(by: offset), text: text?.translated(by: offset),
                               sourceCardinality: sourceCardinality?.translated(by: offset), targetCardinality: targetCardinality?.translated(by: offset))
    }
}

extension ClassDiagramLayoutEdge {
    /// Moved by `offset` where it stands, each point as `translated(by:)` moves it: its path's points in their own list.
    mutating func translate(by offset: CGVector) {
        path.translate(by: offset)
        sourceMark = sourceMark?.translated(by: offset)
        targetMark = targetMark?.translated(by: offset)
        text = text?.translated(by: offset)
        sourceCardinality = sourceCardinality?.translated(by: offset)
        targetCardinality = targetCardinality?.translated(by: offset)
    }
}

extension ClassDiagramRelationMark {
    func translated(by offset: CGVector) -> ClassDiagramRelationMark {
        ClassDiagramRelationMark(end: end, tip: tip.translated(by: offset), direction: direction)
    }
}
