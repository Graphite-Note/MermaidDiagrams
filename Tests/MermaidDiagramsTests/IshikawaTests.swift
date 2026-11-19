/**
 * File: IshikawaTests.swift
 * -------------------------
 * Layer: Tests
 * Description: An Ishikawa diagram is read as Mermaid reads it (Mermaid 12.1.0's ishikawa.spec.ts as Pele ports it, its
 *              lexer's blank lines, keyword and errors) and laid out with Pele's measurements, across and down.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Reads an Ishikawa diagram for a test, from its whole text, through `MermaidDiagramReader`.
enum IshikawaReading {
    struct NotAnIshikawaDiagram: Error {}

    static func diagram(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> IshikawaDiagram {
        guard case .ishikawa(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw NotAnIshikawaDiagram() }
        return diagram
    }

    /// Each node's text set in by its depth, for a comparison of the tree at a glance.
    static func outline(_ diagram: IshikawaDiagram) -> [String] {
        func depth(_ index: Int) -> Int { diagram.nodes[index].parentIndex.map { parent in depth(parent) + 1 } ?? 0 }
        return diagram.nodes.indices.map { index in String(repeating: "  ", count: depth(index)) + diagram.nodes[index].text }
    }
}

final class IshikawaParserTests: XCTestCase {
    private func outline(_ source: String) throws -> [String] {
        IshikawaReading.outline(try IshikawaReading.diagram(source))
    }

    func testTheMermaidSpec() throws {
        XCTAssertEqual(try outline("ishikawa-beta\n    Blurry Photo\n        Process\n            Out of focus\n        User\n            Shaky hands\n"),
                       ["Blurry Photo", "  Process", "    Out of focus", "  User", "    Shaky hands"])
        XCTAssertEqual(try outline("ishikawa-beta\nProblem\nCause A\n  Subcause A1\nCause B\n"), ["Problem", "  Cause A", "    Subcause A1", "  Cause B"])
        XCTAssertEqual(try outline("ishikawa-beta\n    Problem\nCause A\n  Subcause A1\nCause B\n"), ["Problem", "  Cause A", "    Subcause A1", "  Cause B"],
                       "The effect may be indented more than the causes")
    }

    func testTheKeywordInAnyCaseBlankLinesCommentsAndTheDocumentationExample() throws {
        XCTAssertEqual(try outline("Ishikawa\n  Effect\n    Cause"), ["Effect", "  Cause"])
        XCTAssertEqual(try outline("ISHIKAWA-BETA\n  Effect\n\n   \n    %% a comment\n    Cause  \r\n"), ["Effect", "  Cause"])
        XCTAssertEqual(try outline("ishikawa-beta Effect\n  Cause"), ["Effect", "  Cause"], "Text may follow the keyword on its line")
        XCTAssertEqual(try outline("ishikawa-beta\n  Effect\n      Deep\n    Shallow\n  Top"), ["Effect", "  Deep", "  Shallow", "  Top"],
                       "Every cause is at least a category, nested from the first cause's indentation")
        let documented = try IshikawaReading.diagram(try XCTUnwrap(IshikawaCorpus.documentationExamples().first))
        XCTAssertEqual(documented.nodes.first?.childIndices.map { index in documented.nodes[index].text }, ["Process", "User", "Equipment", "Environment"])
        XCTAssertEqual(documented.nodes.count, 19)
        XCTAssertEqual(try IshikawaReading.diagram("---\ntitle: Why\n---\nishikawa\n  Effect").title, "Why")
    }

    func testWhatTheGrammarRefusesIsATypedErrorWithItsLine() {
        func error(_ source: String) -> MermaidDiagramReadError? {
            do {
                _ = try IshikawaReading.diagram(source)
                return nil
            } catch {
                return error as? MermaidDiagramReadError
            }
        }
        XCTAssertEqual(error("ishikawa-beta"), .invalidSyntax(line: 1, problem: .expectedNode))
        XCTAssertEqual(error("ishikawa-beta\n  Effect\n  ishikawa again"), .invalidSyntax(line: 3, problem: .unexpectedText("ishikawa")),
                       "The keyword is read again wherever a token starts with it")
        XCTAssertNil(error("ishikawa\n%% only a comment"))
        XCTAssertTrue(try IshikawaReading.diagram("ishikawa\n%% only a comment").nodes.isEmpty)
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 2
        XCTAssertThrowsError(try IshikawaReading.diagram("ishikawa\n E\n  a\n  b", limits: limits)) { thrown in
            XCTAssertEqual(thrown as? MermaidDiagramReadError, .tooManyNodes(limit: 2))
        }
    }
}

final class IshikawaLayoutEngineTests: XCTestCase {
    private let measurers = DiagramTextMeasurerSet(regular: UniformWidthTextMeasurer(), bold: UniformWidthTextMeasurer(),
                                                   small: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21))

    private func layout(_ source: String, maximumWidth: CGFloat? = nil) throws -> IshikawaLayout {
        IshikawaLayoutEngine.layout(try IshikawaReading.diagram(source), measurers: measurers, font: UniformWidthLayout.font, maximumWidth: maximumWidth)
    }

    /// One category above the spine with one cause: the head, its bone, its row and its box, in Pele's numbers.
    func testAFishboneIsPlacedWithPelesMeasurements() throws {
        let layout = try layout("ishikawa\n  Effect\n    Category\n      Cause")
        let head = try XCTUnwrap(layout.head)
        // "Effect" is 48 wide: the head is 48 high (at least), 48 + 24 + 24 wide.
        XCTAssertEqual(head.frame.size, CGSize(width: 96, height: 48))
        let category = try XCTUnwrap(layout.categories.first)
        // The cause's row: 14 from the spine, 21 + 6 high, so its middle rises 27.5 and the bone 14 + 27 + 8 = 49.
        let spineY = head.frame.midY
        XCTAssertEqual(category.box.size, CGSize(width: 64 + 20, height: 24 + 10))
        XCTAssertEqual(category.box.maxY, spineY - 49)
        XCTAssertEqual(category.causes.map(\.text.center.y), [spineY - 27.5])
        XCTAssertEqual(category.arrow.tip, CGPoint(x: head.frame.minX - 34, y: spineY))
        XCTAssertEqual(category.arrow.direction.dx, 0.5 / 1.25.squareRoot(), accuracy: 0.0001)
        let cause = category.causes[0]
        // The cause's bone runs level from the category's bone 18 points toward the tail, and its text ends 5 before that.
        let boneAcrossAtRow = category.arrow.tip.x - 27.5 * 0.5
        XCTAssertEqual(cause.text.frame.maxX, boneAcrossAtRow - 18 - 5, accuracy: 0.0001)
        XCTAssertEqual(layout.spine?.start.x, category.arrow.tip.x - 28)
        XCTAssertEqual(layout.spineArrow?.tip, CGPoint(x: head.frame.minX, y: spineY))
    }

    func testCategoriesAlternateAboveAndBelowAndPairsMoveTowardTheTail() throws {
        let layout = try layout("ishikawa\n  E\n    A\n      a1\n    B\n    C\n    D")
        let spineY = try XCTUnwrap(layout.head).frame.midY
        XCTAssertEqual(layout.categories.map { category in category.box.midY < spineY }, [true, false, true, false])
        XCTAssertEqual(layout.categories[0].arrow.tip.x, layout.categories[1].arrow.tip.x)
        XCTAssertLessThan(layout.categories[2].arrow.tip.x, layout.categories[0].arrow.tip.x - 26)
        XCTAssertEqual(layout.categories[2].arrow.tip.x, layout.categories[3].arrow.tip.x)
        XCTAssertEqual(layout.categories[1].causes.count, 0)
        XCTAssertEqual(layout.categories[1].box.minY, spineY + 24 + 14, "A category without causes still carries its name clear of the head")
    }

    func testEveryCauseHasARowOfItsOwnSoNoTwoTextsMeet() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        for source in try IshikawaCorpus.documentationExamples() + [IshikawaCorpus.fishbone(categoryCount: 6, causesPerCategory: 5)] {
            let layout = IshikawaLayoutEngine.layout(try IshikawaReading.diagram(source), typography: typography)
            let frames = layout.categories.flatMap { category in category.causes.map(\.text.frame) + [category.box] } + [try XCTUnwrap(layout.head).frame]
            for (index, frame) in frames.enumerated() {
                for other in frames[(index + 1)...] { XCTAssertFalse(frame.insetBy(dx: 0.5, dy: 0.5).intersects(other), "\(frame) \(other)") }
                XCTAssertTrue(CGRect(origin: .zero, size: layout.size).contains(frame))
            }
        }
    }

    func testANarrowWidthTurnsTheDiagramToRunDown() throws {
        let source = "ishikawa\n  Blurry photo\n    Process\n      Out of focus\n    User\n      Shaky hands\n    Equipment\n      Dirty lens"
        let across = try layout(source)
        XCTAssertTrue(across.outlineEntries.isEmpty)
        XCTAssertEqual(try layout(source, maximumWidth: 700), across, "Pele turns it only under its 640-point breakpoint")
        let down = try layout(source, maximumWidth: 300)
        XCTAssertNil(down.head)
        XCTAssertLessThan(down.size.width, across.size.width)
        XCTAssertLessThanOrEqual(down.size.width, 300)
        XCTAssertEqual(down.outlineEntries.map(\.depth), [0, 1, 2, 1, 2, 1, 2])
        XCTAssertEqual(down.outlineEntries.map(\.isFramed), [true, true, false, true, false, true, false])
        XCTAssertEqual(down.outlineConnectors.count, 6)
        let first = down.outlineEntries[0].frame
        XCTAssertEqual(first, CGRect(x: 8, y: 8, width: 12 * 8 + 20, height: 24 + 12))
        XCTAssertEqual(down.outlineEntries[1].frame.minX, 8 + 20)
        XCTAssertEqual(down.outlineEntries[1].frame.minY, first.maxY + 12)
        XCTAssertEqual(down.outlineConnectors[0], DiagramPath(start: CGPoint(x: 18, y: first.maxY), segments: [
            .line(to: CGPoint(x: 18, y: down.outlineEntries[1].frame.midY)), .line(to: CGPoint(x: 28, y: down.outlineEntries[1].frame.midY)),
        ]))
    }

    func testTheSceneIsPaintedInPelesColorsAndOrder() throws {
        let scene = DiagramScene(layout: try layout("ishikawa\n  Effect\n    Category\n      Cause\n        Reason"))
        let parts = scene.items.map { item -> DiagramScenePart in
            switch item {
            case .shape(let shape): shape.part
            case .text(let text): text.part
            }
        }
        XCTAssertEqual(parts, [.ishikawaSpine, .marker, .ishikawaBones, .marker, .node, .label, .label, .label, .node, .label])
        XCTAssertEqual(scene.texts.map(\.paint), [.foreground, .foreground, .muted, .foreground], "A cause of a cause is muted")
        XCTAssertEqual(scene.texts.map(\.isBold), [false, false, false, true], "The effect is bold")
        XCTAssertEqual(scene.shapes.map(\.painting).first, .stroke(.line, DiagramStroke(lineWidth: 1)))
    }
}
