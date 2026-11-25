/**
 * File: AgentFlowPlainMetadataTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The one-line metadata read on bytes against the YAML reader: every `@{ … }` body of the agent flow
 *              corpora and of Pele's compatibility tests, and random bodies of plain entries and of what YAML treats
 *              apart, each read alike or left to the YAML reader.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class AgentFlowPlainMetadataTests: XCTestCase {
    func testEveryBodyOfTheCorporaIsReadAsTheYAMLReaderReadsIt() throws {
        let sources = try PeleResults.sources(ofCorpus: "agentflow-docs") + PeleResults.sources(ofCorpus: "agentflow-reference")
            + PeleResults.compatInputs().filter { $0.key.hasPrefix("agentflow/") }.flatMap(\.value)
        var bodies: [String] = []
        for source in sources {
            var rest = Substring(source)
            while let open = rest.range(of: "@{") {
                rest = rest[open.upperBound...]
                guard let close = rest.firstIndex(of: "}") else { break }
                bodies.append(String(rest[..<close]))
                rest = rest[close...]
            }
        }
        XCTAssertGreaterThan(bodies.count, 100)
        let readOnBytes = Self.assertReadAlike(bodies)
        XCTAssertGreaterThan(readOnBytes, bodies.count / 3)
    }

    func testRandomBodiesAreReadAsTheYAMLReaderReadsThem() {
        let plainKeys = ["shape", "label", "view", "k_1", "a-b", "_x", "Shape"]
        let otherKeys = ["true", "Null", "FALSE", "__proto__", "constructor", "1", "x y", "é", "key:", ""]
        let plainValues = ["input", "task", "collapsed", "1", "1e3", "0x1f", "0o7", "0b2", "0b", "0x", "1.5", "1_000", "9007199254740993", "_", "true", "True",
                           "TRUE", "false", "null", "Null", "NULL", "nan", "inf", "hello world", "a.b", "a  b", "1-2", "a-", "x+y", "NaN", "Infinity"]
        let quotedValues = ["\"collapsed\"", "\"https://api.github.com\"", "\"city :: String\"", "\"a, b\"", "\" spaced \"", "\"\"", "\"x\\\"y\"",
                            "\"t\\ty\"", "\"é\"", "\"\u{7F}\"", "\"a\" b", "\"a\",", "\"#c\"", "\"'q'\"", "\"{x}\""]
        let otherValues = ["-2", "+3", ".5", "-", "~", "a:b", "\"q\"", "'q'", "[x]", "{y}", "#c", "a #c", "x\ty", ".inf", "-.Inf", ".nan", "a,b", "é", "",
                           "?", "-x", "&a", "*a", "!t", "|", ">", "%", "@", "`"]
        let separators = [", ", ",", " , ", "  ,", ",  "]
        var state: UInt64 = 0x5EED
        func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        var bodies: [String] = []
        for _ in 0..<20_000 {
            var body = String(repeating: " ", count: below(3))
            for entry in 0..<(1 + below(4)) {
                if entry > 0 { body += separators[below(separators.count)] }
                let key = below(5) == 0 ? otherKeys[below(otherKeys.count)] : plainKeys[below(plainKeys.count)]
                let value = switch below(6) {
                case 0: otherValues[below(otherValues.count)]
                case 1, 2: quotedValues[below(quotedValues.count)]
                default: plainValues[below(plainValues.count)]
                }
                body += key + (below(5) == 0 ? [":", ":  ", " : "][below(3)] : ": ") + value
            }
            body += below(4) == 0 ? ["", " ", "  ", ",", ", ", "\r"][below(6)] : ""
            bodies.append(body)
        }
        XCTAssertGreaterThan(Self.assertReadAlike(bodies), 2_000)
    }

    /// Reads each body both ways where the byte reader takes it, fails for each that differs, and returns how many it took.
    private static func assertReadAlike(_ bodies: [String], file: StaticString = #filePath, line: UInt = #line) -> Int {
        var taken = 0
        var mismatches = 0
        for body in bodies {
            guard let plain = AgentFlowPlainMetadata.value(of: body) else { continue }
            taken += 1
            let expected = AgentFlowMetadataReading.yamlValue(of: body)
            if !Self.same(plain, expected) {
                mismatches += 1
                if mismatches <= 5 { XCTFail("\(body.debugDescription): \(plain) where YAML reads \(String(describing: expected))", file: file, line: line) }
            }
        }
        XCTAssertEqual(mismatches, 0, file: file, line: line)
        return taken
    }

    /// Equal, a NaN equal to a NaN.
    private static func same(_ first: SequenceAttributeValue, _ second: SequenceAttributeValue?) -> Bool {
        guard case .mapping(let firstFields) = first, case .mapping(let secondFields)? = second, firstFields.count == secondFields.count else {
            return first == second
        }
        return firstFields.allSatisfy { key, value in
            guard let other = secondFields[key] else { return false }
            if case .number(let number) = value, case .number(let otherNumber) = other { return number.bitPattern == otherNumber.bitPattern }
            return value == other
        }
    }
}
