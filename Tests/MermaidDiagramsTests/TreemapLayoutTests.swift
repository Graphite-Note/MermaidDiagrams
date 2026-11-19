/**
 * File: TreemapLayoutTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: Placing, laying out and painting treemaps with Pele's measurements: squarified areas, gaps and insets, headers, texts,
 *              classes, and the documentation examples.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class TreemapLayoutTests: XCTestCase {
    private let basic = "treemap-beta\n\"Category A\"\n    \"Item A1\": 10\n    \"Item A2\": 20\n\"Category B\"\n    \"Item B1\": 15\n    \"Item B2\": 25\n"
    private let insets = TreemapInsets(gap: 4, header: 28, shortHeader: 18, side: 6)

    private func leaf(_ name: String, _ value: Double) -> TreemapNode { TreemapNode(name: name, value: value, isSection: false, parentIndex: nil, className: nil) }

    private func place(_ nodes: [TreemapNode], _ width: Double, _ height: Double, _ insets: TreemapInsets) -> [TreemapBox] {
        let result = TreemapSquarifiedPlacement.place(nodes, width: width, height: height, insets: insets)
        return result.placed.map { index in result.boxes[index] }
    }

    private func overlap(_ a: TreemapBox, _ b: TreemapBox) -> Bool {
        a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
    }

    private func layout(_ source: String) throws -> TreemapLayout {
        TreemapLayoutEngine.layout(try SimpleChartReading.treemap(source), text: UniformWidthTextMeasurer(characterWidth: 8, fontSize: 16, lineHeight: 24),
                                   boldText: UniformWidthTextMeasurer(characterWidth: 9, fontSize: 16, lineHeight: 24), font: UniformWidthLayout.font)
    }

    private func name(_ layout: TreemapLayout, _ source: TreemapDiagram, _ text: String) -> TreemapLayoutBox? {
        layout.boxes.first { box in source.nodes[box.nodeIndex].name == text }
    }

    func testEachBoxGetsAnAreaInProportionToItsValue() {
        let nodes = [40, 30, 20, 8, 2].enumerated().map { index, value in leaf("n\(index)", Double(value)) }
        let boxes = place(nodes, 1000, 600, TreemapInsets(gap: 0, header: 28, shortHeader: 18, side: 6))
        XCTAssertEqual(boxes.count, 5)
        for box in boxes { XCTAssertEqual(box.width * box.height / 600_000, box.value / 100, accuracy: 0.01) }
        for a in boxes { for b in boxes where a.nodeIndex != b.nodeIndex { XCTAssertFalse(overlap(a, b)) } }
    }

    func testBoxesStayCloseToSquare() {
        let nodes = (0..<40).map { index in leaf("n\(index)", Double(1 + index % 7)) }
        let ratios = place(nodes, 800, 500, TreemapInsets(gap: 0, header: 28, shortHeader: 18, side: 6)).map { box in max(box.width / box.height, box.height / box.width) }
        XCTAssertLessThan(ratios.reduce(0, +) / Double(ratios.count), 1.6)
        XCTAssertLessThan(ratios.max() ?? 0, 4)
    }

    func testTheFrameIsFilledAndTheGapLeftBetweenSiblings() {
        let boxes = place([leaf("a", 1), leaf("b", 1)], 400, 200, TreemapInsets(gap: 10, header: 28, shortHeader: 18, side: 6)).sorted { $0.x < $1.x }
        XCTAssertEqual([boxes[0].x, boxes[0].y, boxes[0].height], [0, 0, 200])
        XCTAssertEqual(boxes[1].x + boxes[1].width, 400)
        XCTAssertEqual(boxes[1].x - (boxes[0].x + boxes[0].width), 10)
    }

    func testChildrenNestInsideTheirSectionUnderItsHeaderAndTakeTheSeriesOfTheTopLevelNode() {
        let nodes = [TreemapNode(name: "s", value: nil, isSection: true, parentIndex: nil, className: nil),
                     TreemapNode(name: "a", value: 3, isSection: false, parentIndex: 0, className: nil),
                     TreemapNode(name: "t", value: nil, isSection: true, parentIndex: 0, className: nil),
                     TreemapNode(name: "b", value: 1, isSection: false, parentIndex: 2, className: nil),
                     TreemapNode(name: "c", value: 1, isSection: false, parentIndex: 2, className: nil), leaf("d", 2)]
        let result = TreemapSquarifiedPlacement.place(nodes, width: 600, height: 400, insets: insets)
        XCTAssertEqual(result.placed.count, 6)
        XCTAssertEqual(result.boxes[0].value, 5)
        XCTAssertEqual(result.boxes[2].value, 2)
        for box in result.placed.map({ index in result.boxes[index] }) {
            guard let parent = box.parent.map({ index in result.boxes[index] }) else { continue }
            XCTAssertGreaterThanOrEqual(box.x, parent.x + insets.side)
            XCTAssertGreaterThanOrEqual(box.y, parent.y + insets.header)
            XCTAssertLessThanOrEqual(box.x + box.width, parent.x + parent.width - insets.side)
            XCTAssertLessThanOrEqual(box.y + box.height, parent.y + parent.height - insets.side)
        }
        XCTAssertEqual(result.placed.map { index in result.boxes[index].series }.sorted(), [0, 0, 0, 0, 0, 1])
    }

    func testASectionTooSmallForItsHeaderGivesItsWholeBoxToItsChildren() {
        let nodes = [TreemapNode(name: "s", value: nil, isSection: true, parentIndex: nil, className: nil), TreemapNode(name: "a", value: 2, isSection: false, parentIndex: 0, className: nil),
                     TreemapNode(name: "t", value: nil, isSection: true, parentIndex: 0, className: nil), TreemapNode(name: "b", value: 1, isSection: false, parentIndex: 2, className: nil),
                     TreemapNode(name: "c", value: 1, isSection: false, parentIndex: 2, className: nil)]
        let small = TreemapSquarifiedPlacement.place(nodes, width: 300, height: 30, insets: insets)
        XCTAssertFalse(small.boxes[0].isHeaded)
        for index in small.placed where index != 0 {
            let box = small.boxes[index]
            XCTAssertGreaterThan(box.width * box.height, 0)
            XCTAssertGreaterThanOrEqual(box.x, small.boxes[0].x)
            XCTAssertLessThanOrEqual(box.x + box.width, small.boxes[0].x + small.boxes[0].width)
        }
        XCTAssertTrue(TreemapSquarifiedPlacement.place(nodes, width: 300, height: 300, insets: insets).boxes[0].isHeaded)
    }

    func testAThinBoxKeepsItsGapAndAHopelessOneKeepsAnEmptyBox() {
        let thin = place([leaf("big", 397), leaf("thin", 3)], 400, 100, insets)
        XCTAssertEqual(thin.count, 2)
        XCTAssertGreaterThan(thin[1].width, 0)
        XCTAssertFalse(overlap(thin[0], thin[1]))
        let nodes = [leaf("big", 1e6), TreemapNode(name: "s", value: nil, isSection: true, parentIndex: nil, className: nil),
                     TreemapNode(name: "speck", value: 1, isSection: false, parentIndex: 1, className: nil)]
        let speck = TreemapSquarifiedPlacement.place(nodes, width: 100, height: 100, insets: insets)
        XCTAssertEqual(speck.placed.count, 3)
        for index in speck.placed.dropFirst() { XCTAssertEqual(speck.boxes[index].width * speck.boxes[index].height, 0) }
    }

    func testEveryBoxStaysInsideItsAreaWithAFiniteSize() {
        for box in place([leaf("big", 397), leaf("thin", 3)], 400, 100, TreemapInsets(gap: 40, header: 28, shortHeader: 18, side: 6)) { XCTAssertLessThanOrEqual(box.x + box.width, 400) }
        let huge = place([leaf("big", 1e20), leaf("small", 1)], 640, 400, insets)
        XCTAssertEqual(huge.count, 2)
        for box in huge { for number in [box.x, box.y, box.width, box.height] { XCTAssertTrue(number.isFinite && number >= 0) } }
    }

    func testWhatHasNoPositiveValueIsLeftOut() {
        let nodes = [leaf("a", 1), leaf("zero", 0), leaf("negative", -5), TreemapNode(name: "nan", value: nil, isSection: false, parentIndex: nil, className: nil),
                     TreemapNode(name: "empty", value: nil, isSection: true, parentIndex: nil, className: nil)]
        XCTAssertEqual(place(nodes, 100, 100, insets).map(\.nodeIndex), [0])
        XCTAssertTrue(place([], 100, 100, insets).isEmpty)
        XCTAssertTrue(place([leaf("huge", 1e308), leaf("also", 1e308)], 100, 100, insets).isEmpty, "A total that overflows places nothing")
    }

    func testTheBasicTreemapIs656By416WithTwoSectionsAndFourLeaves() throws {
        let diagram = try SimpleChartReading.treemap(basic)
        let chart = try layout(basic)
        XCTAssertEqual(chart.size, CGSize(width: 656, height: 416))
        XCTAssertEqual(chart.boxes.filter(\.isSection).count, 2)
        XCTAssertEqual(chart.boxes.filter { box in !box.isSection }.count, 4)
        let a = try XCTUnwrap(name(chart, diagram, "Category A")), b = try XCTUnwrap(name(chart, diagram, "Category B"))
        XCTAssertGreaterThan(b.frame.width * b.frame.height, a.frame.width * a.frame.height)
        XCTAssertEqual(a.seriesIndex, 0)
        XCTAssertEqual(b.seriesIndex, 1)
        XCTAssertEqual(try XCTUnwrap(name(chart, diagram, "Item A1")).seriesIndex, 0)
        XCTAssertEqual(a.frame.maxX + 4 <= b.frame.minX + 0.5 || b.frame.maxX + 4 <= a.frame.minX + 0.5, true, "Four points between top-level boxes")
        XCTAssertEqual(a.value?.lines, ["30"])
        XCTAssertEqual(try XCTUnwrap(name(chart, diagram, "Item B2")).value?.lines, ["25"])
    }

    func testLeavesAreSizedByValueAndStayInsideTheirSectionUnderItsHeader() throws {
        let diagram = try SimpleChartReading.treemap(basic)
        let chart = try layout(basic)
        let section = try XCTUnwrap(name(chart, diagram, "Category A"))
        for id in ["Item A1", "Item A2"] {
            let box = try XCTUnwrap(name(chart, diagram, id))
            XCTAssertGreaterThan(box.frame.minX, section.frame.minX)
            XCTAssertGreaterThanOrEqual(box.frame.minY, section.frame.minY + 28)
            XCTAssertLessThan(box.frame.maxX, section.frame.maxX)
            XCTAssertLessThan(box.frame.maxY, section.frame.maxY)
        }
        let b2 = try XCTUnwrap(name(chart, diagram, "Item B2")), b1 = try XCTUnwrap(name(chart, diagram, "Item B1"))
        XCTAssertGreaterThan(b2.frame.width * b2.frame.height, b1.frame.width * b1.frame.height)
    }

    func testHeadersHoldTheNameAtTheLeftAndTheTotalAtTheRight() throws {
        let diagram = try SimpleChartReading.treemap(basic)
        let chart = try layout(basic)
        let section = try XCTUnwrap(name(chart, diagram, "Category B"))
        let label = try XCTUnwrap(section.name), total = try XCTUnwrap(section.value)
        XCTAssertEqual(label.center.x - label.size.width / 2, section.frame.minX + 8, accuracy: 1e-9)
        XCTAssertEqual(total.center.x + total.size.width / 2, section.frame.maxX - 8, accuracy: 1e-9)
        XCTAssertEqual(label.center.y, section.frame.minY + 15, accuracy: 1e-9)
        XCTAssertEqual(label.fontSize, 14)
        XCTAssertEqual(total.fontSize, 12)
    }

    func testTextThatDoesNotFitShrinksIsCutOrIsLeftOut() throws {
        let source = "treemap\n\"A section with a very long name indeed\"\n  \"big\": 1000\n  \"A leaf with quite a long name\": 60\n  \"tiny\": 0.01\n\"other\": 3000"
        let diagram = try SimpleChartReading.treemap(source)
        let chart = try layout(source)
        let section = try XCTUnwrap(name(chart, diagram, "A section with a very long name indeed"))
        XCTAssertTrue(section.name?.lines[0].hasSuffix("\u{2026}") == true)
        let long = try XCTUnwrap(name(chart, diagram, "A leaf with quite a long name"))
        XCTAssertLessThan(long.name?.fontSize ?? 99, 16)
        XCTAssertNil(try XCTUnwrap(name(chart, diagram, "tiny")).name, "A box too small for its text is drawn without it")
    }

    func testAShortHeaderHasASmallerNameAndNoTotalAndALowOneNoHeaderAtAll() throws {
        let short = try layout("---\nconfig:\n  treemap:\n    nodeHeight: 4\n---\ntreemap\n\"Section\"\n  \"Leaf\": 1")
        let diagram = try SimpleChartReading.treemap("---\nconfig:\n  treemap:\n    nodeHeight: 4\n---\ntreemap\n\"Section\"\n  \"Leaf\": 1")
        let section = try XCTUnwrap(name(short, diagram, "Section"))
        XCTAssertEqual(section.name?.fontSize, 12)
        XCTAssertNil(section.value)
        XCTAssertEqual(try XCTUnwrap(name(short, diagram, "Leaf")).frame.minY - section.frame.minY, 18)
        let headerless = try layout("---\nconfig:\n  treemap:\n    nodeHeight: 3\n---\ntreemap\n\"Section\"\n  \"Leaf\": 1")
        XCTAssertFalse(headerless.boxes[0].hasHeader)
        XCTAssertNil(headerless.boxes[0].name)
        let scene = DiagramScene(layout: headerless)
        XCTAssertEqual(scene.shapes.map(\.part), [.leaf], "A section without a header draws no box")
    }

    func testSmallBoxesKeepTheirCornersWithinAQuarterOfTheirShorterSide() throws {
        let chart = try layout("treemap\n\"big\": 1000\n\"small\": 4")
        XCTAssertEqual(chart.boxes[0].cornerRadius, 4)
        XCTAssertEqual(chart.boxes[1].cornerRadius, min(4, min(chart.boxes[1].frame.width, chart.boxes[1].frame.height) / 4))
        XCTAssertLessThan(chart.boxes[1].cornerRadius, 4)
    }

    func testGapsAndInsetsShrinkAsTheAverageLeafDoes() throws {
        func smallestGap(_ diagram: TreemapDiagram, _ names: [String]) throws -> CGFloat {
            let chart = TreemapLayoutEngine.layout(diagram, typography: SimpleChartReading.typography)
            let boxes = chart.boxes.filter { box in names.contains(diagram.nodes[box.nodeIndex].name) }
            var least = CGFloat.infinity
            for a in boxes { for b in boxes where min(a.frame.width, a.frame.height, b.frame.width, b.frame.height) >= 8 {
                if a.frame.minY < b.frame.maxY, b.frame.minY < a.frame.maxY, b.frame.minX >= a.frame.maxX { least = min(least, b.frame.minX - a.frame.maxX) }
                if a.frame.minX < b.frame.maxX, b.frame.minX < a.frame.maxX, b.frame.minY >= a.frame.maxY { least = min(least, b.frame.minY - a.frame.maxY) }
            } }
            return least
        }
        var crowded = "treemap\n"
        for i in 0..<6 {
            crowded += "\"top \(i)\"\n"
            for j in 0..<8 {
                crowded += "  \"mid \(i).\(j)\"\n    \"inner \(i).\(j)\"\n"
                for k in 0..<8 { crowded += "      \"leaf \(i).\(j).\(k)\": \(1 + ((i * 64 + j * 8 + k) % 37) * ((i * 64 + j * 8 + k) % 37) * ((i * 64 + j * 8 + k) % 37))\n" }
            }
        }
        let diagram = try SimpleChartReading.treemap(crowded)
        let chart = TreemapLayoutEngine.layout(diagram, typography: SimpleChartReading.typography)
        let top = try XCTUnwrap(chart.boxes.first { diagram.nodes[$0.nodeIndex].name == "top 0" })
        let mids = chart.boxes.filter { diagram.nodes[$0.nodeIndex].name.hasPrefix("mid 0.") }
        XCTAssertEqual(mids.map(\.frame.minX).min().map { $0 - top.frame.minX }, 3, "A crowded treemap's inset is 3")
        XCTAssertEqual(try smallestGap(diagram, (0..<6).map { "top \($0)" }), 2)
        let roomy = "treemap-beta\n\"Budget\"\n    \"Operations\"\n        \"Salaries\": 700000\n        \"Equipment\": 200000\n        \"Supplies\": 100000\n    \"Marketing\"\n        \"Advertising\": 400000\n        \"Events\": 100000"
        let budget = try SimpleChartReading.treemap(roomy)
        let chart2 = TreemapLayoutEngine.layout(budget, typography: SimpleChartReading.typography)
        let budgetBox = try XCTUnwrap(chart2.boxes.first { budget.nodes[$0.nodeIndex].name == "Budget" })
        let operations = try XCTUnwrap(chart2.boxes.first { budget.nodes[$0.nodeIndex].name == "Operations" })
        XCTAssertEqual(operations.frame.minX - budgetBox.frame.minX, 6)
        XCTAssertEqual(operations.frame.minY - budgetBox.frame.minY, 28)
        XCTAssertEqual(try smallestGap(budget, ["Salaries", "Equipment", "Supplies"]), 4)
        XCTAssertEqual(try smallestGap(budget, ["Operations", "Marketing"]), 4)
        let custom = try SimpleChartReading.treemap("---\nconfig:\n  treemap:\n    padding: 1\n---\n" + roomy)
        let boxes = TreemapLayoutEngine.layout(custom, typography: SimpleChartReading.typography).boxes
        let first = try XCTUnwrap(boxes.first { custom.nodes[$0.nodeIndex].name == "Salaries" }), second = try XCTUnwrap(boxes.first { custom.nodes[$0.nodeIndex].name == "Equipment" })
        XCTAssertEqual(min(abs(second.frame.minX - first.frame.maxX), abs(second.frame.minY - first.frame.maxY)), 1)
    }

    func testOptionsSizeThePageAndTheValuesAreWrittenByTheFormat() throws {
        XCTAssertEqual(try layout("---\nconfig:\n  treemap:\n    nodeWidth: 30\n    nodeHeight: 20\n---\n" + basic).size, CGSize(width: 316, height: 216))
        XCTAssertEqual(try layout("---\nconfig:\n  treemap:\n    diagramPadding: 50\n---\n" + basic).size.width - 656, 84)
        let bare = try layout("---\nconfig:\n  treemap:\n    showValues: false\n---\n" + basic)
        XCTAssertTrue(bare.boxes.allSatisfy { box in box.value == nil })
        XCTAssertTrue(bare.boxes.contains { box in box.name != nil })
        let money = try layout("---\nconfig:\n  treemap:\n    valueFormat: '$0,0'\n---\ntreemap\n\"Budget\"\n  \"Salaries\": 700000\n  \"Equipment\": 200000")
        XCTAssertEqual(money.boxes.compactMap { box in box.value?.lines[0] }, ["$900,000", "$700,000", "$200,000"])
    }

    func testTheTitleIsAboveAndAWiderOneMovesTheTreemapOver() throws {
        let chart = try layout("---\ntitle: From front matter\n---\n" + basic)
        XCTAssertGreaterThan(chart.size.height, 416)
        XCTAssertEqual(chart.title?.center.x ?? 0, chart.size.width / 2, accuracy: 1e-9)
        let wide = try layout("treemap\ntitle " + String(repeating: "x", count: 100) + "\n\"a\": 1")
        XCTAssertEqual(wide.boxes[0].frame.minX, 8 + (900 - 640) / 2)
    }

    func testClassesColorBoxesAndTheirTextAndPickAReadableInk() throws {
        let source = "treemap\n\"S\":::frame\n  \"a\": 10:::dark\n  \"b\": 20:::own\n  \"c\": 30:::hot\nclassDef frame fill:#FFF9C4\nclassDef dark fill:navy\nclassDef own fill:navy,color:#ddd\nclassDef hot fill:red,stroke:#FFD600,stroke-width:2px"
        let diagram = try SimpleChartReading.treemap(source)
        let parts = TreemapDrawingParts(layout: TreemapLayoutEngine.layout(diagram, typography: SimpleChartReading.typography))
        let dark = DiagramPaint.color(DiagramColor(red: 1, green: 1, blue: 1)), light = DiagramPaint.color(DiagramColor(red: 31.0 / 255, green: 31.0 / 255, blue: 31.0 / 255))
        XCTAssertEqual(parts.sectionNames.map(\.paint), [light], "A light fill takes the dark ink")
        XCTAssertEqual(parts.sectionValues.map(\.paint), [light])
        XCTAssertEqual(Set(parts.leafNames.map(\.paint)).count, 3)
        XCTAssertTrue(parts.leafNames.contains { $0.paint == dark }, "A dark fill takes white")
        XCTAssertTrue(parts.leafNames.contains { $0.paint == .color(DiagramColor(cssText: "#ddd")!) }, "The class's own text color wins")
        XCTAssertEqual(parts.sectionBoxes[0].fill, .color(DiagramColor(cssText: "#FFF9C4")!), "A class's fill replaces the tint")
        let hot = try XCTUnwrap(parts.leafBoxes.first { $0.outline != nil })
        XCTAssertEqual(hot.stroke.lineWidth, 2)
        XCTAssertEqual(hot.fill, .color(DiagramColor(cssText: "red")!))
    }

    func testTheSceneDrawsSectionsAsTintsThenLeavesInTheirSeriesColors() throws {
        let scene = DiagramScene(layout: TreemapLayoutEngine.layout(try SimpleChartReading.treemap("treemap\ntitle T\n" + String(basic.dropFirst("treemap-beta\n".count))),
                                                                    typography: SimpleChartReading.typography))
        XCTAssertEqual(scene.texts[0].part, .title)
        let sections = scene.shapes.filter { $0.part == .section }, leaves = scene.shapes.filter { $0.part == .leaf }
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(leaves.count, 2, "Leaves of one series are merged into one shape")
        XCTAssertEqual(Set(sections.map(\.painting)), [.fillAndStroke(DiagramPaint.series(0).atOpacity(0.12), .series(0), DiagramStroke(lineWidth: 1)),
                                                        .fillAndStroke(DiagramPaint.series(1).atOpacity(0.12), .series(1), DiagramStroke(lineWidth: 1))])
        XCTAssertEqual(Set(leaves.map(\.painting)), [.fill(.series(0)), .fill(.series(1))])
        XCTAssertEqual(scene.texts.filter { $0.part == .value }.count, 6)
        XCTAssertEqual(scene.texts.filter { $0.isBold && $0.part == .label }.count, 2, "Sections' names are bold")
        XCTAssertTrue(scene.texts.filter { $0.part == .label && !$0.isBold }.allSatisfy { $0.paint == .background }, "Leaves write in the background color")
    }

    func testTheDocumentationExamplesAreLaidOutWithoutOverlapAndNestedTreesToo() throws {
        let examples = try TreemapCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 8)
        for example in examples + [TreemapCorpus.generated(leafCount: 200)] {
            let diagram = try SimpleChartReading.treemap(example)
            let chart = TreemapLayoutEngine.layout(diagram, typography: SimpleChartReading.typography)
            XCTAssertFalse(chart.boxes.isEmpty, example)
            let page = CGRect(origin: .zero, size: chart.size)
            for box in chart.boxes { XCTAssertTrue(page.insetBy(dx: -0.001, dy: -0.001).contains(box.frame), example) }
            let leaves = chart.boxes.filter { box in !box.isSection }
            for (index, box) in leaves.enumerated() {
                for other in leaves[(index + 1)...] where box.frame.width * box.frame.height > 0 && other.frame.width * other.frame.height > 0 {
                    XCTAssertFalse(box.frame.intersects(other.frame), "\(box.frame) \(other.frame) \(example)")
                }
            }
        }
    }

    func testNothingToSizeHasNothingToDraw() throws {
        for source in ["treemap", "treemap\n\"Only a section\"", "treemap\n\"a\": 0\n\"b\": .", "treemap\n\"a\": " + String(repeating: "9", count: 400)] {
            XCTAssertTrue(try MermaidDiagramReader.read(source, limits: .standard).hasNothingToDraw, source)
            let chart = TreemapLayoutEngine.layout(try SimpleChartReading.treemap(source), typography: SimpleChartReading.typography)
            XCTAssertTrue(chart.boxes.isEmpty, source)
        }
        XCTAssertFalse(try MermaidDiagramReader.read(basic, limits: .standard).hasNothingToDraw)
    }

    func testTheAccessibilityValueNamesEachNodeWithItsValueAsWritten() throws {
        let prepared = try MermaidDiagramPreparation.prepare(source: "treemap\ntitle T\naccDescr: Described\n\"A\"\n  \"b\": 1234.5", typography: SimpleChartReading.typography)
        XCTAssertEqual(prepared.kind, .treemap)
        XCTAssertEqual(prepared.accessibility.label, "T")
        XCTAssertEqual(prepared.accessibility.value, "Described")
        XCTAssertEqual(prepared.accessibility.summary, ["A", "b: 1,234.5"])
    }
}
