/**
 * File: FlatTextMeasuringBenchmark.swift
 * --------------------------------------
 * Layer: Benchmark
 * Description: Times the flat text measuring, which no type calls yet, against the label decoder and the text block on
 *              the texts of the C4 documentation examples, the costliest text measuring found, and the constant widths
 *              on the C4 shapes' kind names; or repeats one of them for a sampler.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics
import Foundation
@_spi(Benchmark) import MermaidDiagrams

/// `--flat-text [blocks|flat|constant-blocks|constant] [seconds]`: with no work named, times each pair of measurings in
/// alternating rounds and prints the medians per text; with one named, repeats it until the seconds (5 by default) are
/// spent, for sample(1).
enum FlatTextMeasuringBenchmark {
    /// The C4 layout's rooms: a shape's label room and an unbounded one.
    private static let widths: [CGFloat] = [.infinity, 166]
    private static let roundCount = 41

    static func run(arguments: [String]) throws {
        let texts = try c4Texts()
        let names = C4ShapeKind.allCases.map { kind in "«" + kind.rawValue.replacingOccurrences(of: "_", with: " ") + "»" } + ["«include»", "«extend»"]
        let font = DiagramFont(postScriptName: nil, size: 14)
        if let work = arguments.first {
            let seconds = arguments.dropFirst().first.flatMap(Double.init) ?? 5
            var workload = DiagramFlatTextMeasuringWorkload(texts: texts, font: font, maximumWidth: 166)
            var constants = DiagramConstantTextsWorkload(texts: names, font: font)
            let end = Date().addingTimeInterval(seconds)
            var total = 0.0
            var rounds = 0
            while Date() < end {
                switch work {
                case "blocks": total += workload.measureAsBlocks()
                case "flat": total += workload.measureFlat()
                case "constant-blocks": total += constants.measureAsBlocks(repeats: 10)
                case "constant": total += constants.measureConstant(repeats: 10)
                default: return print("--flat-text: blocks, flat, constant-blocks or constant")
                }
                rounds += 1
            }
            return print("\(work): \(rounds) rounds (\(total))")
        }
        print("flat text measuring, \(texts.count) texts of the C4 documentation examples, 14 points:")
        for width in widths {
            var workload = DiagramFlatTextMeasuringWorkload(texts: texts, font: font, maximumWidth: width)
            let (fastPathCount, differenceCount) = workload.check()
            let (blocks, flat) = alternated(repeats: 20, { _ = workload.measureAsBlocks() }, { _ = workload.measureFlat() })
            let perText = { (seconds: Double) in seconds / Double(20 * texts.count) * 1e9 }
            print("  at \(width): blocks \(format(perText(blocks))) ns a text, flat \(format(perText(flat))) ns a text (\(format(blocks / flat))x); "
                  + "\(fastPathCount) of \(texts.count) on the fast path, \(differenceCount) unlike their blocks")
        }
        var constants = DiagramConstantTextsWorkload(texts: names, font: font)
        let (blocks, constant) = alternated(repeats: 1, { _ = constants.measureAsBlocks(repeats: 50) }, { _ = constants.measureConstant(repeats: 50) })
        let perName = { (seconds: Double) in seconds / Double(50 * names.count) * 1e9 }
        print("  \(names.count) kind names: blocks \(format(perName(blocks))) ns a name, constant widths \(format(perName(constant))) ns a name "
              + "(\(format(blocks / constant))x)")
    }

    /// The medians of `roundCount` rounds of each, run in turn, in seconds a round.
    private static func alternated(repeats: Int, _ first: () -> Void, _ second: () -> Void) -> (Double, Double) {
        var firstTimes: [Double] = []
        var secondTimes: [Double] = []
        for _ in 0..<roundCount {
            firstTimes.append(timed(repeats, first))
            secondTimes.append(timed(repeats, second))
        }
        return (median(firstTimes), median(secondTimes))
    }

    private static func timed(_ repeats: Int, _ work: () -> Void) -> Double {
        let started = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<repeats { work() }
        return Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
    }

    private static func median(_ values: [Double]) -> Double {
        values.sorted()[values.count / 2]
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Every text the C4 layout measures, as the documentation examples write it: elements' labels, types, descriptions
    /// and technologies, relations' labels and technologies, titles.
    static func c4Texts() throws -> [String] {
        var texts: [String] = []
        for source in try C4Corpus.documentationExamples() {
            guard case .c4(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { continue }
            if let title = diagram.title { texts.append(title) }
            let elements = diagram.shapes.map(\.element) + diagram.boundaries.map(\.element)
            for element in elements {
                texts.append(element.label)
                texts += [element.type.map { type in "[" + type + "]" }, element.description, element.technology.map { technology in "[" + technology + "]" }]
                    .compactMap { text in text.flatMap { text in text.isEmpty ? nil : text } }
            }
            for relation in diagram.relations {
                texts.append(relation.label)
                if let technology = relation.technology, !technology.isEmpty { texts.append("[" + technology + "]") }
            }
        }
        return texts.filter { text in !text.isEmpty }
    }
}
