/**
 * File: MeasuredSceneTextBenchmark.swift
 * --------------------------------------
 * Layer: Benchmark
 * Description: Times texts taken to a scene as blocks of labels decoded from Strings against texts measured from their
 *              bytes and given to the scene builder as measured texts, on the C4 documentation examples' texts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
import Foundation
@_spi(Benchmark) import MermaidDiagrams

/// `--measured-scene-text [blocks|measured] [seconds]`: with no work named, times both ways in alternating rounds and
/// prints the medians per text; with one named, repeats it until the seconds (5 by default) are spent, for sample(1).
enum MeasuredSceneTextBenchmark {
    private static let widths: [CGFloat] = [.infinity, 166]
    private static let roundCount = 41
    private static let repeats = 20

    static func run(arguments: [String]) throws {
        let texts = try FlatTextMeasuringBenchmark.c4Texts()
        let font = DiagramFont(postScriptName: nil, size: 14)
        if let work = arguments.first {
            let seconds = arguments.dropFirst().first.flatMap(Double.init) ?? 5
            var workload = DiagramMeasuredSceneTextWorkload(texts: texts, font: font, maximumWidth: 166)
            let end = Date().addingTimeInterval(seconds)
            var drawn = 0
            var rounds = 0
            while Date() < end {
                switch work {
                case "blocks": drawn += workload.sceneFromBlocks()
                case "measured": drawn += workload.sceneFromMeasuredTexts()
                default: return print("--measured-scene-text: blocks or measured")
                }
                rounds += 1
            }
            return print("\(work): \(rounds) rounds (\(drawn) texts)")
        }
        print("texts to a scene, \(texts.count) texts of the C4 documentation examples, 14 points:")
        for width in widths {
            var workload = DiagramMeasuredSceneTextWorkload(texts: texts, font: font, maximumWidth: width)
            var blockTimes: [Double] = []
            var measuredTimes: [Double] = []
            for _ in 0..<roundCount {
                blockTimes.append(timed { _ = workload.sceneFromBlocks() })
                measuredTimes.append(timed { _ = workload.sceneFromMeasuredTexts() })
            }
            let perText = { (seconds: Double) in seconds / Double(repeats * texts.count) * 1e9 }
            let (blocks, measured) = (median(blockTimes), median(measuredTimes))
            print(String(format: "  at %@: blocks %.1f ns a text, measured texts %.1f ns a text (%.2fx)", "\(width)", perText(blocks), perText(measured),
                         blocks / measured))
        }
    }

    private static func timed(_ work: () -> Void) -> Double {
        let started = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<repeats { work() }
        return Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
    }

    private static func median(_ values: [Double]) -> Double {
        values.sorted()[values.count / 2]
    }
}
