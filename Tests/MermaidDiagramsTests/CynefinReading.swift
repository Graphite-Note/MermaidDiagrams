/**
 * File: CynefinReading.swift
 * --------------------------
 * Layer: Tests
 * Description: Reads a Cynefin framework for a test, and lays one out with text of fixed widths.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

@testable import MermaidDiagrams

/// Reads a Cynefin framework for a test, as the reading view does.
enum CynefinReading {
    static func cynefin(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> CynefinDiagram {
        guard case .cynefin(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return diagram
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try cynefin(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// The framework of `source` laid out with text of fixed widths, half the size a character: names and the title at
    /// 16 points, subtitles at 13, items at 14, labels at 13.
    static func uniformLayout(_ source: String) throws -> CynefinLayout {
        let measurers = CynefinMeasurers(nameText: UniformWidthTextMeasurer(characterWidth: 8, fontSize: 16, lineHeight: 24),
                                         subtitleText: UniformWidthTextMeasurer(characterWidth: 6.5, fontSize: 13, lineHeight: 20),
                                         itemText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                         labelText: UniformWidthTextMeasurer(characterWidth: 6.5, fontSize: 13, lineHeight: 20))
        return CynefinLayoutEngine.layout(try cynefin(source), measurers: measurers, font: DiagramFont(postScriptName: nil, size: 16))
    }
}
