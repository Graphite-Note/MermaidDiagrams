/**
 * File: TreeViewLayoutEngineTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: A tree view is laid out with Pele's measurements: rows, guide lines with their elbow, icon room shared by
 *              siblings, descriptions beside the names, highlights, the tight layout for a narrow width, and its scene.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class TreeViewLayoutEngineTests: XCTestCase {
    private let measurers = DiagramTextMeasurerSet(regular: UniformWidthTextMeasurer(), bold: UniformWidthTextMeasurer(),
                                                   small: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21))

    private func layout(_ source: String, maximumWidth: CGFloat? = nil) throws -> TreeViewLayout {
        TreeViewLayoutEngine.layout(try TreeViewReading.tree(source), measurers: measurers, font: UniformWidthLayout.font, maximumWidth: maximumWidth)
    }

    func testRowsAndGuideLinesArePlacedWithPelesMeasurements() throws {
        let layout = try layout("treeView-beta\nsrc/\n    index.js\n    utils.ts\nREADME.md")
        XCTAssertEqual(layout.size, CGSize(width: 100, height: 128))
        XCTAssertEqual(layout.rows.map { row in row.nameLines[0].center }, [CGPoint(x: 20, y: 22), CGPoint(x: 60, y: 50), CGPoint(x: 60, y: 78),
                                                                           CGPoint(x: 44, y: 106)])
        XCTAssertEqual(layout.rows.map(\.isFolder), [true, false, false, false])
        let corner = CGPoint(x: 15, y: 78)
        XCTAssertEqual(layout.guides, [
            DiagramPath(start: CGPoint(x: 15, y: 34), segments: [
                .line(to: CGPoint(x: 15, y: 74)),
                .curve(to: CGPoint(x: 19, y: 78), control1: CGPoint(x: 15, y: 74 + 8.0 / 3), control2: CGPoint(x: 19 + 2 / 3 * (corner.x - 19), y: 78)),
                .line(to: CGPoint(x: 23, y: 78)),
            ]),
            DiagramPath(start: CGPoint(x: 15, y: 50), segments: [.line(to: CGPoint(x: 23, y: 50))]),
        ])
        XCTAssertEqual(layout.guideLineWidth, 1)
    }

    func testSiblingsLeaveRoomForAnIconWhenOneOfThemShowsOne() throws {
        let siblings = try layout("treeView-beta\na.txt icon(file)\nb.txt\nsrc/\n    c.txt")
        XCTAssertEqual(siblings.rows.map(\.glyph), [.file, nil, nil, nil])
        let nameStarts: [CGFloat] = [30, 30, 30, 28]
        XCTAssertEqual(siblings.rows.map { row in row.nameLines[0].frame.minX }, nameStarts, "Set in 16 and 6 for the icon; c.txt has no sibling with one")
        XCTAssertEqual(siblings.rows[0].glyphFrame, CGRect(x: 8, y: 14, width: 16, height: 16))
        let icons = try layout("---\nconfig:\n  treeView:\n    showIcons: true\n---\ntreeView-beta\nsrc/\n    a.txt icon(none)\n    b.txt")
        XCTAssertEqual(icons.rows.map(\.glyph), [.folder, nil, .file])
    }

    func testDescriptionsStandInAColumnRightOfTheLongestNameAndHighlightsReachTheRightEdge() throws {
        let layout = try layout("treeView-beta\nsrc/ :::highlight\n    index.js ## entry\nREADME.md ## the docs")
        // Names end at 84 (index.js set in 20) and 72; the descriptions start 16 later, inside the highlight's 4 more.
        let left = CGFloat(8 + 4)
        XCTAssertEqual(layout.rows[1].descriptionLines.map(\.frame.minX), [left + 84 + 16])
        XCTAssertEqual(layout.rows[2].descriptionLines.map(\.frame.minX), [left + 84 + 16])
        XCTAssertEqual(layout.size.width, (84 + 16 + 64 + 2 * left).rounded(.up))
        XCTAssertEqual(layout.rows[0].highlight, CGRect(x: left - 4, y: 9, width: layout.size.width - left + 4 - (left - 4), height: 26))
        XCTAssertNil(layout.rows[1].highlight)
    }

    func testATreeTooWideForItsWidthIsLaidOutTight() throws {
        let source = "treeView-beta\nsrc/\n    components/\n        a-very-long-component-name.swift ## what it does in a few words"
        let loose = try layout(source)
        let tight = try layout(source, maximumWidth: 200)
        XCTAssertLessThan(tight.size.width, loose.size.width)
        XCTAssertLessThanOrEqual(tight.size.width, 200 + 1)
        let deepest = try XCTUnwrap(tight.rows.last)
        XCTAssertGreaterThan(deepest.nameLines.count, 1, "The long name is broken over lines")
        XCTAssertEqual(deepest.descriptionLines.first?.frame.minX, deepest.nameLines.first?.frame.minX, "The description goes under the name")
        XCTAssertEqual(try layout(source, maximumWidth: 2_000), loose, "A tree that fits stays loose")
    }

    func testTheSceneIsPaintedInPelesColorsAndOrder() throws {
        let scene = DiagramScene(layout: try layout("---\ntitle: Files\n---\ntreeView-beta\nsrc/ :::highlight\n    a.txt icon(file) ## note"))
        let parts = scene.items.map { item -> DiagramScenePart in
            switch item {
            case .shape(let shape): shape.part
            case .text(let text): text.part
            }
        }
        XCTAssertEqual(parts, [.title, .treeGuides, .treeHighlight, .label, .icon, .label, .treeDescription])
        XCTAssertEqual(scene.shapes.map(\.painting), [.stroke(.border, DiagramStroke(lineWidth: 1)), .fill(DiagramPaint.accent.atOpacity(0.14)),
                                                      .stroke(.muted, DiagramStroke.rounded(lineWidth: 1))])
        XCTAssertEqual(scene.texts.map(\.isBold), [true, true, false, false])
        XCTAssertEqual(scene.texts.map(\.isItalic), [false, false, false, true])
        XCTAssertEqual(scene.texts.map(\.paint), [.foreground, .foreground, .foreground, .muted])
    }

    func testEveryDocumentationExampleIsDrawnWithItsRowsApart() throws {
        let examples = try TreeViewCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 13)
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        for source in examples + [TreeViewCorpus.tree(entryCount: 500)] {
            let tree = try TreeViewReading.tree(source)
            XCTAssertFalse(tree.entries.isEmpty, source)
            for maximumWidth in [nil, CGFloat(280)] {
                let layout = TreeViewLayoutEngine.layout(tree, typography: typography, maximumWidth: maximumWidth)
                XCTAssertEqual(layout.rows.count, tree.entries.count)
                let names = layout.rows.flatMap(\.nameLines).map(\.frame)
                for (index, frame) in names.enumerated() where index > 0 { XCTAssertGreaterThanOrEqual(frame.minY, names[index - 1].maxY - 0.001, source) }
                XCTAssertTrue(names.allSatisfy { frame in frame.maxX <= layout.size.width - 7.99 }, source)
            }
        }
    }
}
