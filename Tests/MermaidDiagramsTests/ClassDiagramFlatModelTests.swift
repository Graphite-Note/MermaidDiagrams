/**
 * File: ClassDiagramFlatModelTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The class diagram's flat model: labels, relation texts and notes the decoder reads as written kept as
 *              ranges and the others as labels, members and annotations written for classes out of their order put in
 *              one run a class, and its layout's texts measured from those ranges and from the shown bytes the blocks
 *              0.7.0 measured.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class ClassDiagramFlatModelTests: XCTestCase {
    func testTextsReadAsWrittenAreRangesAndTheOthersLabels() throws {
        let diagram = try ClassDiagramReading.classDiagram("""
        classDiagram
          class A["Plain label"]
          class B["**bold**"]
          A --> B : uses
          B --> A : two<br>lines
          note for A "a note"
          note "*marked*"
        """)
        let model = diagram.model
        XCTAssertEqual(model.classes.map(\.label.isSourceRange), [true, false])
        XCTAssertEqual(model.relations.map(\.label.isSourceRange), [true, false])
        XCTAssertEqual(model.notes.map(\.text.isSourceRange), [true, false])
        XCTAssertEqual(diagram.classes.map(\.label.lines), [["Plain label"], ["**bold**"]])
        XCTAssertEqual(diagram.relations.map { relation in relation.label?.lines ?? [] }, [["uses"], ["two", "lines"]])
    }

    /// Members and annotations written for classes out of their order, interleaved, attributes among methods: each class's
    /// attributes then methods in the order written, as the reference reader keeps them.
    func testMembersWrittenOutOfOrderAreEachClassesInTheOrderWritten() throws {
        var lines = ["classDiagram"]
        for index in 0..<30 { lines.append("  C\(index) <|-- C\((index + 1) % 30)") }
        for round in 0..<3 {
            for index in stride(from: 29, through: 0, by: -4) {
                lines.append("  C\(index) : +method\(round)(int x) bool")
                lines.append("  C\(index) : -field\(round) int")
                lines.append("  <<interface\(round)>> C\(index)")
            }
            for index in stride(from: 2, to: 30, by: 9) { lines.append("  class C\(index) {\n    +inner\(round)() void\n    +attribute\(round)\n  }") }
        }
        let source = lines.joined(separator: "\n")
        XCTAssertEqual(ClassReadingEquivalenceTests.assertReadAlike([source]), 1)
        let diagram = try ClassDiagramReading.classDiagram(source)
        XCTAssertEqual(diagram.class(at: 29).methods.map(\.text), ["+method0(int x) : bool", "+inner0() : void", "+method1(int x) : bool", "+inner1() : void",
                                                                    "+method2(int x) : bool", "+inner2() : void"])
        XCTAssertEqual(diagram.class(at: 29).attributes.map(\.text), ["-field0 int", "+attribute0", "-field1 int", "+attribute1", "-field2 int", "+attribute2"])
        XCTAssertEqual(diagram.class(at: 29).annotations, ["interface0", "interface1", "interface2"])
    }

    /// Every corpus class diagram and random ones laid out from their records, regular and at the narrow widths, are laid
    /// out to the bit as the same diagram made from its façade's classes, relations and notes (every text a label then).
    func testTextsMeasuredFromRangesAndShownBytesAreTheBlocksOfTheirLabels() throws {
        let typography = DiagramSceneSamples.typography
        var sources = try OutputDigest.corpora().flatMap(\.sources)
        var generator = ClassRandomTexts(seed: 53)
        sources += (0..<400).map { _ in generator.text(statementCount: 20) }
        var compared = 0
        for source in sources {
            guard case .classDiagram(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            var labelled = ClassDiagram(direction: diagram.direction, classes: diagram.classes, relations: diagram.relations, notes: diagram.notes,
                                        namespaces: diagram.namespaces, title: diagram.title, accessibilityTitle: diagram.accessibilityTitle,
                                        accessibilityDescription: diagram.accessibilityDescription, unappliedStatementCount: diagram.unappliedStatementCount)
            labelled.hierarchicalNamespaces = diagram.hierarchicalNamespaces
            labelled.hidesEmptyMemberBoxes = diagram.hidesEmptyMemberBoxes
            XCTAssertEqual(labelled, diagram)
            for width in [nil] + OutputDigest.narrowColumnWidths.map(Optional.some) {
                let fromRecords = ClassDiagramLayoutBits { try ClassDiagramLayoutEngine.layout(diagram, typography: typography, limits: .standard, availableWidth: width) }
                let fromLabels = ClassDiagramLayoutBits { try ClassDiagramLayoutEngine.layout(labelled, typography: typography, limits: .standard, availableWidth: width) }
                XCTAssertEqual(fromRecords, fromLabels, "\(width.map { "\($0) points wide" } ?? "regular"):\n\(source.prefix(400))")
            }
            compared += 1
        }
        XCTAssertGreaterThan(compared, 200)
    }
}
