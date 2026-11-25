/**
 * File: RequirementDiagramBuilder.swift
 * -------------------------------------
 * Layer: Core
 * Description: Builds a requirement diagram from its statements as Mermaid's database and Pele's `db.ts` do, its names
 *              interned from the text's bytes: bodies' fields held until their requirement or element, a name declared
 *              twice kept as first declared, styles and classes copied onto the nodes, every count bounded.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

/// Builds a requirement diagram as Mermaid's `requirementDb` does. The grammar reports a body's fields before the
/// requirement or element they belong to, so the parser holds them until it comes; they are dropped if it was declared
/// before. A requirement or element counts as a node of the limits and a relation as an edge, each before it is made.
/// Applying a class copies its declarations onto each node, so a short text can ask for hundreds of millions of copies:
/// the declarations copied and the classes given, together, are bounded by Pele's million. Names are byte ranges of the
/// text, interned (`GraphDiagramNameTable`), so that each is compared as 0.7.0's String dictionaries compared it.
struct RequirementDiagramBuilder {
    /// Pele's `MAX_STYLE_COPIES`.
    static let maximumStyleCopyCount = 1_000_000

    var diagram = RequirementDiagram()
    let limits: MermaidDiagramLimits
    let bytes: UnsafeBufferPointer<UInt8>
    private var names: GraphDiagramNameTable
    /// What each name number names, by the number.
    var namedByNumber: [RequirementNamed] = []
    /// The number of the name `default`, the class every node has, or -1 while it is not written.
    var defaultClassNumber = -1
    /// The nodes given each class other than `default`, as lists through `classMembers`, from `RequirementNamed.firstMember`.
    var classMembers: [RequirementClassMember] = []
    /// Each node and class given, as `RequirementClassMember.key`, so that a node given a class twice is listed once.
    var givenClasses: Set<UInt64> = []
    var styleCopyCount = 0

    init(limits: MermaidDiagramLimits, bytes: UnsafeBufferPointer<UInt8>, isASCII: Bool) {
        self.limits = limits
        self.bytes = bytes
        names = GraphDiagramNameTable(isASCII: isASCII)
        let nameCount = min(bytes.count / Self.bytesPerName + 4, Self.mostReserved)
        names.reserveCapacity(nameCount)
        namedByNumber.reserveCapacity(nameCount)
    }

    /// About the bytes a name takes with what is written around it.
    private static let bytesPerName = 24
    /// The most names made room for at once; a longer text's lists grow.
    private static let mostReserved = 2_048

    /// Why a statement could not be applied, which the parser reports at the statement's line.
    enum Refusal: Error, Equatable {
        case tooManyNodes, tooManyEdges, tooManyStyleCopies
    }

    /// The number of the name `range` spells, with what it names.
    mutating func number(of range: Range<Int>) -> Int {
        let (number, isNew) = names.intern(bytes, MermaidTextRange(start: range.lowerBound, end: range.upperBound))
        if isNew {
            namedByNumber.append(RequirementNamed())
            if defaultClassNumber < 0, Self.spellsDefault(bytes, range) { defaultClassNumber = number }
        }
        return number
    }

    /// Whether `range` spells `default`: in a text beyond ASCII too, only these bytes make a String equal to it.
    private static func spellsDefault(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Bool {
        range.count == 7 && bytes[range].elementsEqual("default".utf8)
    }

    func string(_ range: Range<Int>) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self)
    }

    mutating func setDirection(_ direction: FlowchartDirection) {
        diagram.direction = direction
    }

    mutating func setAccessibilityTitle(_ text: String) {
        diagram.accessibilityTitle = text
    }

    /// The description with the whitespace after each line break left out, as Mermaid's `/\n\s+/g` replaces it.
    mutating func setAccessibilityDescription(_ text: String) {
        let bytes = Array(text.utf8)
        var kept: [UInt8] = []
        var position = 0
        while position < bytes.count {
            kept.append(bytes[position])
            position = bytes[position] == MermaidByte.newline ? JavaScriptWhitespace.endOfRun(in: bytes, from: position + 1) : position + 1
        }
        diagram.accessibilityDescription = String(decoding: kept, as: UTF8.self)
    }

    /// The requirement named, with the fields held for it, unless it was declared before.
    mutating func addRequirement(named name: Range<Int>, kind: RequirementKind, fields: RequirementBodyFields) throws(Refusal) {
        let number = number(of: name)
        guard namedByNumber[number].requirementIndex < 0 else { return }
        guard diagram.requirements.count + diagram.elements.count < limits.maximumNodeCount else { throw .tooManyNodes }
        namedByNumber[number].requirementIndex = Int32(diagram.requirements.count)
        diagram.requirements.append(RequirementDiagramRequirement(name: string(name), kind: kind, identifier: fields.identifier.map(string) ?? "",
                                                                  text: fields.text.map(string) ?? "", risk: fields.risk,
                                                                  verificationMethod: fields.verificationMethod, styleDeclarations: [],
                                                                  classNames: ["default"]))
    }

    mutating func addElement(named name: Range<Int>, fields: RequirementBodyFields) throws(Refusal) {
        let number = number(of: name)
        guard namedByNumber[number].elementIndex < 0 else { return }
        guard diagram.requirements.count + diagram.elements.count < limits.maximumNodeCount else { throw .tooManyNodes }
        namedByNumber[number].elementIndex = Int32(diagram.elements.count)
        diagram.elements.append(RequirementDiagramElement(name: string(name), type: fields.type.map(string) ?? "",
                                                          documentReference: fields.documentReference.map(string) ?? "", styleDeclarations: [],
                                                          classNames: ["default"]))
    }

    mutating func addRelation(_ kind: RequirementRelationKind, from source: Range<Int>, to target: Range<Int>) throws(Refusal) {
        guard diagram.relations.count < limits.maximumEdgeCount else { throw .tooManyEdges }
        diagram.relations.append(RequirementDiagramRelation(kind: kind, source: string(source), target: string(target)))
    }
}

/// What a name names: the requirement, the element and the style class of that name, each -1 for none, and the first
/// of the nodes given the class it names, -1 for none.
struct RequirementNamed {
    var requirementIndex: Int32 = -1
    var elementIndex: Int32 = -1
    var styleClassIndex: Int32 = -1
    var firstMember: Int32 = -1
}

/// A node given a class: a requirement's index, or an element's index with its bits inverted, and the next node given
/// the same class, -1 for none.
struct RequirementClassMember {
    var node: Int32
    var next: Int32

    /// The node and the class's name number as one key.
    static func key(node: Int32, classNumber: Int) -> UInt64 {
        UInt64(UInt32(bitPattern: node)) << 32 | UInt64(UInt32(truncatingIfNeeded: classNumber))
    }
}

/// The fields of a body as held for its requirement or element: the first of each written, as Mermaid applies a right
/// recursive grammar's fields last to first. Texts are byte ranges of the text.
struct RequirementBodyFields {
    var identifier: Range<Int>?
    var text: Range<Int>?
    var risk: RequirementRisk?
    var verificationMethod: RequirementVerificationMethod?
    var type: Range<Int>?
    var documentReference: Range<Int>?
}
