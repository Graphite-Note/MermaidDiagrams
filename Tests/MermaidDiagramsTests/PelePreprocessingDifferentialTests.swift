/**
 * File: PelePreprocessingDifferentialTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: The package's preprocessing of a diagram's text compared with Pele's own preprocess.ts on directives,
 *              line breaks, front matter and colour semicolons: refused or read, the title, the options and the text left.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// `pele-preprocessing.json`'s `preprocessing` (scripts/pele/preprocessing-recorder.ts): each text as Pele's
/// `preprocess` and `encodeEntities` left it, with its title and configuration, or the error.
final class PelePreprocessingDifferentialTests: XCTestCase {
    func testEveryTextIsPreprocessedAsPeleDoesIt() throws {
        let texts = try PeleResults.preprocessing().preprocessing
        XCTAssertGreaterThan(texts.count, 25)
        for text in texts {
            let name = text.source.debugDescription
            guard text.error == nil else {
                XCTAssertThrowsError(try MermaidDiagramReader.preprocessed(text.source), name)
                continue
            }
            // Front matter whose closing fence ends the text is none for Pele, whose text then starts with `---` and
            // names no type; the package reports it as unclosed.
            if (text.text ?? "").hasPrefix("---") {
                XCTAssertThrowsError(try MermaidDiagramReader.read(text.source, limits: .standard), name)
                continue
            }
            let (title, cursor) = try MermaidDiagramReader.preprocessed(text.source)
            XCTAssertEqual(title, text.title, name)
            XCTAssertEqual(Self.contentLines(Array(cursor.bytes[cursor.position...])), Self.contentLines(Array((text.text ?? "").utf8)), name)
            guard case .object(let configuration)? = text.config else { continue }
            for (section, value) in configuration {
                guard case .object(let options) = value else { continue }
                let mine = MermaidConfigurationOptions(section: section, in: cursor.sourceBytes).values
                XCTAssertEqual(mine, options.compactMapValues(\.optionValue), "\(name): \(section)")
            }
        }
    }

    /// The lines that hold more than white space, trimmed, without Pele's comment lines (`%%` and more, not `%%{`) and
    /// with Pele's entity placeholders read back: blanked and removed directives, removed comment lines and the trimmed
    /// start then read the same.
    private static func contentLines(_ bytes: [UInt8]) -> [String] {
        String(decoding: bytes, as: UTF8.self).components(separatedBy: "\n")
            .map { line in line.replacingOccurrences(of: "ﬂ°°", with: "#").replacingOccurrences(of: "ﬂ°", with: "#").replacingOccurrences(of: "¶ß", with: ";") }
            .map { line in line.trimmingCharacters(in: .whitespaces) }
            .filter { line in !line.isEmpty && !(line.hasPrefix("%%") && !line.hasPrefix("%%{") && line.count > 2) }
    }
}
