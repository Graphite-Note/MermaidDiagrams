/**
 * File: DiagramFlatTextBoundaryTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Checks the flat text measuring where a wrap decides by a tie: a room exactly as wide as a line of whole
 *              words, and a bit either side of it, wraps as the text block wraps; and the constant texts' widths, kept
 *              once per face, are the same when twelve threads ask for them at once as when one asks alone.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation
@testable import MermaidDiagrams
import XCTest

final class DiagramFlatTextBoundaryTests: XCTestCase {
    /// Faces whose advances sum exactly, so that the fast path wraps: 16 points, 16 points bold and 12 points.
    private static let measurers = [CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 16)),
                                    CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 16), isBold: true),
                                    CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 12))]

    /// A room exactly as wide as the text's first words with the spaces between them, the next word just fitting, and a
    /// bit narrower and wider: each wraps on the fast path as the block wraps (a word that ends exactly at the room stays).
    func testARoomExactlyAsWideAsWholeWordsWrapsAsTheBlock() {
        let texts = ["alpha beta gamma delta", "one  two   three four five", "Wrapping words at exactly their width", "a b c d e f g h",
                     "x1 (y) - z. w:v #q"]
        var checkedOnFastPath = 0
        var differences: [String] = []
        for measurer in Self.measurers {
            XCTAssertTrue(measurer.printableASCIIAdvances?.isExactlySummable == true, "\(measurer.fontSize) points sums exactly")
            let flat = DiagramFlatMeasurer(measurer)
            for text in texts {
                let words = text.split(separator: " ", omittingEmptySubsequences: false)
                for count in 1...words.count {
                    let prefix = words.prefix(count).joined(separator: " ")
                    let prefixWidth = DiagramTextBlock(label: DiagramLabelDecoder.label(from: String(prefix), form: .plain), measurer: measurer,
                                                       maximumWidth: .infinity).size.width
                    for maximumWidth in [prefixWidth.nextDown, prefixWidth, prefixWidth.nextUp] {
                        let bytes = Array(text.utf8)
                        var lines = DiagramMeasuredLines()
                        let block = DiagramTextBlock(label: DiagramLabelDecoder.label(from: text, form: .plain), measurer: measurer, maximumWidth: maximumWidth)
                        let (fast, measured) = bytes.withUnsafeBufferPointer { buffer in
                            let range = MermaidTextRange(start: 0, end: buffer.count)
                            let fast = DiagramFlatTextMeasuring.measuredOnFastPath(buffer, range, form: .plain, measurer: flat, maximumWidth: maximumWidth,
                                                                                   into: &lines)
                            return (fast, DiagramFlatTextMeasuring.measure(buffer, range, form: .plain, measurer: flat, maximumWidth: maximumWidth, into: &lines))
                        }
                        if let fast {
                            checkedOnFastPath += 1
                            if let difference = DiagramFlatTextMeasuringTests.difference(fast, lines, source: bytes, block) {
                                differences.append("fast path \(text.debugDescription) at \(maximumWidth) in \(measurer.fontSize): \(difference)")
                            }
                        }
                        if let difference = DiagramFlatTextMeasuringTests.difference(measured, lines, source: bytes, block) {
                            differences.append("\(text.debugDescription) at \(maximumWidth) in \(measurer.fontSize): \(difference)")
                        }
                    }
                }
            }
        }
        XCTAssertEqual(differences, [])
        XCTAssertGreaterThan(checkedOnFastPath, 100, "measured on the fast path")
    }

    /// Twelve threads take the widths of new constant texts at once, in three faces, each thread many times: every
    /// thread's widths are the widths one thread takes alone.
    func testConstantWidthsTakenOnTwelveThreadsAtOnceAreTheWidthsTakenAlone() {
        let names = ["«include»", "«extend»", "«person»", "«external system db»", "[Container]", "Requirement", "two words"]
        let alone = Self.measurers.map { measurer in DiagramConstantTexts(names).widths(for: measurer).widths }
        for _ in 0..<20 {
            let constants = DiagramConstantTexts(names)
            let found = ThreadDifferences()
            DispatchQueue.concurrentPerform(iterations: 12) { thread in
                let face = thread % Self.measurers.count
                for _ in 0..<5 where constants.widths(for: Self.measurers[face]).widths != alone[face] {
                    found.add("thread \(thread) in \(Self.measurers[face].fontSize) points")
                }
            }
            XCTAssertEqual(found.differences, [])
        }
    }
}

/// The differences threads found, gathered under a lock.
private final class ThreadDifferences: @unchecked Sendable {
    private let lock = NSLock()
    private var found: [String] = []

    func add(_ difference: String) {
        lock.lock()
        found.append(difference)
        lock.unlock()
    }

    var differences: [String] {
        lock.lock()
        defer { lock.unlock() }
        return found
    }
}
