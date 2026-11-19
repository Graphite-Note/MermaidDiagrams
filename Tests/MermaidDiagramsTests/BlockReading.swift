/**
 * File: BlockReading.swift
 * ------------------------
 * Layer: Tests
 * Description: Reads block diagrams for the tests, the errors they throw, the blocks drawn by identifier, and their
 *              layouts with text of fixed widths, half the size a character, as Pele's differential tests measure it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

enum BlockReading {
    static func block(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> BlockDiagram {
        guard case .block(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return diagram
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try block(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// The blocks the root holds, Pele's `getBlocks()`.
    static func topBlocks(_ diagram: BlockDiagram) -> [BlockDiagramBlock] {
        diagram.blocks[BlockDiagram.rootIndex].childIndices.map { index in diagram.blocks[index] }
    }

    /// The blocks `block` holds.
    static func children(of block: BlockDiagramBlock, in diagram: BlockDiagram) -> [BlockDiagramBlock] {
        block.childIndices.map { index in diagram.blocks[index] }
    }

    /// The block of `identifier` Pele's database keeps (the last registered of it), or nil.
    static func named(_ identifier: String, in diagram: BlockDiagram) -> BlockDiagramBlock? {
        diagram.reachableBlockIndices.map { index in diagram.blocks[index] }.first { block in block.identifier == identifier }
    }

    /// Pele's `getColumns("root")`: the root's columns, -1 for one row.
    static func rootColumns(_ diagram: BlockDiagram) -> Int {
        diagram.blocks[BlockDiagram.rootIndex].columns ?? -1
    }

    /// Text half the size a character wide: blocks at 16 points, edges at 14, lines 1.5 times the size apart.
    static var measurers: BlockMeasurers<UniformWidthTextMeasurer> { BlockMeasurers(nodeText: UniformWidthTextMeasurer(characterWidth: 8, fontSize: 16, lineHeight: 24),
                                          edgeText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                          titleText: UniformWidthTextMeasurer(characterWidth: 8, fontSize: 16, lineHeight: 24),
                                          restyled: { fontSize, _, _ in
                                              UniformWidthTextMeasurer(characterWidth: fontSize / 2, fontSize: fontSize, lineHeight: (fontSize * 1.5).rounded())
                                          }) }

    static func uniformLayout(_ source: String, availableWidth: CGFloat? = nil, isTight: Bool = false) throws -> BlockLayout {
        try BlockLayoutEngine.layout(try block(source), measurers: measurers, font: DiagramFont(postScriptName: nil, size: 16),
                                     availableWidth: availableWidth, isTight: isTight)
    }

    /// Each block's and composite's frame by its identifier.
    static func frames(_ layout: BlockLayout) -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        for composite in layout.composites { frames[composite.identifier] = composite.frame }
        for node in layout.nodes { frames[node.identifier] = node.frame }
        return frames
    }
}
