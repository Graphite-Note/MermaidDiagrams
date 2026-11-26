/**
 * File: C4LayoutEquivalenceTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The C4 layout against the frozen 0.7.0 one (Reference/ReferenceC4Layout, laying out what the frozen
 *              0.7.0 reader reads): every corpus input, Pele's compatibility inputs, generated, random and changed
 *              texts and hostile ones, as written, tight in four columns and fitted, in three faces, on many threads at
 *              once, compared field by field and to the bit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class C4LayoutEquivalenceTests: XCTestCase {
    /// Faces of 16 and 12 points, whose advances add up exactly, and of 12.8, whose do not, so that wrapping takes the
    /// full path.
    static var typographies: [DiagramTypography] {
        [16, 12, 12.8].map { size in DiagramTypography(font: DiagramFont(postScriptName: nil, size: CGFloat(size))) }
    }
    static let columnWidths: [CGFloat?] = [nil, 180, 320, 520]

    func testEveryInputOfTheCorporaAndOfPelesCompatibilityTestsIsLaidOutAsTheReferenceLaysItOut() throws {
        let sources = try OutputDigest.corpora().flatMap(\.sources) + PeleResults.compatInputs().sorted { $0.key < $1.key }.flatMap(\.value)
        XCTAssertGreaterThanOrEqual(Self.assertLaidOutAlike(sources, typographies: Self.typographies), 27)
    }

    func testGeneratedDiagramsAreLaidOutAsTheReferenceLaysThemOut() {
        var sources: [String] = []
        for shapeCount in [1, 10, 40] {
            for boundaryCount in [0, 3, 20] {
                sources.append(C4Corpus.generated(shapeCount: shapeCount, boundaryCount: boundaryCount, relationCount: shapeCount * 2))
            }
        }
        let typographies = Self.typographies
        // A diagram of more boundaries than shapes leaves relations to boundaries it has no shape in: three are refused.
        XCTAssertGreaterThanOrEqual(Self.assertLaidOutAlike(sources, typographies: [typographies[0], typographies[2]]), 6)
    }

    func testRandomAndChangedTextsAreLaidOutAsTheReferenceLaysThemOut() throws {
        var generator = C4RandomTexts(seed: 31)
        var sources = (0..<1_500).map { _ in generator.text() }
        let originals = try C4Corpus.documentationExamples() + PeleResults.compatInputs().filter { $0.key.hasPrefix("c4/") }.sorted { $0.key < $1.key }
            .flatMap(\.value)
        for round in 0..<1_500 { sources.append(generator.mutated(originals[round % originals.count])) }
        var diagrams = RandomC4Diagrams(seed: 17)
        for _ in 0..<400 { sources.append(diagrams.text()) }
        let typographies = Self.typographies
        XCTAssertGreaterThan(Self.assertLaidOutAlike(sources, typographies: [typographies[0], typographies[2]]), 700)
    }

    func testHostileTextsAreLaidOutAsTheReferenceLaysThemOut() {
        for (name, text) in C4HostileTexts.named {
            XCTAssertEqual(Self.assertLaidOutAlike([text], typographies: Self.typographies), 1, "\(name) is not read as C4")
        }
    }

    func testLayoutsOnManyThreadsAtOnceAreTheReferenceLayouts() throws {
        let sources = try C4Corpus.documentationExamples() + C4HostileTexts.all.prefix(4)
        let mismatches = ManagedCounter()
        let typographies = Self.typographies
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            let typography = typographies[thread % typographies.count]
            for round in 0..<6 {
                for source in sources where Self.difference(source, typography: typography, columnWidth: Self.columnWidths[(thread + round) % 4]) != nil {
                    mismatches.increment()
                }
            }
        }
        XCTAssertEqual(mismatches.value, 0)
    }

    /// Lays out each source both ways in every face and column and fails for each that differs; returns how many the
    /// reference read as C4.
    @discardableResult
    static func assertLaidOutAlike(_ sources: [String], typographies: [DiagramTypography], file: StaticString = #filePath, line: UInt = #line) -> Int {
        var checked = 0
        var mismatches = 0
        for source in sources {
            guard case .c4? = try? ReferenceC4Reading.read(source, limits: .standard) else { continue }
            checked += 1
            for typography in typographies {
                for columnWidth in columnWidths {
                    guard let difference = difference(source, typography: typography, columnWidth: columnWidth) else { continue }
                    mismatches += 1
                    if mismatches <= 5 { XCTFail("\(difference) (size \(typography.font.size), column \(String(describing: columnWidth))):\n\(source.prefix(600))",
                                                 file: file, line: line) }
                }
            }
        }
        XCTAssertEqual(mismatches, 0, file: file, line: line)
        return checked
    }

    /// What differs between the two layouts of `source`: as written when `columnWidth` is nil, else tight in that column
    /// and fitted to it; nil when nothing does.
    static func difference(_ source: String, typography: DiagramTypography, columnWidth: CGFloat?) -> String? {
        guard case .c4(let expected)? = try? ReferenceC4Reading.read(source, limits: .standard) else { return nil }
        guard case .c4(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { return "not read as C4" }
        let pairs: [(String, Result<ReferenceC4Layout, C4LayoutError>, Result<C4Layout, C4LayoutError>)]
        if let columnWidth {
            pairs = [
                ("tight", Result { () throws(C4LayoutError) in try ReferenceC4LayoutEngine.tightLayout(expected, typography: typography, columnWidth: columnWidth) },
                 Result { () throws(C4LayoutError) in try C4LayoutEngine.tightLayout(diagram, typography: typography, columnWidth: columnWidth) }),
                ("fitted", Result { () throws(C4LayoutError) in try ReferenceC4LayoutEngine.layout(expected, typography: typography, fittingWidth: columnWidth) },
                 Result { () throws(C4LayoutError) in try C4LayoutEngine.layout(diagram, typography: typography, fittingWidth: columnWidth) }),
            ]
        } else {
            pairs = [("as written", Result { () throws(C4LayoutError) in try ReferenceC4LayoutEngine.layout(expected, typography: typography) },
                      Result { () throws(C4LayoutError) in try C4LayoutEngine.layout(diagram, typography: typography) })]
        }
        for (name, reference, laidOut) in pairs {
            switch (reference, laidOut) {
            case (.failure(let expectedError), .failure(let error)):
                if expectedError != error { return "\(name): error \(error) where the reference throws \(expectedError)" }
            case (.success(let expectedLayout), .success(let layout)):
                if let field = differingField(expectedLayout, layout) { return "\(name): \(field) differs" }
            case (.failure(let expectedError), .success): return "\(name): laid out where the reference throws \(expectedError)"
            case (.success, .failure(let error)): return "\(name): throws \(error) where the reference lays out"
            }
        }
        return nil
    }

    /// The first field of the layout that differs from the reference's, or nil.
    static func differingField(_ expected: ReferenceC4Layout, _ layout: C4Layout) -> String? {
        if expected.size != layout.size { return "size" }
        if expected.font != layout.font { return "font" }
        if expected.title != layout.title { return "title" }
        if expected.boundaries != layout.boundaries { return "boundaries" }
        if expected.shapes != layout.shapes { return "shapes" }
        if expected.relations != layout.relations { return "relations" }
        return nil
    }
}

/// A count several threads add to.
final class ManagedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() { lock.withLock { count += 1 } }
}

/// C4 texts made to stretch the layout: long lines, many items, deep nesting, every kind of text a label measures.
enum C4HostileTexts {
    static var named: [(String, String)] {
        [("long labels", longLabels), ("many shapes", manyShapes), ("deep nesting", deepNesting), ("every text form", everyTextForm),
         ("shared names", sharedNames), ("loops and pairs", loopsAndPairs)]
    }

    static var all: [String] { named.map { _, text in text } }

    /// Labels, descriptions and technologies thousands of bytes long, with and without spaces, within the standard limit
    /// of 50,000 bytes.
    static var longLabels: String {
        let words = Array(repeating: "word", count: 700).joined(separator: " ")
        let unbroken = String(repeating: "x", count: 3_000)
        return """
        C4Context
        title \(words)
        Person(a, "\(words)", "\(unbroken)")
        System(b, "\(unbroken)", "\(words)")
        Container(c, "c", "\(words)", "\(unbroken)")
        Rel(a, b, "\(words)", "\(unbroken)")
        Rel(b, c, "\(unbroken)", "\(words)")
        """
    }

    /// A hundred and twenty shapes in rows of two and two hundred relations.
    static var manyShapes: String {
        var lines = ["C4Container", "UpdateLayoutConfig($c4ShapeInRow=\"2\", $c4BoundaryInRow=\"1\")"]
        for index in 0..<120 { lines.append("Container(s\(index), \"Shape \(index)\", \"tech\", \"Description of shape \(index)\")") }
        for index in 0..<200 { lines.append("Rel(s\(index % 120), s\((index * 7 + 3) % 120), \"r\(index)\")") }
        return lines.joined(separator: "\n")
    }

    /// Forty boundaries, each inside the one before, a shape in each and relations across the levels.
    static var deepNesting: String {
        var lines = ["C4Deployment"]
        for depth in 0..<40 { lines.append(String(repeating: " ", count: depth) + "Deployment_Node(n\(depth), \"Node \(depth)\", \"Kind\", \"Level \(depth)\") {") }
        for depth in 0..<40 { lines.append("Container(c\(depth), \"C \(depth)\")") }
        for _ in 0..<40 { lines.append("}") }
        for depth in 0..<39 { lines.append("Rel(c\(depth), n\(depth + 1), \"down\")") }
        return lines.joined(separator: "\n")
    }

    /// Texts with breaks, entities, tags, emphasis, white space alone, bytes past ASCII, and the derived texts a reading
    /// writes (a boundary's default type, a title from the front matter).
    static var everyTextForm: String {
        """
        ---
        title: From the front matter &amp; more
        ---
        C4Dynamic
        Enterprise_Boundary(e, "Enterprise &lt;one&gt;") {
          System_Boundary(s, " ") {
            Person(p, "<br>", "line<br/>two\\nthree", $sprite="person")
            System(q, "**bold** and _em_", "Ünïcödé 中文 text", $tags="db,queue")
            SystemQueue(r, "a\\Nb", "<b>tag</b> &#x41; &#65;", $shape="queue")
          }
          Container_Boundary(k, "") {
            ContainerDb(d, "   ", "   ")
          }
        }
        Rel(p, q, "Read & write to", "3: select * from users")
        Rel(q, r, " ", "<br>")
        Rel(r, d, "", "")
        BiRel(d, p, "x<br>y<br>z", "Ünïcödé")
        UpdateElementStyle(q, $bgColor="#202020", $fontColor="red", $borderColor="blue")
        UpdateRelStyle(p, q, $textColor="green", $lineColor="orange", $offsetX="40", $offsetY="-20")
        """
    }

    /// Aliases that differ only past ASCII, or in spellings Swift holds equal, and boundaries named as shapes.
    static var sharedNames: String {
        """
        C4Context
        Boundary(b1, "B") {
          Person(caf\u{E9}, "composed")
          Person(cafe\u{301}, "decomposed")
          System(\u{212A}, "Kelvin")
          System(K, "K")
        }
        Boundary(b2, "B2") {
          System(b1, "named as the boundary")
        }
        Rel(caf\u{E9}, cafe\u{301}, "one")
        Rel(\u{212A}, K, "two")
        Rel(b1, b2, "three")
        Rel(b2, K, "four")
        """
    }

    /// Relations from a shape to itself and pairs running opposite ways between the same two shapes.
    static var loopsAndPairs: String {
        """
        C4Context
        System(a, "A")
        System(b, "B")
        System(c, "C")
        System(d, "D")
        System(e, "E")
        Rel(a, a, "self")
        Rel(a, b, "there")
        Rel(b, a, "back")
        Rel(a, c, "across the row", "tech")
        Rel(c, a, "and back")
        Rel(a, e, "down the column")
        Rel(e, a, "up again")
        BiRel(b, d, "both")
        Rel_Back(d, b, "back")
        """
    }
}
