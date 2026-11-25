/**
 * File: DiagramSVGNumberWritingTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The branchless number writer writes the bytes 0.7.0's writer wrote (kept as ReferenceSVGNumberWriting) on
 *              the design's 1.2 million values: coordinates, quarters, eighths, ties, signed zeros, values that are not
 *              finite, the limits around 10,000 and 1e12 and a sweep of two-hundredths, and every hundredth its tables
 *              cover; it stores nothing past its room; and path elements are written as 0.7.0 wrote them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics
import Darwin
import XCTest
@testable import MermaidDiagrams

final class DiagramSVGNumberWritingTests: XCTestCase {
    /// The design's values: a million of the kinds a scene holds (whole points to 1,200, hundredths to 1,200, random
    /// values from -50 to 900, eighths to 300), the edges, and 200,000 steps of a two-hundredth from -300.
    private static func designValues() -> [CGFloat] {
        var generator = DiagramPathLaneSamples(seed: 0x1_2000_0021)
        var values: [CGFloat] = []
        values.reserveCapacity(1_200_021)
        for index in 0..<1_000_000 {
            switch index % 4 {
            case 0: values.append(CGFloat(generator.next() % 1_201))
            case 1: values.append(CGFloat(generator.next() % 120_001) / 100)
            case 2: values.append(generator.fraction() * 950 - 50)
            default: values.append(CGFloat(generator.next() % 2_401) / 8)
            }
        }
        values += [0, -0.0, 0.004, -0.004, 0.005, -0.005, 9_998.995, 9_998.994, 9_999, -9_999, 1e11, -1e12, .nan, .infinity, 12.345, 0.125,
                   100.125, -100.125, 99.995, 999.995, 9.995]
        for step in 0..<200_000 { values.append(CGFloat(step) / 200 - 300) }
        return values
    }

    func testTheDesignsValuesAreWrittenAs070WroteThem() {
        let values = Self.designValues()
        XCTAssertEqual(values.count, 1_200_021)
        let written = UnsafeMutablePointer<UInt8>.allocate(capacity: 64), reference = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        defer {
            written.deallocate()
            reference.deallocate()
        }
        var differenceCount = 0
        for value in values {
            let writtenCount = DiagramSVGNumberWriting.writeNumber(value, to: written)
            let referenceCount = ReferenceSVGNumberWriting.writeNumber(value, to: reference)
            guard writtenCount != referenceCount || memcmp(written, reference, writtenCount) != 0 else { continue }
            differenceCount += 1
            if differenceCount <= 5 { XCTFail("\(value): \(Self.text(written, writtenCount)) against \(Self.text(reference, referenceCount))") }
        }
        XCTAssertEqual(differenceCount, 0)
    }

    /// Around every limit the writer's rule changes at (10,000 for the branchless path, 1e12 for any number), each value
    /// and the next ones up and down are written as 0.7.0 wrote them.
    func testValuesAroundTheLimitsAreWrittenAs070WroteThem() {
        var values: [CGFloat] = []
        for limit: CGFloat in [9_999, 10_000, 999.995, 99.995, 9.995, 1e12, 999_999_999_999.99, 0.005, 1, 100, 1_000] {
            for signed in [limit, -limit] {
                var nearby = signed
                for _ in 0..<64 { nearby = nearby.nextUp }
                for _ in 0..<128 {
                    values.append(nearby)
                    nearby = nearby.nextDown
                }
            }
        }
        values += [.greatestFiniteMagnitude, -.greatestFiniteMagnitude, .leastNonzeroMagnitude, -.leastNonzeroMagnitude, -.nan, -.infinity]
        let written = UnsafeMutablePointer<UInt8>.allocate(capacity: 64), reference = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        defer {
            written.deallocate()
            reference.deallocate()
        }
        for value in values {
            let writtenCount = DiagramSVGNumberWriting.writeNumber(value, to: written)
            let referenceCount = ReferenceSVGNumberWriting.writeNumber(value, to: reference)
            XCTAssertEqual(Self.text(written, writtenCount), Self.text(reference, referenceCount), "\(value)")
        }
    }

    /// Every number of hundredths the tables cover, from -9,999 to 9,999, signed both ways, is written as 0.7.0 wrote it:
    /// each whole part's word and each fraction's word of `DiagramSVGDigitTables` is read at least once.
    func testEveryHundredthTheTablesCoverIsWrittenAs070WroteIt() {
        let written = UnsafeMutablePointer<UInt8>.allocate(capacity: 64), reference = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        defer {
            written.deallocate()
            reference.deallocate()
        }
        var differenceCount = 0
        for hundredths in -999_899...999_899 {
            let value = CGFloat(hundredths) / 100
            let writtenCount = DiagramSVGNumberWriting.writeNumber(value, to: written)
            let referenceCount = ReferenceSVGNumberWriting.writeNumber(value, to: reference)
            guard writtenCount != referenceCount || memcmp(written, reference, writtenCount) != 0 else { continue }
            differenceCount += 1
            if differenceCount <= 5 { XCTFail("\(value): \(Self.text(written, writtenCount)) against \(Self.text(reference, referenceCount))") }
        }
        XCTAssertEqual(differenceCount, 0)
    }

    /// The tables hold each whole part's digits without leading zeros, the first lowest, and each fraction's point,
    /// decimals and written count, as their documentation says.
    func testTheDigitTablesHoldWhatTheyDocument() {
        let tables = DiagramSVGDigitTables.shared
        XCTAssertEqual(tables.wholeParts[0], 0x30)
        XCTAssertEqual(tables.wholeParts[7], 0x37)
        XCTAssertEqual(tables.wholeParts[1_250], 0x30_35_32_31)
        XCTAssertEqual(tables.wholeParts[9_999], 0x39_39_39_39)
        XCTAssertEqual(tables.fractions[0], 0x00_30_30_2E)
        XCTAssertEqual(tables.fractions[50], 0x02_30_35_2E)
        XCTAssertEqual(tables.fractions[25], 0x03_35_32_2E)
        for whole in 0..<DiagramSVGDigitTables.wholePartCount {
            let word = tables.wholeParts[whole]
            let characters = (0..<4).map { index in UInt8(truncatingIfNeeded: word >> UInt32(8 * index)) }.filter { byte in byte != 0 }
            XCTAssertEqual(String(decoding: characters, as: UTF8.self), String(whole))
        }
    }

    /// The writer stores within the room a number is given (`largestNumberByteCount`), whatever it writes.
    func testNothingIsStoredPastTheRoomOfANumber() {
        let room = DiagramSVGNumberWriting.largestNumberByteCount
        let block = UnsafeMutablePointer<UInt8>.allocate(capacity: room + 16)
        defer { block.deallocate() }
        for value in Self.designValues().prefix(50_000) + [-9_998.99, 999_999_999_999.99, -999_999_999_999.99, -0.01] {
            block.initialize(repeating: 0xAA, count: room + 16)
            _ = DiagramSVGNumberWriting.writeNumber(value, to: block)
            XCTAssertTrue((room..<(room + 16)).allSatisfy { index in block[index] == 0xAA }, "\(value)")
        }
    }

    /// Path elements of random points are written as 0.7.0 wrote each Core Graphics element, and those of a lane's verbs
    /// as those of its Core Graphics elements.
    func testPathElementsAreWrittenAs070WroteThem() {
        var samples = DiagramSVGSceneSamples(seed: 0xE1E3)
        let written = UnsafeMutablePointer<UInt8>.allocate(capacity: 256), reference = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
        defer {
            written.deallocate()
            reference.deallocate()
        }
        for _ in 0..<5_000 {
            let path = samples.path()
            path.applyWithBlock { element in
                let writtenCount = DiagramSVGNumberWriting.writePathElement(element.pointee, to: written)
                let referenceCount = ReferenceSVGNumberWriting.writePathElement(element.pointee, to: reference)
                XCTAssertEqual(Self.text(written, writtenCount), Self.text(reference, referenceCount))
                XCTAssertLessThanOrEqual(writtenCount, DiagramSVGNumberWriting.largestPathElementByteCount)
            }
            DiagramSceneWorkspace.withRecording { workspace in
                let lane = workspace.makeLane()
                lane.appendElements(of: path)
                var laneData: [UInt8] = []
                lane.forEachElement { verb, points in
                    let count = DiagramSVGNumberWriting.writePathElement(verb, points, to: written)
                    laneData += UnsafeBufferPointer(start: written, count: count)
                }
                XCTAssertEqual(String(decoding: laneData, as: UTF8.self), DiagramSVGSyntax.pathData(path))
            }
        }
    }

    private static func text(_ bytes: UnsafePointer<UInt8>, _ count: Int) -> String {
        String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
    }
}
