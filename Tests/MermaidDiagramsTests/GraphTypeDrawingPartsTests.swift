/**
 * File: GraphTypeDrawingPartsTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The public state, class, entity relationship and requirement drawing parts Graphite paints, now made by
 *              the generic path code with the Core Graphics maker, are 0.7.0's frozen drawing parts to the bit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class GraphTypeDrawingPartsTests: XCTestCase {
    private let typography = DiagramSceneSamples.typography

    /// A path's elements as text: each element's kind and every point's bits.
    static func transcript(of path: CGPath) -> [String] {
        var lines: [String] = []
        path.applyWithBlock { element in
            let pointCount: Int
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: pointCount = 1
            case .addQuadCurveToPoint: pointCount = 2
            case .addCurveToPoint: pointCount = 3
            case .closeSubpath: pointCount = 0
            @unknown default: pointCount = 0
            }
            var line = "\(element.pointee.type.rawValue)"
            for index in 0..<pointCount {
                let point = element.pointee.points[index]
                line += " \(point.x.bitPattern),\(point.y.bitPattern)"
            }
            lines.append(line)
        }
        return lines
    }

    private func assertSamePaths(_ paths: [(String, CGPath, CGPath)], file: StaticString, line: UInt) {
        for (name, made, reference) in paths {
            XCTAssertEqual(Self.transcript(of: made), Self.transcript(of: reference), name, file: file, line: line)
        }
    }

    private func assertSameParts(_ layout: StateDiagramLayout, file: StaticString = #filePath, line: UInt = #line) {
        let made = StateDiagramDrawingParts(layout: layout)
        let reference = ReferenceStateDiagramDrawingParts(layout: layout)
        assertSamePaths([("composite title rules", made.compositeTitleRules, reference.compositeTitleRules),
                         ("region dividers", made.regionDividers, reference.regionDividers),
                         ("transition lines", made.transitionLines, reference.transitionLines),
                         ("note connectors", made.noteConnectors, reference.noteConnectors), ("arrows", made.arrows, reference.arrows),
                         ("transition text patches", made.transitionTextPatches, reference.transitionTextPatches),
                         ("state fills", made.stateFills, reference.stateFills), ("state outlines", made.stateOutlines, reference.stateOutlines),
                         ("end rings", made.endRings, reference.endRings), ("solid marks", made.solidMarks, reference.solidMarks),
                         ("note sheets", made.noteSheets, reference.noteSheets), ("note folds", made.noteFolds, reference.noteFolds)],
                        file: file, line: line)
        XCTAssertEqual(made.transitionTexts, reference.transitionTexts, file: file, line: line)
        XCTAssertEqual(made.stateTexts, reference.stateTexts, file: file, line: line)
        XCTAssertEqual(made.noteTexts, reference.noteTexts, file: file, line: line)
        XCTAssertEqual(made.title, reference.title, file: file, line: line)
    }

    private func assertSameParts(_ layout: ClassDiagramLayout, file: StaticString = #filePath, line: UInt = #line) {
        let made = ClassDiagramDrawingParts(layout: layout)
        let reference = ReferenceClassDiagramDrawingParts(layout: layout)
        assertSamePaths([("solid lines", made.solidLines, reference.solidLines), ("dashed lines", made.dashedLines, reference.dashedLines),
                         ("dotted lines", made.dottedLines, reference.dottedLines), ("filled marks", made.filledMarks, reference.filledMarks),
                         ("stroked marks", made.strokedMarks, reference.strokedMarks),
                         ("edge text patches", made.edgeTextPatches, reference.edgeTextPatches),
                         ("class fills", made.classFills, reference.classFills), ("note fills", made.noteFills, reference.noteFills),
                         ("outlines", made.outlines, reference.outlines), ("member underlines", made.memberUnderlines, reference.memberUnderlines)],
                        file: file, line: line)
        XCTAssertEqual(made.edgeTexts, reference.edgeTexts, file: file, line: line)
        XCTAssertEqual(made.cardinalities, reference.cardinalities, file: file, line: line)
        XCTAssertEqual(made.annotations, reference.annotations, file: file, line: line)
        XCTAssertEqual(made.names, reference.names, file: file, line: line)
        XCTAssertEqual(made.members, reference.members, file: file, line: line)
        XCTAssertEqual(made.noteTexts, reference.noteTexts, file: file, line: line)
        XCTAssertEqual(made.title, reference.title, file: file, line: line)
    }

    private func assertSameParts(_ layout: EntityRelationshipLayout, file: StaticString = #filePath, line: UInt = #line) {
        let made = EntityRelationshipDrawingParts(layout: layout)
        let reference = ReferenceEntityRelationshipDrawingParts(layout: layout)
        assertSamePaths([("identifying lines", made.identifyingLines, reference.identifyingLines),
                         ("non-identifying lines", made.nonIdentifyingLines, reference.nonIdentifyingLines),
                         ("mark fills", made.markFills, reference.markFills), ("mark outlines", made.markOutlines, reference.markOutlines),
                         ("label patches", made.labelPatches, reference.labelPatches), ("box fills", made.boxFills, reference.boxFills),
                         ("row stripes", made.rowStripes, reference.rowStripes), ("box outlines", made.boxOutlines, reference.boxOutlines)],
                        file: file, line: line)
        XCTAssertEqual(made.labels, reference.labels, file: file, line: line)
        XCTAssertEqual(made.entityTexts, reference.entityTexts, file: file, line: line)
        XCTAssertEqual(made.attributeDetails, reference.attributeDetails, file: file, line: line)
        XCTAssertEqual(made.title, reference.title, file: file, line: line)
    }

    private func assertSameParts(_ layout: RequirementLayout, file: StaticString = #filePath, line: UInt = #line) {
        let made = RequirementDrawingParts(layout: layout)
        let reference = ReferenceRequirementDrawingParts(layout: layout)
        assertSamePaths([("solid lines", made.solidLines, reference.solidLines), ("dashed lines", made.dashedLines, reference.dashedLines),
                         ("marks", made.marks, reference.marks), ("text patches", made.textPatches, reference.textPatches),
                         ("box fills", made.boxFills, reference.boxFills), ("box outlines", made.boxOutlines, reference.boxOutlines)],
                        file: file, line: line)
        XCTAssertEqual(made.texts, reference.texts, file: file, line: line)
        XCTAssertEqual(made.stereotypes, reference.stereotypes, file: file, line: line)
        XCTAssertEqual(made.names, reference.names, file: file, line: line)
        XCTAssertEqual(made.fieldNames, reference.fieldNames, file: file, line: line)
        XCTAssertEqual(made.fieldValues, reference.fieldValues, file: file, line: line)
        XCTAssertEqual(made.styledBoxes, reference.styledBoxes, file: file, line: line)
        XCTAssertEqual(made.title, reference.title, file: file, line: line)
        for box in made.styledBoxes {
            let fill = CGMutablePath()
            let outline = CGMutablePath()
            RequirementDrawingParts.addBox(box, fill: fill, outline: outline)
            let referenceFill = CGMutablePath()
            let referenceOutline = CGMutablePath()
            ReferenceRequirementDrawingParts.addBox(box, fill: referenceFill, outline: referenceOutline)
            assertSamePaths([("styled box fill", fill, referenceFill), ("styled box outline", outline, referenceOutline)], file: file, line: line)
        }
    }

    /// Compares the drawing parts of `source`, as laid out and narrow, when it is one of the types these tests cover;
    /// false otherwise.
    private func assertSameParts(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let diagram = try? MermaidDiagramReader.read(source, limits: .standard) else { return false }
        switch diagram {
        case .stateDiagram(let stateDiagram):
            guard let layout = try? StateDiagramLayoutEngine.layout(stateDiagram, typography: typography, limits: .standard) else { return false }
            assertSameParts(layout, file: file, line: line)
            if let narrow = try? StateDiagramLayoutEngine.layout(stateDiagram, typography: typography, limits: .standard, availableWidth: 280) {
                assertSameParts(narrow, file: file, line: line)
            }
        case .classDiagram(let classDiagram):
            guard let layout = try? ClassDiagramLayoutEngine.layout(classDiagram, typography: typography, limits: .standard) else { return false }
            assertSameParts(layout, file: file, line: line)
            if let narrow = try? ClassDiagramLayoutEngine.layout(classDiagram, typography: typography, limits: .standard, availableWidth: 280) {
                assertSameParts(narrow, file: file, line: line)
            }
        case .entityRelationship(let entityRelationship):
            guard let layout = try? EntityRelationshipLayoutEngine.layout(entityRelationship, typography: typography, limits: .standard) else { return false }
            assertSameParts(layout, file: file, line: line)
            if let turned = entityRelationship.turnedTopToBottom,
               let narrow = try? EntityRelationshipLayoutEngine.layout(turned, typography: typography, limits: .standard) {
                assertSameParts(narrow, file: file, line: line)
            }
        case .requirement(let requirement):
            guard let layout = try? RequirementLayoutEngine.layout(requirement, typography: typography, limits: .standard) else { return false }
            assertSameParts(layout, file: file, line: line)
            if let turned = requirement.turnedToRunDown, let narrow = try? RequirementLayoutEngine.layout(turned, typography: typography, limits: .standard) {
                assertSameParts(narrow, file: file, line: line)
            }
        default:
            return false
        }
        return true
    }

    func testDrawingPartsOfEveryCorpusAreTheFrozenOnes() throws {
        var sources = try OutputDigest.corpora().flatMap(\.sources)
        sources += try StateDiagramCorpus.documentationExamples() + ClassDiagramCorpus.documentationExamples()
        sources += try EntityRelationshipCorpus.documentationExamples() + RequirementCorpus.documentationExamples()
        var comparedCount = 0
        for source in sources where assertSameParts(source) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 100)
    }

    func testDrawingPartsOfRandomDiagramsAreTheFrozenOnes() {
        var stateTexts = StateRandomTexts(seed: 0xD2A_57A7)
        var classTexts = ClassRandomTexts(seed: 0xD2A_C1A5)
        var entityRelationshipTexts = EntityRelationshipRandomTexts(seed: 0xD2A_E2)
        var requirementTexts = RequirementRandomTexts(seed: 0xD2A_2E)
        var comparedCount = 0
        for index in 0..<800 {
            let statementCount = 2 + index % 30
            for source in [stateTexts.text(statementCount: statementCount), classTexts.text(statementCount: statementCount),
                           entityRelationshipTexts.text(statementCount: statementCount), requirementTexts.text(statementCount: statementCount)]
                where assertSameParts(source) {
                comparedCount += 1
            }
        }
        XCTAssertGreaterThan(comparedCount, 1_200)
    }
}
