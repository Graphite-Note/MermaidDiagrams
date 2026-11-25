/**
 * File: ClassDiagramPageFinishing.swift
 * -------------------------------------
 * Layer: Core
 * Description: A placed class diagram finished on the page: the rectangle its drawing covers, its parts that nothing
 *              joins set in rows for a narrow container, and every part placed once where the padding moves it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
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
                                                             edges: placedEdges, rowWidth: rowWidth, gap: gap) else { return nil }
        var wrapped = self
        wrapped.nodeCenters = zip(nodeCenters, rows.nodeOffsets).map { center, offset in center.translated(by: offset) }
        wrapped.edges = zip(edges, rows.edgeOffsets).map { edge, offset in edge?.translated(by: offset) }
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
            case .interface(let interfaceIndex): bounds = bounds.union(centered(measured.interfaceTexts[interfaceIndex], at: center).frame)
            }
        }
        for namespace in namespaces { bounds = bounds.union(namespace.frame) }
        for (edgeIndex, edge) in measured.edges.enumerated() where edge.relationIndex != nil {
            if let placed = edges[edgeIndex] { bounds = ClassDiagramLayoutBounds.union(bounds, edge: placed) }
        }
        for (edgeIndex, edge) in measured.edges.enumerated() where edge.relationIndex == nil {
            if let placed = edges[edgeIndex] { bounds = ClassDiagramLayoutBounds.union(bounds, edge: placed) }
        }
        return bounds.isNull ? .zero : bounds
    }

    /// The finished layout: everything moved so that the drawing, which covers `bounds`, starts `padding` from the top
    /// left, below the title, and centered under the title when the title is wider. Each part is placed where it is
    /// moved to, each list made once.
    func finished(font: DiagramFont, title: DiagramTextBlock?, padding: CGFloat, titleGap: CGFloat, bounds: CGRect) -> ClassDiagramLayout {
        let titleSize = title?.size ?? .zero
        let innerWidth = max(bounds.width, titleSize.width)
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let offset = CGVector(dx: padding + (innerWidth - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        let (classes, notes, interfaces) = placedNodes(offset: offset)
        var relations: [ClassDiagramLayoutEdge] = []
        var noteLinks: [ClassDiagramLayoutEdge] = []
        relations.reserveCapacity(measured.edges.count)
        for (edgeIndex, edge) in measured.edges.enumerated() {
            guard var placed = edges[edgeIndex] else { continue }
            placed.translate(by: offset)
            if edge.relationIndex == nil { noteLinks.append(placed) } else { relations.append(placed) }
        }
        var placedNamespaces = namespaces
        for index in placedNamespaces.indices { placedNamespaces[index] = placedNamespaces[index].translated(by: offset) }
        return ClassDiagramLayout(size: size, font: font, classes: classes, notes: notes, interfaces: interfaces, relations: relations, noteLinks: noteLinks,
                                  title: placedTitle, namespaces: placedNamespaces)
    }

    /// The classes' boxes, the notes and the interfaces' names at their nodes' centers, moved by `offset`.
    private func placedNodes(offset: CGVector) -> ([ClassDiagramLayoutClass], [ClassDiagramLayoutNote], [DiagramTextBlock]) {
        var classes: [ClassDiagramLayoutClass] = []
        var notes: [ClassDiagramLayoutNote] = []
        var interfaces: [DiagramTextBlock] = []
        classes.reserveCapacity(measured.boxes.count)
        notes.reserveCapacity(measured.noteTexts.count)
        interfaces.reserveCapacity(measured.interfaceTexts.count)
        for (node, kind) in measured.nodes.enumerated() {
            let center = nodeCenters[node]
            switch kind {
            case .classBox(let boxIndex): classes.append(measured.boxes[boxIndex].placed(at: center, offset: offset))
            case .note(let noteIndex):
                let size = measured.sizes[node]
                notes.append(ClassDiagramLayoutNote(frame: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width,
                                                                  height: size.height).offsetBy(dx: offset.dx, dy: offset.dy),
                                                    text: centered(measured.noteTexts[noteIndex], at: center.translated(by: offset))))
            case .interface(let interfaceIndex): interfaces.append(centered(measured.interfaceTexts[interfaceIndex], at: center.translated(by: offset)))
            }
        }
        return (classes, notes, interfaces)
    }
}
