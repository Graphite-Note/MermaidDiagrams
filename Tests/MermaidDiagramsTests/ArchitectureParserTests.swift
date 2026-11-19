/**
 * File: ArchitectureParserTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The inputs of Mermaid 12.1.0's architecture specs (architecture.spec.ts and the parser's
 *              architecture.test.ts, as Pele ports them in tests/compat/architecture), Pele's own reading rules, the
 *              database's refusals with their lines, the options and the limits.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class ArchitectureParserTests: XCTestCase {
    private func read(_ source: String) throws -> ArchitectureDiagram {
        try ArchitectureReading.architecture(source)
    }

    func testTheKeywordReadsWithWhiteSpaceAroundIt() throws {
        for source in ["architecture-beta", "  architecture-beta  ", "\tarchitecture-beta\t", "\n        \tarchitecture-beta\n        ",
                       "architecture-beta\n            service db\n            "] {
            XCTAssertNoThrow(try read(source), source)
        }
        XCTAssertEqual(ArchitectureReading.readError("architecture\n  service a"), .invalidSyntax(line: 1, problem: .architecture(.expectedKeyword)))
    }

    func testTitlesOnTheKeywordsLineOrTheNextAndAccessibilityStatements() throws {
        for source in ["architecture-beta title sample title", "  architecture-beta  title sample title  ", "\tarchitecture-beta\ttitle sample title\t",
                       "architecture-beta\n            \ttitle sample title\n            ", "architecture-beta\n            title sample title"] {
            XCTAssertEqual(try read(source).title, "sample title", source)
        }
        let described = try read("architecture-beta\n  title sample title\n  accTitle: sample accTitle\n  accDescr: sample accDescr\n")
        XCTAssertEqual(described.accessibilityTitle, "sample accTitle")
        XCTAssertEqual(described.accessibilityDescription, "sample accDescr")
        XCTAssertEqual(try read("architecture-beta\n  accDescr {\n      Accessibility Description\n  }\n").accessibilityDescription, "Accessibility Description")
    }

    func testServiceTitlesQuotedOrNot() throws {
        let cases: [(String, String)] = [
            ("[\"Database\"]", "Database"), ("['Database']", "Database"), ("[Database]", "Database"), ("[\"John's Database\"]", "John's Database"),
            ("[\"The \\\"Main\\\" API\"]", "The \"Main\" API"), ("[采集器]", "采集器"), ("[Hello 世界]", "Hello 世界"), ("[Café]", "Café"),
            ("[Structure + Src]", "Structure + Src"), ("[Multi-Agent]", "Multi-Agent"), ("[A, B, C]", "A, B, C"), ("[TCP/IP: v6]", "TCP/IP: v6"),
        ]
        for (written, title) in cases {
            let diagram = try read("architecture-beta\n  group api\n  service db(database)\(written) in api\n")
            XCTAssertEqual(diagram.nodes.first?.title, title, written)
        }
        XCTAssertEqual(try read("architecture-beta\n  group g1(server)[你好世界]\n").groups.first?.title, "你好世界")
        XCTAssertEqual(try read("architecture-beta\n  group api(cloud)[\"API\"]\n").groups.first?.title, "API")
    }

    func testADeeplyNestedDiagramKeepsEveryServiceGroupAndEdge() throws {
        let diagram = try read("""
            architecture-beta
                group sub1(cloud)[Subscription A]
                group vnet1(cloud)[VNet A] in sub1
                service vm1(server)[VM] in vnet1
                group sub2(cloud)[Subscription B]
                group shared(cloud)[Shared] in sub2
                service reg(database)[Registry] in shared
                group env(cloud)[Environment] in sub2
                group vnet(cloud)[VNet] in env
                group snet1(cloud)[App Subnet] in vnet
                service nsg(server)[NSG] in snet1
                service asp(server)[App Plan] in snet1
                service web(server)[Web App] in snet1
                group snet2(cloud)[PE Subnet] in vnet
                service pe1(server)[PE Blob] in snet2
                service pe2(server)[PE Bus] in snet2
                service storage(disk)[Storage] in env
                service container(disk)[Container] in env
                service bus(server)[Service Bus] in env
                service dns(server)[DNS Zone] in env
                service client(internet)[Client]
                reg:B --> T:web
                nsg:R --> L:asp
                asp:R --> L:web
                web:R --> L:pe1
                pe1:R --> L:storage
                storage:B --> T:container
                web:B --> T:pe2
                pe2:R --> L:bus
                vm1:R --> L:pe2
            """)
        XCTAssertEqual(diagram.nodes.filter { node in node.kind == .service }.count, 12)
        XCTAssertEqual(diagram.groups.count, 8)
        XCTAssertEqual(diagram.edges.count, 9)
        XCTAssertEqual(diagram.edges[0].targetSide, .top)
        XCTAssertTrue(diagram.edges[0].hasTargetArrow)
        XCTAssertFalse(diagram.edges[0].hasSourceArrow)
    }

    func testGroupsAndServicesKeepTheirOrderAndNames() throws {
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  group marker(cloud)[Marker]\n  service a(server)[A] in __proto__\n"),
                       .invalidSyntax(line: 3, problem: .architecture(.parentMissing("a"))))
        XCTAssertEqual(try read("architecture-beta\n  group __proto__(cloud)[Marker]\n  service a(server)[A] in __proto__\n  service b(server)[B] in __proto__\n  a:R -- L:b")
            .groups.map(\.identifier), ["__proto__"])
        XCTAssertEqual(try read("architecture-beta\n  service a(server)[A]\n  service 20(server)[B]\n  service 10(server)[C]").nodes.map(\.identifier), ["a", "20", "10"])
    }

    func testAlignments() throws {
        let row = try read("architecture-beta\n  group api(cloud)[API]\n  service db1(database)[DB1] in api\n  service db2(database)[DB2] in api\n  service db3(database)[DB3] in api\n  align row db1 db2 db3")
        XCTAssertEqual(row.alignments, [ArchitectureAlignment(isRow: true, memberIndices: [0, 1, 2])])
        XCTAssertEqual(try read("architecture-beta\n  service a(server)[A]\n  service b(server)[B]\n  align column a b").alignments.first?.isRow, false)
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  service a(server)[A]\n  service b(server)[B]\n  align row a b ghost"),
                       .invalidSyntax(line: 4, problem: .architecture(.alignmentMemberNotANode("ghost"))))
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  service a(server)[A]\n  align row a a"),
                       .invalidSyntax(line: 3, problem: .architecture(.alignmentMemberRepeated("a"))))
        XCTAssertEqual(try read("architecture-beta\n  service rowspan(server)[Rowspan]\n  service columnar(server)[Columnar]\n  align row rowspan columnar")
            .nodes.map(\.identifier), ["rowspan", "columnar"])
        for keyword in ["align", "row", "column"] {
            XCTAssertNotNil(ArchitectureReading.readError("architecture-beta\n  service \(keyword)(database)[Service Using Reserved Word]"), keyword)
        }
    }

    func testJunctionsAreCheckedAsServicesAre() throws {
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  group g1[Group]\n  service svc(server)[Svc] in g1\n  junction svc"),
                       .invalidSyntax(line: 4, problem: .architecture(.identifierInUse("svc"))))
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  group g1[Group]\n  junction g1"),
                       .invalidSyntax(line: 3, problem: .architecture(.identifierInUse("g1"))))
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  junction j1 in nonexistent"),
                       .invalidSyntax(line: 2, problem: .architecture(.parentMissing("j1"))))
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  service app(server)[App]\n  junction j1 in app"),
                       .invalidSyntax(line: 3, problem: .architecture(.parentNotAGroup("j1"))))
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  junction j1 in j1"),
                       .invalidSyntax(line: 2, problem: .architecture(.placedInItself("j1"))))
        let diagram = try read("architecture-beta\n  group app_env(cloud)[App Env]\n  service app(server)[Web App] in app_env\n  service db(database)[DB] in app_env\n  service api(server)[API] in app_env\n  junction mid in app_env\n  app:B -- T:mid\n  mid:R -- L:db\n  mid:B -- T:api")
        XCTAssertEqual(diagram.nodes.filter { node in node.kind == .junction }.map(\.groupIndex), [0])
    }

    /// Pele's rules beyond Mermaid's specs: an edge naming a group is refused, `{group}` within one group is refused,
    /// an identifier starting with L, R, T or B reads as a side (as Mermaid's lexer reads it), and one starting with
    /// `title` is an identifier.
    func testPelesOwnReadingRules() throws {
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  group g\n  service a\n  a:R -- L:g"),
                       .invalidSyntax(line: 4, problem: .architecture(.edgeEndIsAGroup("g"))))
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  service a\n  a:R -- L:b"),
                       .invalidSyntax(line: 3, problem: .architecture(.edgeEndMissing("b"))))
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  group g\n  service a in g\n  service b in g\n  a{group}:R -- L:b"),
                       .invalidSyntax(line: 5, problem: .architecture(.groupModifierWithinOneGroup("a"))))
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  service Bob"), .invalidSyntax(line: 2, problem: .architecture(.expectedIdentifier)))
        XCTAssertEqual(try read("architecture-beta\n  service titled\n  service title-x").nodes.map(\.identifier), ["titled", "title-x"])
        let edge = try read("architecture-beta\n  service a\n  service b\n  a:L <-[Calls]-> R:b").edges[0]
        XCTAssertEqual(edge.title, "Calls")
        XCTAssertTrue(edge.hasSourceArrow && edge.hasTargetArrow)
        XCTAssertEqual(try read("architecture-beta\n  service a \"DB\"").nodes[0].iconText, "DB")
    }

    func testSyntaxErrorsSayWhatWasExpectedOnTheirLine() {
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  service a\n  a:R --"),
                       .invalidSyntax(line: 3, problem: .architecture(.expectedSide)))
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  service a service b"),
                       .invalidSyntax(line: 2, problem: .architecture(.expectedLineEnd)))
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  align diagonal a b"),
                       .invalidSyntax(line: 2, problem: .architecture(.expectedRowOrColumn)))
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  service a\n  a R -- L:b"),
                       .invalidSyntax(line: 3, problem: .architecture(.expectedColon)))
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  service a #"), .invalidSyntax(line: 2, problem: .unexpectedText("#")))
    }

    func testOptionsAreReadWithinPelesBounds() throws {
        let options = try read("---\nconfig:\n  architecture:\n    iconSize: 1000\n    fontSize: 2\n    padding: 30\n---\narchitecture-beta\n  service a").options
        XCTAssertEqual(options.iconSize, 512)
        XCTAssertEqual(options.fontSize, 4)
        XCTAssertEqual(options.padding, 30)
        XCTAssertEqual(try read("architecture-beta\n  service a").options, ArchitectureOptions())
    }

    func testCountsAreBoundedByTheLimits() {
        let limits = MermaidDiagramLimits(maximumSourceBytes: 50_000, maximumNodeCount: 3, maximumEdgeCount: 2, maximumLayoutPointCount: 50_000)
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  group g\n  service a\n  service b\n  junction j", limits: limits), .tooManyNodes(limit: 3))
        XCTAssertEqual(ArchitectureReading.readError("architecture-beta\n  service a\n  service b\n  a:R -- L:b\n  align row a b", limits: limits),
                       .tooManyEdges(limit: 2))
    }
}
