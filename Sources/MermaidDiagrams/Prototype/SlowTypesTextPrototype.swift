/**
 * File: SlowTypesTextPrototype.swift
 * ----------------------------------
 * Layer: Core (prototype of the slow-types redesign, not for merging as is)
 * Description: Records every text a C4 layout measures, checks that the flat measuring gives the same lines, widths
 *              and sizes as C4TextLabel.block, and times both, alternately.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation

public enum SlowTypesTextPrototype {
    struct Call {
        let text: String
        let measurer: CoreTextDiagramTextMeasurer
        let maximumWidth: CGFloat
    }

    nonisolated(unsafe) static var isRecording = false
    nonisolated(unsafe) static var recordedCalls: [Call] = []

    /// Lays out each C4 source once while recording, compares the two paths on every recorded call, then times them in
    /// `pairs` alternating pairs of `rounds` rounds and prints the medians.
    public static func run(sources: [String], typography: DiagramTypography, rounds: Int, pairs: Int) -> String {
        recordedCalls = []
        isRecording = true
        for source in sources {
            if case .c4(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) { _ = try? C4LayoutEngine.layout(diagram, typography: typography) }
        }
        isRecording = false
        let calls = recordedCalls
        let advances = calls.map { call in call.measurer.printableASCIIAdvances.advances }
        // A C4 shape's kind is one of a closed set of names, measured once per font face and kept (here: before the
        // timing, as a face would keep them); a text of the set takes its width by its kind.
        let kindNames = Set(C4ShapeKind.allCases.map(\.guillemetedName))
        let constantWidths: [CGFloat?] = calls.map { call in
            guard kindNames.contains(call.text) else { return nil }
            let width = call.measurer.width(of: call.text)
            return width <= call.maximumWidth ? width : nil
        }
        var report = "calls recorded: \(calls.count) (\(String(format: "%.1f", Double(calls.count) / Double(sources.count))) a diagram)\n"
        // Check.
        var lines = DiagramFlatTextLines()
        var fastCount = 0
        var mismatchCount = 0
        var fallbackExamples: [String] = []
        for (index, call) in calls.enumerated() {
            let old = C4TextLabel.block(call.text, measurer: call.measurer, maximumWidth: call.maximumWidth)
            lines.removeAll()
            let flat = flatMeasure(call, advances: advances[index], lines: &lines)
            if flat == nil, let constant = constantWidths[index] {
                if let old, old.size == CGSize(width: constant, height: call.measurer.lineHeight), old.lines == [call.text] { fastCount += 1 } else { mismatchCount += 1 }
                continue
            }
            guard let flat else {
                if fallbackExamples.count < 8 { fallbackExamples.append(call.text) }
                continue
            }
            fastCount += 1
            guard let old else { mismatchCount += 1; continue }
            var same = old.size == CGSize(width: flat.width, height: flat.height) && old.lines.count == Int(flat.lineCount) && old.lineHeight == flat.lineHeight
            let utf8 = Array(call.text.utf8)
            for line in 0..<Int(flat.lineCount) where same {
                let lineIndex = Int(flat.firstLine) + line
                let text = String(decoding: utf8[Int(lines.starts[lineIndex])..<Int(lines.ends[lineIndex])], as: UTF8.self)
                same = text == old.lines[line] && lines.widths[lineIndex] == old.lineWidths[line] && old.lineRuns == nil
            }
            if !same {
                mismatchCount += 1
                if mismatchCount < 5 { report += "MISMATCH: \(call.text.debugDescription) old \(old.lines) \(old.lineWidths) flat \(flat)\n" }
            }
        }
        report += "fast path: \(fastCount) of \(calls.count); mismatches: \(mismatchCount); off the fast path, e.g. \(fallbackExamples.map(\.debugDescription))\n"
        // Time, alternately.
        var oldTimes: [Double] = []
        var newTimes: [Double] = []
        var sink: CGFloat = 0
        for _ in 0..<pairs {
            oldTimes.append(time(rounds: rounds) {
                for call in calls { sink += C4TextLabel.block(call.text, measurer: call.measurer, maximumWidth: call.maximumWidth)?.size.width ?? 0 }
            })
            newTimes.append(time(rounds: rounds) {
                lines.removeAll()
                for (index, call) in calls.enumerated() {
                    if let flat = flatMeasure(call, advances: advances[index], lines: &lines) {
                        sink += flat.width
                    } else if let constant = constantWidths[index] {
                        sink += constant
                    } else {
                        sink += C4TextLabel.block(call.text, measurer: call.measurer, maximumWidth: call.maximumWidth)?.size.width ?? 0
                    }
                }
            })
        }
        // The fast path alone, on the texts it takes.
        let fastIndices = calls.indices.filter { index in
            var scratch = DiagramFlatTextLines()
            return flatMeasure(calls[index], advances: advances[index], lines: &scratch) != nil
        }
        var fastOld: [Double] = []
        var fastNew: [Double] = []
        for _ in 0..<pairs {
            fastOld.append(time(rounds: rounds) {
                for index in fastIndices { sink += C4TextLabel.block(calls[index].text, measurer: calls[index].measurer, maximumWidth: calls[index].maximumWidth)?.size.width ?? 0 }
            })
            fastNew.append(time(rounds: rounds) {
                lines.removeAll()
                for index in fastIndices { sink += flatMeasure(calls[index], advances: advances[index], lines: &lines)?.width ?? 0 }
            })
        }
        report += String(format: "on the %d texts of the fast path: old %.1f ns a text, flat %.1f ns a text\n", fastIndices.count,
                         median(fastOld) * 1e9 / Double(rounds * fastIndices.count), median(fastNew) * 1e9 / Double(rounds * fastIndices.count))
        // As the redesign holds them: every text a byte range of one buffer (the source's), the measurers' tables in one
        // flat list, the call's numbers in a flat struct; no string, array or class touched per text.
        struct FlatCall { var start: Int; var end: Int; var table: Int; var fontSize: CGFloat; var lineHeight: CGFloat; var maximumWidth: CGFloat }
        var buffer: [UInt8] = []
        var tables: [CGFloat] = []
        var tableStarts: [ObjectIdentifier: Int] = [:]
        var flatCalls: [FlatCall] = []
        for index in fastIndices {
            let call = calls[index]
            let start = buffer.count
            buffer.append(contentsOf: call.text.utf8)
            let key = ObjectIdentifier(advances[index] as AnyObject)
            let table = tableStarts[key] ?? {
                tables.append(contentsOf: advances[index])
                return tables.count - advances[index].count
            }()
            tableStarts[key] = table
            flatCalls.append(FlatCall(start: start, end: buffer.count, table: table, fontSize: call.measurer.fontSize, lineHeight: call.measurer.lineHeight,
                                      maximumWidth: call.maximumWidth))
        }
        var flatTimes: [Double] = []
        for _ in 0..<pairs {
            flatTimes.append(buffer.withUnsafeBufferPointer { bytes in
                tables.withUnsafeBufferPointer { tableBuffer in
                    flatCalls.withUnsafeBufferPointer { flatCallBuffer in
                        time(rounds: rounds) {
                            lines.removeAll()
                            for call in flatCallBuffer {
                                let text = UnsafeBufferPointer(rebasing: bytes[call.start..<call.end])
                                let table = UnsafeBufferPointer(rebasing: tableBuffer[call.table..<call.table + 95])
                                sink += DiagramFlatTextMeasuring.measure(text, advances: table, fontSize: call.fontSize, singleLineHeight: call.lineHeight,
                                                                         maximumWidth: call.maximumWidth, isLiteral: false, into: &lines)?.width ?? 0
                            }
                        }
                    }
                }
            })
        }
        report += String(format: "the same texts from one byte buffer: flat %.1f ns a text\n", median(flatTimes) * 1e9 / Double(rounds * fastIndices.count))
        var wrappedCount = 0
        var wrappedBytes = 0
        for index in fastIndices {
            var scratch = DiagramFlatTextLines()
            let call = calls[index]
            let size = flatMeasure(call, advances: advances[index], lines: &scratch)!
            if size.lineCount > 1 { wrappedCount += 1; wrappedBytes += call.text.utf8.count }
        }
        report += "texts of more than one line: \(wrappedCount), \(wrappedCount > 0 ? wrappedBytes / wrappedCount : 0) bytes on average\n"
        let averageBytes = Double(fastIndices.reduce(0) { sum, index in sum + calls[index].text.utf8.count }) / Double(fastIndices.count)
        report += String(format: "average text: %.1f bytes\n", averageBytes)
        let perDiagram = { (times: [Double]) -> Double in median(times) * 1e6 / Double(rounds * sources.count) }
        let perCall = { (times: [Double]) -> Double in median(times) * 1e9 / Double(rounds * calls.count) }
        report += String(format: "C4TextLabel.block: %.2f µs a diagram, %.1f ns a text\n", perDiagram(oldTimes), perCall(oldTimes))
        report += String(format: "flat measuring (full path where it falls back): %.2f µs a diagram, %.1f ns a text\n", perDiagram(newTimes), perCall(newTimes))
        report += String(format: "speed-up: %.1fx (sink %.0f)\n", median(oldTimes) / median(newTimes), sink)
        return report
    }

    private static func flatMeasure(_ call: Call, advances: [CGFloat], lines: inout DiagramFlatTextLines) -> DiagramFlatTextSize? {
        call.text.utf8.withContiguousStorageIfAvailable { bytes in
            advances.withUnsafeBufferPointer { advanceTable in
                DiagramFlatTextMeasuring.measure(bytes, advances: advanceTable, fontSize: call.measurer.fontSize, singleLineHeight: call.measurer.lineHeight,
                                                 maximumWidth: call.maximumWidth, isLiteral: false, into: &lines)
            }
        } ?? nil
    }

    private static func time(rounds: Int, _ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<rounds { body() }
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
