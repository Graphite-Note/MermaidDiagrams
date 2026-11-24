/**
 * File: C4Diagram.swift
 * ---------------------
 * Layer: Core
 * Description: A Mermaid C4 diagram (`C4Context`, `C4Container`, `C4Component`, `C4Dynamic`, `C4Deployment`) as Pele's
 *              model holds it: its shapes, its boundaries nested in one another, its relations and its row counts, kept
 *              as small records of ranges of its text, its shapes, boundaries and relations made when read.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

/// A Mermaid C4 diagram as Pele's `C4Db` holds it once read. Shapes and boundaries are listed in the order first
/// written; an alias written again changes the element it names and keeps its place. The diagram keeps its text from
/// the keyword on and records of ranges of it (`C4ShapeRecord`, `C4BoundaryRecord`, `C4RelationRecord`), which the
/// layout reads; `shapes`, `boundaries` and `relations` make the value types with Strings each time they are read, and
/// two diagrams are equal when those and the other fields are.
public struct C4Diagram: Equatable, Sendable {
    /// The text from the keyword on, which the records' ranges index.
    let source: [UInt8]
    /// The texts the reading made (`C4DerivedText`) and the title set from the front matter.
    var derived: [UInt8]
    /// The keyword the diagram starts with.
    public internal(set) var level: C4DiagramLevel
    var titleText = C4Text.none
    var accessibilityDescriptionText = C4Text.none
    var shapeRecords: [C4ShapeRecord] = []
    /// The boundaries, the first the unnamed one that holds everything at the top level (`global`).
    var boundaryRecords: [C4BoundaryRecord]
    var relationRecords: [C4RelationRecord] = []
    /// Every named argument written where a field's place is, by the index the records keep.
    var namedArguments: [C4NamedArgumentRecord] = []
    /// The named arguments that set no field, each name once with its last value, in the order first written, by the
    /// index the records keep.
    var otherArgumentLists: [[C4NamedArgumentRecord]] = []
    /// How many names the aliases and relations' ends were interned into (`C4NameTable`).
    var nameCount = 0
    /// `UpdateLayoutConfig`'s first value: how many shapes a row of a boundary holds, 4 unless set to one or more.
    public internal(set) var shapesPerRow = 4
    /// Its second: how many boundaries a row holds, 2 unless set.
    public internal(set) var boundariesPerRow = 2

    init(source: [UInt8], level: C4DiagramLevel = .context) {
        self.source = source
        derived = C4DerivedText.words
        self.level = level
        let global = C4DerivedText.global
        boundaryRecords = [C4BoundaryRecord(element: C4ElementRecord(alias: global, label: global, type: global), deploymentNode: nil)]
    }

    /// `title …` or `accTitle: …` (which Mermaid's grammar hands to the title), else `title:` in the front matter.
    public internal(set) var title: String? {
        get { string(titleText) }
        set {
            guard let newValue else {
                titleText = .none
                return
            }
            titleText = appendDerived(newValue.utf8)
        }
    }

    /// `accDescr: …`, `accDescr { … }` or `accDescription …`.
    public var accessibilityDescription: String? { string(accessibilityDescriptionText) }

    public var shapes: [C4Shape] {
        shapeRecords.map { record in C4Shape(element: element(of: record.element), kind: record.kind) }
    }

    public var boundaries: [C4Boundary] {
        boundaryRecords.map { record in C4Boundary(element: element(of: record.element), deploymentNode: record.deploymentNode) }
    }

    public var relations: [C4Relation] {
        relationRecords.map(relation(of:))
    }

    /// The shape or else the boundary written with `alias`, as Pele's `getC4Shape` finds a relation's end.
    public func element(named alias: String) -> C4ElementReference? {
        if let index = shapeRecords.firstIndex(where: { shape in shape.element.aliasArgument < 0 && string(shape.element.alias) == alias }) {
            return .shape(index)
        }
        let boundaryIndex = boundaryRecords.indices.dropFirst().first { index in
            boundaryRecords[index].element.aliasArgument < 0 && string(boundaryRecords[index].element.alias) == alias
        }
        return boundaryIndex.map(C4ElementReference.boundary)
    }

    public static func == (lhs: C4Diagram, rhs: C4Diagram) -> Bool {
        lhs.level == rhs.level && lhs.title == rhs.title && lhs.accessibilityDescription == rhs.accessibilityDescription
            && lhs.shapesPerRow == rhs.shapesPerRow && lhs.boundariesPerRow == rhs.boundariesPerRow && lhs.shapes == rhs.shapes
            && lhs.boundaries == rhs.boundaries && lhs.relations == rhs.relations
    }

    // MARK: - Texts

    /// Calls `body` with the bytes of `text`, valid inside `body` only; none for a text not written.
    func withBytes<Result>(of text: C4Text, _ body: (UnsafeBufferPointer<UInt8>) throws -> Result) rethrows -> Result {
        guard !text.isNone else { return try body(UnsafeBufferPointer(start: nil, count: 0)) }
        if text.isDerived {
            let start = Int(text.start - C4Text.derivedOffset)
            return try derived.withUnsafeBufferPointer { bytes in try body(UnsafeBufferPointer(rebasing: bytes[start..<(start + text.count)])) }
        }
        return try source.withUnsafeBufferPointer { bytes in try body(UnsafeBufferPointer(rebasing: bytes[Int(text.start)..<Int(text.end)])) }
    }

    /// The text as a String, nil for a text not written.
    func string(_ text: C4Text) -> String? {
        guard !text.isNone else { return nil }
        return withBytes(of: text) { bytes in String(decoding: bytes, as: UTF8.self) }
    }

    /// The text as a String, empty for a text not written.
    func text(_ text: C4Text) -> String {
        string(text) ?? ""
    }

    /// Adds `bytes` to the derived bytes, and returns their text.
    mutating func appendDerived(_ bytes: some Collection<UInt8>) -> C4Text {
        let start = derived.count
        derived.append(contentsOf: bytes)
        return .derived(start: start, end: derived.count)
    }

    /// Whether two texts hold the same bytes.
    func sameBytes(_ first: C4Text, _ second: C4Text) -> Bool {
        guard first.count == second.count else { return false }
        return withBytes(of: first) { firstBytes in withBytes(of: second) { secondBytes in firstBytes.elementsEqual(secondBytes) } }
    }

    /// Whether `text` holds the bytes of `word`.
    func text(_ text: C4Text, is word: StaticString) -> Bool {
        guard text.count == word.utf8CodeUnitCount else { return false }
        return withBytes(of: text) { bytes in
            word.withUTF8Buffer { wordBytes in bytes.elementsEqual(wordBytes) }
        }
    }
}

/// The words a C4 diagram writes in itself, at the start of its derived bytes: the top level's `global`, a boundary
/// macro's kind (`ENTERPRISE`, `SYSTEM`, `CONTAINER`) and the types a boundary gets when none is written.
enum C4DerivedText {
    static let words = Array("globalENTERPRISESYSTEMCONTAINERnodecontainersystem".utf8)
    static let global = C4Text.derived(start: 0, end: 6)
    static let enterprise = C4Text.derived(start: 6, end: 16)
    static let systemWord = C4Text.derived(start: 16, end: 22)
    static let containerWord = C4Text.derived(start: 22, end: 31)
    static let node = C4Text.derived(start: 31, end: 35)
    static let container = C4Text.derived(start: 35, end: 44)
    static let system = C4Text.derived(start: 44, end: 50)
    /// An empty text, written: Pele's `""`.
    static let empty = C4Text.derived(start: 0, end: 0)
}
