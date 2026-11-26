/**
 * File: ClassDiagramLayoutParts.swift
 * -----------------------------------
 * Layer: Core
 * Description: A class diagram's layout made from classes, notes and edges given as blocks and paths of their own
 *              (0.7.0's, which the tests keep), their texts copied into one list of lines and their paths into one
 *              list of segments.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

extension ClassDiagramLayout {
    init(size: CGSize, font: DiagramFont, classes: [ClassDiagramLayoutClass], notes: [ClassDiagramLayoutNote], interfaces: [DiagramTextBlock],
         relations: [ClassDiagramLayoutEdge], noteLinks: [ClassDiagramLayoutEdge], title: DiagramTextBlock?, namespaces: [FlowchartLayoutCluster] = []) {
        var parts = Parts()
        let placedClasses = classes.map { box in parts.placed(box) }
        let placedNotes = notes.map { note in ClassDiagramPlacedNote(frame: note.frame, text: parts.measured(note.text)) }
        let placedInterfaces = interfaces.map { interface in parts.measured(interface) }
        let placedRelations = relations.map { edge in parts.placed(edge) }
        let placedNoteLinks = noteLinks.map { edge in parts.placed(edge) }
        let placedTitle = title.map { title in parts.measured(title) }
        self.init(size: size, font: font, lines: parts.lines, source: MermaidSourceText(bytes: []), segments: parts.segments, placedClasses: placedClasses,
                  placedAnnotations: parts.annotations, placedMembers: parts.members, placedNotes: placedNotes, placedInterfaces: placedInterfaces,
                  placedRelations: placedRelations, placedNoteLinks: placedNoteLinks, placedTitle: placedTitle, namespaces: namespaces)
    }

    /// The lists a layout made of blocks and paths is copied into.
    private struct Parts {
        var lines = DiagramMeasuredLines()
        var segments: [DiagramPathSegment] = []
        var annotations: [DiagramMeasuredText] = []
        var members: [ClassDiagramPlacedMember] = []

        mutating func measured(_ block: DiagramTextBlock) -> DiagramMeasuredText {
            DiagramFlatTextMeasuring.copied(block, into: &lines).centered(at: block.center)
        }

        mutating func placed(_ box: ClassDiagramLayoutClass) -> ClassDiagramPlacedClass {
            let firstAnnotation = annotations.count
            for annotation in box.annotations { annotations.append(measured(annotation)) }
            let name = measured(box.name)
            let firstMember = members.count
            for member in box.members { members.append(ClassDiagramPlacedMember(text: measured(member.text), classifier: member.classifier)) }
            let dividers = box.dividerYs.count == 2 ? (box.dividerYs[0], box.dividerYs[1]) : (0, 0)
            precondition(box.dividerYs.isEmpty || box.dividerYs.count == 2, "a class's box has its two dividers or none")
            return ClassDiagramPlacedClass(frame: box.frame, hasDividers: !box.dividerYs.isEmpty, dividerYs: dividers,
                                           annotations: Int32(firstAnnotation)..<Int32(annotations.count), name: name,
                                           members: Int32(firstMember)..<Int32(members.count))
        }

        mutating func placed(_ edge: ClassDiagramLayoutEdge) -> ClassDiagramPlacedEdge {
            let first = segments.count
            segments += edge.path.segments
            return ClassDiagramPlacedEdge(line: edge.line, path: DiagramSegmentRun(start: edge.path.start, firstSegment: Int32(first),
                                                                                   segmentCount: Int32(edge.path.segments.count)),
                                          sourceMark: edge.sourceMark, targetMark: edge.targetMark, text: edge.text.map { measured($0) },
                                          sourceCardinality: edge.sourceCardinality.map { measured($0) },
                                          targetCardinality: edge.targetCardinality.map { measured($0) })
        }
    }
}
