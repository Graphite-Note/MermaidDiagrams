/**
 * File: FlatFlowchartModel.swift
 * ------------------------------
 * Layer: Core (design prototype, not for merging as is)
 * Description: A flowchart read into flat lists of small records whose names and texts are byte ranges of the text
 *              read, and the conversion to the present FlowchartDiagram that proves the two models equal.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// A range of the UTF-8 bytes of a flowchart's text, or of its side bytes when `start` is negative (`~start`).
struct FlatTextRange: Equatable {
    var start: Int32
    var end: Int32

    var length: Int { Int(end - start) }
}

/// The text of a node, an edge or a group: none, a range of the text that is the one line drawn, or a label that had
/// to be decoded (markup, a string joined with plain text, text beyond ASCII that Foundation trims), by its index.
struct FlatLabel: Equatable {
    /// `.none`, `.line` (the range is the label's single line, trimmed and unmarked) or `.decoded` (`start` indexes
    /// `FlatFlowchartDocument.decodedLabels`).
    enum Kind: UInt8 {
        case none
        case line
        /// Written text with markup, decoded when it is first needed (DiagramLabelDecoder, plain or Markdown form).
        case writtenPlain
        case writtenMarkdown
        case decoded
    }

    var kind: Kind
    var range: FlatTextRange

    static let none = FlatLabel(kind: .none, range: FlatTextRange(start: 0, end: 0))
}

struct FlatFlowchartNode {
    /// The node's name, a range of the text.
    var identifier: FlatTextRange
    var label: FlatLabel
    var shape: FlowchartNodeShape
    /// Index into the rare parts' `assetAttributes`, or -1.
    var assetIndex: Int32 = -1
}

struct FlatFlowchartEdge {
    var sourceIndex: Int32
    var targetIndex: Int32
    var minimumRankSpan: Int32
    var stroke: FlowchartEdgeStroke
    var sourceArrowhead: FlowchartArrowhead
    var targetArrowhead: FlowchartArrowhead
    var label: FlatLabel
}

struct FlatFlowchartSubgraph {
    /// The written identifier's range, when `generatedNumber` is -1.
    var writtenRange: FlatTextRange
    var generatedNumber: Int32
    var title: FlatLabel
    var direction: FlowchartDirection?
    var representingNodeIndex: Int32
    var isCollapsed: Bool
    /// Ranges of `FlatFlowchartDocument.subgraphMembers`.
    var nodeIndices: Range<Int32>
    var childSubgraphIndices: Range<Int32>
}

/// What few flowcharts have, kept apart so that the usual document is five words: groups, decoded labels, icons and
/// pictures, styles, titles. Made by the reading that needs it, never changed after the reading.
final class FlatFlowchartRareParts {
    var subgraphs: [FlatFlowchartSubgraph] = []
    var subgraphMembers: [Int32] = []
    var decodedLabels: [DiagramLabel] = []
    var assetAttributes: [FlowchartNodeAssetAttributes] = []
    /// Parallel to the nodes and edges when any statement styles the diagram, else empty.
    var nodeStyles: [DiagramElementStyle?] = []
    var edgeStyles: [DiagramElementStyle?] = []
    var title: String?
    var accessibilityTitle: String?
    var accessibilityDescription: String?
}

/// A flowchart as flat lists: two arrays for the usual diagram (nodes and edges), the text kept as the String it was
/// handed in when no preprocessing changed it.
struct FlatFlowchartDocument {
    var text: String
    var direction: FlowchartDirection = .topToBottom
    var nodes: [FlatFlowchartNode] = []
    var edges: [FlatFlowchartEdge] = []
    var unappliedStatementCount = 0
    var rareStorage: FlatFlowchartRareParts?

    var rare: FlatFlowchartRareParts {
        mutating get {
            if let rareStorage { return rareStorage }
            let made = FlatFlowchartRareParts()
            rareStorage = made
            return made
        }
    }

    func string(_ range: FlatTextRange) -> String {
        var text = text
        return text.withUTF8 { bytes in
            String(decoding: UnsafeBufferPointer(rebasing: bytes[Int(range.start)..<Int(range.end)]), as: UTF8.self)
        }
    }

    func label(_ label: FlatLabel) -> DiagramLabel? {
        switch label.kind {
        case .none: nil
        case .line: DiagramLabel(lines: [string(label.range)])
        case .writtenPlain: DiagramLabelDecoder.label(from: string(label.range), form: .plain)
        case .writtenMarkdown: DiagramLabelDecoder.label(from: string(label.range), form: .markdown)
        case .decoded: rareStorage!.decodedLabels[Int(label.range.start)]
        }
    }

    /// The present model, made from the flat one: what the prototype's output is compared with.
    func materialized() -> FlowchartDiagram {
        let rare = rareStorage
        let materializedNodes = nodes.indices.map { index in
            let node = nodes[index]
            var materialized = FlowchartNode(identifier: string(node.identifier), label: label(node.label) ?? DiagramLabel(lines: []), shape: node.shape)
            if node.assetIndex >= 0, let rare { materialized.assetAttributes = rare.assetAttributes[Int(node.assetIndex)] }
            if let rare, !rare.nodeStyles.isEmpty { materialized.style = rare.nodeStyles[index] }
            return materialized
        }
        let materializedEdges = edges.indices.map { index in
            let edge = edges[index]
            return FlowchartEdge(sourceIndex: Int(edge.sourceIndex), targetIndex: Int(edge.targetIndex), stroke: edge.stroke, sourceArrowhead: edge.sourceArrowhead,
                                 targetArrowhead: edge.targetArrowhead, minimumRankSpan: Int(edge.minimumRankSpan), label: label(edge.label),
                                 style: rare.flatMap { rare in rare.edgeStyles.isEmpty ? nil : rare.edgeStyles[index] })
        }
        let members = rare?.subgraphMembers ?? []
        let materializedSubgraphs = (rare?.subgraphs ?? []).map { group in
            FlowchartSubgraph(identifier: group.generatedNumber >= 0 ? "subGraph\(group.generatedNumber)" : string(group.writtenRange),
                              title: label(group.title) ?? DiagramLabel(lines: []),
                              nodeIndices: members[Int(group.nodeIndices.lowerBound)..<Int(group.nodeIndices.upperBound)].map(Int.init),
                              childSubgraphIndices: members[Int(group.childSubgraphIndices.lowerBound)..<Int(group.childSubgraphIndices.upperBound)].map(Int.init),
                              direction: group.direction, representingNodeIndex: group.representingNodeIndex >= 0 ? Int(group.representingNodeIndex) : nil,
                              isCollapsed: group.isCollapsed)
        }
        return FlowchartDiagram(direction: direction, nodes: materializedNodes, edges: materializedEdges, subgraphs: materializedSubgraphs, title: rare?.title,
                                accessibilityTitle: rare?.accessibilityTitle, accessibilityDescription: rare?.accessibilityDescription,
                                unappliedStatementCount: unappliedStatementCount)
    }
}
