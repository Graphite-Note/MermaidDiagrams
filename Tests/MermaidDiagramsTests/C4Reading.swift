/**
 * File: C4Reading.swift
 * ---------------------
 * Layer: Tests
 * Description: Reads and lays out C4 diagrams for the tests, as the reading view does, and with text of fixed widths.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Reads a C4 diagram for a test, as the reading view does.
enum C4Reading {
    static func c4(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> C4Diagram {
        guard case .c4(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return diagram
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try c4(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// The problem of the syntax error reading `source` throws, with its line, or nil.
    static func syntaxProblem(_ source: String) -> (line: Int, problem: C4SyntaxProblem)? {
        guard case .invalidSyntax(let line, .c4(let problem)) = readError(source) else { return nil }
        return (line, problem)
    }

    /// Text of fixed widths, half the size a character: names at 16 points, the small size at 13, a kind at 12.
    static var uniformMeasurers: C4Measurers<UniformWidthTextMeasurer> { C4Measurers(name: UniformWidthTextMeasurer(characterWidth: 8, fontSize: 16, lineHeight: 24),
                                              small: UniformWidthTextMeasurer(characterWidth: 6.5, fontSize: 13, lineHeight: 20),
                                              smallest: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 12, lineHeight: 18),
                                              italicSmall: UniformWidthTextMeasurer(characterWidth: 6.5, fontSize: 13, lineHeight: 20)) }

    /// `source` laid out with text of fixed widths, with room to spare, or tight for a column `columnWidth` wide.
    static func uniformLayout(_ source: String, columnWidth: CGFloat? = nil, gap: CGFloat = C4Metrics.narrowGap) throws -> C4Layout {
        let room = columnWidth.map { width in max(C4Metrics.leastRoom, width - 2 * C4Metrics.padding) }
        return try C4LayoutEngine.drawing(try c4(source), measurers: uniformMeasurers, font: DiagramFont(postScriptName: nil, size: 16), room: room,
                                          gap: gap).layout
    }
}

extension C4Layout {
    func shape(_ alias: String) -> C4LayoutShape? { shapes.first { shape in shape.alias == alias } }
    func boundary(_ alias: String) -> C4LayoutBoundary? { boundaries.first { boundary in boundary.alias == alias } }
    func relation(_ from: String, _ to: String) -> C4LayoutRelation? { relations.first { relation in relation.from == from && relation.to == to } }
}
