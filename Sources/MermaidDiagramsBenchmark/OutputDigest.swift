/**
 * File: OutputDigest.swift
 * ------------------------
 * Layer: Benchmark
 * Description: Prepares every input of Pele's corpora and benchmark and prints a digest of what each gives (its SVG, its
 *              narrow scenes, what a screen reader says, or why it is refused), so that two builds can be compared byte
 *              for byte; writes the SVGs to a folder when one is given.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import Foundation
import MermaidDiagrams

/// `--output-digest [folder]`: every input Pele's runner drew (`pele-corpus.json`'s corpora: each type's documentation
/// examples, the agent flow reference, the generated graphs of Pele's benchmark, and the random flat flowcharts) is
/// prepared as Graphite prepares it, and one line per input gives a digest of its outcome: the kind and the number of
/// statements not applied, the regular scene's SVG with Pele's variables and with a fixed palette and background, what a
/// screen reader says, and the narrow scene's SVG for a column 280, 390 and 600 points wide (Pele's narrow widths), or why
/// it is refused. The last line is the digest of every line. Two builds give the same lines when their output is the
/// same: a speed change is checked by comparing this run's output on both (`diff`). With a folder, each SVG is also written
/// there as `<corpus>-<index>[-narrow-<width>].svg`, to look at or compare.
enum OutputDigest {
    /// Pele's narrow widths (`scripts/pele/run.sh --max-width=280,390,600`), the first Graphite's narrowest column.
    static let narrowColumnWidths: [CGFloat] = [280, 390, 600]

    static func run(arguments: [String], typography: DiagramTypography) throws {
        let folder = arguments.first.map { path in URL(fileURLWithPath: path, isDirectory: true) }
        if let folder { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        var everyLine = FowlerNollVoDigest()
        var inputCount = 0
        for (corpus, sources) in try corpora() {
            for (index, source) in sources.enumerated() {
                let outcome = Outcome(source: source, typography: typography, narrowColumnWidths: narrowColumnWidths)
                let line = "\(corpus) \(index) \(outcome.summaryLine)"
                print(line)
                everyLine.add(line)
                everyLine.add("\n")
                inputCount += 1
                if let folder { try outcome.write(into: folder, name: "\(corpus)-\(index)") }
            }
        }
        print("every input (\(inputCount)): \(everyLine.hexadecimal)")
    }

    /// Each corpus Pele's runner drew, in the order of its first input in `pele-corpus.json`, then the random flat
    /// flowcharts.
    static func corpora() throws -> [(name: String, sources: [String])] {
        var names: [String] = []
        for input in try PeleResults.everyInput() where !names.contains(input.corpus) { names.append(input.corpus) }
        return try names.map { name in (name, try PeleResults.sources(ofCorpus: name)) }
    }

    /// What preparing one input gives, as the texts the digest is of.
    struct Outcome {
        let summaryLine: String
        /// The SVGs by the suffix of their file name ("" for the regular scene, "-narrow-280" for a narrow one).
        let documents: [(suffix: String, text: String)]

        init(source: String, typography: DiagramTypography, narrowColumnWidths: [CGFloat]) {
            func prepared(_ narrowestColumnWidth: CGFloat?) -> Result<PreparedMermaidDiagram, MermaidDiagramPreparationFailure> {
                Result { () throws(MermaidDiagramPreparationFailure) in
                    try MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: narrowestColumnWidth,
                                                          now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone)
                }
            }
            switch prepared(nil) {
            case .failure(let failure):
                summaryLine = "refused \(FowlerNollVoDigest.of(String(describing: failure)))"
                documents = []
            case .success(let diagram):
                var documents: [(suffix: String, text: String)] = [("", diagram.svgDocument())]
                let fixedPalette = DiagramSVGWriter(colors: .palette(MermaidDiagramsBenchmark.palette), paintsBackground: true)
                let accessibility = diagram.accessibility
                let spoken = [accessibility.title ?? "-", accessibility.description ?? "-", accessibility.summary.joined(separator: "\u{1}"),
                              accessibility.summarySeparator, accessibility.label, accessibility.value]
                var fields = [diagram.kind.peleName, "unapplied=\(diagram.unappliedStatementCount)", "svg=\(FowlerNollVoDigest.of(documents[0].text))",
                              "palette=" + FowlerNollVoDigest.of(fixedPalette.document(of: diagram.scene, diagramType: diagram.kind.peleName)),
                              "spoken=" + FowlerNollVoDigest.of(spoken.joined(separator: "\u{2}"))]
                for width in narrowColumnWidths {
                    let narrowName = "narrow-\(Int(width))"
                    switch prepared(width) {
                    case .failure(let failure):
                        fields.append("\(narrowName)=refused \(FowlerNollVoDigest.of(String(describing: failure)))")
                    case .success(let narrowPrepared):
                        guard let narrowScene = narrowPrepared.narrowScene else {
                            fields.append("\(narrowName)=none")
                            continue
                        }
                        let text = DiagramSVGWriter().document(of: narrowScene, diagramType: diagram.kind.peleName)
                        documents.append(("-\(narrowName)", text))
                        fields.append("\(narrowName)=\(FowlerNollVoDigest.of(text))")
                    }
                }
                summaryLine = fields.joined(separator: " ")
                self.documents = documents
            }
        }

        func write(into folder: URL, name: String) throws {
            for (suffix, text) in documents {
                try Data(text.utf8).write(to: folder.appendingPathComponent("\(name)\(suffix).svg"))
            }
        }
    }
}

/// FNV-1a over UTF-8 bytes, 64 bits: a digest to compare outputs, not a protection against anyone.
struct FowlerNollVoDigest {
    private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

    mutating func add(_ text: String) {
        for byte in text.utf8 { value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
    }

    var hexadecimal: String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }

    static func of(_ text: String) -> String {
        var digest = FowlerNollVoDigest()
        digest.add(text)
        return digest.hexadecimal
    }
}
