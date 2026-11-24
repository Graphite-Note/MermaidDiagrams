/**
 * File: ReferenceRequirementMeasurement.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 RequirementMeasurement kept as the reference the 0.8.0 layout is checked against:
 *              a requirement diagram's boxes and relations measured as Pele's requirement renderer measures them: the
 *              stereotype, the bold name and the rows of fields of each box, and each relation's text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The measurers of a requirement diagram's text: the names in the nodes' font in bold, and the stereotypes, fields,
/// values and relations' texts at seven eighths of it, as Pele's renderer measures them.
struct ReferenceRequirementTextMeasurers<Measurer: DiagramTextMeasuring> {
    let names: Measurer
    let body: Measurer
}

/// One box measured: its stereotype, its name and its rows of fields, the widest field name, the height of its head and
/// its size, the room its loops take kept apart (`layoutSize`).
struct ReferenceRequirementMeasuredBox {
    let isRequirement: Bool
    let stereotype: DiagramTextBlock
    let name: DiagramTextBlock
    let rows: [(key: DiagramTextBlock, value: DiagramTextBlock, height: CGFloat)]
    let keyWidth: CGFloat
    let headHeight: CGFloat
    let size: CGSize
    let style: DiagramElementStyle?
}

/// A relation that joins two boxes drawn: the relation it draws, its ends by box, and its text, `«kind»`.
struct ReferenceRequirementMeasuredEdge {
    let relationIndex: Int
    let kind: RequirementRelationKind
    let source: Int
    let target: Int
    let text: DiagramTextBlock

    var isSelfLoop: Bool { source == target }
    var isContainment: Bool { kind == .contains }
}

/// A requirement diagram measured, its boxes the requirements then the elements, as Mermaid orders them, and its edges the
/// relations whose two names are declared, in the order written: what the layout needs before it places anything.
struct ReferenceRequirementMeasurement {
    /// Pele's measurements: 14 points of padding across a box and 10 along it, 2 between rows, 12 between a row's name and
    /// value, boxes at least 120 points wide, names wrapped at 280 points and values at 240.
    static let paddingAcross: CGFloat = 14
    static let paddingAlong: CGFloat = 10
    static let rowGap: CGFloat = 2
    static let columnGap: CGFloat = 12
    static let minimumWidth: CGFloat = 120
    static let nameWrappingWidth: CGFloat = 280
    static let valueWrappingWidth: CGFloat = 240
    /// A text that is not wrapped: the stereotype, a field's name, a relation's text.
    static let unwrapped: CGFloat = 4000
    /// The room a relation's text takes beyond its lines.
    static let edgeTextRoom = CGSize(width: 12, height: 4)

    let boxes: [ReferenceRequirementMeasuredBox]
    let edges: [ReferenceRequirementMeasuredEdge]
    /// For each box, the indexes of its edges to itself, in their written order.
    let selfLoopEdgeIndices: [[Int]]

    init<Measurer: DiagramTextMeasuring>(diagram: RequirementDiagram, measurers: ReferenceRequirementTextMeasurers<Measurer>) {
        var styles = ReferenceRequirementStyleResolution()
        var boxes: [ReferenceRequirementMeasuredBox] = []
        var boxIndices: [String: Int] = [:]
        for requirement in diagram.requirements {
            if boxIndices[requirement.name] == nil { boxIndices[requirement.name] = boxes.count }
            let fields = [("ID", requirement.identifier), ("Text", requirement.text), ("Risk", requirement.risk?.rawValue ?? ""),
                          ("Verification", requirement.verificationMethod?.rawValue ?? "")]
            boxes.append(Self.box(isRequirement: true, kind: requirement.kind.rawValue, name: requirement.name, fields: fields,
                                  style: styles.style(of: requirement.styleDeclarations), measurers: measurers))
        }
        // A requirement and an element may share a name; relations then go to the requirement.
        for element in diagram.elements {
            if boxIndices[element.name] == nil { boxIndices[element.name] = boxes.count }
            boxes.append(Self.box(isRequirement: false, kind: "Element", name: element.name,
                                  fields: [("Type", element.type), ("Doc Ref", element.documentReference)],
                                  style: styles.style(of: element.styleDeclarations), measurers: measurers))
        }
        self.boxes = boxes
        var edges: [ReferenceRequirementMeasuredEdge] = []
        var selfLoops = [[Int]](repeating: [], count: boxes.count)
        for (relationIndex, relation) in diagram.relations.enumerated() {
            guard let source = boxIndices[relation.source], let target = boxIndices[relation.target] else { continue }
            if source == target { selfLoops[source].append(edges.count) }
            let text = DiagramTextBlock(label: DiagramLabel("«\(relation.kind.rawValue)»"), measurer: measurers.body, maximumWidth: Self.unwrapped)
            edges.append(ReferenceRequirementMeasuredEdge(relationIndex: relationIndex, kind: relation.kind, source: source, target: target, text: text))
        }
        self.edges = edges
        selfLoopEdgeIndices = selfLoops
    }

    /// A box's texts and size, as Pele's `draw` measures a node.
    private static func box<Measurer: DiagramTextMeasuring>(isRequirement: Bool, kind: String, name: String, fields: [(String, String)],
                                                            style: DiagramElementStyle?, measurers: ReferenceRequirementTextMeasurers<Measurer>) -> ReferenceRequirementMeasuredBox {
        let stereotype = DiagramTextBlock(label: DiagramLabelDecoder.label(from: "«\(kind)»", form: .plain), measurer: measurers.body,
                                          maximumWidth: unwrapped)
        let nameText = DiagramTextBlock(label: DiagramLabelDecoder.label(from: name, form: .markdown), measurer: measurers.names,
                                        maximumWidth: nameWrappingWidth)
        var rows: [(key: DiagramTextBlock, value: DiagramTextBlock, height: CGFloat)] = []
        var keyWidth: CGFloat = 0
        var valueWidth: CGFloat = 0
        var bodyHeight: CGFloat = 0
        for (key, value) in fields where !value.isEmpty {
            let keyText = DiagramTextBlock(label: DiagramLabel(key), measurer: measurers.body, maximumWidth: unwrapped)
            let valueText = DiagramTextBlock(label: DiagramLabelDecoder.label(from: value, form: .markdown), measurer: measurers.body,
                                             maximumWidth: valueWrappingWidth)
            let height = max(keyText.size.height, valueText.size.height)
            rows.append((keyText, valueText, height))
            keyWidth = max(keyWidth, keyText.size.width)
            valueWidth = max(valueWidth, valueText.size.width)
            bodyHeight += height + rowGap
        }
        if !rows.isEmpty { bodyHeight += 2 * paddingAlong - rowGap }
        let headHeight = 2 * paddingAlong + stereotype.size.height + nameText.size.height
        let width = max(minimumWidth, max(stereotype.size.width, nameText.size.width) + 2 * paddingAcross,
                        rows.isEmpty ? 0 : keyWidth + columnGap + valueWidth + 2 * paddingAcross)
        return ReferenceRequirementMeasuredBox(isRequirement: isRequirement, stereotype: stereotype, name: nameText, rows: rows, keyWidth: keyWidth,
                                      headHeight: headHeight, size: CGSize(width: width, height: headHeight + bodyHeight), style: style)
    }

    /// Each box's size in its rank: its own, grown on both sides across the flow by each of its loops, as Pele grows the
    /// node it lays out (`ReferenceRequirementSelfLoops.room`).
    func layoutSizes(flowIsVertical: Bool) -> [CGSize] {
        boxes.indices.map { box in
            var size = boxes[box].size
            for edgeIndex in selfLoopEdgeIndices[box] {
                let room = ReferenceRequirementSelfLoops.room(textSize: edges[edgeIndex].text.size, flowIsVertical: flowIsVertical)
                if flowIsVertical { size.width += 2 * room } else { size.height += 2 * room }
            }
            return size
        }
    }
}

/// The look each box's declarations give it, as Pele's `resolveStyle` gives it (each property's last value wins), each
/// distinct declaration read once.
struct ReferenceRequirementStyleResolution {
    private var read: [String: (style: DiagramElementStyle, isUnapplied: Bool)] = [:]
    private(set) var unappliedCount = 0

    mutating func style(of declarations: [String]) -> DiagramElementStyle? {
        guard !declarations.isEmpty else { return nil }
        var style = DiagramElementStyle()
        for declaration in declarations {
            let reading = read[declaration] ?? {
                let reading = DiagramElementStyle.reading(declaration)
                return (reading.style, reading.hasUnappliedDeclaration)
            }()
            read[declaration] = reading
            style = style.overridden(by: reading.style)
            if reading.isUnapplied { unappliedCount += 1 }
        }
        return style.isEmpty ? nil : style
    }
}
