/**
 * File: main.swift
 * ----------------
 * Layer: Benchmark (prototype of the slow-types redesign)
 * Description: Runs the slow-types prototypes on a corpus of the benchmark's resources given by path.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
import MermaidDiagrams

let arguments = CommandLine.arguments.dropFirst()
let corpusPath = arguments.first ?? ""
let data = try Data(contentsOf: URL(fileURLWithPath: corpusPath))
var sources: [String] = []
if corpusPath.hasSuffix(".svg") {
} else if let strings = try? JSONDecoder().decode([String].self, from: data) {
    sources = strings
} else {
    struct Input: Decodable { let src: String }
    sources = try JSONDecoder().decode([Input].self, from: data).map(\.src)
}
let which = arguments.dropFirst().first ?? "text"
let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
switch which {
case "text": print(SlowTypesTextPrototype.run(sources: sources, typography: typography, rounds: 2_000, pairs: 9))
case "journey":
    print(SlowTypesJourneyPrototype.run(sources: sources, rounds: 20_000, pairs: 9))
    // Generated journeys: sections of tasks, each with one to three of five actors.
    let actors = ["Me", "Cat", "Partner", "Neighbour", "Boss"]
    let generated = [2, 5, 10].map { sectionCount -> String in
        var text = "journey\n    title A generated day of \(sectionCount) sections\n"
        for section in 0..<sectionCount {
            text += "    section Part \(section + 1) of the day\n"
            for task in 0..<6 {
                let named = (0...(task % 3)).map { offset in actors[(section + task + offset) % actors.count] }.joined(separator: ", ")
                text += "      Do task \(task + 1) of part \(section + 1): \((section + task) % 5 + 1): \(named)\n"
            }
        }
        return text
    }
    print("generated journeys (2, 5 and 10 sections of 6 tasks):")
    print(SlowTypesJourneyPrototype.run(sources: generated, rounds: 5_000, pairs: 9))
case "numbers":
    // The corpus path is an SVG here: its numbers, written again.
    let svg = try String(contentsOfFile: corpusPath, encoding: .utf8)
    let pattern = try NSRegularExpression(pattern: "-?[0-9]+(\\.[0-9]+)?")
    let values = pattern.matches(in: svg, range: NSRange(svg.startIndex..., in: svg)).compactMap { match in Double((svg as NSString).substring(with: match.range)) }
    print(SlowTypesNumberFloor.run(values: values, byteCount: svg.utf8.count, rounds: 5_000, pairs: 9))
default: print("unknown prototype \(which)")
}
