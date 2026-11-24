/**
 * File: TextPrototypeBenchmark.swift
 * ----------------------------------
 * Layer: Prototype
 * Description: Records the labels and text blocks of a corpus's preparation, checks the flat prototype's lines and
 *              widths against the present text blocks bit for bit, and times both in alternating rounds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation

/// Prototype only: the flat text path against the present one, on the text of real preparations.
public enum TextPrototypeBenchmark {
    struct SourceText {
        var blocks: [TextPrototypeRecorder.RecordedBlock]
        var flatLabels: [FlatLabel]
        var fonts: [FlatFontStyles]
        var decodes: [(rawText: String, form: DiagramLabelDecoder.Form)]
        var decodeRanges: [Range<Int>]
    }

    public static func run(corpusName: String, sources: [String], typography: DiagramTypography, pairCount: Int, roundSeconds: Double) {
        var arena = FlatTextArena()
        var decodeBytes: [UInt8] = []
        var fontsByKey: [String: FlatFontStyles] = [:]
        var texts: [SourceText] = []
        for source in sources {
            TextPrototypeRecorder.blocks = []
            TextPrototypeRecorder.decodes = []
            TextPrototypeRecorder.isRecording = true
            _ = try? MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: nil).svgDocument()
            TextPrototypeRecorder.isRecording = false
            var text = SourceText(blocks: TextPrototypeRecorder.blocks, flatLabels: [], fonts: [], decodes: TextPrototypeRecorder.decodes, decodeRanges: [])
            for block in text.blocks {
                text.flatLabels.append(flatLabel(block.label, into: &arena))
                let measurer = block.measurer
                let key = "\(measurer.diagramFont.postScriptName ?? "")|\(measurer.fontSize)|\(measurer.isBold)|\(measurer.isItalic)|\(measurer.isMonospaced)"
                if fontsByKey[key] == nil { fontsByKey[key] = FlatFontStyles(measurer: measurer) }
                text.fonts.append(fontsByKey[key]!)
            }
            for decode in text.decodes {
                let start = decodeBytes.count
                decodeBytes.append(contentsOf: decode.rawText.utf8)
                text.decodeRanges.append(start..<decodeBytes.count)
            }
            texts.append(text)
        }
        let check = checked(texts, arena: &arena)
        // The same labels in fonts whose advances do not sum exactly, and at narrower widths, so that the sequential path and
        // more wrapping are checked too.
        for size in [12.8, 17.3, 9.1, 16, 14, 12] as [CGFloat] {
            let measurer = CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: size))
            let fonts = FlatFontStyles(measurer: measurer)
            var narrowed = texts
            for index in narrowed.indices {
                narrowed[index].blocks = narrowed[index].blocks.map { block in
                    TextPrototypeRecorder.RecordedBlock(label: block.label, measurer: measurer, maximumWidth: min(block.maximumWidth, 60))
                }
                narrowed[index].fonts = narrowed[index].blocks.map { _ in fonts }
            }
            let other = checked(narrowed, arena: &arena)
            print("  at \(size) points (advances sum exactly: \(fonts.isExactlySummable)), wrapped at 60 or less: \(other.mismatchCount) differ, "
                  + "\(other.wrappedCount) wrapped, \(other.fallbackCount) left to the present path")
            for message in other.messages.prefix(3) { print("    differs: \(message)") }
        }
        for (key, fonts) in fontsByKey.sorted(by: { $0.key < $1.key }) {
            var largestFractionBits = 0
            var largestAdvance: CGFloat = 0
            for raw in 0..<8 {
                for byte in 32...126 {
                    let advance = fonts.advances[raw * 256 + byte]
                    largestAdvance = max(largestAdvance, advance)
                    var bits = 0
                    while bits < 60, (advance * CGFloat(sign: .plus, exponent: bits, significand: 1)).rounded() != advance * CGFloat(sign: .plus, exponent: bits, significand: 1) { bits += 1 }
                    largestFractionBits = max(largestFractionBits, bits)
                }
            }
            print("  font \(key): advances have at most \(largestFractionBits) fraction bits, largest \(largestAdvance)")
        }
        let byteCount = texts.reduce(0) { total, text in total + text.blocks.reduce(0) { $0 + $1.label.lines.reduce(0) { $0 + $1.utf8.count } } }
        print("  \(byteCount) label bytes measured, \(String(format: "%.1f", Double(byteCount) / Double(max(1, texts.reduce(0) { $0 + $1.blocks.count })))) a block")
        let blockCount = texts.reduce(0) { $0 + $1.blocks.count }
        let decodeCount = texts.reduce(0) { $0 + $1.decodes.count }
        let unmarkedCount = texts.reduce(0) { total, text in
            total + text.decodeRanges.indices.filter { index in
                let range = text.decodeRanges[index]
                return DiagramLabelLineBreaks.isUnmarked(decodeBytes[range], isLiteral: text.decodes[index].form == .literal)
            }.count
        }
        print("\(corpusName): \(sources.count) sources, \(blockCount) blocks (\(String(format: "%.1f", Double(blockCount) / Double(sources.count))) a source), "
              + "\(check.fallbackCount) left to the present path (beyond printable ASCII), \(check.mismatchCount) differ, \(check.wrappedCount) wrapped, "
              + "\(check.emphasisCount) with emphasis; \(decodeCount) labels decoded, \(unmarkedCount) without markup")
        for message in check.messages.prefix(5) { print("  differs: \(message)") }

        var checksum = 0
        let measureRounds = alternate(pairCount: pairCount, roundSeconds: roundSeconds, inputCount: sources.count, present: {
            for text in texts {
                for block in text.blocks {
                    checksum &+= DiagramTextBlock(label: block.label, measurer: block.measurer, maximumWidth: block.maximumWidth).lines.count
                }
            }
        }, flat: {
            for text in texts {
                arena.removeMeasured()
                for index in text.blocks.indices {
                    let block = text.blocks[index]
                    if let measured = arena.measure(text.flatLabels[index], fonts: text.fonts[index], maximumWidth: block.maximumWidth) {
                        checksum &+= Int(measured.lineCount)
                    } else {
                        checksum &+= DiagramTextBlock(label: block.label, measurer: block.measurer, maximumWidth: block.maximumWidth).lines.count
                    }
                }
            }
        })
        let materializedRounds = alternate(pairCount: pairCount, roundSeconds: roundSeconds, inputCount: sources.count, present: {
            for text in texts {
                for block in text.blocks {
                    checksum &+= DiagramTextBlock(label: block.label, measurer: block.measurer, maximumWidth: block.maximumWidth).lines.count
                }
            }
        }, flat: {
            for text in texts {
                arena.removeMeasured()
                for index in text.blocks.indices {
                    let block = text.blocks[index]
                    guard let measured = arena.measure(text.flatLabels[index], fonts: text.fonts[index], maximumWidth: block.maximumWidth) else {
                        checksum &+= DiagramTextBlock(label: block.label, measurer: block.measurer, maximumWidth: block.maximumWidth).lines.count
                        continue
                    }
                    // What a block of Strings, as today's, costs on top: each line's String and the two lists.
                    var lines: [String] = []
                    var widths: [CGFloat] = []
                    lines.reserveCapacity(Int(measured.lineCount))
                    widths.reserveCapacity(Int(measured.lineCount))
                    arena.bytes.withUnsafeBufferPointer { bytes in
                        for line in arena.lines[Int(measured.firstLine)..<Int(measured.firstLine + measured.lineCount)] {
                            let run = arena.runs[Int(line.firstRun)]
                            lines.append(line.runCount == 0 ? "" : String(decoding: UnsafeBufferPointer(rebasing: bytes[Int(run.start)..<Int(arena.runs[Int(line.firstRun + line.runCount - 1)].end)]), as: UTF8.self))
                            widths.append(line.width)
                        }
                    }
                    checksum &+= lines.count &+ widths.count
                }
            }
        })
        print("  measure and wrap into Strings and lists as today's blocks hold them, µs a source: present \(format(materializedRounds.present)), "
              + "flat then Strings \(format(materializedRounds.flat)), \(String(format: "%.1f", materializedRounds.present / materializedRounds.flat))x")
        // The design's blocks: the label's bytes copied into the layout's storage, found through the thread, each block a
        // reference to it and its record, kept in a list as a layout keeps its texts.
        var labelBytesByBlock: [[UInt8]] = []
        for text in texts {
            for index in text.blocks.indices {
                let label = text.flatLabels[index]
                let lines = arena.labelLines[Int(label.firstLine)..<Int(label.firstLine + label.lineCount)]
                labelBytesByBlock.append(lines.isEmpty ? [] : Array(arena.bytes[Int(lines.first!.start)..<Int(lines.last!.end)]))
            }
        }
        var keptBlocks: [FlatStoredBlock] = []
        keptBlocks.reserveCapacity(512)
        let storedRounds = alternate(pairCount: pairCount, roundSeconds: roundSeconds, inputCount: sources.count, present: {
            for text in texts {
                var kept: [DiagramTextBlock] = []
                kept.reserveCapacity(text.blocks.count)
                for block in text.blocks {
                    kept.append(DiagramTextBlock(label: block.label, measurer: block.measurer, maximumWidth: block.maximumWidth))
                }
                checksum &+= kept.count
            }
        }, flat: {
            var flatIndex = 0
            for text in texts {
                let storage = FlatTextStorage()
                storage.arena.bytes.reserveCapacity(256)
                FlatTextStorage.withCurrent(storage) {
                    keptBlocks.removeAll(keepingCapacity: true)
                    for index in text.blocks.indices {
                        let current = FlatTextStorage.current!
                        // The label's bytes copied in after the storage's, its records moved by as much.
                        var label = text.flatLabels[index]
                        let offset = Int32(current.arena.bytes.count) - (label.lineCount > 0 ? arena.labelLines[Int(label.firstLine)].start : 0)
                        current.arena.bytes.append(contentsOf: labelBytesByBlock[flatIndex])
                        let firstLine = Int32(current.arena.labelLines.count)
                        for lineIndex in Int(label.firstLine)..<Int(label.firstLine + label.lineCount) {
                            var line = arena.labelLines[lineIndex]
                            line.start += offset
                            line.end += offset
                            let firstSpan = Int32(current.arena.labelSpans.count)
                            for spanIndex in Int(line.firstSpan)..<Int(line.firstSpan + line.spanCount) {
                                var span = arena.labelSpans[spanIndex]
                                span.start += offset
                                span.end += offset
                                current.arena.labelSpans.append(span)
                            }
                            line.firstSpan = firstSpan
                            current.arena.labelLines.append(line)
                        }
                        label.firstLine = firstLine
                        flatIndex += 1
                        if let record = current.arena.measure(label, fonts: text.fonts[index], maximumWidth: text.blocks[index].maximumWidth) {
                            keptBlocks.append(FlatStoredBlock(storage: current, record: record))
                        } else {
                            checksum &+= DiagramTextBlock(label: text.blocks[index].label, measurer: text.blocks[index].measurer,
                                                          maximumWidth: text.blocks[index].maximumWidth).lines.count
                        }
                    }
                }
                checksum &+= keptBlocks.count
            }
        })
        print("  measure and wrap into blocks kept in a list, µs a source: present \(format(storedRounds.present)), "
              + "blocks of a storage found through the thread \(format(storedRounds.flat)), \(String(format: "%.1f", storedRounds.present / storedRounds.flat))x")
        print("  measure and wrap, µs a source: present \(format(measureRounds.present)), flat \(format(measureRounds.flat)), "
              + "\(String(format: "%.1f", measureRounds.present / measureRounds.flat))x")

        var decoder = FlatLabelDecoder()
        var decodeMismatches: [String] = []
        decodeBytes.withUnsafeBufferPointer { bytes in
            for text in texts {
                for index in text.decodes.indices {
                    let (rawText, form) = text.decodes[index]
                    let present = DiagramLabelDecoder.label(from: rawText, form: form)
                    decoder.removeAll()
                    let range = text.decodeRanges[index]
                    let flat = decoder.decode(bytes, range.lowerBound, range.upperBound, form: form)
                    var lines: [String] = []
                    var spans: [[DiagramLabelSpan]] = []
                    for line in decoder.lines[Int(flat.label.firstLine)..<Int(flat.label.firstLine + flat.label.lineCount)] {
                        let lineBytes = flat.isInSource ? Array(bytes[Int(line.start)..<Int(line.end)]) : Array(decoder.output[Int(line.start)..<Int(line.end)])
                        lines.append(String(decoding: lineBytes, as: UTF8.self))
                        spans.append(decoder.spans[Int(line.firstSpan)..<Int(line.firstSpan + line.spanCount)].map { span in
                            DiagramLabelSpan(text: String(decoding: decoder.output[Int(span.start)..<Int(span.end)], as: UTF8.self), style: span.style)
                        })
                    }
                    let sameSpans = flat.label.hasSpans ? present.spans == spans : present.spans == nil
                    if lines != present.lines || !sameSpans || flat.label.isReadWithoutMarkup != present.isReadWithoutMarkup {
                        decodeMismatches.append("\(rawText.debugDescription) \(form): \(present.lines) \(String(describing: present.spans)) against \(lines) \(spans)")
                    }
                }
            }
        }
        print("  decode: \(decodeMismatches.count) of \(decodeCount) differ")
        for message in decodeMismatches.prefix(6) { print("    differs: \(message)") }
        let decodeRounds = decodeBytes.withUnsafeBufferPointer { bytes in
            alternate(pairCount: pairCount, roundSeconds: roundSeconds, inputCount: sources.count, present: {
                for text in texts {
                    for decode in text.decodes { checksum &+= DiagramLabelDecoder.label(from: decode.rawText, form: decode.form).lines.count }
                }
            }, flat: {
                for text in texts {
                    decoder.removeAll()
                    for index in text.decodes.indices {
                        let range = text.decodeRanges[index]
                        checksum &+= Int(decoder.decode(bytes, range.lowerBound, range.upperBound, form: text.decodes[index].form).label.lineCount)
                    }
                }
            })
        }
        let markedDecodes = texts.flatMap { text in text.decodes.indices.filter { index in
            !DiagramLabelLineBreaks.isUnmarked(Array(text.decodes[index].rawText.utf8), isLiteral: text.decodes[index].form == .literal) }.map { index in
            (text.decodes[index], text.decodeRanges[index]) } }
        let markedRounds = decodeBytes.withUnsafeBufferPointer { bytes in
            alternate(pairCount: pairCount, roundSeconds: roundSeconds, inputCount: max(markedDecodes.count, 1), present: {
                for (decode, _) in markedDecodes { checksum &+= DiagramLabelDecoder.label(from: decode.rawText, form: decode.form).lines.count }
            }, flat: {
                decoder.removeAll()
                for (decode, range) in markedDecodes {
                    checksum &+= Int(decoder.decode(bytes, range.lowerBound, range.upperBound, form: decode.form).label.lineCount)
                }
            })
        }
        print("  decode, µs a source: present \(format(decodeRounds.present)), flat \(format(decodeRounds.flat)), "
              + "\(String(format: "%.1f", decodeRounds.present / decodeRounds.flat))x; a label with markup: present \(format(markedRounds.present)), flat "
              + "\(format(markedRounds.flat)) (\(markedDecodes.count) of them)  (checksum \(checksum & 1))")
    }

    private static func format(_ value: Double) -> String { String(format: "%.3f", value) }

    /// The median per source of alternating rounds of both.
    private static func alternate(pairCount: Int, roundSeconds: Double, inputCount: Int, present: () -> Void, flat: () -> Void) -> (present: Double, flat: Double) {
        var presentTimes: [Double] = []
        var flatTimes: [Double] = []
        for _ in 0..<pairCount {
            presentTimes.append(timed(roundSeconds, inputCount, present))
            flatTimes.append(timed(roundSeconds, inputCount, flat))
        }
        return (presentTimes.sorted()[pairCount / 2], flatTimes.sorted()[pairCount / 2])
    }

    private static func timed(_ seconds: Double, _ inputCount: Int, _ work: () -> Void) -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        let end = start + .milliseconds(Int(seconds * 1_000))
        var rounds = 0
        while clock.now < end {
            work()
            rounds += 1
        }
        let elapsed = clock.now - start
        let microseconds = Double(elapsed.components.seconds) * 1e6 + Double(elapsed.components.attoseconds) / 1e12
        return microseconds / Double(rounds * max(inputCount, 1))
    }

    /// `label` written into the arena's bytes as a flat label.
    static func flatLabel(_ label: DiagramLabel, into arena: inout FlatTextArena) -> FlatLabel {
        let firstLine = Int32(arena.labelLines.count)
        var isPrintableASCII = true
        for index in label.lines.indices {
            let lineStart = Int32(arena.bytes.count)
            let firstSpan = Int32(arena.labelSpans.count)
            if label.spans != nil {
                for span in label.spans(ofLine: index) {
                    let start = Int32(arena.bytes.count)
                    arena.bytes.append(contentsOf: span.text.utf8)
                    arena.labelSpans.append(FlatLabelSpan(start: start, end: Int32(arena.bytes.count), style: span.style))
                }
            } else {
                arena.bytes.append(contentsOf: label.lines[index].utf8)
            }
            for byte in arena.bytes[Int(lineStart)...] where byte < 0x20 || byte > 0x7E { isPrintableASCII = false }
            arena.labelLines.append(FlatLabelLine(start: lineStart, end: Int32(arena.bytes.count), firstSpan: firstSpan,
                                                  spanCount: Int32(arena.labelSpans.count) - firstSpan))
        }
        return FlatLabel(firstLine: firstLine, lineCount: Int32(label.lines.count), hasSpans: label.spans != nil,
                         isReadWithoutMarkup: label.isReadWithoutMarkup, isPrintableASCII: isPrintableASCII)
    }

    /// Every block measured both ways and compared: lines, widths to the bit, line height and runs.
    private static func checked(_ texts: [SourceText], arena: inout FlatTextArena)
        -> (fallbackCount: Int, mismatchCount: Int, wrappedCount: Int, emphasisCount: Int, messages: [String]) {
        var fallbackCount = 0, mismatchCount = 0, wrappedCount = 0, emphasisCount = 0
        var messages: [String] = []
        for text in texts {
            for index in text.blocks.indices {
                let recorded = text.blocks[index]
                let present = DiagramTextBlock(label: recorded.label, measurer: recorded.measurer, maximumWidth: recorded.maximumWidth)
                if present.lines.count > recorded.label.lines.count { wrappedCount += 1 }
                if present.lineRuns != nil { emphasisCount += 1 }
                arena.removeMeasured()
                guard let flat = arena.measure(text.flatLabels[index], fonts: text.fonts[index], maximumWidth: recorded.maximumWidth) else {
                    fallbackCount += 1
                    continue
                }
                var lines: [String] = []
                var widths: [CGFloat] = []
                var runs: [[DiagramTextRun]] = []
                for line in arena.lines[Int(flat.firstLine)..<Int(flat.firstLine + flat.lineCount)] {
                    var lineRuns: [DiagramTextRun] = []
                    for run in arena.runs[Int(line.firstRun)..<Int(line.firstRun + line.runCount)] {
                        let runText = String(decoding: arena.bytes[Int(run.start)..<Int(run.end)], as: UTF8.self)
                        lineRuns.append(DiagramTextRun(text: runText, style: run.style, width: run.width))
                    }
                    lines.append(lineRuns.map(\.text).joined())
                    widths.append(line.width)
                    runs.append(lineRuns)
                }
                let sameWidths = widths.count == present.lineWidths.count
                    && zip(widths, present.lineWidths).allSatisfy { flatWidth, presentWidth in flatWidth.bitPattern == presentWidth.bitPattern }
                let sameRuns = flat.hasEmphasis ? present.lineRuns == runs : present.lineRuns == nil
                if lines != present.lines || !sameWidths || flat.lineHeight != present.lineHeight || !sameRuns {
                    mismatchCount += 1
                    messages.append("\(present.lines) \(present.lineWidths) against \(lines) \(widths)")
                }
            }
        }
        return (fallbackCount, mismatchCount, wrappedCount, emphasisCount, messages)
    }
}

/// Label bytes as the flat decoder reads them first: whether Pele reads them without markup, and their trimmed range.
enum FlatLabelScanning {
    @inline(__always)
    static func isUnmarked(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int, isLiteral: Bool) -> Bool {
        DiagramLabelLineBreaks.isUnmarked(bytes[start..<end], isLiteral: isLiteral)
    }

    static func trimmed(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> Range<Int> {
        let slice = bytes[start..<end]
        let trimmedStart = JavaScriptWhitespace.endOfRun(in: slice, from: start)
        var trimmedEnd = end
        while trimmedEnd > trimmedStart, case let length = JavaScriptWhitespace.lengthOfLast(in: bytes[trimmedStart..<trimmedEnd]), length > 0 {
            trimmedEnd -= length
        }
        return trimmedStart..<trimmedEnd
    }
}
