/**
 * File: C4ParserTests.swift
 * -------------------------
 * Layer: Tests
 * Description: C4 diagrams read as Mermaid's Jison grammar and Pele's model read them: the inputs of Mermaid's C4
 *              specs as Pele ports them (tests/compat/c4), and the model cases of Pele's render tests.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class C4ParserTests: XCTestCase {
    private let customerDescription = "A customer of the bank, with personal bank accounts."

    // MARK: - c4Diagram.spec.ts

    func testTrailingWhitespaceAfterStatements() throws {
        let diagram = try C4Reading.c4("C4Context \ntitle System Context diagram for Internet Banking System \nPerson(customerA, \"Banking Customer A\", \"\(customerDescription)\") ")
        XCTAssertEqual(diagram.shapes.count, 1)
        XCTAssertEqual(diagram.title, "System Context diagram for Internet Banking System ")
    }

    func testParameterNamesThatAreKeywords() throws {
        let diagram = try C4Reading.c4("C4Context\ntitle title\nPerson(Person, \"Person\", \"Person\")")
        XCTAssertEqual(diagram.title, "title")
        XCTAssertEqual(diagram.shapes.map(\.element.alias), ["Person"])
        XCTAssertEqual(diagram.shapes[0].element.label, "Person")
        XCTAssertEqual(diagram.shapes[0].element.description, "Person")
        let defaults = try C4Reading.c4("C4Context\nPerson(default, \"default\", \"default\")").shapes[0].element
        XCTAssertEqual([defaults.alias, defaults.label, defaults.description], ["default", "default", "default"])
    }

    // MARK: - c4Person, c4PersonExt, c4System, c4Container and c4Component specs

    func testEveryShapeMacroReadsItsKindAndFields() throws {
        let macros: [(String, C4ShapeKind)] = [
            ("Person", .person), ("Person_Ext", .externalPerson), ("System", .system), ("SystemDb", .systemDatabase), ("SystemQueue", .systemQueue),
            ("System_Ext", .externalSystem), ("SystemDb_Ext", .externalSystemDatabase), ("SystemQueue_Ext", .externalSystemQueue),
            ("Container", .container), ("ContainerDb", .containerDatabase), ("ContainerQueue", .containerQueue), ("Container_Ext", .externalContainer),
            ("ContainerDb_Ext", .externalContainerDatabase), ("ContainerQueue_Ext", .externalContainerQueue), ("Component", .component),
            ("ComponentDb", .componentDatabase), ("ComponentQueue", .componentQueue), ("Component_Ext", .externalComponent),
            ("ComponentDb_Ext", .externalComponentDatabase), ("ComponentQueue_Ext", .externalComponentQueue),
        ]
        for (macro, kind) in macros {
            let takesTechnology = kind.takesTechnology
            let arguments = takesTechnology ? "\"Technology\", \"\(customerDescription)\"" : "\"\(customerDescription)\""
            let diagram = try C4Reading.c4("C4Context\ntitle T\n\(macro)(alias, \"Label\", \(arguments))")
            let shape = try XCTUnwrap(diagram.shapes.first, macro)
            XCTAssertEqual(shape.kind, kind, macro)
            XCTAssertEqual(shape.element.alias, "alias", macro)
            XCTAssertEqual(shape.element.label, "Label", macro)
            XCTAssertEqual(shape.element.description, customerDescription, macro)
            XCTAssertEqual(shape.element.technology, takesTechnology ? "Technology" : nil, macro)
            XCTAssertEqual(shape.element.parentBoundaryIndex, 0, macro)
            XCTAssertNil(shape.element.sprite, macro)
            XCTAssertNil(shape.element.link, macro)
            let empty = try C4Reading.c4("C4Context\n\(macro)(alias, \"\", \"\(takesTechnology ? "Java" : "d")\")").shapes[0].element
            XCTAssertEqual(takesTechnology ? empty.technology : empty.description, takesTechnology ? "Java" : "d", macro)
            if takesTechnology {
                let described = try C4Reading.c4("C4Context\n\(macro)(alias, \"\", \"\", \"Allows\")").shapes[0].element
                XCTAssertEqual(described.description, "Allows", macro)
            }
        }
    }

    func testANamedArgumentInTheLabelsPlaceSetsWhatItNames() throws {
        for (key, value) in [("sprite", "users"), ("link", "https://github.com/mermaidjs"), ("tags", "tag1,tag2")] {
            for macro in ["Person", "Person_Ext", "System", "SystemDb_Ext", "Container", "ComponentQueue"] {
                let element = try C4Reading.c4("C4Context\n\(macro)(customerA, $\(key)=\"\(value)\")").shapes[0].element
                XCTAssertEqual(element.labelArgument, C4NamedArgument(key: key, value: value), macro)
                XCTAssertEqual(element.label, "", macro)
                XCTAssertEqual(key == "sprite" ? element.sprite : key == "link" ? element.link : element.tags, value, macro)
            }
        }
        let person = try C4Reading.c4("C4Context\nPerson(customerA, \"Banking Customer A\", \"A customer.\", $tags=\"v1.0+internal\", $link=\"https://example.com\")")
        XCTAssertEqual(person.shapes[0].element.tags, "v1.0+internal")
        XCTAssertEqual(person.shapes[0].element.link, "https://example.com")
    }

    // MARK: - c4Boundary.spec.ts

    func testABoundaryHoldsWhatIsWrittenInIt() throws {
        let diagram = try C4Reading.c4("C4Context\ntitle System Context diagram for Internet Banking System\nBoundary(b1, \"BankBoundary\") {\nSystem(SystemAA, \"Internet Banking System\")\n}")
        XCTAssertEqual(diagram.boundaries.count, 2)
        let boundary = diagram.boundaries[1].element
        XCTAssertEqual(boundary.alias, "b1")
        XCTAssertEqual(boundary.label, "BankBoundary")
        XCTAssertEqual(boundary.type, "system")
        XCTAssertEqual(boundary.parentBoundaryIndex, 0)
        XCTAssertNil(boundary.link)
        XCTAssertNil(boundary.tags)
        XCTAssertEqual(diagram.shapes[0].element.parentBoundaryIndex, 1)
        XCTAssertEqual(try C4Reading.c4("C4Context\nBoundary(b1, \"\", \"company\") {\nSystem(SystemAA, \"I\")\n}").boundaries[1].element.type, "company")
        let linked = try C4Reading.c4("C4Context\nBoundary(b1, $link=\"https://github.com/mermaidjs\") {\nSystem(SystemAA, \"I\")\n}").boundaries[1].element
        XCTAssertEqual(linked.labelArgument, C4NamedArgument(key: "link", value: "https://github.com/mermaidjs"))
        XCTAssertEqual(linked.link, "https://github.com/mermaidjs")
        XCTAssertEqual(try C4Reading.c4("C4Context\nBoundary(b1, $tags=\"tag1,tag2\") {\nSystem(SystemAA, \"I\")\n}").boundaries[1].element.tags, "tag1,tag2")
    }

    /// Regression test for Mermaid's #4864: a relation may end at a boundary, found among the boundaries after the shapes.
    func testABoundaryAliasIsARelationsEnd() throws {
        let diagram = try C4Reading.c4("C4Context\nBoundary(b1, \"BankBoundary\") {\nSystem(SystemAA, \"Internet Banking System\")\n}\nRel(b1, SystemAA, \"Contains\")")
        XCTAssertEqual(diagram.element(named: "b1"), .boundary(1))
        XCTAssertEqual(diagram.element(named: "SystemAA"), .shape(0))
        XCTAssertNil(diagram.element(named: "missing"))
        XCTAssertNoThrow(try C4LayoutEngine.layout(diagram, typography: DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))))
    }

    func testEachBoundaryMacroWritesItsKindAsItsType() throws {
        let diagram = try C4Reading.c4("""
            C4Container
            Enterprise_Boundary(e, "E") {
              System_Boundary(s, "S") {
                Container_Boundary(c, "C") {
                  Boundary(b, "B") {
                    Boundary(t, "T", "custom") {
                      System(x, "X")
                    }
                  }
                }
              }
            }
            """)
        XCTAssertEqual(diagram.boundaries.dropFirst().map(\.element.type), ["ENTERPRISE", "SYSTEM", "CONTAINER", "system", "custom"])
        XCTAssertEqual(diagram.boundaries.dropFirst().map(\.element.parentBoundaryIndex), [0, 1, 2, 3, 4])
        let nodes = try C4Reading.c4("C4Deployment\nDeployment_Node(a, \"A\", \"Linux\", \"A machine\") {\nNode_L(l, \"L\") {\nNode_R(r, \"R\")\n{\nContainer(app, \"App\")\n}\n}\n}")
        XCTAssertEqual(nodes.boundaries.dropFirst().map(\.deploymentNode), [.node, .leftNode, .rightNode])
        XCTAssertEqual(nodes.boundaries[1].element.description, "A machine")
        XCTAssertEqual(nodes.boundaries[2].element.type, "node")
    }

    // MARK: - c4NamedAttributes.spec.ts

    func testNamedArgumentsArrivingInAPositionalPlace() throws {
        XCTAssertEqual(try C4Reading.c4("C4Context\nSystem(s, \"S\", $tags=\"cylinder\")").shapes[0].element.tags, "cylinder")
        let described = try C4Reading.c4("C4Context\nSystem(s, \"S\", \"desc\", $tags=\"cylinder\")").shapes[0].element
        XCTAssertEqual([described.tags, described.description], ["cylinder", "desc"])
        XCTAssertEqual(try C4Reading.c4("C4Context\nSystem(s, \"S\", $descr=\"a description\")").shapes[0].element.description, "a description")
        let container = try C4Reading.c4("C4Container\nContainer(c, \"C\", $sprite=\"browser\", $link=\"https://x.test\")").shapes[0].element
        XCTAssertEqual([container.sprite, container.link], ["browser", "https://x.test"])
        XCTAssertEqual(try C4Reading.c4("C4Container\nContainer(c, \"C\", $descr=\"a description\")").shapes[0].element.description, "a description")
        let technology = try C4Reading.c4("C4Container\nContainer(c, \"C\", $techn=\"Java\")").shapes[0].element
        XCTAssertEqual([technology.technology, technology.description], ["Java", ""])
        let related = "C4Context\nPerson(a, \"A\")\nPerson(b, \"B\")\n"
        XCTAssertEqual(try C4Reading.c4(related + "Rel(a, b, \"uses\", $tags=\"async\")").relations[0].tags, "async")
        XCTAssertEqual(try C4Reading.c4(related + "Rel(a, b, \"uses\", $descr=\"how it is used\")").relations[0].description, "how it is used")
    }

    /// Every kind of declaration given one named argument, which lands in its first optional place, rarely its own.
    func testOneNamedArgumentWhicheverPlaceItLandsIn() throws {
        let elements: [(String, String, [String])] = [
            ("C4Context", "System(x, \"L\", $F=\"V\")", ["descr", "tags", "sprite", "link"]),
            ("C4Context", "Person(x, \"L\", $F=\"V\")", ["descr", "tags", "sprite", "link"]),
            ("C4Container", "Container(x, \"L\", $F=\"V\")", ["descr", "techn", "tags", "sprite", "link"]),
            ("C4Component", "Component(x, \"L\", $F=\"V\")", ["descr", "techn", "tags", "sprite", "link"]),
        ]
        for (header, template, fields) in elements {
            for field in fields {
                let element = try C4Reading.c4(header + "\n" + template.replacingOccurrences(of: "$F", with: "$" + field)).shapes[0].element
                XCTAssertEqual(Self.field(field, of: element), "V", "\(template) \(field)")
            }
        }
        let boundaries: [(String, String, [String])] = [
            ("C4Context", "System_Boundary(x, \"L\", $F=\"V\")", ["type", "tags", "link"]),
            ("C4Container", "Container_Boundary(x, \"L\", $F=\"V\")", ["type", "tags", "link"]),
            ("C4Deployment", "Node(x, \"L\", $F=\"V\")", ["type", "descr", "tags", "sprite", "link"]),
        ]
        for (header, template, fields) in boundaries {
            for field in fields {
                let source = header + "\n" + template.replacingOccurrences(of: "$F", with: "$" + field) + " {\nContainer(i, \"I\")\n}"
                XCTAssertEqual(Self.field(field, of: try C4Reading.c4(source).boundaries[1].element), "V", "\(template) \(field)")
            }
        }
        for field in ["techn", "descr", "tags", "sprite", "link"] {
            let relation = try C4Reading.c4("C4Context\nPerson(a, \"A\")\nPerson(b, \"B\")\nRel(a, b, \"uses\", $\(field)=\"V\")").relations[0]
            let value = [("techn", relation.technology), ("descr", relation.description), ("tags", relation.tags), ("sprite", relation.sprite),
                         ("link", relation.link)].first { name, _ in name == field }?.1
            XCTAssertEqual(value, "V", field)
        }
    }

    private static func field(_ name: String, of element: C4Element) -> String? {
        switch name {
        case "descr": element.description
        case "techn": element.technology
        case "type": element.type
        case "tags": element.tags
        case "sprite": element.sprite
        default: element.link
        }
    }

    // MARK: - The model cases of Pele's render tests

    func testTheFiveKeywords() throws {
        for level in C4DiagramLevel.allCases {
            XCTAssertEqual(try C4Reading.c4("\(level.rawValue)\nPerson(a, \"A\")").level, level)
        }
    }

    func testUpdateLayoutConfigByPlaceNotByName() throws {
        let base = "C4Context\nSystem(a, \"A\")\n"
        let both = try C4Reading.c4(base + "UpdateLayoutConfig($c4ShapeInRow=\"1\", $c4BoundaryInRow=\"3\")")
        XCTAssertEqual([both.shapesPerRow, both.boundariesPerRow], [1, 3])
        let ignored = try C4Reading.c4(base + "UpdateLayoutConfig(\"0\", \"-3\")")
        XCTAssertEqual([ignored.shapesPerRow, ignored.boundariesPerRow], [4, 2])
        let byPlace = try C4Reading.c4(base + "UpdateLayoutConfig($c4BoundaryInRow=\"3\")")
        XCTAssertEqual([byPlace.shapesPerRow, byPlace.boundariesPerRow], [3, 2])
        XCTAssertEqual(try C4Reading.c4(base + "UpdateLayoutConfig(\"99999999\", \"1\")").shapesPerRow, 99_999_999)
    }

    func testRelationsTheirKindsIndicesAndThoseWithoutALabel() throws {
        let diagram = try C4Reading.c4("C4Dynamic\nSystem(a, \"A\")\nSystem(b, \"B\")\nRelIndex(7, a, b, \"x\")\nRel(b, \"a\")")
        XCTAssertEqual(diagram.relations.count, 1)
        XCTAssertEqual(diagram.relations[0].kind, .relation)
        XCTAssertEqual([diagram.relations[0].from, diagram.relations[0].to, diagram.relations[0].label], ["a", "b", "x"])
        let kinds: [(String, C4RelationKind)] = [("BiRel", .bidirectional), ("Rel_Up", .relationUp), ("Rel_U", .relationUp), ("Rel_Down", .relationDown),
                                                  ("Rel_D", .relationDown), ("Rel_Left", .relationLeft), ("Rel_L", .relationLeft), ("Rel_Right", .relationRight),
                                                  ("Rel_R", .relationRight), ("Rel_Back", .relationBack)]
        for (macro, kind) in kinds {
            XCTAssertEqual(try C4Reading.c4("C4Context\nSystem(a, \"A\")\nSystem(b, \"B\")\n\(macro)(a, b, \"x\")").relations[0].kind, kind, macro)
        }
    }

    func testARepeatedAliasMergesAndKeepsItsPlace() throws {
        let diagram = try C4Reading.c4("""
            C4Context
            System(a, "First", "d1")
            System(b, "B")
            Boundary(x, "X") {
              Person(a, "Second")
            }
            Rel(a, b, "one", "t")
            BiRel(a, b, "two")
            """)
        XCTAssertEqual(diagram.shapes.map(\.element.alias), ["a", "b"])
        XCTAssertEqual(diagram.shapes[0].element.label, "Second")
        XCTAssertEqual(diagram.shapes[0].element.description, "d1")
        XCTAssertEqual(diagram.shapes[0].kind, .person)
        XCTAssertEqual(diagram.shapes[0].element.parentBoundaryIndex, 1)
        XCTAssertEqual(diagram.relations.count, 1)
        XCTAssertEqual(diagram.relations[0].kind, .bidirectional)
        XCTAssertEqual(diagram.relations[0].label, "two")
        XCTAssertEqual(diagram.relations[0].technology, "t")
    }

    func testANamedArgumentAppliesWhereverItIsWritten() throws {
        let diagram = try C4Reading.c4("""
            C4Container
            Person(a, $sprite="users")
            Container(b, "B", $descr="described")
            Container($tags="t", "Anonymous")
            Node(n, "N", "t", "d", $link="https://example.com") {
              Container(c, "C", $unknown="kept", $__proto__="safe")
            }
            Rel(a, b, $techn="HTTP")
            """)
        XCTAssertEqual([diagram.shapes[0].element.alias, diagram.shapes[0].element.label, diagram.shapes[0].element.sprite], ["a", "", "users"])
        XCTAssertEqual(diagram.shapes[1].element.description, "described")
        XCTAssertNil(diagram.shapes[1].element.technology)
        XCTAssertEqual([diagram.shapes[2].element.alias, diagram.shapes[2].element.label, diagram.shapes[2].element.tags], ["", "Anonymous", "t"])
        XCTAssertEqual(diagram.shapes[2].element.aliasArgument, C4NamedArgument(key: "tags", value: "t"))
        let node = diagram.boundaries[1]
        XCTAssertEqual([node.element.type, node.element.description, node.element.link], ["t", "d", "https://example.com"])
        XCTAssertEqual(node.deploymentNode, .node)
        XCTAssertEqual(diagram.shapes[3].element.otherArguments.arguments,
                       [C4NamedArgument(key: "unknown", value: "kept"), C4NamedArgument(key: "__proto__", value: "safe")])
        XCTAssertEqual([diagram.relations[0].label, diagram.relations[0].technology], ["", "HTTP"])
    }

    func testStylesAreKeptOnTheirElementsAndRelations() throws {
        let diagram = try C4Reading.c4("""
            C4Context
            System(a, "A", "d", "sprite", "t1,t2")
            System(b, "B")
            Rel(a, b, "x")
            UpdateElementStyle(a, $legendText="L", $legendSprite="S", $shadowing="true", $bgColor="grey")
            UpdateElementStyle(nobody, "red")
            UpdateRelStyle(a, b, $textColor="red", $lineColor="blue", $offsetX="30", $offsetY="-10px")
            UpdateRelStyle(b, a, "red")
            """)
        let element = diagram.shapes[0].element
        XCTAssertEqual([element.sprite, element.tags, element.legendText, element.legendSprite, element.shadowing, element.backgroundColor],
                       ["sprite", "t1,t2", "L", "S", "true", "grey"])
        let relation = diagram.relations[0]
        XCTAssertEqual([relation.textColor, relation.lineColor], ["red", "blue"])
        XCTAssertEqual(relation.labelOffsetX, 30)
        XCTAssertEqual(relation.labelOffsetY, -10)
        let positional = try C4Reading.c4("C4Context\nSystem(a, \"A\")\nSystem(b, \"B\")\nRel(a, b, \"x\")\nUpdateRelStyle(a, b, \"red\", \"blue\", \"abc\", \"0x10\")")
        XCTAssertNil(positional.relations[0].labelOffsetX)
        XCTAssertEqual(positional.relations[0].labelOffsetY, 16)
    }

    func testTitlesAndAccessibilityStatements() throws {
        let bare = try C4Reading.c4("C4Context\ntitle\nPerson(a, \"Alice\")\nPerson(b, \"Bob\")")
        XCTAssertNil(bare.title)
        XCTAssertEqual(bare.shapes.map(\.element.label), ["Alice", "Bob"])
        XCTAssertEqual(try C4Reading.c4("C4Context\ntitle\tOwn\nSystem(a, \"A\")").title, "Own")
        let accessible = try C4Reading.c4("C4Context\naccTitle: Shown on top\naccDescr: For screen readers\nSystem(a, \"A\")")
        XCTAssertEqual(accessible.title, "Shown on top")
        XCTAssertEqual(accessible.accessibilityDescription, "For screen readers")
        XCTAssertEqual(try C4Reading.c4("C4Context\naccDescr {\n  two\n  lines\n}\nSystem(a, \"A\")").accessibilityDescription, "two\nlines")
        XCTAssertEqual(try C4Reading.c4("C4Context\naccDescription one line\nSystem(a, \"A\")").accessibilityDescription, "one line")
        XCTAssertEqual(try C4Reading.c4("---\ntitle: From front matter\n---\nC4Context\nSystem(a, \"A\")").title, "From front matter")
        XCTAssertEqual(try C4Reading.c4("---\ntitle: From front matter\n---\nC4Context\ntitle Own\nSystem(a, \"A\")").title, "Own")
    }

    func testAnUnquotedLastArgumentRunsToTheNextComma() throws {
        let diagram = try C4Reading.c4("C4Context\nPerson(a, plain label)\nSystem(b, \"B\")")
        XCTAssertEqual(diagram.shapes.count, 1)
        XCTAssertEqual(diagram.shapes[0].element.label, "plain label)\nSystem(b")
    }

    /// A comment takes the line breaks after it, so one after a statement leaves it without its line break, as in Mermaid.
    func testCommentsAndBlankLines() throws {
        let diagram = try C4Reading.c4("C4Context\n%% a comment\nSystem(a, \"A\")\n\n   %% another\nSystem(b, \"B\")\n")
        XCTAssertEqual(diagram.shapes.map(\.element.alias), ["a", "b"])
        XCTAssertEqual(C4Reading.syntaxProblem("C4Context\nSystem(a, \"A\") %% after\nSystem(b, \"B\")")?.problem,
                       .unexpectedToken(found: "SYSTEM", expected: .lineBreakOrEnd))
    }

    func testSyntaxErrorsAsJisonFindsThem() {
        XCTAssertEqual(C4Reading.syntaxProblem("C4Context\nPerson (a, \"A\")")?.problem, .unrecognizedText)
        XCTAssertEqual(C4Reading.syntaxProblem("C4Context\nPerson (a, \"A\")")?.line, 2)
        let twoOnALine = C4Reading.syntaxProblem("C4Context\nPerson(a, \"A\") Person(b, \"B\")")
        XCTAssertEqual(twoOnALine?.line, 2)
        XCTAssertEqual(twoOnALine?.problem, .unexpectedToken(found: "PERSON", expected: .lineBreakOrEnd))
        XCTAssertEqual(C4Reading.syntaxProblem("C4Context\nBoundary(b, \"B\")\nSystem(a, \"A\")")?.problem,
                       .unexpectedToken(found: "SYSTEM", expected: .openingBrace))
        XCTAssertEqual(C4Reading.syntaxProblem("C4Context\nBoundary(b, \"B\") {\nSystem(a, \"A\")")?.problem,
                       .unexpectedToken(found: "EOF", expected: .lineBreakOrClosingBrace))
        XCTAssertEqual(C4Reading.syntaxProblem("C4Context\n")?.problem, .unexpectedToken(found: "EOF", expected: .statement))
        XCTAssertEqual(C4Reading.syntaxProblem("C4Context\nPerson(a, \"A\", $link=\"\")")?.problem,
                       .unexpectedToken(found: "EOF", expected: .namedValue))
        XCTAssertNotNil(C4Reading.syntaxProblem("C4Context\nPerson(a, \"A\""))
        XCTAssertEqual(C4Reading.syntaxProblem("C4Context direction TB\nPerson(a, \"A\")")?.problem,
                       .unexpectedToken(found: "direction_tb", expected: .header))
        XCTAssertEqual(C4Reading.syntaxProblem("C4Context\nPerson(a, \"x direction LR\")")?.problem,
                       .unexpectedToken(found: "direction_lr", expected: .statement))
        XCTAssertEqual(C4Reading.readError("C4Contexts\nPerson(a, \"A\")"), .unsupportedDiagramType(keyword: "C4Contexts"))
    }

    func testLimitsAreCheckedBeforeAnythingIsMade() {
        let limits = MermaidDiagramLimits(maximumSourceBytes: 50_000, maximumNodeCount: 3, maximumEdgeCount: 2, maximumLayoutPointCount: 50_000)
        XCTAssertEqual(C4Reading.readError("C4Context\nSystem(a, \"A\")\nSystem(b, \"B\")\nBoundary(c, \"C\") {\nSystem(d, \"D\")\n}", limits: limits),
                       .tooManyNodes(limit: 3))
        XCTAssertNil(C4Reading.readError("C4Context\nSystem(a, \"A\")\nSystem(a, \"A\")\nSystem(b, \"B\")\nSystem(c, \"C\")", limits: limits))
        let relations = "C4Context\nSystem(a, \"A\")\nSystem(b, \"B\")\nRel(a, b, \"1\")\nRel(b, a, \"2\")\nRel(a, b, \"again\")\n"
        XCTAssertNil(C4Reading.readError(relations, limits: limits))
        XCTAssertEqual(C4Reading.readError(relations + "Rel(a, a, \"3\")", limits: limits), .tooManyEdges(limit: 2))
    }
}
