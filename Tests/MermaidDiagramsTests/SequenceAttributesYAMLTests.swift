/**
 * File: SequenceAttributesYAMLTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The YAML reader of a sequence participant's attributes against the cases of Pele's own YAML tests, each
 *              with the value js-yaml's JSON schema gives it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// Pele checks its YAML reader against js-yaml on what Mermaid passes it (`tests/util/yaml.test.ts`): the inputs are
/// those cases, the expected values what js-yaml's `JSON_SCHEMA` loads from them.
final class SequenceAttributesYAMLTests: XCTestCase {
    private typealias Value = SequenceAttributeValue

    private func read(_ source: String) -> Value? {
        try? SequenceAttributesBlockSyntax.value(of: source)
    }

    func testFlowMappingsAgreeWithJavaScriptYAML() {
        XCTAssertEqual(read("{\n shape: rounded \n}"), .mapping(["shape": .text("rounded")]))
        XCTAssertEqual(read("{\nshape: rounded , label: \"DD\"\n}"), .mapping(["shape": .text("rounded"), "label": .text("DD")]))
        XCTAssertEqual(read("{\n label: \"This is }\", other: \"clock\"\n}"), .mapping(["label": .text("This is }"), "other": .text("clock")]))
        XCTAssertEqual(read("{\n animate: true, animation: fast, w: 100, h: 50.5, x: null, y: ~\n}"),
                       .mapping(["animate": .boolean(true), "animation": .text("fast"), "w": .number(100), "h": .number(50.5), "x": .null, "y": .null]))
        XCTAssertEqual(read("{\n label: 'single quoted', icon: \"fa:fa-user\", form: circle, pos: t \n}"),
                       .mapping(["label": .text("single quoted"), "icon": .text("fa:fa-user"), "form": .text("circle"), "pos": .text("t")]))
        XCTAssertEqual(read("{\n a: [1, 2, three], b: {c: d, e: [f]}\n}"),
                       .mapping(["a": .list([.number(1), .number(2), .text("three")]), "b": .mapping(["c": .text("d"), "e": .list([.text("f")])])]))
        XCTAssertEqual(read("{\n}"), .mapping([:]))
        XCTAssertEqual(read("{\n a: 1, # comment\n b: 2\n}"), .mapping(["a": .number(1), "b": .number(2)]))
    }

    func testBlockValuesAgreeWithJavaScriptYAML() {
        XCTAssertEqual(read("\n        shape: circle\n        other: \"clock\"\n     \n"), .mapping(["shape": .text("circle"), "other": .text("clock")]))
        XCTAssertEqual(read("\n        label: |\n          This is a\n          multiline string\n        other: \"clock\"\n     \n"),
                       .mapping(["label": .text("This is a\nmultiline string\n"), "other": .text("clock")]))
        XCTAssertEqual(read("\n        label: >\n          folded\n          text\n\n          second paragraph\n        other: 1\n"),
                       .mapping(["label": .text("folded text\nsecond paragraph\n"), "other": .number(1)]))
        XCTAssertEqual(read("\n        label: \"This is a<br/>multiline string\"\n        other: \"clock\"\n"),
                       .mapping(["label": .text("This is a<br/>multiline string"), "other": .text("clock")]))
        XCTAssertEqual(read("title: Hello world\nconfig:\n  theme: dark\n  flowchart:\n    curve: linear\n    htmlLabels: false\n"),
                       .mapping(["title": .text("Hello world"),
                                 "config": .mapping(["theme": .text("dark"), "flowchart": .mapping(["curve": .text("linear"), "htmlLabels": .boolean(false)])])]))
        XCTAssertEqual(read("title: \"Quoted: title\"\ndisplayMode: compact\n"), .mapping(["title": .text("Quoted: title"), "displayMode": .text("compact")]))
        XCTAssertEqual(read("config:\n  themeVariables:\n    primaryColor: \"#ff0000\"\n    fontSize: 16px\n  look: handDrawn # trailing comment\n"),
                       .mapping(["config": .mapping(["themeVariables": .mapping(["primaryColor": .text("#ff0000"), "fontSize": .text("16px")]),
                                                     "look": .text("handDrawn")])]))
        XCTAssertEqual(read("list:\n  - a\n  - b: 1\n    c: 2\n  - [x, y]\nempty:\n"),
                       .mapping(["list": .list([.text("a"), .mapping(["b": .number(1), "c": .number(2)]), .list([.text("x"), .text("y")])]), "empty": .null]))
        XCTAssertEqual(read("key with spaces: plain value\nurl: http://example.com/a#b\n"),
                       .mapping(["key with spaces": .text("plain value"), "url": .text("http://example.com/a#b")]))
        XCTAssertEqual(read("multi: this is\n  continued on the next line\nnext: 1\n"),
                       .mapping(["multi": .text("this is continued on the next line"), "next": .number(1)]))
        XCTAssertEqual(read("a: {\n  b: 1,\n  c: [2,\n    3]\n}\nd: \"two\n  lines\"\ne: 5\n"),
                       .mapping(["a": .mapping(["b": .number(1), "c": .list([.number(2), .number(3)])]), "d": .text("two lines"), "e": .number(5)]))
        XCTAssertEqual(read("__proto__: 1\nb:\n  __proto__: {x: 1}\n"), .mapping(["__proto__": .number(1), "b": .mapping(["__proto__": .mapping(["x": .number(1)])])]))
    }

    func testScalarsAndDocumentsWithoutAMappingAgreeWithJavaScriptYAML() {
        XCTAssertEqual(read("a: 0x1f\nb: -12\nc: 1e3\nd: .5\ne: \"12\"\nf: True\ng: FALSE\nh: Null\n"),
                       .mapping(["a": .number(31), "b": .number(-12), "c": .number(1000), "d": .number(0.5), "e": .text("12"), "f": .boolean(true),
                                 "g": .boolean(false), "h": .null]))
        XCTAssertEqual(read("# only a comment\n"), .null)
        XCTAssertEqual(read(""), .null)
        XCTAssertEqual(read("just a scalar"), .text("just a scalar"))
        XCTAssertEqual(read("- 1\n- 2\n"), .list([.number(1), .number(2)]))
    }

    func testAbsurdNestingAndUnterminatedCollectionsAreRefusedQuickly() {
        XCTAssertNil(read("{ a: " + String(repeating: "[", count: 20_000) + " }"))
        XCTAssertNil(read("{ a: 1"))
        let started = Date()
        XCTAssertNil(read("a: {\n" + String(repeating: " b: 1,\n", count: 7_000)))
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "linear in the text's length")
    }
}
