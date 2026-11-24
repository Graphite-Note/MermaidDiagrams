/**
 * File: MermaidDiagramBlockPreparation.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Prepares a block diagram, with the diagram laid out within a narrow column or tight, and says what a
 *              screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

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
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (diagram, width) }, regularSize: layout.size, laidOut: { diagram, width in
                try BlockLayoutEngine.narrowLayout(diagram, typography: typography, width: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .block, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(block: diagram))
    }
}

extension MermaidDiagramAccessibility {
    /// Each block drawn by its text, breadth first as it is laid out, a composite by its title when it has one.
    init(block diagram: BlockDiagram) {
        self.init(kind: .block, title: diagram.title, description: nil) {
            let model = diagram.model
            let summary = diagram.reachableBlockIndices.dropFirst().compactMap { index -> String? in
                let block = model.blocks[index]
                guard block.kind != .space else { return nil }
                let label = model.bytes.withUnsafeBufferPointer { buffer in
                    DiagramLabelDecoder.label(fromUTF8: UnsafeBufferPointer(rebasing: buffer[block.label.lowerBound..<block.label.upperBound]), form: .plain)
                }.spokenText
                return label.isEmpty ? nil : label
            }
            return summary
        }
    }
}

extension BlockDiagram {
    /// Whether the root reaches no block but spaces: nothing is drawn.
    var drawsNoBlock: Bool {
        !reachableBlockIndices.dropFirst().contains { index in model.blocks[index].kind != .space }
    }
}
