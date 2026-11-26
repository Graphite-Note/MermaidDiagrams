/**
 * File: RequirementModel.swift
 * ----------------------------
 * Layer: Core
 * Description: A requirement diagram as its reading keeps it: flat records of byte ranges into its text (the
 *              requirements then the elements, the relations with the boxes they join, the classes), its style
 *              declarations as ranges of bytes the reading joined after the text, and each node's declarations and
 *              classes as runs of two shared lists.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// A requirement or an element as its reading keeps it: the ranges of its name and fields in the diagram's text, an empty
/// range for a field left out, and where its style declarations and its classes lie in the model's shared lists.
struct RequirementNodeRecord: Sendable {
    var name: MermaidTextRange
    /// A requirement's `id`, an element's `type`.
    var firstField: MermaidTextRange
    /// A requirement's `text`, an element's `docref`.
    var secondField: MermaidTextRange
    /// A requirement's kind; an element's is never read.
    var kind: RequirementKind
    var risk: RequirementRisk?
    var verificationMethod: RequirementVerificationMethod?
    /// Its declarations' numbers, `styleDeclarationCount` of the model's `numbers` from `firstStyleDeclaration`, in the
    /// order they were given.
    var firstStyleDeclaration: Int32 = 0
    var styleDeclarationCount: Int32 = 0
    /// The classes given to it after `default`, `classNameCount` of the model's `ranges` from `firstClassName`.
    var firstClassName: Int32 = 0
    var classNameCount: Int32 = 0

    var styleDeclarationIndices: Range<Int> { Int(firstStyleDeclaration)..<Int(firstStyleDeclaration + styleDeclarationCount) }
    var classNameIndices: Range<Int> { Int(firstClassName)..<Int(firstClassName + classNameCount) }
}

/// A relation by the ranges of the names written, and the boxes they name: the requirement of that name, else the element
/// (its index after every requirement), -1 for a name that names neither.
struct RequirementRelationRecord: Sendable {
    var kind: RequirementRelationKind
    var source: MermaidTextRange
    var target: MermaidTextRange
    var sourceBox: Int32
    var targetBox: Int32
}

/// A `classDef` class: its name's range, and its declarations' numbers, `declarationCount` of the model's `numbers`
/// from `firstDeclaration`.
struct RequirementStyleClassRecord: Sendable {
    var name: MermaidTextRange
    var firstDeclaration: Int32 = 0
    var declarationCount: Int32 = 0

    var declarationIndices: Range<Int> { Int(firstDeclaration)..<Int(firstDeclaration + declarationCount) }
}

/// A requirement diagram's content as flat records: ranges of `text` (the text its lexer read, then the bytes of each
/// style declaration's parts joined), the boxes in one list, the requirements first. A usual diagram is its text and two
/// lists of small records, nodes and relations, and no String.
struct RequirementModel: Sendable {
    /// The text the names, fields, class names and declarations are ranges of.
    var text: [UInt8] = []
    /// The requirements, then the elements: the boxes in their order.
    var nodes: [RequirementNodeRecord] = []
    var requirementCount = 0
    var relations: [RequirementRelationRecord] = []
    var styleClasses: [RequirementStyleClassRecord] = []
    /// The declarations, a declaration's number its place here, and the classes given to the nodes, each node's in one
    /// run.
    var ranges: [MermaidTextRange] = []
    /// The nodes' declarations by number, each node's in one run, then the classes' likewise.
    var numbers: [Int32] = []

    var boxCount: Int { nodes.count }
    var elementCount: Int { nodes.count - requirementCount }
    var requirements: ArraySlice<RequirementNodeRecord> { nodes[0..<requirementCount] }
    var elements: ArraySlice<RequirementNodeRecord> { nodes[requirementCount...] }

    func string(_ range: MermaidTextRange) -> String {
        precondition(range.start >= 0 && range.start <= range.end && range.upperBound <= text.count, "range outside the requirement diagram's text")
        return text.withUnsafeBufferPointer { bytes in String(decoding: UnsafeBufferPointer(rebasing: bytes[range.lowerBound..<range.upperBound]), as: UTF8.self) }
    }

    /// Declaration `number`'s text.
    func declaration(_ number: Int32) -> String {
        string(ranges[Int(number)])
    }

    /// Calls `body` with declaration `number`'s bytes, valid in `body` only.
    func withDeclarationBytes<Result>(_ number: Int32, _ body: (UnsafeBufferPointer<UInt8>) -> Result) -> Result {
        let range = ranges[Int(number)]
        precondition(range.start >= 0 && range.start <= range.end && range.upperBound <= text.count, "declaration outside its bytes")
        return text.withUnsafeBufferPointer { bytes in body(UnsafeBufferPointer(rebasing: bytes[range.lowerBound..<range.upperBound])) }
    }
}
