/**
 * File: ArchitectureReading.swift
 * -------------------------------
 * Layer: Tests
 * Description: Reads architecture diagrams for the tests, the errors they throw, and their layouts with text of fixed
 *              widths, half the size a character, as Pele's differential tests measure it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

enum ArchitectureReading {
    static func architecture(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> ArchitectureDiagram {
        guard case .architecture(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return diagram
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try architecture(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// The diagram laid out with text half its size wide, lines 1.5 times the size apart.
    static func uniformLayout(_ source: String, availableWidth: CGFloat? = nil, isTight: Bool = false) throws -> ArchitectureLayout {
        ArchitectureLayoutEngine.layout(try architecture(source), font: DiagramFont(postScriptName: nil, size: 16), availableWidth: availableWidth,
                                        isTight: isTight) { fontSize, _ in
            UniformWidthTextMeasurer(characterWidth: fontSize / 2, fontSize: fontSize, lineHeight: (fontSize * 1.5).rounded())
        }
    }

    /// Each service's square and each junction's dot (a square of no size) by identifier.
    static func squares(_ layout: ArchitectureLayout) -> [String: CGRect] {
        var squares: [String: CGRect] = [:]
        for node in layout.nodes {
            switch node.form {
            case .service(let square, _, _, _): squares[node.identifier] = square
            case .junction(let center, _): squares[node.identifier] = CGRect(origin: center, size: .zero)
            }
        }
        return squares
    }

    /// The cell of each node by identifier.
    static func cells(_ source: String) throws -> [String: (column: Int, row: Int)] {
        let diagram = try architecture(source)
        let grid = ArchitectureGridPlacement.grid(of: diagram)
        var cells: [String: (column: Int, row: Int)] = [:]
        for (index, node) in diagram.nodes.enumerated() { cells[node.identifier] = (grid.nodeColumns[index], grid.nodeRows[index]) }
        return cells
    }
}
