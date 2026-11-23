/**
 * File: PeleNarrowComparison.swift
 * --------------------------------
 * Layer: Tests
 * Description: Prepares every documentation example for a column 280, 390 and 600 points wide, measured in Arial as
 *              Pele's fallback measures it, and sets the scene that column shows beside what Pele shows in it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import Foundation
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

enum PeleNarrowComparison {
    /// An input's name in PeleKnownDifferences.md's narrow table: `corpus#index@width`.
    static func name(of input: PeleNarrowInput) -> String {
        "\(input.rendered.corpus)#\(input.rendered.index)@\(Int(input.maxWidth))"
    }

    /// Every documentation example of `corpora` Pele drew for a narrow container, prepared by the package for a column
    /// that wide (`narrowestColumnWidth`), compared with the scene that column shows (`scene(inColumnWidth:)`).
    static func compared(corpora: Set<String>) throws -> [(name: String, compared: PeleComparedInput)] {
        let typography = PeleComparison.typography
        var sourcesByCorpus: [String: [String]] = [:]
        return try PeleResults.narrow().inputs.filter { input in corpora.contains(input.rendered.corpus) }.map { input in
            let pele = input.rendered
            if sourcesByCorpus[pele.corpus] == nil { sourcesByCorpus[pele.corpus] = try PeleResults.sources(ofCorpus: pele.corpus) }
            let source = sourcesByCorpus[pele.corpus]?[pele.index] ?? ""
            let columnWidth = CGFloat(input.maxWidth)
            let outcome = Result { () throws(MermaidDiagramPreparationFailure) -> DiagramScene in
                try MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: columnWidth, now: GanttChartCorpus.now,
                                                      timeZone: GanttChartCorpus.timeZone).scene(inColumnWidth: columnWidth)
            }
            return (name(of: input), PeleComparedInput(pele: pele, source: source, outcome: outcome))
        }
    }
}
