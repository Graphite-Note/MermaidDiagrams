/**
 * File: InputDigest.swift
 * -----------------------
 * Layer: Benchmark
 * Description: Prepares every text of a JSON file of texts (an array of strings) and prints the digest line of what each
 *              gives, as the output digest prints the corpora's, so that two builds can be compared byte for byte on
 *              generated or changed texts no corpus holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
import MermaidDiagrams

/// `--input-digest <file.json>`: the output digest of the texts a file holds instead of the corpora's.
enum InputDigest {
    static func run(arguments: [String], typography: DiagramTypography) throws {
        guard let path = arguments.first else {
            print("usage: --input-digest <file.json holding an array of texts>")
            return
        }
        let sources = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        var everyLine = FowlerNollVoDigest()
        for (index, source) in sources.enumerated() {
            let outcome = OutputDigest.Outcome(source: source, typography: typography, narrowColumnWidths: OutputDigest.narrowColumnWidths)
            let line = "\(index) \(outcome.summaryLine)"
            print(line)
            everyLine.add(line)
            everyLine.add("\n")
        }
        print("every input (\(sources.count)): \(everyLine.hexadecimal)")
    }
}
