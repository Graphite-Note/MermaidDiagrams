/**
 * File: ConfigurationReadersCharacterFuzzTests.swift
 * --------------------------------------------------
 * Layer: Tests
 * Description: Checks the byte readers of front matter, directives, colors and style declarations against the readers
 *              they stand in for on texts made character by character from the punctuation each grammar gives a
 *              meaning to, rather than from whole tokens: what the byte reader reads is what the reference reads.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams

final class ConfigurationReadersCharacterFuzzTests: XCTestCase {
    /// A seeded generator of texts drawn from an alphabet, one character at a time.
    private struct CharacterTexts {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }

        mutating func text(from alphabet: [String], length: Int) -> String {
            (0..<below(length + 1)).map { _ in alphabet[below(alphabet.count)] }.joined()
        }
    }

    private static let yamlAlphabet = ["a", "b", "k", "1", "0", ".", "-", "+", "_", " ", " ", "  ", ":", ": ", "#", " #", "'", "\"", "\\", "\n", "\n",
                                       "\n  ", "\n    ", "?", "&", "*", "!", "|", ">", "{", "}", "[", "]", ",", "%", "@", "`", "~", "e", "x", "n", "t",
                                       "title", "config", "null", "true", "False", "---", "- ", "\t", "é"]

    func testYAMLTextsMadeCharacterByCharacterAreReadAsTheReferenceReadsThem() {
        var texts = CharacterTexts(seed: 0xC4A2_0001)
        var found: [String] = []
        var readOnBytes = 0
        for _ in 0..<40_000 {
            // Most texts start as a mapping does, so that the byte reader reads far into them.
            let start = ["title: ", "config:\n  ", "a: ", "'k': ", ""][texts.below(5)]
            let yaml = start + texts.text(from: Self.yamlAlphabet, length: 24)
            let bytes = Array(yaml.utf8)
            if MermaidYAMLTreeReader.tree(of: bytes) != nil { readOnBytes += 1 }
            let expected = MermaidYAMLDocument.value(of: bytes)
            let read = MermaidYAMLTree.read(bytes).map { tree in tree.value(of: MermaidYAMLTree.root) }
            let isSame = switch (read, expected) {
            case (nil, nil): true
            case (let read?, let expected?): DirectiveValueComparison.isIdentical(read, expected)
            default: false
            }
            if !isSame { found.append("\(String(describing: read)), expected \(String(describing: expected)) for \(yaml.debugDescription)") }
            if found.count == 5 { break }
        }
        XCTAssertEqual(found, [])
        XCTAssertGreaterThan(readOnBytes, 4_000, "too few texts read on bytes to compare")
    }

    private static let jsonAlphabet = ["{", "}", "[", "]", ",", ":", "\"", "\"a\"", "\"k\"", " ", "\n", "\t", "\r", "\u{0B}", "0", "1", "9", "-", ".",
                                       "e", "E", "+", "true", "false", "null", "t", "\\", "\\\"", "\\u0041", "é", "\u{0}", "'", "x", "%", "}%%"]

    func testDirectiveContentsMadeCharacterByCharacterAreReadAsJSONDecoderReadsThem() {
        var texts = CharacterTexts(seed: 0xC4A2_0002)
        var found: [String] = []
        var readOnBytes = 0
        for _ in 0..<40_000 {
            let start = ["{\"themeVariables\": {", "{", " {\"a\":", ""][texts.below(4)]
            let content = start + texts.text(from: Self.jsonAlphabet, length: 16) + ["}}", "}", "", "]}"][texts.below(4)]
            let expected = ReferenceMermaidConfigurationOptions.directiveObject(content)
            let read = Array(content.utf8).withUnsafeBufferPointer { buffer in MermaidDirectiveConfiguration.object(in: buffer) }
            let trimmed = Array(content.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
            if trimmed.withUnsafeBufferPointer({ buffer in MermaidConfigurationJSONReader.object(in: buffer) }) != nil { readOnBytes += 1 }
            let isSame = switch (read, expected) {
            case (nil, nil): true
            case (let read?, let expected?): DirectiveValueComparison.isIdentical(.object(read), .object(expected))
            default: false
            }
            if !isSame { found.append("\(String(describing: read)), expected \(String(describing: expected)) for \(content.debugDescription)") }
            if found.count == 5 { break }
        }
        XCTAssertEqual(found, [])
        XCTAssertGreaterThan(readOnBytes, 300, "too few contents read on bytes to compare")
    }

    private static let colorAlphabet = ["#", "#", "f", "F", "0", "9", "a", "g", "r", "g", "b", "rgb(", "rgba(", "(", ")", ",", " ", "\t", "/", "%", ".",
                                        "-", "+", "e", "1", "5", "255", "none", "red", "Grey", "transparent", "\u{A0}", "é", "\n", "!important", "!"]

    func testColorsMadeCharacterByCharacterAreReadAsBefore() {
        var texts = CharacterTexts(seed: 0xC4A2_0003)
        var found: [String] = []
        for _ in 0..<60_000 {
            let text = texts.text(from: Self.colorAlphabet, length: 10)
            let read = DiagramColor(cssText: text)
            let expected = ReferenceDiagramColor.color(cssText: text)
            let isSame = switch (read, expected) {
            case (nil, nil): true
            case (let read?, let expected?):
                [read.red, read.green, read.blue, read.alpha].map(\.bitPattern) == [expected.red, expected.green, expected.blue, expected.alpha].map(\.bitPattern)
            default: false
            }
            if !isSame { found.append("\(String(describing: read)), expected \(String(describing: expected)) for \(text.debugDescription)") }
            let themeColor = DiagramThemeColor(cssText: text)
            let trimmed = String(JavaScriptWhitespace.trimmed(Substring(text)))
            let isSafe = DiagramThemeColor.isSafe(trimmed)
            if themeColor?.cssText != (isSafe ? trimmed : nil) || themeColor?.expression != (isSafe ? DiagramThemeColorExpression.read(Substring(trimmed)) : nil) {
                found.append("theme color \(String(describing: themeColor)) for \(text.debugDescription)")
            }
            if found.count >= 5 { break }
        }
        XCTAssertEqual(found, [])
    }

    private static let declarationAlphabet = ["fill", "stroke", "color", "stroke-width", "stroke-dasharray", "FILL", ":", ":", ",", ",", " ", "\t", "#",
                                              "f", "0", "3", "rgb(", "(", ")", "px", "5", ".", "-", "!important", "!", "\u{A0}", ";", "none", "red"]

    func testDeclarationsMadeCharacterByCharacterAreReadAsBefore() {
        var texts = CharacterTexts(seed: 0xC4A2_0004)
        var found: [String] = []
        for _ in 0..<40_000 {
            let list = texts.text(from: Self.declarationAlphabet, length: 14)
            let read = DiagramElementStyle.reading(list)
            let expected = ReferenceDiagramElementStyle.reading(list)
            if read.hasUnappliedDeclaration != expected.hasUnappliedDeclaration || !DiagramElementStyleBytesTests.isIdentical(read.style, expected.style) {
                found.append("\(read), expected \(expected) for \(list.debugDescription)")
            }
            if found.count == 5 { break }
        }
        XCTAssertEqual(found, [])
    }

    /// Diagrams at the standard source limit whose front matter or directives are shaped to make the byte readers
    /// work hardest (the longest keys a mapping compares, blank lines a scalar looks past, the deepest mappings and
    /// collections, then text left to the reference readers) are prepared with their SVG in bounded time, their pie
    /// options those the frozen reader reads.
    func testHostileConfiguredDiagramsArePreparedInBoundedTime() {
        let limit = MermaidDiagramLimits.standard.maximumSourceBytes
        let sharedPrefix = String(repeating: "k", count: 300)
        let longKeys = (0..<128).map { index in "\(sharedPrefix)\(String(format: "%03d", index)): 1" }
        let blankLines = (0..<80).map { index in "k\(index): v" + String(repeating: "\n   ", count: 90) }
        let deepMappings = (0..<33).map { depth in String(repeating: " ", count: depth) + "k\(depth):" } + [String(repeating: " ", count: 33) + "k: 1"]
        let wideMapping = (0..<129).map { index in "k\(index): '\(index)'" }
        let deepJSON = String(repeating: "[", count: 31) + String(repeating: "1,", count: 4_000) + "1" + String(repeating: "]", count: 31)
        var sources = [longKeys, blankLines, deepMappings, wideMapping].map { lines in
            "---\nconfig:\n  pie:\n" + lines.map { line in "    " + line }.joined(separator: "\n") + "\n---\npie\n\"A\": 1"
        }
        sources.append("%%{init: {\"pie\": {\"textPosition\": 0.5, \"list\": \(deepJSON)}}}%%\npie\n\"A\": 1")
        sources.append(String(repeating: "%%{init: {\"pie\": {\"textPosition\": 0.5}}}%%\n", count: limit / 48) + "pie\n\"A\": 1")
        let typography = DiagramSceneSamples.typography
        let start = ContinuousClock.now
        for source in sources {
            XCTAssertLessThanOrEqual(source.utf8.count, limit)
            XCTAssertNoThrow(try MermaidDiagramPreparation.prepare(source: source, typography: typography).svgDocument)
            guard let frontEnd = try? MermaidFrontEnd.read(source), let (_, reference) = try? ReferenceMermaidReader.preprocessed(source) else {
                XCTFail("not read: \(source.prefix(60).debugDescription)")
                continue
            }
            let read = ReferenceMermaidConfigurationOptions(MermaidConfigurationOptions(section: "pie", in: MermaidTextCursor(frontEnd)))
            XCTAssertEqual(read, ReferenceMermaidConfigurationOptions(section: "pie", in: reference.sourceBytes), String(source.prefix(60)))
        }
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(10))
    }
}
