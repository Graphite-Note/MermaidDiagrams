/**
 * File: UseCaseJSONTests.swift
 * ----------------------------
 * Layer: Tests
 * Description: A use case diagram's JSON is read in the order its keys are written and refused where it is not JSON,
 *              as Pele's port of Mermaid's usecaseJson.spec.ts checks it, and flattened to rows as getData does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class UseCaseJSONTests: XCTestCase {
    private func read(_ text: String) throws -> UseCaseJSONValue {
        try UseCaseJSONReader.read(Array(text.utf16)[...])
    }

    func testPointersRecordTheOrderOfNestedObjectsAndObjectsInArrays() throws {
        let value = try read("""
            {
              "a/b": {
                "items": [
                  { "~name": "first", "id": 1 },
                  { "id": 2, "details": { "enabled": true } }
                ]
              },
              "last": null
            }
            """)
        XCTAssertEqual(value.propertyOrder, ["": ["a/b", "last"], "/a~1b": ["items"], "/a~1b/items/0": ["~name", "id"],
                                             "/a~1b/items/1": ["id", "details"], "/a~1b/items/1/details": ["enabled"]])
    }

    func testIntegerLikeKeysKeepTheirWrittenOrder() throws {
        XCTAssertEqual(try read("{\"10\":\"ten\",\"2\":\"two\",\"1\":\"one\",\"plain\":true}").propertyOrder, ["": ["10", "2", "1", "plain"]])
    }

    func testAKeyWrittenTwiceKeepsItsFirstPlaceAndItsLastValue() throws {
        let value = try read("{\n \"entry\": { \"discarded\": { \"old\": true } },\n \"tail\": 0,\n \"entry\": { \"second\": 2, \"first\": 1, \"\\u0073econd\": 3 }\n}")
        XCTAssertEqual(value.propertyOrder, ["": ["entry", "tail"], "/entry": ["second", "first"]])
        XCTAssertEqual(UseCaseJSONRow.rows(of: value).map(\.value), ["3", "1", "0"])
    }

    func testEmptyContainersAndStringsAreValues() throws {
        let value = try read("{\"emptyObject\":{},\"emptyArray\":[],\"emptyString\":\"\"}")
        XCTAssertEqual(value.propertyOrder, ["": ["emptyObject", "emptyArray", "emptyString"], "/emptyObject": []])
        let strings = try read(#"{"text":"a } and { plus [brackets] and \"quotes\"","nested":{"value":"{\"key\": 1}"}}"#)
        XCTAssertEqual(UseCaseJSONRow.rows(of: strings).map(\.value), [#"a } and { plus [brackets] and "quotes""#, #"{"key": 1}"#])
    }

    func testMalformedJSONIsRefusedAtTheLineAndColumnOfItsFirstWrongCharacter() {
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\njson P@{\n  \"valid\": true,\n  \"invalid\":\n}")?.line, 5)
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\njson P@{\n  \"valid\": true,\n  \"invalid\":\n}")?.problem, .invalidJSON(column: 1))
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\njson Payload@{\"key\":,}")?.problem, .invalidJSON(column: 21))
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\njson P@{\r\n  \"key\": true,\r\n}")?.line, 4)
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\njson P@{\r\n  \"key\": true,\r\n}")?.problem, .invalidJSON(column: 1))
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\njson P@{\"a\": tru}")?.problem, .invalidJSON(column: 17))
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\njson P@{\"a\": \"x\\q\"}")?.problem, .invalidJSON(column: 17))
    }

    /// The whole text is read before its JSON: a syntax error after a JSON table that is not JSON wins.
    func testTheTextIsReadBeforeItsJSON() {
        guard case .unexpectedToken? = UseCaseReading.problem("usecase-beta\njson P@{\"a\":}\nactor A B")?.problem else { return XCTFail("not the grammar") }
    }

    func testRowsFlattenEachLeafDepthFirstInTheOrderWritten() throws {
        let value = try read(#"{"2": "second", "1": "first", "colors": ["Red", "Green"], "items": [{ "name": "A" }, {}], "empty": {}, "list": [], "n": 29.95, "big": 1e21, "z": null, "t": false}"#)
        let rows = UseCaseJSONRow.rows(of: value)
        XCTAssertEqual(rows.map(\.key), ["2", "1", "colors", "", "items[0].name", "items[1]", "empty", "list", "n", "big", "z", "t"])
        XCTAssertEqual(rows.map(\.accessibleKey)[3], "colors")
        XCTAssertEqual(rows.map(\.value), ["second", "first", "Red", "Green", "A", "{}", "{}", "[]", "29.95", "1e+21", "null", "false"])
        XCTAssertEqual(UseCaseJSONRow.rows(of: try read("{}")), [UseCaseJSONRow(key: "", accessibleKey: "", value: "{}")])
        XCTAssertEqual(UseCaseJSONRow.rows(of: try read(#"{"m": [1, {"a": 2}]}"#)).map(\.key), ["m[0]", "m[1].a"])
    }

    /// Pele's worst cases for JSON: nesting kept on a stack of its own, and a key written thousands of times.
    func testDeepAndWideJSONIsReadWithoutRecursion() throws {
        let deep = try read(String(repeating: "{\"a\":", count: 12_000) + "1" + String(repeating: "}", count: 12_000))
        XCTAssertEqual(UseCaseJSONRow.rows(of: deep).count, 1)
        let arrays = try read("{\"a\":" + String(repeating: "[", count: 20_000) + String(repeating: "]", count: 20_000) + "}")
        XCTAssertEqual(UseCaseJSONRow.rows(of: arrays).count, 1)
        let repeated = try read("{" + String(repeating: "\"k\":{\"a\":{}},", count: 8_000) + "\"z\":0}")
        XCTAssertEqual(repeated.root.keys, ["k", "z"])
        XCTAssertNotEqual(deep, arrays)
    }
}
