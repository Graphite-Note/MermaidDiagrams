/**
 * File: VennReading.swift
 * -----------------------
 * Layer: Tests
 * Description: Reads a Venn diagram for a test, and lays one out with text of fixed widths.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

@testable import MermaidDiagrams

/// Reads a Venn diagram for a test, as the reading view does.
enum VennReading {
    static func venn(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> VennDiagram {
        guard case .venn(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return diagram
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try venn(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// The Venn diagram of `source` laid out with text of fixed widths: half the size a character (Pele's differential
    /// measurer), sets at 16 points, overlaps at 14, texts at 13, the title at 16.
    static func uniformLayout(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> VennLayout {
        let measurers = VennMeasurers(setText: UniformWidthTextMeasurer(characterWidth: 8, fontSize: 16, lineHeight: 24),
                                      overlapText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                      regionText: UniformWidthTextMeasurer(characterWidth: 6.5, fontSize: 13, lineHeight: 20),
                                      titleText: UniformWidthTextMeasurer(characterWidth: 8, fontSize: 16, lineHeight: 24))
        return try VennLayoutEngine.layout(try venn(source), measurers: measurers, font: DiagramFont(postScriptName: nil, size: 16), limits: limits)
    }
}
