/**
 * File: SimpleChartReading.swift
 * ------------------------------
 * Layer: Tests
 * Description: Reads an info diagram, a packet diagram, a radar chart or a treemap for a test, and finds the error reading refuses with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

@testable import MermaidDiagrams

/// Reads the four simple charts for a test, as the reading view does.
enum SimpleChartReading {
    static func info(_ source: String) throws(MermaidDiagramReadError) -> InfoDiagram {
        guard case .info(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw .noDiagram }
        return diagram
    }

    static func packet(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> PacketDiagram {
        guard case .packet(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return diagram
    }

    static func radar(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> RadarChart {
        guard case .radar(let chart) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return chart
    }

    static func treemap(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> TreemapDiagram {
        guard case .treemap(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return diagram
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try MermaidDiagramReader.read(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    static var typography: DiagramTypography { DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16)) }
}
