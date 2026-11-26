/**
 * File: TypeReaderSpeedTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: Checks the C4, agent flow, quadrant chart, tree view and kanban readers that read bytes where they read
 *              UTF-16 code units, characters or Foundation's searches: Foundation's trimming and search done on bytes
 *              against Foundation itself, and the models those readers make of their documentation examples, cut and
 *              mixed with white space beyond ASCII, combining marks and quotation marks, against a digest of the models
 *              the readers made before.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 26/11/2026
 */

import Foundation
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark
import XCTest

final class TypeReaderSpeedTests: XCTestCase {
    /// Pieces that sit at the edges of what the byte readers tell apart: white space beyond ASCII, a combining mark and a
    /// mark that joins the character after it, line breaks, quotation marks doubled or not, backslashes, comments and
    /// the punctuation the grammars read.
    static let pieces = [" ", "\t", "  ", "\u{A0}", "\u{3000}", "\u{2028}", "\u{2029}", "\u{FEFF}", "\u{85}", "\u{200B}", "\u{301}",
                                 "\u{600}", "\r\n", "\n", "\r", "_", "''", "'", "\"", "\\", " #", "#", "é", "\u{1F600}", "├── ", "│   ", ":",
                                 ",", "{", "}", "(", ")", "[", "]", "Icons", "0.5", "--> ", "<", ">", "^", "v", "x", "%%", "@{", "a", "Z", "1"]

    /// Texts made of the pieces, the same at every run.
    private static func generatedTexts(count: Int, longest: UInt64, seed: UInt64) -> [String] {
        var state = seed
        var texts = pieces + [""]
        for _ in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            var text = ""
            for _ in 0..<Int((state >> 40) % longest) {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                text += pieces[Int((state >> 33) % UInt64(pieces.count))]
            }
            texts.append(text)
        }
        return texts
    }

    func testTrimmingOnBytesTrimsAsFoundationTrims() {
        for text in Self.generatedTexts(count: 30_000, longest: 7, seed: 0x5EED_0101) {
            XCTAssertEqual(FoundationTextOnBytes.trimmed(text, includingLineBreaks: false), text.trimmingCharacters(in: .whitespaces),
                           text.debugDescription)
            XCTAssertEqual(FoundationTextOnBytes.trimmed(text, includingLineBreaks: true), text.trimmingCharacters(in: .whitespacesAndNewlines),
                           text.debugDescription)
        }
    }

    func testASearchOnBytesFindsTheCharacterFoundationFinds() {
        for text in Self.generatedTexts(count: 30_000, longest: 7, seed: 0x5EED_0102) {
            for character in ["_", "<", ">", "^", "v"] {
                XCTAssertEqual(FoundationTextOnBytes.contains(text, character: character.utf8.first ?? 0), text.contains(character),
                               "\(character) in \(text.debugDescription)")
            }
        }
    }

    func testAKanbanValueWithoutALineFeedCharacterIsNotFolded() {
        for text in Self.generatedTexts(count: 20_000, longest: 7, seed: 0x5EED_0103) where !text.contains("\n") {
            XCTAssertEqual(KanbanFlowReader.folded(text), text, text.debugDescription)
        }
    }

    /// The tree view's box-drawing pass is skipped for a text without a box character's bytes, so each of the eight
    /// must open it alone: a branch alone makes its line an entry one level down, a dash alone makes its line go, and a
    /// vertical bar alone leaves the lines as written (Pele converts only when a line other than bars holds one).
    func testEachBoxCharacterAloneOpensTheBoxDrawingPass() throws {
        for branch in ["└", "┗", "├", "┣"] {
            let lines = try TreeViewBoxDrawingReader.lines(after: 1, in: "treeView-beta\nroot\n\(branch) child\n")
            XCTAssertEqual(lines.map(\.text), ["treeView-beta", "root", "    child", ""], branch)
        }
        for dash in ["─", "━"] {
            let lines = try TreeViewBoxDrawingReader.lines(after: 1, in: "treeView-beta\nroot\n\(dash)\(dash)\nchild\n")
            XCTAssertEqual(lines.map(\.text), ["treeView-beta", "root", "child", ""], dash)
        }
        for bar in ["│", "┃"] {
            let lines = try TreeViewBoxDrawingReader.lines(after: 1, in: "treeView-beta\nroot\n\(bar)\nchild\n")
            XCTAssertEqual(lines.map(\.text), ["treeView-beta", "root", bar, "child", ""], bar)
        }
    }

    /// The digests of the models (or the errors) the readers made, by corpus, before they read bytes (origin/main
    /// abdf545): a change that alters what a reader makes of any of these texts changes its digest.
    private static let modelDigests: [String: String] = [
        "agentflow-docs": "1c026460da6a1333",
        "agentflow-reference": "915fa0c73d973db2",
        "c4-docs": "db509a58f6f6f479",
        "kanban-docs": "b41092c3d237a9cc",
        "quadrant-docs": "f5c6e78830cc0ba7",
        "treeview-docs": "4160f6aba98dfd6d",
        "block-docs": "1ec701be11e8d78d",
    ]

    func testTheReadersMakeTheModelsTheyMadeOfEveryExampleCutAndMixed() throws {
        var digests: [String: String] = [:]
        for corpus in Self.modelDigests.keys.sorted() {
            var digest = Self.offsetBasis
            for text in try Self.variants(of: PeleResults.sources(ofCorpus: corpus), seed: 0x5EED_0104) {
                let model: String
                do {
                    model = Self.canonicalDescription(of: try MermaidDiagramReader.read(text, limits: .standard))
                } catch {
                    model = "refused: " + Self.canonicalDescription(of: error)
                }
                digest = Self.digest(model + "\u{0}", from: digest)
            }
            digests[corpus] = String(digest, radix: 16)
        }
        print("type reader model digests: \(digests.sorted { first, second in first.key < second.key })")
        XCTAssertEqual(digests, Self.modelDigests)
    }

    /// White space other than the space: ASCII's, JavaScript's beyond it, and what only Foundation or neither holds white.
    static let blanks = ["\t", "\u{A0}", "\u{3000}", "\u{2028}", "\u{FEFF}", "\u{85}", "\u{200B}", "\u{2007}", "\u{0B}", " \u{301}"]

    /// Each text, then copies of it with a piece put in at a character boundary, copies cut at one, and copies with their
    /// spaces and line breaks made other white space.
    static func variants(of sources: [String], seed: UInt64) -> [String] {
        var state = seed
        var variants: [String] = []
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return bound > 0 ? Int((state >> 33) % UInt64(bound)) : 0
        }
        for source in sources {
            variants.append(source)
            let characters = Array(source)
            for _ in 0..<24 {
                var mixed = characters
                for _ in 0...next(3) {
                    mixed.insert(contentsOf: pieces[next(pieces.count)], at: next(mixed.count + 1))
                }
                variants.append(String(mixed))
            }
            for _ in 0..<4 { variants.append(String(characters.prefix(next(characters.count + 1)))) }
            // Every space within a line after the first, or every other one, made another white space character, and the line
            // breaks other ones.
            for blank in blanks {
                variants.append(replacingInnerSpaces(of: source, with: blank, everyOther: false, firstOfLineOnly: false))
                variants.append(replacingInnerSpaces(of: source, with: blank, everyOther: true, firstOfLineOnly: false))
                variants.append(replacingInnerSpaces(of: source, with: blank, everyOther: false, firstOfLineOnly: true))
            }
            for lineBreak in ["\r\n", "\r", "\u{2028}", " \n", "\n\u{A0}"] { variants.append(source.replacingOccurrences(of: "\n", with: lineBreak)) }
        }
        return variants
    }

    /// The text with each space after the first character of a line but the first made `blank`, every other one, or the
    /// first of each line only (the one after a statement's keyword).
    static func replacingInnerSpaces(of source: String, with blank: String, everyOther: Bool, firstOfLineOnly: Bool) -> String {
        var replaced = ""
        var isFirstLine = true
        var isLineStart = true
        var isReplaced = false
        var isLineReplaced = false
        for character in source {
            if character == "\n" {
                isFirstLine = false
                isLineStart = true
                isLineReplaced = false
            } else if character == " ", !isFirstLine, !isLineStart, !(firstOfLineOnly && isLineReplaced) {
                isLineReplaced = true
                isReplaced.toggle()
                if !everyOther || isReplaced || firstOfLineOnly {
                    replaced += blank
                    continue
                }
            } else if character != " " {
                isLineStart = false
            }
            replaced.append(character)
        }
        return replaced
    }

    /// A description of a value that does not depend on the order a dictionary or a set holds its entries in.
    static func canonicalDescription(of value: Any) -> String {
        // A block diagram is a view over its flat model: it is described by the values it gives, field by field in the
        // order 0.7.0 stored them, so that its digest is the one of the values 0.7.0's reader made.
        if let block = value as? BlockDiagram {
            let fields: [(String, Any)] = [("title", block.title as Any), ("blocks", block.blocks), ("edges", block.edges), ("classes", block.classes),
                                           ("padding", block.padding as Any)]
            return "BlockDiagram(" + fields.map { label, field in "\(label): \(canonicalDescription(of: field))" }.joined(separator: ", ") + ")"
        }
        // A use case diagram too, its fields in the order 0.7.0 stored them.
        if let useCase = value as? UseCaseDiagram {
            let fields: [(String, Any)] = [("actors", useCase.actors), ("useCases", useCase.useCases), ("systemBoundaries", useCase.systemBoundaries),
                                           ("relationships", useCase.relationships), ("notes", useCase.notes), ("jsonNodes", useCase.jsonNodes),
                                           ("classDefinitions", useCase.classDefinitions), ("direction", useCase.direction), ("title", useCase.title as Any),
                                           ("accessibilityTitle", useCase.accessibilityTitle), ("accessibilityDescription", useCase.accessibilityDescription),
                                           ("nodeSpacing", useCase.nodeSpacing as Any), ("rankSpacing", useCase.rankSpacing as Any)]
            return "UseCaseDiagram(" + fields.map { label, field in "\(label): \(canonicalDescription(of: field))" }.joined(separator: ", ") + ")"
        }
        // A requirement diagram too, its fields in the order 0.7.0 stored them.
        if let requirement = value as? RequirementDiagram {
            let fields: [(String, Any)] = [("direction", requirement.direction), ("requirements", requirement.requirements), ("elements", requirement.elements),
                                           ("relations", requirement.relations), ("styleClasses", requirement.styleClasses),
                                           ("title", requirement.title as Any), ("accessibilityTitle", requirement.accessibilityTitle as Any),
                                           ("accessibilityDescription", requirement.accessibilityDescription as Any)]
            return "RequirementDiagram(" + fields.map { label, field in "\(label): \(canonicalDescription(of: field))" }.joined(separator: ", ") + ")"
        }
        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .dictionary:
            let entries = mirror.children.map { entry in
                Mirror(reflecting: entry.value).children.map { part in canonicalDescription(of: part.value) }.joined(separator: ": ")
            }
            return "[" + entries.sorted().joined(separator: ", ") + "]"
        case .set:
            return "{" + mirror.children.map { member in canonicalDescription(of: member.value) }.sorted().joined(separator: ", ") + "}"
        case .optional:
            return mirror.children.first.map { wrapped in canonicalDescription(of: wrapped.value) } ?? "nil"
        case .collection:
            return "[" + mirror.children.map { element in canonicalDescription(of: element.value) }.joined(separator: ", ") + "]"
        case .enum:
            guard let payload = mirror.children.first else { return String(describing: value) }
            return "\(payload.label ?? "")(\(canonicalDescription(of: payload.value)))"
        case .struct, .class, .tuple:
            let fields = mirror.children.map { field in "\(field.label ?? ""): \(canonicalDescription(of: field.value))" }
            return "\(mirror.subjectType)(" + fields.joined(separator: ", ") + ")"
        default:
            return String(reflecting: value)
        }
    }

    static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325

    /// FNV-1a over the UTF-8 bytes, 64 bits, carried on from `digest`.
    static func digest(_ text: String, from digest: UInt64) -> UInt64 {
        var hash = digest
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return hash
    }
}
