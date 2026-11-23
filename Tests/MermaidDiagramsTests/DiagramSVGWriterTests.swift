/**
 * File: DiagramSVGWriterTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Every sample's scene written as SVG is well-formed XML of its size and view box with a path per shape and
 *              a text per text, in either color mode; hostile text is escaped; numbers are compact; text beyond ASCII
 *              and gradients are written whole.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class DiagramSVGWriterTests: XCTestCase {
    func testEverySampleIsWrittenAsWellFormedSVGWithAnElementPerItem() throws {
        var writtenCount = 0
        for sample in try DiagramSceneSamples.all() {
            guard let prepared = try? MermaidDiagramPreparation.prepare(source: sample.source, typography: DiagramSceneSamples.typography,
                                                                        now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone) else { continue }
            let scene = prepared.scene
            for colors in [DiagramSVGColors.peleVariables, .palette(DiagramScenePaletteSamples.dark)] {
                let document = DiagramSVGWriter(colors: colors).document(of: scene, diagramType: prepared.kind.peleName)
                let reading = try XCTUnwrap(DiagramSVGDocumentReading.read(document), sample.name)
                let root = try XCTUnwrap(reading.elements.first, sample.name)
                XCTAssertEqual(root.name, "svg")
                XCTAssertEqual(root.attributes["viewBox"],
                               "0 0 \(DiagramSVGSyntax.number(scene.size.width)) \(DiagramSVGSyntax.number(scene.size.height))", sample.name)
                XCTAssertEqual(root.attributes["width"], DiagramSVGSyntax.number(scene.size.width), sample.name)
                XCTAssertEqual(root.attributes["class"], "pele pele-\(prepared.kind.peleName)", sample.name)
                XCTAssertEqual(reading.elements(named: "path").count, scene.shapes.count, sample.name)
                let texts = reading.elements(named: "text")
                // A text with an outline is written twice: its outline first, then the text.
                XCTAssertEqual(texts.map(\.text), scene.texts.flatMap { text in
                    Array(repeating: text.block.lines.joined(), count: text.outline == nil ? 1 : 2)
                }, sample.name)
                XCTAssertEqual(texts.filter { text in text.attributes["xml:space"] != "preserve" }.count, 0,
                               "\(sample.name): every text keeps its spaces, of one line as of several")
                XCTAssertFalse(document.contains("<script") || document.contains("href") || document.contains("url(h"), sample.name)
            }
            writtenCount += 1
        }
        XCTAssertGreaterThanOrEqual(writtenCount, 320)
    }

    func testHostileLabelsAreEscapedAndTheDocumentStaysWellFormed() throws {
        let source = """
            flowchart LR
                A["#lt;script#gt;alert(#quot;x#quot;)#lt;/script#gt; & 'it'"] --> B["]]#gt; #lt;!-- --#gt;"]
            """
        let prepared = try MermaidDiagramPreparation.prepare(source: source, typography: DiagramSceneSamples.typography)
        let document = DiagramSVGWriter().document(of: prepared.scene, diagramType: "flowchart", title: "A <title> & \"more\"",
                                                   description: "</desc><script>")
        XCTAssertFalse(document.contains("<script"))
        XCTAssertTrue(document.contains("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"))
        XCTAssertTrue(document.contains("&amp; &#39;it&#39;"))
        let reading = try XCTUnwrap(DiagramSVGDocumentReading.read(document))
        XCTAssertEqual(reading.elements(named: "text").map(\.text), ["<script>alert(\"x\")</script>& 'it'", "]]> <!-- -->"],
                       "Read back as written, the first label wrapped on two lines")
        XCTAssertEqual(reading.elements(named: "title").count, 1)
        XCTAssertEqual(DiagramSVGSyntax.escaped("a\u{0}b\u{1B}c\u{FFFE}d\te"), "abcd\te")
    }

    func testNumbersAreWrittenToTwoDecimalsWithoutTrailingZeros() {
        XCTAssertEqual([0, 12, 12.5, 12.25, 12.05, -0.25, -3, 0.004, 1e13, .infinity].map { value in DiagramSVGSyntax.number(value) },
                       ["0", "12", "12.5", "12.25", "12.05", "-0.25", "-3", "0", "0", "0"])
    }

    func testPeleVariablesNameEachRoleAndAPaletteWritesItsColors() throws {
        let sankey = try MermaidDiagramPreparation.prepare(source: try DiagramSceneSamples.sankeyEnergy(), typography: DiagramSceneSamples.typography)
        let variables = DiagramSVGWriter().document(of: sankey.scene, diagramType: "sankey")
        XCTAssertTrue(variables.contains("--_bg:var(--pele-bg,#fff)"))
        XCTAssertTrue(variables.contains("stop-color=\"var(--pele-series-1,#4c78a8)\""))
        XCTAssertTrue(variables.contains("fill=\"url(#pele-gradient-1)\" fill-opacity=\"0.4\""))
        XCTAssertTrue(variables.contains("fill=\"var(--_m)\""), "the values")
        let written = DiagramSVGWriter(colors: .palette(DiagramScenePaletteSamples.light), identifierPrefix: "note-7")
            .document(of: sankey.scene, diagramType: "sankey")
        XCTAssertFalse(written.contains("var("))
        XCTAssertTrue(written.contains("stop-color=\"#4c78a8\""))
        XCTAssertTrue(written.contains("url(#note-7-gradient-1)"))
        XCTAssertEqual(DiagramSVGWriter(identifierPrefix: "x\" onload=\"").identifierPrefix, "pele")
    }

    func testAnIdentifierPrefixSetAfterTheWriterIsMadeIsCheckedAsOneGivenToIt() throws {
        let sankey = try MermaidDiagramPreparation.prepare(source: try DiagramSceneSamples.sankeyEnergy(), typography: DiagramSceneSamples.typography)
        var writer = DiagramSVGWriter()
        writer.identifierPrefix = "x\"/><script>alert(1)</script><g a=\""
        XCTAssertEqual(writer.identifierPrefix, "pele")
        let document = writer.document(of: sankey.scene, diagramType: "sankey", title: "Energy")
        XCTAssertFalse(document.contains("<script"))
        XCTAssertNotNil(DiagramSVGDocumentReading.read(document), "Well-formed XML")
        writer.identifierPrefix = "note-8"
        XCTAssertTrue(writer.document(of: sankey.scene, diagramType: "sankey", title: "Energy").contains("aria-labelledby=\"note-8-title\""))
    }

    func testMixturesTurnedTextAndDashesAreWrittenAsSVGSays() throws {
        let highlighted = try XCTUnwrap(DiagramSceneSamples.styled.first { name, _ in name == "sequence highlighted" }?.1)
        let sequence = try MermaidDiagramPreparation.prepare(source: highlighted,
                                                             typography: DiagramSceneSamples.typography)
        let document = DiagramSVGWriter().document(of: sequence.scene, diagramType: "sequence")
        XCTAssertTrue(document.contains("color-mix(in srgb,var(--_bg),var(--_fg) 64.73%)"), "the blocks' muted text")
        XCTAssertTrue(document.contains("stroke-dasharray=\"4 4\""))
        let chart = try MermaidDiagramPreparation.prepare(source: try XCTUnwrap(XYChartCorpus.documentationExamples().first),
                                                          typography: DiagramSceneSamples.typography)
        let turned = DiagramSVGWriter().document(of: chart.scene, diagramType: "xychart")
        XCTAssertTrue(turned.contains("transform=\"rotate(-90 "))
    }

    func testTextBeyondASCIIIsWrittenWholeAndReadBackAsItWasGiven() throws {
        let source = """
            flowchart LR
                A["Café ﬁ 日本語 🧭"] --> B["e\u{301} — naïve"]
            """
        let prepared = try MermaidDiagramPreparation.prepare(source: source, typography: DiagramSceneSamples.typography)
        for colors in [DiagramSVGColors.peleVariables, .palette(DiagramScenePaletteSamples.light)] {
            let document = DiagramSVGWriter(colors: colors, paintsBackground: true)
                .document(of: prepared.scene, diagramType: "flowchart", title: "Überblick 🧭", description: "naïve\u{FFFE} résumé")
            let reading = try XCTUnwrap(DiagramSVGDocumentReading.read(document))
            XCTAssertTrue(document.contains("<title id=\"pele-title\">Überblick 🧭</title><desc id=\"pele-desc\">naïve résumé</desc>"),
                          "U+FFFE left out")
            XCTAssertEqual(reading.elements(named: "text").map(\.text).joined(separator: " "), "Café ﬁ 日本語 🧭 e\u{301} — naïve")
            XCTAssertEqual(reading.elements(named: "rect").count, 1, "the background")
        }
    }

    func testGradientsAreDefinedBeforeTheBodyAndNumberedInTheOrderTheyAreUsed() throws {
        let sankey = try MermaidDiagramPreparation.prepare(source: try DiagramSceneSamples.sankeyEnergy(), typography: DiagramSceneSamples.typography)
        let document = DiagramSVGWriter(colors: .palette(DiagramScenePaletteSamples.light), identifierPrefix: "note-9", paintsBackground: true)
            .document(of: sankey.scene, diagramType: "sankey", title: "Energy")
        let definitions = try XCTUnwrap(document.range(of: "<defs>"))
        let title = try XCTUnwrap(document.range(of: "</title>"))
        let background = try XCTUnwrap(document.range(of: "<rect "))
        XCTAssertEqual(title.upperBound, definitions.lowerBound, "the definitions come right after the title")
        XCTAssertLessThan(definitions.lowerBound, background.lowerBound, "and before the background and the body")
        let gradientCount = document.components(separatedBy: "<linearGradient ").count - 1
        XCTAssertGreaterThan(gradientCount, 1)
        for index in 1...gradientCount {
            XCTAssertTrue(document.contains("<linearGradient id=\"note-9-gradient-\(index)\""), "gradient \(index) defined")
            XCTAssertTrue(document.contains("fill=\"url(#note-9-gradient-\(index))\""), "gradient \(index) used")
        }
        XCTAssertNotNil(DiagramSVGDocumentReading.read(document), "Well-formed XML")
    }
}
