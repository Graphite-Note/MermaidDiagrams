/**
 * File: PeleComparison.swift
 * --------------------------
 * Layer: Tests
 * Description: Prepares every input Pele's runner drew, measured in Arial as Pele's fallback measures it, and compares
 *              the scene with what Pele drew: the page within a tolerance, the texts and the shapes' subpaths by part.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics
import Foundation
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// What a prepared scene holds, counted as Pele's runner counts its SVG: the texts by part, and the subpaths of the
/// shapes by part (each move to a point starts one).
struct PeleSceneCounts {
    var texts: [String: Int] = [:]
    var subpaths: [String: Int] = [:]

    init(_ scene: DiagramScene) {
        for item in scene.items {
            switch item {
            case .text(let text):
                texts[text.part.rawValue, default: 0] += 1
            case .shape(let shape):
                var count = 0
                shape.path.applyWithBlock { element in
                    if element.pointee.type == .moveToPoint { count += 1 }
                }
                subpaths[shape.part.rawValue, default: 0] += count
            }
        }
    }

    var textCount: Int { texts.values.reduce(0, +) }
}

/// One input prepared by the package and drawn by Pele, and how they compare.
struct PeleComparedInput {
    let pele: PeleRenderedInput
    let source: String
    /// The scene, or why the package refused the input.
    let outcome: Result<DiagramScene, MermaidDiagramPreparationFailure>

    var name: String { "\(pele.corpus)#\(pele.index)" }

    /// What differs beyond the tolerance, each a short word for the known-differences file: `refused` (one side drew
    /// it, the other refused it), `width`, `height`, `texts` (how many texts in all), `edges` (the subpaths of the edges,
    /// where Pele draws `pele-edge` parts; the charts' lines, bands and series are classed otherwise).
    var differences: [String] {
        switch (outcome, pele.error) {
        case (.failure, .some): return []
        case (.failure, .none), (.success, .some): return ["refused"]
        case (.success(let scene), .none):
            var found: [String] = []
            let counts = PeleSceneCounts(scene)
            if !PeleComparison.isWithinTolerance(scene.size.width, pele.width ?? 0) { found.append("width") }
            if !PeleComparison.isWithinTolerance(scene.size.height, pele.height ?? 0) { found.append("height") }
            if counts.textCount != (pele.texts ?? [:]).values.reduce(0, +) { found.append("texts") }
            let peleDrawsEdges = pele.subpaths?["edge"] != nil || pele.groups?["edge"] != nil
            if peleDrawsEdges, counts.subpaths["edge", default: 0] != pele.subpaths?["edge", default: 0] ?? 0 { found.append("edges") }
            return found
        }
    }
}

enum PeleComparison {
    /// Arial, the font of the advance table Pele measures with outside a browser (`text/metrics.ts`); the package measures
    /// printable ASCII from the font's own advances without kerning, as the table holds them, at Pele's 16 pixels.
    static var typography: DiagramTypography { DiagramTypography(font: DiagramFont(postScriptName: "ArialMT", size: 16)) }

    /// The page may differ by 2 points, or 1 % of its side, whichever is more. Pele's table holds Arial's advances
    /// rounded to a thousandth of the size (Arial's own units are 2,048ths), so a line of text differs by at most 0.008
    /// points a character at 16, a fraction of a point for the longest labels; Pele rounds its page up to whole
    /// pixels (Math.ceil) where the package keeps fractions, one more point. Text outside ASCII (Pele: 580 thousandths,
    /// 1,000 for wide scripts; the package: Core Text with its fallback fonts) and monospaced text (Pele: 600 thousandths;
    /// the package: the system's monospaced font) can differ more; the 1 % covers sums of such small differences along
    /// a wide page, not a word wrapped onto another line.
    static func isWithinTolerance(_ mine: CGFloat, _ peles: Double) -> Bool {
        abs(Double(mine) - peles) <= max(2, 0.01 * peles)
    }

    /// Every input of `corpora` Pele's runner drew, prepared by the package.
    static func compared(corpora: Set<String>) throws -> [PeleComparedInput] {
        let inputs = try PeleResults.everyInput()
        let typography = typography
        var sourcesByCorpus: [String: [String]] = [:]
        return try inputs.filter { pele in corpora.contains(pele.corpus) }.map { pele in
            if sourcesByCorpus[pele.corpus] == nil { sourcesByCorpus[pele.corpus] = try PeleResults.sources(ofCorpus: pele.corpus) }
            let source = sourcesByCorpus[pele.corpus]?[pele.index] ?? ""
            let outcome = Result { () throws(MermaidDiagramPreparationFailure) -> DiagramScene in
                try MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: nil, now: GanttChartCorpus.now,
                                                      timeZone: GanttChartCorpus.timeZone).scene
            }
            return PeleComparedInput(pele: pele, source: source, outcome: outcome)
        }
    }
}
