/**
 * File: FlowchartModelParts.swift
 * -------------------------------
 * Layer: Core
 * Description: The lists of a flowchart's model as its reading fills them, made into the model when the reading ends:
 *              the box of what few flowcharts have is made only when one of its lists holds anything.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// A flowchart's model while it is read.
struct FlowchartModelParts {
    var nodes: [FlowchartNodeRecord] = []
    var edges: [FlowchartEdgeRecord] = []
    var groups: [FlowchartGroupRecord] = []
    var groupMembers: [Int32] = []
    var decodedLabels: [DiagramLabel] = []
    var assetAttributes: [FlowchartNodeAssetAttributes] = []
    var nodeStyles: [DiagramElementStyle?] = []
    var edgeStyles: [DiagramElementStyle?] = []
    var sideBytes: [UInt8] = []

    /// The model over `text`.
    func model(text: MermaidSourceText) -> FlowchartModel {
        let hasExtras = !groups.isEmpty || !decodedLabels.isEmpty || !assetAttributes.isEmpty || !nodeStyles.isEmpty || !edgeStyles.isEmpty
            || !sideBytes.isEmpty
        let extras = hasExtras ? FlowchartModelExtras(groups: groups, groupMembers: groupMembers, decodedLabels: decodedLabels,
                                                      assetAttributes: assetAttributes, nodeStyles: nodeStyles, edgeStyles: edgeStyles,
                                                      sideBytes: sideBytes) : nil
        return FlowchartModel(text: text, nodes: nodes, edges: edges, extras: extras)
    }

    /// The text of `range`, of the text read or of the side bytes.
    func string(_ range: MermaidTextRange, in bytes: FlowchartBytes) -> String {
        guard range.start < 0 else { return bytes.string(from: range.lowerBound, to: range.upperBound) }
        let start = Int(~range.start)
        return String(decoding: sideBytes[start..<start + range.count], as: UTF8.self)
    }

    /// The label a reference stands for, decoded now.
    func label(_ reference: FlowchartLabelReference, in bytes: FlowchartBytes) -> DiagramLabel? {
        switch reference.kind {
        case .none: nil
        case .line: DiagramLabel(lines: [string(reference.range, in: bytes)])
        case .plain: DiagramLabelDecoder.label(from: string(reference.range, in: bytes), form: .plain)
        case .markdown: DiagramLabelDecoder.label(from: string(reference.range, in: bytes), form: .markdown)
        case .decoded: decodedLabels[reference.range.lowerBound]
        }
    }

    /// `bytes` added to the side bytes, by their range there.
    mutating func sideRange(of bytes: [UInt8]) -> MermaidTextRange {
        let start = sideBytes.count
        sideBytes.append(contentsOf: bytes)
        return MermaidTextRange(start: Int(~Int32(start)), end: Int(~Int32(start)) + bytes.count)
    }
}
