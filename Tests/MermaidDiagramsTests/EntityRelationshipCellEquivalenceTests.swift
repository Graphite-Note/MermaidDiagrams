/**
 * File: EntityRelationshipCellEquivalenceTests.swift
 * --------------------------------------------------
 * Layer: Tests
 * Description: Attribute rows whose cells take each of the layout's ways of measuring them, laid out by the entity
 *              relationship layout and by the 0.7.0 engine kept as the reference, alike to the bit: types with a `?`
 *              written right after them or after spaces, with pairs of `~`, in backticks beyond ASCII; lists of no key
 *              to eight keys (packed and kept apart); comments plain, wrapped, with markup, entity codes, line breaks,
 *              `~` and bytes beyond ASCII; the same rows set on a diagram in code; and texts mixing them at random.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams
import XCTest

final class EntityRelationshipCellEquivalenceTests: XCTestCase {
    private static let types = ["string", "string?", "string ?", "`a b`", "`é`", "`x\\ny`", "int[]", "*star", "décimal"]
    private static let names = ["id", "name", "`two words`", "naïve", "a-b.c(1)", "_hidden"]
    private static let keys = ["", "PK", "pk, fk", "PK, FK, UK", "PK, PK, FK, UK", "PK, FK, UK, PK, FK", "UK, UK, UK, UK, UK, UK, UK, UK"]
    private static let comments = [
        "", "\"plain words\"", "\"\"", "\"a comment long enough to be wrapped where it passes the width of two hundred and sixty points across the box\"",
        "\"*emphasis* and __strong__\"", "\"a &amp; b &#35; c\"", "\"one<br>two<br/>three\"", "\"accents é and ü\"",
        "\"tab\tinside\"", "\"inner_underscore_words\"", "\"`code`\"",
    ]

    /// Rows with pairs of `~`, each alone on its line where the run holding them reads to the line's last `~`.
    private static let rowsWithTildes = ["    List~int~ items", "    Map~K,V~? lookup PK \"plain\"", "    string List~int~ FK", "    string x \"List~int~ here\"",
                                         "    Set~List~int~~ nested UK", "    string ~tilde \"a ~ alone\""]

    /// Every type, name, keys and comment, one row each, in an entity of their own, laid out as written, across, and in a group.
    func testEveryWayOfMeasuringACellMatchesTheReferenceBitForBit() throws {
        var rows: [String] = Self.rowsWithTildes
        for (index, type) in Self.types.enumerated() {
            for (keyIndex, keys) in Self.keys.enumerated() {
                let comment = Self.comments[(index + keyIndex) % Self.comments.count]
                rows.append("    \(type) \(Self.names[(index + keyIndex) % Self.names.count]) \(keys) \(comment)")
            }
        }
        var comparedCount = 0
        for prefix in ["erDiagram\n", "erDiagram\ndirection LR\n", "erDiagram\nsubgraph g [Group]\n"] {
            for chunk in stride(from: 0, to: rows.count, by: 7) {
                let block = rows[chunk..<min(chunk + 7, rows.count)].joined(separator: "\n")
                let suffix = prefix.contains("subgraph") ? "\nend\n" : "\n"
                let source = prefix + "  E\(chunk) {\n" + block + "\n  }\n  E\(chunk) ||--o{ F : \"has *many*\"\n  F {\n" + block + "\n  }" + suffix
                guard case .entityRelationship(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
                comparedCount += 1
                XCTAssertNil(EntityRelationshipLayoutEquivalenceTests.firstDifference(diagram, limits: .standard), source)
                // The same rows set in code: their texts as they are, their comments decoded already.
                var built = diagram
                built.entities = diagram.entities
                XCTAssertNil(EntityRelationshipLayoutEquivalenceTests.firstDifference(built, limits: .standard), "set in code:\n\(source)")
            }
        }
        XCTAssertGreaterThan(comparedCount, 24)
    }

    /// Random rows of those pieces, many to an entity, several entities and relationships to a diagram.
    func testRandomRowsMatchTheReferenceBitForBit() {
        var state: UInt64 = 0xCE11_5EED
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        var comparedCount = 0
        for _ in 0..<300 {
            var source = "erDiagram\n"
            let entityCount = 1 + next(4)
            for entity in 0..<entityCount {
                source += "  E\(entity) {\n"
                for _ in 0..<(1 + next(6)) {
                    source += "    \(Self.types[next(Self.types.count)]) \(Self.names[next(Self.names.count)]) \(Self.keys[next(Self.keys.count)]) "
                        + "\(Self.comments[next(Self.comments.count)])\n"
                }
                source += "  }\n"
                if entity > 0 { source += "  E\(next(entity)) ||--o{ E\(entity) : \(Self.comments[next(Self.comments.count)].isEmpty ? "x" : "\"r\"")\n" }
            }
            guard case .entityRelationship(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            comparedCount += 1
            XCTAssertNil(EntityRelationshipLayoutEquivalenceTests.firstDifference(diagram, limits: .standard), source)
        }
        XCTAssertGreaterThan(comparedCount, 250)
    }
}
