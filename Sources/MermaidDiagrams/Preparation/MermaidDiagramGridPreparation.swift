/**
 * File: MermaidDiagramGridPreparation.swift
 * -----------------------------------------
 * Layer: Core
 * Description: The preparation of the types laid out on grids, block diagrams and architecture diagrams: their scenes,
 *              their tight scenes for a narrow column, and what a screen reader says of them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

extension MermaidDiagramPreparationContext {
    /// A block diagram, and for a narrow column the diagram as Pele's `tighten` draws it for a host too narrow: laid out
    /// within the column, or tight (smaller gaps, text wrapped sooner, titles wrapped to the column) when that is
    /// narrower still.
    func prepared(_ diagram: BlockDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: BlockLayout
        do {
            layout = try BlockLayoutEngine.layout(diagram, typography: typography)
        } catch {
            throw .blockLayout(error)
        }
        let narrow = narrowScene(of: narrowestColumnWidth.map { width in (diagram, width) }, regularSize: layout.size, laidOut: { diagram, width in
            try BlockLayoutEngine.narrowLayout(diagram, typography: typography, width: width)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .block, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(block: diagram))
    }
}

extension MermaidDiagramPreparationContext {
    /// An architecture diagram, and for a narrow column the diagram drawn tight, as Pele's `tighten` draws it.
    func prepared(_ diagram: ArchitectureDiagram) -> PreparedMermaidDiagram {
        let layout = ArchitectureLayoutEngine.layout(diagram, typography: typography)
        let narrow = narrowScene(of: narrowestColumnWidth.map { width in (diagram, width) }, regularSize: layout.size, laidOut: { diagram, width in
            ArchitectureLayoutEngine.layout(diagram, typography: typography, availableWidth: width, isTight: true)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .architecture, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(architecture: diagram))
    }
}

extension MermaidDiagramAccessibility {
    /// Each service by its title (its identifier without one), each group by its title, in the order written.
    init(architecture diagram: ArchitectureDiagram) {
        let services = diagram.nodes.filter { node in node.kind == .service }.map { node in node.title ?? node.identifier }
        let groups = diagram.groups.map { group in group.title ?? group.identifier }
        self.init(kind: .architecture, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription,
                  summary: groups + services)
    }

    /// Each block drawn by its text, breadth first as it is laid out, a composite by its title when it has one.
    init(block diagram: BlockDiagram) {
        let summary = diagram.reachableBlockIndices.dropFirst().compactMap { index -> String? in
            let block = diagram.blocks[index]
            guard block.kind != .space else { return nil }
            let label = DiagramLabelDecoder.label(from: block.label, form: .plain).spokenText
            return label.isEmpty ? nil : label
        }
        self.init(kind: .block, title: diagram.title, description: nil, summary: summary)
    }
}

extension BlockDiagram {
    /// Whether the root reaches no block but spaces: nothing is drawn.
    var drawsNoBlock: Bool {
        !reachableBlockIndices.dropFirst().contains { index in blocks[index].kind != .space }
    }
}
