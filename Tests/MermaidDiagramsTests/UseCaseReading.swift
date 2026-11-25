/**
 * File: UseCaseReading.swift
 * --------------------------
 * Layer: Tests
 * Description: Reads and lays out use case diagrams for the tests, with text of fixed widths where a test asserts
 *              positions.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Reads a use case diagram for a test, as the reading view does.
enum UseCaseReading {
    static func diagram(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> UseCaseDiagram {
        guard case .useCase(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return diagram
    }

    /// `usecase-beta` and the lines given, read.
    static func lines(_ lines: String...) throws(MermaidDiagramReadError) -> UseCaseDiagram {
        try diagram((["usecase-beta"] + lines).joined(separator: "\n"))
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try diagram(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// The problem of the error reading `source`, with its line, or nil when it reads or fails otherwise.
    static func problem(_ source: String) -> (line: Int, problem: UseCaseSyntaxProblem)? {
        guard case .invalidSyntax(let line, .useCase(let problem)) = readError(source) else { return nil }
        return (line, problem)
    }

    /// The contradiction reading `source` finds, or nil.
    static func contradiction(_ source: String) -> UseCaseContradiction? {
        guard case .contradiction(let contradiction)? = problem(source)?.problem else { return nil }
        return contradiction
    }

    /// The tokens' Mermaid names and texts, up to the end, or nil when the lexer finds no token at a character.
    static func tokens(_ source: String) -> [(String, String)]? {
        let text = UseCaseBytes(text: Array(source.utf8), removedLineBreaks: [])
        guard let tokens = try? UseCaseLexer.tokens(of: text) else { return nil }
        return tokens.kinds.indices.filter { index in tokens.kinds[index] != .end }.map { index in
            (tokens.kinds[index].mermaidName, text.string(MermaidTextRange(start: tokens.starts[index], end: tokens.ends[index])))
        }
    }

    /// Text of fixed widths, half the size a character, as Pele's differential tests measure it.
    static var uniformMeasurers: UseCaseTextMeasurers<UniformWidthTextMeasurer> {
        UseCaseTextMeasurers(font: DiagramFont(postScriptName: nil, size: 16)) { size, _, _ in
            UniformWidthTextMeasurer(characterWidth: size / 2, fontSize: size, lineHeight: (size * 1.5).rounded())
        }
    }

    /// `source` laid out with text of fixed widths.
    static func uniformLayout(_ source: String) throws -> UseCaseLayout {
        var measurers = uniformMeasurers
        return try UseCaseLayoutEngine.layout(try diagram(source), measurers: &measurers, limits: .standard)
    }
}

extension UseCaseDiagram {
    func actor(_ identifier: String) -> UseCaseActor? { actors.first { actor in actor.identifier == identifier } }
    func useCase(_ identifier: String) -> UseCase? { useCases.first { useCase in useCase.identifier == identifier } }
    func boundary(_ identifier: String) -> UseCaseSystemBoundary? { systemBoundaries.first { boundary in boundary.identifier == identifier } }
}

extension UseCaseLayout {
    func node(_ identifier: String) -> UseCaseLayoutNode? { nodes.first { node in node.identifier == identifier } }
    func edge(_ identifier: String) -> UseCaseLayoutEdge? { edges.first { edge in edge.identifier == identifier } }
}
