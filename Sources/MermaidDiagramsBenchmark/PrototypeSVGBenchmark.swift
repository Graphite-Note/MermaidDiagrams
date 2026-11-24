/**
 * File: PrototypeSVGBenchmark.swift
 * ---------------------------------
 * Layer: Benchmark (design prototype, not for merging)
 * Description: Checks that the flat SVG writer writes every document of every corpus byte for byte as the writer of
 *              0.7.0 does, and times the two on one case in alternating rounds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation
import MermaidDiagrams

enum PrototypeSVGBenchmark {
    /// `--prototype-svg check` or `--prototype-svg <case> [pairs] [milliseconds]`.
    static func run(arguments: [String], typography: DiagramTypography) throws {
        guard let caseName = arguments.first else { return }
        if caseName == "check" { return try check(typography: typography) }
        let pairs = arguments.dropFirst().first.flatMap(Int.init) ?? 7
        let milliseconds = arguments.dropFirst(2).first.flatMap(Double.init) ?? 300
        try time(caseName, pairs: pairs, milliseconds: milliseconds, typography: typography)
    }

    private static func prepared(_ source: String, typography: DiagramTypography, narrowestColumnWidth: CGFloat? = nil) -> PreparedMermaidDiagram? {
        try? MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: narrowestColumnWidth,
                                               now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone)
    }

    private static func check(typography: DiagramTypography) throws {
        let scratch = DiagramSVGScratch(capacity: 256)
        var documentCount = 0
        var differences = 0
        let palette = DiagramSVGWriter(colors: .palette(MermaidDiagramsBenchmark.palette), paintsBackground: true)
        let flatPalette = DiagramFlatSVGWriter(colors: .palette(MermaidDiagramsBenchmark.palette), paintsBackground: true)
        for (corpus, sources) in try OutputDigest.corpora() {
            for (index, source) in sources.enumerated() {
                guard let diagram = prepared(source, typography: typography) else { continue }
                let flat = DiagramFlatScene(flattening: diagram.scene)
                var pairs: [(String, String, String)] = []
                pairs.append(("pele", diagram.svgDocument(),
                              DiagramFlatSVGWriter().document(of: flat, diagramType: diagram.kind.peleName, title: diagram.accessibility.title,
                                                              description: diagram.accessibility.description, scratch: scratch)))
                pairs.append(("palette", palette.document(of: diagram.scene, diagramType: diagram.kind.peleName),
                              flatPalette.document(of: flat, diagramType: diagram.kind.peleName, scratch: scratch)))
                for width in OutputDigest.narrowColumnWidths {
                    guard let narrow = prepared(source, typography: typography, narrowestColumnWidth: width)?.narrowScene else { continue }
                    pairs.append(("narrow-\(Int(width))", DiagramSVGWriter().document(of: narrow, diagramType: diagram.kind.peleName),
                                  DiagramFlatSVGWriter().document(of: DiagramFlatScene(flattening: narrow), diagramType: diagram.kind.peleName,
                                                                  scratch: scratch)))
                }
                for (name, old, new) in pairs {
                    documentCount += 1
                    if old != new {
                        differences += 1
                        if differences <= 5 { print("differs: \(corpus) \(index) \(name)\n old: \(old.prefix(300))\n new: \(new.prefix(300))") }
                    }
                }
            }
        }
        print("prototype SVG check: \(documentCount) documents, \(differences) differ")
    }

    private static func time(_ caseName: String, pairs: Int, milliseconds: Double, typography: DiagramTypography) throws {
        let sources: [String] = caseName == "docs: all examples" ? try FlowchartCorpus.documentationExamples() : try PeleResults.sources(ofCorpus: caseName)
        let diagrams = sources.compactMap { source in prepared(source, typography: typography) }
        let flats = diagrams.map { diagram in DiagramFlatScene(flattening: diagram.scene) }
        let scratch = DiagramSVGScratch()
        let writer = DiagramFlatSVGWriter()
        let count = Double(diagrams.count)
        func perInput(_ body: () -> Void) -> Double {
            let clock = ContinuousClock()
            let start = clock.now
            let end = start + .milliseconds(Int(milliseconds))
            var rounds = 0
            while clock.now < end {
                body()
                rounds += 1
            }
            let elapsed = clock.now - start
            return (Double(elapsed.components.seconds) * 1e6 + Double(elapsed.components.attoseconds) / 1e12) / (Double(rounds) * count)
        }
        if pairs == 0 {
            let only = perInput {
                for (diagram, flat) in zip(diagrams, flats) {
                    _ = writer.document(of: flat, diagramType: diagram.kind.peleName, title: diagram.accessibility.title,
                                        description: diagram.accessibility.description, scratch: scratch)
                }
            }
            print("flat writer only: \(only) µs")
            return
        }
        var old: [Double] = []
        var new: [Double] = []
        var newFreshScratch: [Double] = []
        var flattening: [Double] = []
        var bytes = 0
        for _ in 0..<pairs {
            old.append(perInput { for diagram in diagrams { bytes &+= diagram.svgDocument().utf8.count } })
            new.append(perInput {
                for (diagram, flat) in zip(diagrams, flats) {
                    bytes &+= writer.document(of: flat, diagramType: diagram.kind.peleName, title: diagram.accessibility.title,
                                              description: diagram.accessibility.description, scratch: scratch).utf8.count
                }
            })
            newFreshScratch.append(perInput {
                for (diagram, flat) in zip(diagrams, flats) {
                    bytes &+= writer.document(of: flat, diagramType: diagram.kind.peleName, title: diagram.accessibility.title,
                                              description: diagram.accessibility.description, scratch: DiagramSVGScratch(capacity: 4_096)).utf8.count
                }
            })
            flattening.append(perInput { for diagram in diagrams { bytes &+= DiagramFlatScene(flattening: diagram.scene).verbs.count } })
        }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        let ratios = zip(old, new).map { $0 / $1 }
        print(String(format: "%@ (%d inputs, %d pairs): SVG 0.7.0 %.3f µs, flat writer %.3f µs (fresh scratch %.3f µs), speed-up %.2fx (median of pair ratios); flattening a scene's CGPaths %.3f µs [%d]",
                     caseName, diagrams.count, pairs, median(old), median(new), median(newFreshScratch), median(ratios), median(flattening), bytes & 1))
    }
}
