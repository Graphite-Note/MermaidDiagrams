/**
 * File: GanttTaskFieldsEquivalenceTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: A Gantt task's data read on its bytes (GanttTaskFields) gives the tags, identifier, start and end, or the
 *              error, of 0.7.0's reader (ReferenceGanttTaskFields) on the data of every corpus's tasks and on tens of
 *              thousands of generated data texts of every spacing, tag and character beyond ASCII; data of many fields
 *              stays linear.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class GanttTaskFieldsEquivalenceTests: XCTestCase {
    /// What a reader gives, as one comparable value.
    private enum Reading: Equatable {
        case fields(flags: [Bool], identifier: String?, startText: String?, endText: String)
        case refused(MermaidDiagramReadError)
    }

    private func reading(_ data: String) -> Reading {
        do {
            let fields = try GanttTaskFields(name: "t", data: data, line: 3)
            return .fields(flags: [fields.isDone, fields.isActive, fields.isCritical, fields.isMilestone, fields.isVerticalMarker],
                           identifier: fields.identifier, startText: fields.startText, endText: fields.endText)
        } catch {
            return .refused(error)
        }
    }

    private func referenceReading(_ data: String) -> Reading {
        do {
            let fields = try ReferenceGanttTaskFields(name: "t", data: data, line: 3)
            return .fields(flags: [fields.isDone, fields.isActive, fields.isCritical, fields.isMilestone, fields.isVerticalMarker],
                           identifier: fields.identifier, startText: fields.startText, endText: fields.endText)
        } catch {
            return .refused(error)
        }
    }

    func testTheDataOfEveryCorpusTaskIsReadAsZeroSevenReadIt() throws {
        var compared = 0
        for source in try ChartReadingEquivalence.corpusSources(keywords: ["gantt"]) {
            for line in source.split(separator: "\n") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let data = String(line[line.index(after: colon)...])
                XCTAssertEqual(reading(data), referenceReading(data), data)
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 40)
    }

    func testGeneratedDataIsReadAsZeroSevenReadIt() {
        let fields = ["active", "done", "crit", "milestone", "vert", " active ", "\tdone", "Done", "crit\u{0B}", "activ", "milestones", "a1",
                      "2014-01-01", "after a1 b2", "until a1", "3d", "24h", " 2014-01-12 ", "", " ", "des1", "é", "crit\u{301}", "x\u{A0}",
                      "\u{3000}5d", "1w ", "\r", "\u{85}", "a\u{300},b"]
        let separators = [",", ", ", " ,", ",\t"]
        var state: UInt64 = 0x6A_77_F1_E1
        func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        var readOnBytes = 0
        for _ in 0..<40_000 {
            var data = ""
            for index in 0..<(1 + below(6)) {
                if index > 0 { data += separators[below(separators.count)] }
                data += fields[below(below(3) == 0 ? fields.count : 18)]
            }
            XCTAssertEqual(reading(data), referenceReading(data), data.debugDescription)
            if data.utf8.allSatisfy({ byte in byte < 0x80 }) { readOnBytes += 1 }
        }
        XCTAssertGreaterThan(readOnBytes, 20_000)
    }

    func testDataOfManyFieldsIsReadInLinearTime() {
        let tags = Array(repeating: "crit", count: 20_000).joined(separator: ",")
        let many = Array(repeating: "x", count: 20_000).joined(separator: ",")
        let clock = ContinuousClock()
        let start = clock.now
        XCTAssertEqual(reading(tags + ",a,b,c"), referenceReading(tags + ",a,b,c"))
        XCTAssertEqual(reading(many), .refused(.invalidSyntax(line: 3, problem: .taskWithTooManyFields(task: "t"))))
        XCTAssertEqual(reading(tags), .refused(.invalidSyntax(line: 3, problem: .taskWithoutEnd(task: "t"))))
        XCTAssertLessThan(clock.now - start, .seconds(2))
    }
}
