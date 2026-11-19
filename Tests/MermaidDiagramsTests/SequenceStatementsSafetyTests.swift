/**
 * File: SequenceStatementsSafetyTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: Sequence texts with boxes, attributes, created and destroyed participants, half arrows and central
 *              connections, cut short and mutated, are drawn or refused with a typed error, never a crash or a hang.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class SequenceStatementsSafetyTests: XCTestCase {
    private static let samples = [
        DiagramSceneSamples.styled.first { name, _ in name == "sequence boxes, shapes and lifetimes" }?.1 ?? "",
        """
        sequenceDiagram
            participant A@{ type: database, alias: "Two<br>lines", list: [a, "b\\tc"] }
            box hsl(200deg 50% 50% / 80%) wrap: A long boxed title that wraps
            participant B@{ 'type' : 'control', "alias": 'It''s' } as Bee
            destroy B
            end
            B--|/A: dotted half
            A\\\\-B: reverse stick
            create actor C
            A()-->>()C: both
            destroy C
            C->>()C: last
        """,
    ]

    /// Each sample cut at every tenth of a byte position and changed at 200 random places (a character removed, an
    /// arrow, brace, quote or slash character added, or a run of text doubled) is laid out at a finite size or refused.
    func testEverySampleCutShortOrMutatedIsDrawnOrRefusedWithoutACrash() {
        var generator = SplitMixGenerator(seed: 0x5E9)
        let insertedBytes = Array("@{}[]()|\\/\"'-:>x+;#\n ".utf8)
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        var laidOutCount = 0
        var refusedCount = 0
        func check(_ text: String) {
            guard case .sequence(let diagram)? = try? MermaidDiagramReader.read(text, limits: .standard) else {
                refusedCount += 1
                return
            }
            guard let layout = try? SequenceLayoutEngine.layout(diagram, typography: typography) else {
                refusedCount += 1
                return
            }
            XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite && layout.size.width >= 0 && layout.size.height >= 0, text)
            _ = DiagramScene(layout: layout)
            laidOutCount += 1
        }
        for sample in Self.samples {
            XCTAssertFalse(sample.isEmpty)
            let bytes = Array(sample.utf8)
            for cut in stride(from: 1, to: bytes.count, by: max(1, bytes.count / 60)) { check(String(decoding: bytes[..<cut], as: UTF8.self)) }
            for _ in 0..<200 {
                var mutated = bytes
                let position = Int(generator.next() % UInt64(mutated.count))
                switch generator.next() % 3 {
                case 0: mutated.remove(at: position)
                case 1: mutated.insert(insertedBytes[Int(generator.next() % UInt64(insertedBytes.count))], at: position)
                default: mutated.insert(contentsOf: mutated[position...].prefix(30), at: position)
                }
                check(String(decoding: mutated, as: UTF8.self))
            }
        }
        XCTAssertGreaterThan(laidOutCount, 50)
        XCTAssertGreaterThan(refusedCount, 50)
    }

    func testTheSecondSampleIsReadAsWritten() throws {
        let diagram = try SequenceReading.sequence(Self.samples[1])
        XCTAssertEqual(diagram.participants.map(\.kind), [.database, .control, .actor])
        XCTAssertEqual(diagram.participants[0].label.lines, ["Two", "lines"])
        XCTAssertEqual(diagram.participants[1].label, DiagramLabel("Bee"))
        XCTAssertEqual(diagram.boxes.first?.wrapsTitle, true)
        XCTAssertNotNil(diagram.boxes.first?.color)
    }

    /// Deeply nested and long attribute texts are read quickly: the nesting is bounded, and a quoted value over many
    /// lines is retried in doubling batches of lines.
    func testHostileAttributesAreRefusedOrReadQuickly() {
        let start = Date()
        let deep = "sequenceDiagram\nparticipant A@{ type: " + String(repeating: "[", count: 5_000) + " }"
        XCTAssertNotNil(SequenceReading.readError(deep))
        let longQuoted = "sequenceDiagram\nparticipant A@{\ntype: database\nalias: \"" + String(repeating: "line\n", count: 5_000) + "\" }"
        XCTAssertNil(SequenceReading.readError(longQuoted))
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}

/// SplitMix64, so that a failure the mutations find is found again.
private struct SplitMixGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
