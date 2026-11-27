/**
 * File: ClassDiagramPageFinishing.swift
 * -------------------------------------
 * Layer: Core
 * Description: A placed class diagram finished on the page: the rectangle its drawing covers, its parts that nothing
 *              joins set in rows for a narrow container, and every part placed once where the padding moves it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

extension ClassDiagramPageAssembly {
    /// The diagram's parts that nothing joins set in rows `rowWidth` wide, `gap` apart, as Pele's `wrapComponents` sets
    /// them for a diagram wider than its container (`ClassDiagramComponentRows`), with the size of the rows; nil when
    /// nothing moves.
    func wrappedInRows(rowWidth: CGFloat, gap: CGFloat) -> (page: ClassDiagramPageAssembly, size: CGSize)? {
        let frames = nodeCenters.indices.map { node in
            CGRect(x: nodeCenters[node].x - measured.sizes[node].width / 2, y: nodeCenters[node].y - measured.sizes[node].height / 2,
                   width: measured.sizes[node].width, height: measured.sizes[node].height)
        }
        let placedEdges = measured.edges.indices.map { index in
            edges[index].map { placed in ClassDiagramComponentRows.Edge(source: measured.edges[index].source, target: measured.edges[index].target, placed: placed) }
        }
        guard let rows = ClassDiagramComponentRows.placement(namespaceFrames: namespaces.map(\.frame), namespaceParents: namespaceParents,
                                                             nodeFrames: frames,
                                                             nodeNamespaces: nodeNamespaces.isEmpty ? Array(repeating: nil, count: frames.count) : nodeNamespaces,
                                                             edges: placedEdges, segments: segments, rowWidth: rowWidth, gap: gap) else { return nil }
        var wrapped = self
        wrapped.nodeCenters = zip(nodeCenters, rows.nodeOffsets).map { center, offset in center.translated(by: offset) }
        for index in wrapped.edges.indices {
            guard var edge = wrapped.edges[index] else { continue }
            let offset = rows.edgeOffsets[index]
            edge.translate(by: offset)
            DiagramRouteSegments.translate(&wrapped.segments, edge.path.segmentIndices, by: offset)
            wrapped.edges[index] = edge
        }
        wrapped.namespaces = zip(namespaces, rows.namespaceOffsets).map { namespace, offset in namespace.translated(by: offset) }
        return (wrapped, rows.size)
    }

    /// The rectangle the drawing covers: its boxes, notes, interfaces and namespaces, then its relations and its notes'
    /// lines (`ClassDiagramLayoutBounds`), each taken in that order, as the finished layout's parts were.
    func drawingBounds() -> CGRect {
        var bounds = CGRect.null
        for (node, kind) in measured.nodes.enumerated() {
            let center = nodeCenters[node]
            switch kind {
            case .classBox, .note:
                let size = measured.sizes[node]
                bounds = bounds.union(CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height))
            case .interface(let interfaceIndex): bounds = bounds.union(measured.interfaceTexts[interfaceIndex].centered(at: center).frame)
            }
        }
        for namespace in namespaces { bounds = bounds.union(namespace.frame) }
        for (edgeIndex, edge) in measured.edges.enumerated() where edge.relationIndex != nil {
            if let placed = edges[edgeIndex] { bounds = ClassDiagramLayoutBounds.union(bounds, edge: placed, segments: segments) }
        }
        for (edgeIndex, edge) in measured.edges.enumerated() where edge.relationIndex == nil {
            if let placed = edges[edgeIndex] { bounds = ClassDiagramLayoutBounds.union(bounds, edge: placed, segments: segments) }
        }
        return bounds.isNull ? .zero : bounds
    }

    /// The finished layout: everything moved so that the drawing, which covers `bounds`, starts `padding` from the top
    /// left, below the title, and centered under the title when the title is wider. Each part is placed where it is
    /// moved to, each list made once.
    func finished(font: DiagramFont, title: DiagramMeasuredText?, padding: CGFloat, titleGap: CGFloat, bounds: CGRect) -> ClassDiagramLayout {
        let titleSize = title?.size ?? .zero
        let innerWidth = max(bounds.width, titleSize.width)
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let offset = CGVector(dx: padding + (innerWidth - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        let placedTitle = title?.centered(at: CGPoint(x: size.width / 2, y: padding + titleSize.height / 2))
        let nodes = placedNodes(offset: offset)
        var relations: [ClassDiagramPlacedEdge] = []
        var noteLinks: [ClassDiagramPlacedEdge] = []
        relations.reserveCapacity(measured.edges.count)
        for (edgeIndex, edge) in measured.edges.enumerated() {
            guard var placed = edges[edgeIndex] else { continue }
            placed.translate(by: offset)
            if edge.relationIndex == nil { noteLinks.append(placed) } else { relations.append(placed) }
        }
        var placedSegments = segments
        DiagramRouteSegments.translate(&placedSegments, by: offset)
        var placedNamespaces = namespaces
        for index in placedNamespaces.indices { placedNamespaces[index] = placedNamespaces[index].translated(by: offset) }
        return ClassDiagramLayout(size: size, font: font, lines: measured.texts.lines, source: measured.source, segments: placedSegments, placedClasses: nodes.classes,
                                  placedAnnotations: nodes.annotations, placedMembers: nodes.members, placedNotes: nodes.notes,
                                  placedInterfaces: nodes.interfaces, placedRelations: relations, placedNoteLinks: noteLinks, placedTitle: placedTitle,
                                  namespaces: placedNamespaces)
    }

    /// The classes' boxes, the notes and the interfaces' names at their nodes' centers, moved by `offset`.
    private func placedNodes(offset: CGVector) -> ClassDiagramPlacedNodes {
        var nodes = ClassDiagramPlacedNodes()
        nodes.classes.reserveCapacity(measured.boxes.count)
        nodes.annotations.reserveCapacity(measured.texts.annotations.count)
        nodes.members.reserveCapacity(measured.texts.members.count)
        nodes.notes.reserveCapacity(measured.noteTexts.count)
        nodes.interfaces.reserveCapacity(measured.interfaceTexts.count)
        for (node, kind) in measured.nodes.enumerated() {
            let center = nodeCenters[node]
            switch kind {
            case .classBox(let boxIndex):
                nodes.classes.append(measured.boxes[boxIndex].placed(at: center, offset: offset, texts: measured.texts, annotations: &nodes.annotations,
                                                                     members: &nodes.members))
            case .note(let noteIndex):
                let size = measured.sizes[node]
                nodes.notes.append(ClassDiagramPlacedNote(frame: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width,
                                                                        height: size.height).offsetBy(dx: offset.dx, dy: offset.dy),
                                                          text: measured.noteTexts[noteIndex].centered(at: center.translated(by: offset))))
            case .interface(let interfaceIndex): nodes.interfaces.append(measured.interfaceTexts[interfaceIndex].centered(at: center.translated(by: offset)))
            }
        }
        return nodes
    }
}

/// The nodes of a class diagram placed on the page, in the records its layout keeps.
struct ClassDiagramPlacedNodes {
    var classes: [ClassDiagramPlacedClass] = []
    var annotations: [DiagramMeasuredText] = []
    var members: [ClassDiagramPlacedMember] = []
    var notes: [ClassDiagramPlacedNote] = []
    var interfaces: [DiagramMeasuredText] = []
}
