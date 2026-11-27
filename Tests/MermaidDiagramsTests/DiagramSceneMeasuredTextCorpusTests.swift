/**
 * File: DiagramSceneMeasuredTextCorpusTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: Builds the scene of every input of every corpus, regular and narrow, of every diagram type, a second time
 *              with each text the builder is given as a block of a decoded label given instead as the text measured from
 *              the bytes it was written in (DiagramFlatTextMeasuring and DiagramSceneBuilder's measured texts): every SVG,
 *              accessibility text and scene text the same to the byte.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

import CoreGraphics
import Foundation
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark
import XCTest

final class DiagramSceneMeasuredTextCorpusTests: XCTestCase {
    /// Every input of every corpus prepared with its texts measured from their written bytes, against prepared as it is:
    /// the digest's line of each (its SVG, the palette's SVG, its spoken texts and its narrow scenes' SVGs) and the lines
    /// of each text of its scene the same.
    /// The graph types whose layouts measure their texts themselves (`DiagramMeasuredText`); none gives its scenes blocks
    /// of its own any more.
    /// State and class diagrams measure their texts too: their scenes are given no block but their boxes' titles
    /// (GraphBoxTitleSceneTextTests).
    private static let graphCorporaMeasuringTheirTexts = ["requirement-docs", "c4-docs"]
    /// The graph types whose layouts measure their texts themselves but give their groups' titles, a flowchart's cluster
    /// blocks, to their scenes as blocks: their inputs without groups give their scenes no block at all.
    private static let graphCorporaMeasuringTheirTextsButGroupTitles = ["er-docs"]

    func testEveryCorpusSceneBuiltFromWrittenBytesIsTheSame() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        let remeasuring = WrittenTextRemeasuring()
        var differences: [String] = []
        var inputCount = 0
        var countsByCorpus: [String: (substituted: Int, fromLabels: Int, kept: Int)] = [:]
        var blockedInputsWithoutGroups: [String] = []
        var inputsWithoutGroupsCount = 0
        for (corpus, sources) in try OutputDigest.corpora() {
            let before = (remeasuring.substitutedCount, remeasuring.fromLabelCount, remeasuring.keptCount)
            defer {
                countsByCorpus[corpus] = (remeasuring.substitutedCount - before.0, remeasuring.fromLabelCount - before.1, remeasuring.keptCount - before.2)
            }
            for (index, source) in sources.enumerated() {
                let blocksBefore = remeasuring.substitutedCount + remeasuring.fromLabelCount + remeasuring.keptCount
                defer {
                    if Self.graphCorporaMeasuringTheirTextsButGroupTitles.contains(corpus), Self.hasNoGroup(source) {
                        inputsWithoutGroupsCount += 1
                        if remeasuring.substitutedCount + remeasuring.fromLabelCount + remeasuring.keptCount != blocksBefore {
                            blockedInputsWithoutGroups.append("\(corpus) \(index)")
                        }
                    }
                }
                let expected = OutputDigest.Outcome(source: source, typography: typography, narrowColumnWidths: OutputDigest.narrowColumnWidths)
                let expectedLines = Self.sceneLines(source, typography: typography)
                let outcome = remeasuring.whileSubstituting {
                    (OutputDigest.Outcome(source: source, typography: typography, narrowColumnWidths: OutputDigest.narrowColumnWidths),
                     Self.sceneLines(source, typography: typography))
                }
                inputCount += 1
                if outcome.0.summaryLine != expected.summaryLine || outcome.1 != expectedLines, differences.count < 20 {
                    differences.append("\(corpus) \(index)")
                }
            }
        }
        XCTAssertEqual(differences, [])
        XCTAssertEqual(inputCount, 825)
        // The texts of the types whose layouts now measure their texts themselves (requirement, C4, most of timeline's)
        // are no longer given to their scenes as blocks, so not counted here: their own equivalence tests compare them.
        XCTAssertGreaterThan(remeasuring.substitutedCount, 28_000, "texts drawn from their written bytes")
        XCTAssertGreaterThan(remeasuring.substitutedCount + remeasuring.fromLabelCount, 4 * remeasuring.keptCount, "texts drawn from measured texts")
        XCTAssertGreaterThan(remeasuring.brokenCount, 50, "texts broken between characters drawn from their written bytes")
        // Those whose layouts measure their texts themselves give their scenes no block at all.
        for corpus in Self.graphCorporaMeasuringTheirTexts {
            let counts = countsByCorpus[corpus] ?? (-1, -1, -1)
            XCTAssertTrue(counts == (0, 0, 0), "\(corpus): \(counts) blocks given to its scenes")
        }
        // Those that give their groups' titles alone: an input without groups gives its scenes no block.
        XCTAssertEqual(blockedInputsWithoutGroups, [], "inputs without groups that gave their scenes blocks")
        XCTAssertGreaterThan(inputsWithoutGroupsCount, 15)
        print(countsByCorpus.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
    }

    /// Whether `source` reads as an entity relationship diagram without groups.
    private static func hasNoGroup(_ source: String) -> Bool {
        guard case .entityRelationship(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { return false }
        return diagram.subgraphCount == 0
    }

    /// The lines of each text of the input's regular scene, or none when it is refused.
    private static func sceneLines(_ source: String, typography: DiagramTypography) -> [[DiagramSceneTextLine]] {
        let prepared = try? MermaidDiagramPreparation.prepare(source: source, typography: typography, now: GanttChartCorpus.now,
                                                              timeZone: GanttChartCorpus.timeZone)
        return prepared?.scene.texts.map(\.lines) ?? []
    }
}

/// Watches the labels decoded and the blocks measured while a preparation runs, and gives the scene builder, for each
/// block of a label it saw decoded, the text measured again from the bytes the label was written in, at the same width in
/// the same measurer. The block's center is kept.
private final class WrittenTextRemeasuring: @unchecked Sendable {
    private struct LabelKey: Hashable {
        let storage: ObjectIdentifier
        let first: Int32
        let end: Int32
        let lineCount: Int32
        let flags: UInt8

        init(_ label: DiagramLabel) {
            storage = ObjectIdentifier(label.storage)
            (first, end, lineCount, flags) = (label.record.first, label.record.end, label.record.lineCount, UInt8(truncatingIfNeeded: label.record.flags.rawValue))
        }
    }

    private struct BlockKey: Hashable {
        let storage: ObjectIdentifier
        let first: Int32
        let end: Int32
        let lineCount: Int32
        let isOneLine: Bool
        let widest: UInt
        let fontSize: UInt

        init(_ block: DiagramTextBlock) {
            storage = ObjectIdentifier(block.storage)
            (first, end, lineCount, isOneLine) = (block.record.first, block.record.end, block.record.lineCount, block.record.isOneLine)
            (widest, fontSize) = (block.record.widestLineWidth.bitPattern, block.fontSize.bitPattern)
        }
    }

    private struct Measuring {
        let label: DiagramLabel
        let measurer: any DiagramTextMeasuring
        let maximumWidth: CGFloat
        let breakingWidth: CGFloat?
    }

    private var written: [LabelKey: (text: String, form: DiagramLabelDecoder.Form)] = [:]
    private var measured: [BlockKey: Measuring] = [:]
    /// Texts measured again from the bytes they were written in.
    private(set) var substitutedCount = 0
    /// Texts of labels made without decoding (names, synthetic texts), measured again from their labels.
    private(set) var fromLabelCount = 0
    /// Texts of blocks not measured from a label (literal lines, fitted texts, lines given with their widths), kept.
    private(set) var keptCount = 0
    private(set) var brokenCount = 0

    /// `body`'s result with every scene built in it given its texts measured from their written bytes; the watch is
    /// emptied before and after, so that a label's storage freed and made again elsewhere is not mistaken for it.
    func whileSubstituting<Result>(_ body: () -> Result) -> Result {
        written.removeAll(keepingCapacity: true)
        measured.removeAll(keepingCapacity: true)
        DiagramLabelDecodingObservation.observer = { [unowned self] text, form, label in written[LabelKey(label)] = (text, form) }
        DiagramTextBlockObservation.observer = { [unowned self] measuring in
            measured[BlockKey(measuring.block)] = Measuring(label: measuring.label, measurer: measuring.measurer,
                                                            maximumWidth: measuring.maximumWidth, breakingWidth: measuring.breakingWidth)
        }
        DiagramSceneTextSubstitution.measuredText = { [unowned self] block in substituted(block) }
        defer {
            DiagramLabelDecodingObservation.observer = nil
            DiagramTextBlockObservation.observer = nil
            DiagramSceneTextSubstitution.measuredText = nil
        }
        return body()
    }

    private func substituted(_ block: DiagramTextBlock) -> DiagramSceneTextSubstitution.Substituted? {
        guard let measuring = measured[BlockKey(block)] else {
            keptCount += 1
            return nil
        }
        guard let (text, form) = written[LabelKey(measuring.label)] else {
            fromLabelCount += 1
            return remeasured(measuring.label, measurer: measuring.measurer, maximumWidth: measuring.maximumWidth, breakingWidth: measuring.breakingWidth,
                              center: block.center)
        }
        substitutedCount += 1
        if measuring.breakingWidth != nil { brokenCount += 1 }
        return remeasured(text, form: form, measurer: measuring.measurer, maximumWidth: measuring.maximumWidth, breakingWidth: measuring.breakingWidth,
                          center: block.center)
    }

    /// `label`, made without decoding, measured as its block was: the layout's way for a text its model keeps as a label
    /// (`DiagramFlatTextMeasuring.measure(_:measurer:maximumWidth:into:)`), or, broken between characters, the block's
    /// lines copied.
    private func remeasured<Measurer: DiagramTextMeasuring>(_ label: DiagramLabel, measurer: Measurer, maximumWidth: CGFloat, breakingWidth: CGFloat?,
                                                            center: CGPoint) -> DiagramSceneTextSubstitution.Substituted {
        var lines = DiagramMeasuredLines()
        let measured = breakingWidth.map { breakingWidth in
            DiagramFlatTextMeasuring.copied(DiagramTextBlock(label: label, measurer: measurer, wrappingWidth: maximumWidth, breakingWidth: breakingWidth),
                                            into: &lines)
        } ?? DiagramFlatTextMeasuring.measure(label, measurer: DiagramFlatMeasurer(measurer), maximumWidth: maximumWidth, into: &lines)
        return DiagramSceneTextSubstitution.Substituted(text: measured.centered(at: center), lines: lines, source: [])
    }

    /// `text` measured from its bytes as its block was measured from its label.
    private func remeasured<Measurer: DiagramTextMeasuring>(_ text: String, form: DiagramLabelDecoder.Form, measurer: Measurer, maximumWidth: CGFloat,
                                                            breakingWidth: CGFloat?, center: CGPoint) -> DiagramSceneTextSubstitution.Substituted {
        let source = Array(text.utf8)
        var lines = DiagramMeasuredLines()
        let measured = source.withUnsafeBufferPointer { bytes in
            let range = MermaidTextRange(start: 0, end: bytes.count)
            guard let breakingWidth else {
                return DiagramFlatTextMeasuring.measure(bytes, range, form: form, measurer: DiagramFlatMeasurer(measurer), maximumWidth: maximumWidth,
                                                        into: &lines)
            }
            return DiagramFlatTextMeasuring.measureBreakingCharacters(bytes, range, form: form, measurer: DiagramFlatMeasurer(measurer),
                                                                      wrappingWidth: maximumWidth, breakingWidth: breakingWidth, into: &lines)
        }
        return DiagramSceneTextSubstitution.Substituted(text: measured.centered(at: center), lines: lines, source: source)
    }
}
