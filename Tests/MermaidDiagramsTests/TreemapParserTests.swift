/**
 * File: TreemapParserTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: Reading treemaps: the inputs of Pele's ported specifications (treemap.test.ts, utils.test.ts), classes and the quirks of
 *              the lexer, errors with their lines, and the limits.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class TreemapParserTests: XCTestCase {
    /// The nodes as `name`, `value or section` and parent index, for comparing.
    private func shape(_ source: String) throws -> [String] {
        try SimpleChartReading.treemap(source).nodes.map { node in
            "\(node.name)|\(node.isSection ? "section" : String(node.value ?? .nan))|\(node.parentIndex.map(String.init) ?? "-")"
        }
    }

    func testAnEmptyTreemapAndASectionAreRead() throws {
        XCTAssertEqual(try SimpleChartReading.treemap("treemap").nodes, [])
        XCTAssertEqual(try SimpleChartReading.treemap("treemap-beta").nodes, [])
        XCTAssertEqual(try shape("treemap\n\"Root\""), ["Root|section|-"])
        XCTAssertEqual(try shape("treemap\n\"My Section\""), ["My Section|section|-"])
    }

    func testASectionWithLeavesTakesAColonOrACommaWithOrWithoutBlanks() throws {
        XCTAssertEqual(try shape("treemap\n\"Root\"\n  \"Child1\" , 100\n  \"Child2\" : 200\n"), ["Root|section|-", "Child1|100.0|0", "Child2|200.0|0"])
        XCTAssertEqual(try shape("treemap\n\"A\":1\n\"B\",2\n"), ["A|1.0|-", "B|2.0|-"])
        XCTAssertEqual(try shape("treemap\n\"Item\" : 123.45"), ["Item|123.45|-"])
        XCTAssertEqual(try shape("treemap\n'A': 5 %% comment\n'B'"), ["A|5.0|-", "B|section|-"])
    }

    func testValuesAreReadAsParseFloatReadsThemWithoutTheirCommas() throws {
        XCTAssertEqual(try shape("treemap\n\"A\" : 1,000.5"), ["A|1000.5|-"])
        XCTAssertEqual(try shape("treemap\n\"A\": 1.2.3"), ["A|1.2|-"])
        XCTAssertEqual(try shape("treemap\n\"A\": 1_000"), ["A|1.0|-"])
        XCTAssertEqual(try shape("treemap\n\"A\": .5"), ["A|0.5|-"])
        let notANumber = try SimpleChartReading.treemap("treemap\n\"A\": .\n\"B\": ..5")
        XCTAssertEqual(notANumber.nodes.map(\.value), [nil, nil])
        XCTAssertEqual(notANumber.nodes.map(\.size), [0, 0])
        XCTAssertEqual(try SimpleChartReading.treemap("treemap\n\"A\": " + String(repeating: "9", count: 400)).nodes[0].value, .infinity)
        XCTAssertEqual(try SimpleChartReading.treemap("treemap\n\"A\": " + String(repeating: "9", count: 400)).nodes[0].size, 0)
    }

    func testValuesAreRefusedWhereTheyBreak() {
        XCTAssertEqual(SimpleChartReading.readError("treemap\n\"A\": _"), .invalidSyntax(line: 2, problem: .treemap(.expectedValue)))
        XCTAssertEqual(SimpleChartReading.readError("treemap\n\"A\": ,5"), .invalidSyntax(line: 2, problem: .treemap(.expectedValue)))
        XCTAssertEqual(SimpleChartReading.readError("treemap\n\"A\":"), .invalidSyntax(line: 2, problem: .treemap(.expectedValue)))
        XCTAssertNotNil(SimpleChartReading.readError("treemap\n\"A\": 1e3"))
        XCTAssertEqual(SimpleChartReading.readError("treemap\nclass myNode myClass"), .invalidSyntax(line: 2, problem: .treemap(.expectedNameOrClassDefinition)))
        XCTAssertEqual(SimpleChartReading.readError("treemap\n\"A"), .invalidSyntax(line: 2, problem: .unclosedQuotation))
        XCTAssertEqual(SimpleChartReading.readError("treemap\n\"A\":::"), .invalidSyntax(line: 2, problem: .treemap(.expectedClassName)))
        XCTAssertNotNil(SimpleChartReading.readError("treemap\n\"A\": 1 :::x"), "A blank before :::, a token of its own, ends the row")
    }

    func testTheOutlineMakesTheHierarchyFromIndentation() throws {
        XCTAssertEqual(try shape("treemap\n\"A\"\n  \"B\"\n    \"c\": 1\n  \"d\": 2\n\"E\"\n      \"f\": 3\n \"g\": 4"),
                       ["A|section|-", "B|section|0", "c|1.0|1", "d|2.0|0", "E|section|-", "f|3.0|4", "g|4.0|4"])
    }

    func testAFlatListOfRowsBecomesTheHierarchyOfThePortedUtilityTests() throws {
        let indented = "treemap\n\"Root\"\n    \"Branch 1\"\n        \"Leaf 1.1\": 10\n        \"Leaf 1.2\": 15\n    \"Branch 2\"\n        \"Leaf 2.1\": 20\n        \"Leaf 2.2\": 25\n        \"Leaf 2.3\": 30"
        XCTAssertEqual(try shape(indented), ["Root|section|-", "Branch 1|section|0", "Leaf 1.1|10.0|1", "Leaf 1.2|15.0|1", "Branch 2|section|0", "Leaf 2.1|20.0|4",
                                             "Leaf 2.2|25.0|4", "Leaf 2.3|30.0|4"])
        XCTAssertEqual(try shape("treemap"), [])
        XCTAssertEqual(try shape("treemap\n\"Root 1\"\n\"Root 2\""), ["Root 1|section|-", "Root 2|section|-"])
        XCTAssertEqual(try shape("treemap\n\"Root\"\n  \"Level 1\"\n    \"Level 2\"\n      \"Leaf 1\": 10\n    \"Level 2 again\"\n      \"Leaf 2\": 20"),
                       ["Root|section|-", "Level 1|section|0", "Level 2|section|1", "Leaf 1|10.0|2", "Level 2 again|section|1", "Leaf 2|20.0|4"])
    }

    func testTrailingBlanksMoveTheNextRowsIndentationAsTheLexerDoesIt() throws {
        XCTAssertEqual(try shape("treemap\n\"A\"   \n\"B\""), ["A|section|-", "B|section|0"], "The blanks after A are the indentation B is read with")
        XCTAssertEqual(try shape("treemap\n\"A\"\n  \n    \"b\": 1"), ["A|section|-", "b|1.0|0"], "A line of blanks only is skipped")
        XCTAssertEqual(try shape("treemap\n\"A\"\n: 5"), ["A|5.0|-"], "A leaf's separator may come on the next line")
    }

    func testTitlesComeBetweenRowsAndTheLaterWinsAndFrontMatterGivesTheFallback() throws {
        let titled = try SimpleChartReading.treemap("treemap\ntitle My Treemap Diagram\naccTitle: Accessible Title\naccDescr: This is an accessible description\n\"Root\"\n  \"Child\": 100")
        XCTAssertEqual(titled.title, "My Treemap Diagram")
        XCTAssertEqual(titled.accessibilityTitle, "Accessible Title")
        XCTAssertEqual(titled.accessibilityDescription, "This is an accessible description")
        XCTAssertEqual(titled.nodes.count, 2)
        XCTAssertEqual(try SimpleChartReading.treemap("treemap title Hello\n\"A\"").title, "Hello")
        XCTAssertEqual(try SimpleChartReading.treemap("---\ntitle: From front matter\n---\ntreemap\n\"a\": 1").title, "From front matter")
        XCTAssertEqual(try SimpleChartReading.treemap("---\ntitle: From front matter\n---\ntreemap\ntitle Own\n\"a\": 1").title, "Own")
        XCTAssertEqual(try SimpleChartReading.treemap("treemap\n  title   Hello  world %% c\n accDescr { a\n b }\n\"A\"").title, "Hello world")
        XCTAssertEqual(try shape("treemap\n\"S\":::titles\n  \"a\": 1:::title_2"), ["S|section|-", "a|1.0|0"])
    }

    func testClassesAreNamedWithThreeColonsAndDefinedAnywhere() throws {
        let section = try SimpleChartReading.treemap("treemap\n\"My Section\":::sectionClass")
        XCTAssertEqual(section.nodes[0].className, "sectionClass")
        XCTAssertTrue(section.nodes[0].isSection)
        let leaf = try SimpleChartReading.treemap("treemap\n\"My Leaf\" : 100:::leafClass")
        XCTAssertEqual(leaf.nodes[0].className, "leafClass")
        XCTAssertEqual(leaf.nodes[0].value, 100)
        let defined = try SimpleChartReading.treemap("treemap\n\"a\": 1:::hot\nclassDef hot fill:red,color:blue,stroke:#FFD600;\nclassDef hot stroke-width:3px")
        XCTAssertEqual(defined.classStyles["hot"]?.fill, DiagramColor(cssText: "red"))
        XCTAssertEqual(defined.classStyles["hot"]?.textColor, DiagramColor(cssText: "blue"))
        XCTAssertEqual(defined.classStyles["hot"]?.stroke, DiagramColor(cssText: "#FFD600"))
        XCTAssertEqual(defined.classStyles["hot"]?.strokeWidth, 3, "A later classDef of the name adds to the earlier")
        XCTAssertEqual(defined.unappliedStatementCount, 0)
    }

    func testClassDefinitionsInTheFormsOfTheSpecification() throws {
        for source in ["treemap\nclassDef myClass fill:red;", "treemap\nclassDef myClass fill:red", "treemap\nclassDef complexClass fill:blue stroke:#ff0000 stroke-width:2px",
                       "treemap\n  classDef foo fill:red,stroke:blue;\n\"A\"", "treemap\nclassDef ab ;\n\"A\"", "treemap\nclassDef ab \n\n"] {
            XCTAssertNil(SimpleChartReading.readError(source), source)
        }
        let styles = try SimpleChartReading.treemap("treemap\nclassDef a1 fill:red; \"A\"").classStyles
        XCTAssertNotNil(styles["a1"], "The text after the semicolon is another row")
        XCTAssertNil(SimpleChartReading.readError("treemap\nclassDef a1 fill:red; \"A\""))
        XCTAssertNotNil(SimpleChartReading.readError("treemap\nclassDef a fill:red"), "A class's name is two characters or more")
        XCTAssertNil(SimpleChartReading.readError("treemap\nclassDef foo"), "A class may have no style")
    }

    func testClassDeclarationsAreSplitAtCommasAndSemicolonsUnlessEscapedAndWhatIsNotDrawnIsCounted() throws {
        let style = TreemapClassStyle.reading("fill:#f96,stroke:#333;stroke-width:2px,stroke-dasharray: 5 5,color:rgb(1\\,2\\,3),font-size:20px,opacity:.5")
        XCTAssertEqual(style.style.fill, DiagramColor(cssText: "#f96"))
        XCTAssertEqual(style.style.strokeWidth, 2)
        XCTAssertEqual(style.style.strokeDashLengths, [5, 5])
        XCTAssertEqual(style.style.textColor, DiagramColor(cssText: "rgb(1,2,3)"))
        XCTAssertEqual(style.unappliedCount, 2)
        XCTAssertEqual(try SimpleChartReading.treemap("treemap\n\"a\": 1:::c1\nclassDef c1 font-size:20px").unappliedStatementCount, 1)
    }

    func testOptionsComeFromTheFrontMatterAndDirectives() throws {
        let options = try SimpleChartReading.treemap("---\nconfig:\n  treemap:\n    nodeWidth: 30\n    nodeHeight: -3\n    diagramPadding: 5000\n    padding: 20\n    showValues: false\n    valueFormat: '$0,0'\n---\ntreemap\n\"a\": 1").options
        XCTAssertEqual([options.nodeWidth, options.nodeHeight, options.diagramPadding, options.boxGap], [30, 40, 2_000, 20])
        XCTAssertFalse(options.showsValues)
        XCTAssertEqual(options.valueFormat, "$0,0")
        XCTAssertEqual(TreemapOptions(), try SimpleChartReading.treemap("treemap").options)
        XCTAssertEqual(try SimpleChartReading.treemap("%%{init: {'treemap': {'padding': 1}}}%%\ntreemap\n\"a\": 1").options.boxGap, 1)
        XCTAssertEqual(try SimpleChartReading.treemap("---\nconfig:\n  treemap:\n    valueFormat: 7\n---\ntreemap").options.valueFormat, ",")
    }

    func testRowsAndClassDefinitionsPastTheLimitAreRefusedAndNestingIsReadWithoutRecursion() throws {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 3
        XCTAssertEqual(SimpleChartReading.readError("treemap\n\"a\": 1\n\"b\": 1\n\"c\": 1\n\"d\": 1", limits: limits), .tooManyNodes(limit: 3))
        XCTAssertEqual(SimpleChartReading.readError("treemap\nclassDef aa x\nclassDef bb x\nclassDef cc x\nclassDef dd x", limits: limits), .tooManyNodes(limit: 3))
        let deep = "treemap\n" + (0..<300).map { level in String(repeating: " ", count: level) + "\"s\(level)\"\n" }.joined() + String(repeating: " ", count: 300) + "\"leaf\": 1\n"
        let nodes = try SimpleChartReading.treemap(deep).nodes
        XCTAssertEqual(nodes.count, 301)
        XCTAssertEqual(nodes.last?.parentIndex, 299)
    }
}
