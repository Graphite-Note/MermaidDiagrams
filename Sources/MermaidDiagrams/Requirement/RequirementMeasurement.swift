/**
 * File: RequirementMeasurement.swift
 * ----------------------------------
 * Layer: Core
 * Description: A requirement diagram's boxes and relations measured as Pele's requirement renderer measures them: the
 *              stereotype, the bold name and the rows of fields of each box, and each relation's text.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics

/// The measurers of a requirement diagram's text: the names in the nodes' font in bold, and the stereotypes, fields,
/// values and relations' texts at seven eighths of it, as Pele's renderer measures them.
struct RequirementTextMeasurers<Measurer: DiagramTextMeasuring> {
    let names: Measurer
    let body: Measurer
}

/// One box measured: its stereotype, its name and its rows of fields, the widest field name, the height of its head and
/// its size, the room its loops take kept apart (`layoutSize`).
struct RequirementMeasuredBox {
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
struct RequirementMeasuredEdge {
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
struct RequirementMeasurement {
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

    let boxes: [RequirementMeasuredBox]
    let edges: [RequirementMeasuredEdge]
    /// For each box, the indexes of its edges to itself, in their written order.
    let selfLoopEdgeIndices: [[Int]]

    init<Measurer: DiagramTextMeasuring>(diagram: RequirementDiagram, measurers: RequirementTextMeasurers<Measurer>) {
        var styles = RequirementStyleResolution()
        var texts = RequirementConstantTexts(measurers: measurers)
        var boxes: [RequirementMeasuredBox] = []
        boxes.reserveCapacity(diagram.requirements.count + diagram.elements.count)
        var boxIndices: [String: Int] = [:]
        boxIndices.reserveCapacity(diagram.requirements.count + diagram.elements.count)
        for requirement in diagram.requirements {
            if boxIndices[requirement.name] == nil { boxIndices[requirement.name] = boxes.count }
            let fields: [(RequirementFieldKey, String)] = [(.identifier, requirement.identifier), (.text, requirement.text),
                                                           (.risk, requirement.risk?.rawValue ?? ""),
                                                           (.verification, requirement.verificationMethod?.rawValue ?? "")]
            boxes.append(Self.box(isRequirement: true, stereotype: texts.stereotype(of: requirement.kind), name: requirement.name, fields: fields,
                                  style: styles.style(of: requirement.styleDeclarations), texts: &texts, measurers: measurers))
        }
        // A requirement and an element may share a name; relations then go to the requirement.
        for element in diagram.elements {
            if boxIndices[element.name] == nil { boxIndices[element.name] = boxes.count }
            boxes.append(Self.box(isRequirement: false, stereotype: texts.elementStereotype(), name: element.name,
                                  fields: [(.type, element.type), (.documentReference, element.documentReference)],
                                  style: styles.style(of: element.styleDeclarations), texts: &texts, measurers: measurers))
        }
        self.boxes = boxes
        var edges: [RequirementMeasuredEdge] = []
        edges.reserveCapacity(diagram.relations.count)
        var selfLoops = [[Int]](repeating: [], count: boxes.count)
        for (relationIndex, relation) in diagram.relations.enumerated() {
            guard let source = boxIndices[relation.source], let target = boxIndices[relation.target] else { continue }
            if source == target { selfLoops[source].append(edges.count) }
            edges.append(RequirementMeasuredEdge(relationIndex: relationIndex, kind: relation.kind, source: source, target: target,
                                                 text: texts.relationText(of: relation.kind)))
        }
        self.edges = edges
        selfLoopEdgeIndices = selfLoops
    }

    /// A box's texts and size, as Pele's `draw` measures a node.
    private static func box<Measurer: DiagramTextMeasuring>(isRequirement: Bool, stereotype: DiagramTextBlock, name: String,
                                                            fields: [(RequirementFieldKey, String)], style: DiagramElementStyle?,
                                                            texts: inout RequirementConstantTexts<Measurer>,
                                                            measurers: RequirementTextMeasurers<Measurer>) -> RequirementMeasuredBox {
        let nameText = DiagramTextBlock(label: DiagramLabelDecoder.label(from: name, form: .markdown), measurer: measurers.names,
                                        maximumWidth: nameWrappingWidth)
        var rows: [(key: DiagramTextBlock, value: DiagramTextBlock, height: CGFloat)] = []
        rows.reserveCapacity(fields.count)
        var keyWidth: CGFloat = 0
        var valueWidth: CGFloat = 0
        var bodyHeight: CGFloat = 0
        for (key, value) in fields where !value.isEmpty {
            let keyText = texts.key(key)
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
        return RequirementMeasuredBox(isRequirement: isRequirement, stereotype: stereotype, name: nameText, rows: rows, keyWidth: keyWidth,
                                      headHeight: headHeight, size: CGSize(width: width, height: headHeight + bodyHeight), style: style)
    }

    /// Each box's size in its rank: its own, grown on both sides across the flow by each of its loops, as Pele grows the
    /// node it lays out (`RequirementSelfLoops.room`).
    func layoutSizes(flowIsVertical: Bool) -> [CGSize] {
        boxes.indices.map { box in
            var size = boxes[box].size
            for edgeIndex in selfLoopEdgeIndices[box] {
                let room = RequirementSelfLoops.room(textSize: edges[edgeIndex].text.size, flowIsVertical: flowIsVertical)
                if flowIsVertical { size.width += 2 * room } else { size.height += 2 * room }
            }
            return size
        }
    }
}

/// A field a box shows, by its name.
enum RequirementFieldKey: Int, CaseIterable {
    case identifier
    case text
    case risk
    case verification
    case type
    case documentReference

    /// The name drawn before the field's value.
    var name: String {
        switch self {
        case .identifier: "ID"
        case .text: "Text"
        case .risk: "Risk"
        case .verification: "Verification"
        case .type: "Type"
        case .documentReference: "Doc Ref"
        }
    }
}

/// The texts of a closed set a diagram's boxes and relations draw again and again, each measured once a diagram, the
/// first time it is drawn: the stereotypes (`«Requirement»`, `«Element»`), the fields' names and the relations' kinds
/// (`«contains»`). A block measured once is the block measuring its text again gives.
struct RequirementConstantTexts<Measurer: DiagramTextMeasuring> {
    let measurers: RequirementTextMeasurers<Measurer>
    private var stereotypes = [DiagramTextBlock?](repeating: nil, count: RequirementConstantTextKinds.requirementKinds.count + 1)
    private var keys = [DiagramTextBlock?](repeating: nil, count: RequirementConstantTextKinds.fieldKeyCount)
    private var relationTexts = [DiagramTextBlock?](repeating: nil, count: RequirementConstantTextKinds.relationKinds.count)

    init(measurers: RequirementTextMeasurers<Measurer>) {
        self.measurers = measurers
    }

    /// The kinds in their declared order, made once rather than at each look-up.
    private static var requirementKinds: [RequirementKind] { RequirementConstantTextKinds.requirementKinds }
    private static var relationKinds: [RequirementRelationKind] { RequirementConstantTextKinds.relationKinds }

    mutating func stereotype(of kind: RequirementKind) -> DiagramTextBlock {
        stereotype(at: Self.requirementKinds.firstIndex(of: kind) ?? 0, kind: kind.rawValue)
    }

    mutating func elementStereotype() -> DiagramTextBlock {
        stereotype(at: Self.requirementKinds.count, kind: "Element")
    }

    private mutating func stereotype(at slot: Int, kind: String) -> DiagramTextBlock {
        if let measured = stereotypes[slot] { return measured }
        let measured = DiagramTextBlock(label: DiagramLabelDecoder.label(from: "«\(kind)»", form: .plain), measurer: measurers.body,
                                        maximumWidth: RequirementMeasurement.unwrapped)
        stereotypes[slot] = measured
        return measured
    }

    mutating func key(_ key: RequirementFieldKey) -> DiagramTextBlock {
        if let measured = keys[key.rawValue] { return measured }
        let measured = DiagramTextBlock(label: DiagramLabel(key.name), measurer: measurers.body, maximumWidth: RequirementMeasurement.unwrapped)
        keys[key.rawValue] = measured
        return measured
    }

    mutating func relationText(of kind: RequirementRelationKind) -> DiagramTextBlock {
        let slot = Self.relationKinds.firstIndex(of: kind) ?? 0
        if let measured = relationTexts[slot] { return measured }
        let measured = DiagramTextBlock(label: DiagramLabel("«\(kind.rawValue)»"), measurer: measurers.body, maximumWidth: RequirementMeasurement.unwrapped)
        relationTexts[slot] = measured
        return measured
    }
}

/// The kinds the constant texts are kept by, in their declared order (`allCases` makes a new list each time it is read).
enum RequirementConstantTextKinds {
    static let requirementKinds = RequirementKind.allCases
    static let relationKinds = RequirementRelationKind.allCases
    static let fieldKeyCount = RequirementFieldKey.allCases.count
}

extension RequirementDiagram {
    /// How many style declarations the requirements and elements hold, each time it is given, that their look has no place
    /// for (`font-weight`, `font-style`, `font-size`) or does not read; the colors and strokes are applied.
    public var unappliedStatementCount: Int {
        var styles = RequirementStyleResolution()
        for requirement in requirements { _ = styles.style(of: requirement.styleDeclarations) }
        for element in elements { _ = styles.style(of: element.styleDeclarations) }
        return styles.unappliedCount
    }
}

/// The look each box's declarations give it, as Pele's `resolveStyle` gives it (each property's last value wins), each
/// distinct declaration read once.
struct RequirementStyleResolution {
    private var read: [String: (style: DiagramElementStyle, isUnapplied: Bool)] = [:]
    private(set) var unappliedCount = 0

    mutating func style(of declarations: [String]) -> DiagramElementStyle? {
        guard !declarations.isEmpty else { return nil }
        var style = DiagramElementStyle()
        for declaration in declarations {
            // A declaration read before is looked up once; one read for the first time is kept.
            let reading: (style: DiagramElementStyle, isUnapplied: Bool)
            if let known = read[declaration] {
                reading = known
            } else {
                let parsed = DiagramElementStyle.reading(declaration)
                reading = (parsed.style, parsed.hasUnappliedDeclaration)
                read[declaration] = reading
            }
            style = style.overridden(by: reading.style)
            if reading.isUnapplied { unappliedCount += 1 }
        }
        return style.isEmpty ? nil : style
    }
}
