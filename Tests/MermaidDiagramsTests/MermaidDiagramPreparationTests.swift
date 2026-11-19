/**
 * File: MermaidDiagramPreparationTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: Any diagram text is prepared through one entry point: its scene as its type lays it out, its narrow scene
 *              where its type has one, what a screen reader says of it, or a typed failure of the right kind.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class MermaidDiagramPreparationTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))

    private func prepared(_ source: String) throws -> PreparedMermaidDiagram {
        try MermaidDiagramPreparation.prepare(source: source, typography: typography, now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone)
    }

    private func failure(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramPreparationFailure? {
        do {
            _ = try MermaidDiagramPreparation.prepare(source: source, typography: typography, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    func testEverySampleIsPreparedAsItsTypeAtItsLayoutsSize() throws {
        var preparedKinds: Set<MermaidDiagramKind> = []
        for sample in try DiagramSceneSamples.all() {
            guard let diagram = try? DiagramSceneSamples.read(sample),
                  let prepared = try? MermaidDiagramPreparation.prepare(diagram, typography: DiagramSceneSamples.typography, now: GanttChartCorpus.now,
                                                                        timeZone: GanttChartCorpus.timeZone) else { continue }
            XCTAssertEqual(prepared.kind, diagram.kind, sample.name)
            XCTAssertFalse(prepared.scene.items.isEmpty && !diagram.hasNothingToDraw && prepared.kind != .ganttChart, sample.name)
            XCTAssertFalse(prepared.accessibility.label.isEmpty, sample.name)
            if let narrow = prepared.narrowScene { XCTAssertLessThan(narrow.size.width, prepared.scene.size.width, sample.name) }
            preparedKinds.insert(prepared.kind)
        }
        XCTAssertEqual(preparedKinds, Set(MermaidDiagramKind.allCases))
    }

    func testTheSimpleChartsAreRefusedAsTheirTextsDeserve() {
        XCTAssertEqual(failure("packet"), .nothingToDraw)
        XCTAssertEqual(failure("radar-beta\ntitle Only a title"), .nothingToDraw)
        XCTAssertEqual(failure("treemap\n\"a\": 0"), .nothingToDraw)
        XCTAssertEqual(failure("treemap\n\"a\": 0")?.category, .notDrawnYet)
        XCTAssertEqual(failure("packet\n0-1: \"a\"\n3: \"b\""), .reading(.invalidSyntax(line: 3, problem: .packet(.notContiguous(firstBit: 3, lastBit: 3, expectedFirstBit: 2)))))
        XCTAssertEqual(failure("packet\n0-1: \"a\"\n3: \"b\"")?.category, .unreadable)
        XCTAssertEqual(failure("radar-beta\naxis a\ncurve c{ b: 1 }")?.category, .unreadable)
        XCTAssertEqual(failure("packet\n+1000000000: \"a\"")?.category, .beyondLimits)
        XCTAssertEqual(failure("---\nconfig:\n  packet:\n    bitsPerRow: 4096\n    bitWidth: 400\n---\npacket\n+4096: \"a\""), .tooLargeToDraw(maximumSideLength: 20_000))
        XCTAssertNil(failure("info"))
    }

    func testAnInfoDiagramWritesItsVersionAndItsSVGKeepsPelesNames() throws {
        let prepared = try MermaidDiagramPreparation.prepare(source: "info\ntitle Hello\naccDescr: Described", typography: typography)
        XCTAssertEqual(prepared.kind, .info)
        XCTAssertEqual(prepared.accessibility.label, "Hello")
        XCTAssertEqual(prepared.accessibility.value, "Described")
        XCTAssertEqual(try MermaidDiagramPreparation.prepare(source: "info", typography: typography).accessibility.label, "Info diagram")
        XCTAssertEqual(try MermaidDiagramPreparation.prepare(source: "info", typography: typography).accessibility.value, MermaidDiagramsVersion.text)
        let svg = prepared.svgDocument()
        XCTAssertTrue(svg.contains("class=\"pele pele-info\""))
        XCTAssertTrue(svg.contains("class=\"pele-version\""))
        for (source, kind) in [("packet\n+8: \"a\"", "packet"), ("radar-beta\naxis a\ncurve c{1}", "radar"), ("treemap\n\"a\": 1", "treemap")] {
            XCTAssertTrue(try MermaidDiagramPreparation.prepare(source: source, typography: typography).svgDocument().contains("class=\"pele pele-\(kind)\""), kind)
        }
    }

    func testAClassDefOfATreemapThatSetsWhatIsNotDrawnIsCounted() throws {
        let prepared = try MermaidDiagramPreparation.prepare(source: "treemap\n\"a\": 1:::c1\nclassDef c1 opacity:0.5,fill:red", typography: typography)
        XCTAssertEqual(prepared.unappliedStatementCount, 1)
    }

    func testFailuresSayWhyAndOfWhatKind() throws {
        XCTAssertEqual(failure("flowchart LR\n  A --> B[unclosed"), .reading(.invalidSyntax(line: 2, problem: .unclosedShape(closingText: "]"))))
        XCTAssertEqual(failure("flowchart LR\n  A --> B[unclosed")?.category, .unreadable)
        XCTAssertEqual(failure("%% only a comment"), .reading(.noDiagram))
        XCTAssertEqual(failure("zenuml\n  Alice->Bob: Hi"), .reading(.unsupportedDiagramType(keyword: "zenuml")))
        XCTAssertEqual(failure("zenuml")?.category, .typeNotDrawn)
        XCTAssertEqual(failure("flowchart LR"), .nothingToDraw)
        XCTAssertEqual(failure("flowchart LR\n  A --> B", limits: MermaidDiagramLimits(maximumSourceBytes: 10, maximumNodeCount: 10, maximumEdgeCount: 10,
                                                                                       maximumLayoutPointCount: 10))?.category, .beyondLimits)
        let small = MermaidDiagramLimits(maximumSourceBytes: 50_000, maximumNodeCount: 5_000, maximumEdgeCount: 5_000, maximumLayoutPointCount: 50_000,
                                         maximumDrawingSideLength: 40)
        XCTAssertEqual(failure("flowchart LR\n  A --> B --> C", limits: small), .tooLargeToDraw(maximumSideLength: 40))
        XCTAssertEqual(failure("sankey\na,b,1\nb,a,1"), .sankeyLayout(.circularLinks))
        XCTAssertEqual(failure("sankey\na,b,1\nb,a,1")?.category, .refusedContent)
        XCTAssertEqual(failure("xychart\n  x-axis [a, b]"), .xyChartLayout(.noSeries))
        XCTAssertNil(failure("gantt\n  task : a1, 2014-01-01, 3d\n  click a1 href \"https://example.com\""), "A click is accepted")
        XCTAssertEqual(failure("gantt\n  dateFormat YYYY-MM-DD\n  task : a1, 2014 foo, 3d")?.category, .refusedContent, "A date neither the format nor JavaScript reads")
    }

    func testAScreenReaderHearsWhatTheReadingViewSays() throws {
        XCTAssertEqual(try prepared("flowchart TD\nX --> one\nsubgraph one [The group]\nA --> B\nend").accessibility.summary, ["X", "A", "B", "The group"])
        XCTAssertEqual(try prepared("flowchart TD\nA --> B").accessibility.label, "Flowchart")
        let pie = try prepared("pie showData title Pets\n \"Dogs\" : 386\n \"Cats\" : 85\n \"Tiny\" : 1").accessibility
        XCTAssertEqual(pie.label, "Pets")
        XCTAssertEqual(pie.value, "Dogs [386] 82%, Cats [85] 18%, Tiny [1]")
        XCTAssertEqual(try prepared("timeline\n  2002 : LinkedIn\n  2004 : Facebook : Google").accessibility.value, "2002: LinkedIn; 2004: Facebook, Google")
        XCTAssertEqual(try prepared("gitGraph\n commit id:\"init\"\n branch develop\n commit tag:\"v1\"\n checkout main\n merge develop").accessibility.value,
                       "main: init; develop: v1")
        let quadrants = "quadrantChart\n  quadrant-1 Plan\n  quadrant-3 Delegate\n  Campaign A: [0.3, 0.6]\n  Off the chart: [0x5, 1]\n  Corner: [1, 0]"
        XCTAssertEqual(try prepared(quadrants).accessibility.summary, ["Plan", "Delegate", "Campaign A (0.3, 0.6)", "Corner (1, 0)"])
        let sankey = try prepared("---\ntitle: Energy\n---\nsankey\nCoal,Solid,75.571\nSolid,Industry,46\nSolid,Waste,none").accessibility
        XCTAssertEqual(sankey.label, "Energy")
        XCTAssertEqual(sankey.summary, ["Coal to Solid: 75.57", "Solid to Industry: 46", "Solid to Waste"])
        XCTAssertEqual(try prepared("sequenceDiagram\naccTitle: Named\ntitle Shown\nAlice->>Bob: Hello<br>there\nBob-->>Alice:").accessibility.value,
                       "Alice, Bob. Alice to Bob: Hello there. Bob to Alice")
        XCTAssertEqual(try prepared("---\ntitle: Front title\n---\nsequenceDiagram\naccDescr: How it goes\nA->>B: Hi").accessibility.value, "How it goes")
        XCTAssertEqual(try prepared("journey\n  title My working day\n  section Go to work\n    Make tea: 5: Me\n    Do work: 1: Me, Cat\n    Rest: x")
            .accessibility.summary, ["Make tea: 5 (Me)", "Do work: 1 (Me, Cat)", "Rest"])
        let sales = "xychart\n  title \"Sales\"\n  x-axis [jan, feb, mar]\n  bar \"Revenue\" [5000, 6000.5]\n  line [1, 2, 3]"
        XCTAssertEqual(try prepared(sales).accessibility.summary,
                       ["Revenue: jan 5000, feb 6000.5", "Line: jan 1, feb 2, mar 3"])
        XCTAssertEqual(try prepared("xychart\n  bar [3, 4]").accessibility.summary, ["Bars: 3, 4"])
        XCTAssertEqual(try prepared("journey\n  a: 9").accessibility.summary, ["a: 5"], "The level the face shows")
        let composite = "stateDiagram-v2\n  [*] --> Idle\n  Idle --> Active\n  state Active {\n    Loading --> Ready\n  }"
        XCTAssertEqual(try prepared(composite).accessibility.summary, ["Active", "Idle", "Loading", "Ready"],
                       "A composite state is named by its box's title, before the states drawn as boxes")
    }

    func testAWideDiagramIsLaidOutAgainForANarrowColumnAndShownWhereTheColumnNeedsIt() throws {
        let flowchart = try prepared(FlowchartCorpus.fourteenShapesInARow)
        let narrow = try XCTUnwrap(flowchart.narrowScene)
        XCTAssertLessThan(narrow.size.width, 360, "It fits an iPhone's column without being scaled down.")
        XCTAssertTrue(flowchart.showsNarrowScene(inColumnWidth: 700))
        XCTAssertFalse(flowchart.showsNarrowScene(inColumnWidth: 0), "A column not measured yet")
        XCTAssertFalse(flowchart.showsNarrowScene(inColumnWidth: flowchart.scene.size.width + 1), "It fits")
        XCTAssertEqual(flowchart.scene(inColumnWidth: 350).size, narrow.size)
        XCTAssertNil(try prepared("flowchart LR\n  A --> B").narrowScene, "No wider than the narrowest column")
        XCTAssertNil(try MermaidDiagramPreparation.prepare(source: FlowchartCorpus.fourteenShapesInARow, typography: typography,
                                                           narrowestColumnWidth: nil).narrowScene, "No narrow layout asked for")
        for source in ["gitGraph\n commit\n commit\n commit\n commit\n commit\n commit\n commit\n commit", TimelineCorpus.generated(periodCount: 8),
                       "stateDiagram-v2\n direction LR\n [*] --> A\n A --> B\n B --> C\n C --> D\n D --> E\n E --> [*]"] {
            let diagram = try prepared(source)
            XCTAssertLessThan(try XCTUnwrap(diagram.narrowScene, source).size.width, diagram.scene.size.width, source)
        }
        XCTAssertNil(try prepared(PieChartCorpus.pie(sliceCount: 8)).narrowScene, "A pie chart has no narrow layout")
        let map = try prepared(try WardleyMapCorpus.documentationExamples()[0])
        XCTAssertLessThanOrEqual(try XCTUnwrap(map.narrowScene, "A Wardley map is drawn tight to fit, as Pele's fitWidth draws it").size.width,
                                 PreparedMermaidDiagram.standardNarrowestColumnWidth + 120)
        XCTAssertLessThan(try XCTUnwrap(map.narrowScene).size.width, map.scene.size.width)
    }

    func testADiagramRefusedAsTooLargeIsNotLaidOutASecondTimeForANarrowColumn() {
        let limits = MermaidDiagramLimits(maximumSourceBytes: 50_000, maximumNodeCount: 5_000, maximumEdgeCount: 5_000, maximumLayoutPointCount: 50_000,
                                          maximumDrawingSideLength: 400)
        let context = MermaidDiagramPreparationContext(typography: typography, limits: limits, narrowestColumnWidth: 280, now: GanttChartCorpus.now,
                                                       timeZone: GanttChartCorpus.timeZone)
        let narrowPage = DiagramScene(size: CGSize(width: 200, height: 300), font: typography.font, items: [])
        var layoutCount = 0
        let layOut = { (turned: String) -> String in
            layoutCount += 1
            return turned
        }
        XCTAssertNil(context.narrowScene(of: "turned", regularSize: CGSize(width: 500, height: 100), laidOut: layOut) { _ in narrowPage },
                     "The regular scene is beyond the limit, so the diagram is refused whatever its narrow scene")
        XCTAssertEqual(layoutCount, 0)
        XCTAssertEqual(context.narrowScene(of: "turned", regularSize: CGSize(width: 390, height: 100), laidOut: layOut) { _ in narrowPage }?.size,
                       narrowPage.size)
        XCTAssertEqual(layoutCount, 1)
    }

    func testAPreparedDiagramWritesItsSVGWithItsTitleAndDescription() throws {
        let document = try prepared("pie\n  accTitle: Pets & owners\n  accDescr: Who adopts what\n  \"Dogs\" : 3\n  \"Cats\" : 1").svgDocument()
        XCTAssertTrue(document.contains("<title id=\"pele-title\">Pets &amp; owners</title><desc id=\"pele-desc\">Who adopts what</desc>"))
        XCTAssertTrue(document.contains("class=\"pele pele-pie\""))
        XCTAssertNotNil(DiagramSVGDocumentReading.read(document))
    }
}
