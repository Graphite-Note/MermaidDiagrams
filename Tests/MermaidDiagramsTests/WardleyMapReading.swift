/**
 * File: WardleyMapReading.swift
 * -----------------------------
 * Layer: Tests
 * Description: Reads a Wardley map for a test, and lays one out with text of fixed widths.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

@testable import MermaidDiagrams

/// Reads a Wardley map for a test, as the reading view does.
enum WardleyMapReading {
    static func map(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> WardleyMap {
        guard case .wardleyMap(let map) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return map
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try map(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// The map of `source` laid out with text of fixed widths, half the size a character: its text at 13 points, links'
    /// labels and forces at 12, annotations' numbers at 11, the title at 16.
    static func uniformLayout(_ source: String) throws -> WardleyMapLayout {
        let text = UniformWidthTextMeasurer(characterWidth: 6.5, fontSize: 13, lineHeight: 20)
        let link = UniformWidthTextMeasurer(characterWidth: 6, fontSize: 12, lineHeight: 18)
        let measurers = WardleyMapMeasurers(text: text, boldText: text, linkText: link, boldLinkText: link,
                                            boldNumberText: UniformWidthTextMeasurer(characterWidth: 5.5, fontSize: 11, lineHeight: 17),
                                            titleText: UniformWidthTextMeasurer(characterWidth: 8, fontSize: 16, lineHeight: 24))
        return WardleyMapLayoutEngine.layout(try map(source), measurers: measurers, font: DiagramFont(postScriptName: nil, size: 16))
    }
}
