/**
 * File: SankeyDiagramBuilder.swift
 * --------------------------------
 * Layer: Core
 * Description: Builds a Sankey diagram row by row as Mermaid's database does, finding each row's nodes by the bytes
 *              of their names in an ASCII text and making a node's name only the first time a row names it.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// Builds a Sankey diagram row by row as Mermaid's database does: a node is made the first time a row names it.
/// Nodes are bounded by `MermaidDiagramLimits.maximumNodeCount` and links by `maximumEdgeCount`.
///
/// In a text of ASCII bytes with no doubled quotation mark, a name is the range of its bytes, found in a table of
/// byte ranges (`GraphDiagramNameTable`), and its String is made once, for its node: two names are the same exactly
/// when their bytes are, as for the Strings Mermaid's database compares. Otherwise names are Strings, compared as
/// Swift compares them (canonical equivalence), as 0.7.0 compared them.
struct SankeyDiagramBuilder {
    private(set) var diagram = SankeyDiagram()
    private var names: GraphDiagramNameTable
    private let limits: MermaidDiagramLimits

    /// `namesAreBytes`: the names are handed over as ranges of ASCII bytes.
    init(limits: MermaidDiagramLimits, namesAreBytes: Bool) {
        self.limits = limits
        names = GraphDiagramNameTable(isASCII: namesAreBytes)
    }

    mutating func addLink(from source: SankeyFieldName, to target: SankeyFieldName, value: Double?,
                          in bytes: UnsafeBufferPointer<UInt8>) throws(MermaidDiagramReadError) {
        guard diagram.links.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        let sourceIndex = try nodeIndex(source, in: bytes)
        let targetIndex = try nodeIndex(target, in: bytes)
        diagram.links.append(SankeyLink(sourceIndex: sourceIndex, targetIndex: targetIndex, value: value))
    }

    private mutating func nodeIndex(_ name: SankeyFieldName, in bytes: UnsafeBufferPointer<UInt8>) throws(MermaidDiagramReadError) -> Int {
        let (number, isNew) = name.text.map { text in names.intern(text) } ?? names.intern(bytes, name.range)
        guard isNew else { return number }
        guard diagram.nodes.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        let text = name.text ?? String(decoding: UnsafeBufferPointer(rebasing: bytes[name.range.lowerBound..<name.range.upperBound]), as: UTF8.self)
        diagram.nodes.append(SankeyNode(name: text))
        return number
    }
}

/// A node's name as a row writes it: the range of its bytes, without the spaces at either end, and the name made as a
/// String when names are compared as Strings.
struct SankeyFieldName {
    let range: MermaidTextRange
    let text: String?
}
