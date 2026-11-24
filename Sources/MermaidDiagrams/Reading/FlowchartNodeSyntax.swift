/**
 * File: FlowchartNodeSyntax.swift
 * -------------------------------
 * Layer: Core
 * Description: Reads what follows a node's identifier: a shape in brackets around its text, read on bytes, and what
 *              the node's definitions set on it as they are read.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.7
 * Date: 24/11/2026
 */

/// What a node's brackets or `@{ … }` say about it: its shape, its text, or both.
struct FlowchartNodeDefinition {
    var shape: FlowchartNodeShape?
    var label: FlowchartLabelReference?
    /// Whether `label:` was written with nothing but spaces in it, or not at all: such a node drawn as an icon or a picture
    /// loses the identifier it would otherwise show, as in Pele.
    var hasBlankWrittenLabel = true
    /// `view: collapsed`, which a group's identifier takes to be drawn as one node.
    var asksForCollapsedView = false
    /// The icon and picture attributes written (`icon`, `img`, `form`, `pos`, `w`, `h`, `constraint`), or nil for none.
    var assetAttributes: FlowchartNodeAssetAttributes?
}

extension FlowchartParser {
    /// Reads a shape and its text right after a node's identifier, or returns nil and moves nothing when no shape opens
    /// there: the brackets that open a shape, longest first so that `((` is not read as `(`, and the texts that close each.
    mutating func readShape() throws(MermaidDiagramReadError) -> FlowchartNodeDefinition? {
        let opening = position
        let openingLength: Int
        let closings: FlowchartClosings
        let shapes: (FlowchartNodeShape, FlowchartNodeShape)
        var state = FlowchartTextState.text
        switch bytes[position] {
        case UInt8(ascii: "("):
            switch bytes[position + 1] {
            case UInt8(ascii: "(") where bytes[position + 2] == UInt8(ascii: "("): (openingLength, closings, shapes) = (3, FlowchartClosings(")))"), (.doubleCircle, .doubleCircle))
            case UInt8(ascii: "("): (openingLength, closings, shapes) = (2, FlowchartClosings("))"), (.circle, .circle))
            case MermaidByte.openingBracket: (openingLength, closings, shapes) = (2, FlowchartClosings("])"), (.stadium, .stadium))
            case MermaidByte.hyphen:
                (openingLength, closings, shapes) = (2, FlowchartClosings("-)", "/)", "))"), (.ellipse, .ellipse))
                state = .ellipse
            default: (openingLength, closings, shapes) = (1, FlowchartClosings(")"), (.roundedRectangle, .roundedRectangle))
            }
        case MermaidByte.openingBracket:
            switch bytes[position + 1] {
            case MermaidByte.verticalBar: return try readRectangleWithProperty()
            case MermaidByte.openingBracket: (openingLength, closings, shapes) = (2, FlowchartClosings("]]"), (.subroutine, .subroutine))
            case UInt8(ascii: "("): (openingLength, closings, shapes) = (2, FlowchartClosings(")]"), (.cylinder, .cylinder))
            case UInt8(ascii: "/"):
                (openingLength, closings, shapes) = (2, FlowchartClosings("/]", "\\]"), (.leanRight, .trapezoid))
                state = .trapezoid
            case UInt8(ascii: "\\"):
                (openingLength, closings, shapes) = (2, FlowchartClosings("\\]", "/]"), (.leanLeft, .invertedTrapezoid))
                state = .trapezoid
            default: (openingLength, closings, shapes) = (1, FlowchartClosings("]"), (.rectangle, .rectangle))
            }
        case MermaidByte.greaterThan: (openingLength, closings, shapes) = (1, FlowchartClosings("]"), (.asymmetric, .asymmetric))
        case MermaidByte.openingBrace:
            let isHexagon = bytes[position + 1] == MermaidByte.openingBrace
            (openingLength, closings, shapes) = isHexagon ? (2, FlowchartClosings("}}"), (.hexagon, .hexagon)) : (1, FlowchartClosings("}"), (.diamond, .diamond))
        default: return nil
        }
        position += openingLength
        let (label, closing) = try readText(closedBy: closings, state: state, openedAt: opening)
        return FlowchartNodeDefinition(shape: closing == 0 ? shapes.0 : shapes.1, label: label)
    }

    /// `[|borders:lt|text]`, a rectangle with a property written before its text, as Pele's parser reads it
    /// (`VERTEX_WITH_PROPS_START`, a word, `:`, a word, `|`, then the text up to `]`): the property is read and left, as
    /// Pele keeps it without drawing it. Written otherwise, it is refused, as Pele refuses it.
    private mutating func readRectangleWithProperty() throws(MermaidDiagramReadError) -> FlowchartNodeDefinition {
        let opening = position
        position += 2
        for separator in [MermaidByte.colon, MermaidByte.verticalBar] {
            let wordStart = position
            while position < bytes.count, case let byte = bytes.base[position], byte != separator, !MermaidByte.isSpace(byte),
                  !MermaidByte.endsStatement(byte), byte != MermaidByte.colon, byte != MermaidByte.verticalBar,
                  byte != MermaidByte.closingBracket { position += 1 }
            guard position > wordStart, position < bytes.count, bytes.base[position] == separator else {
                throw .invalidSyntax(line: bytes.line(at: position),
                                     problem: position >= bytes.count ? .unclosedShape(closingText: "]") : .unexpectedText(bytes.excerpt(at: position)))
            }
            position += 1
        }
        let (label, _) = try readText(closedBy: FlowchartClosings("]"), openedAt: opening)
        return FlowchartNodeDefinition(shape: .rectangle, label: label)
    }

    /// The index of the node named `name`, added with its identifier as its text the first time it is named. A node
    /// named inside a group joins the innermost one.
    mutating func nodeIndex(name: Int, range: MermaidTextRange) throws(MermaidDiagramReadError) -> Int32 {
        var index = lists.names.names[name].nodeIndex
        if index < 0 {
            guard parts.nodes.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
            index = Int32(parts.nodes.count)
            parts.nodes.append(FlowchartNodeRecord(identifier: range, label: writtenLabel(range.lowerBound..<range.upperBound, form: .plain),
                                                   shape: .rectangle))
            lists.names.names[name].nodeIndex = index
        }
        if !lists.openGroups.isEmpty { listMember(name) }
        return index
    }

    /// A later definition of a node replaces what an earlier one set, as in Mermaid. The icon or picture attributes
    /// written replace the node's, and a node made an icon or a picture without a label of its own shows none rather
    /// than its identifier (Pele's `addVertex`).
    mutating func define(nodeAt index: Int32, name: Int, as definition: FlowchartNodeDefinition) throws(MermaidDiagramReadError) {
        let place = Int(index)
        if let shape = definition.shape { parts.nodes[place].shape = shape }
        if let label = definition.label { parts.nodes[place].label = label }
        if definition.asksForCollapsedView { lists.names.names[name].isCollapsed = true }
        guard let written = definition.assetAttributes, written != FlowchartNodeAssetAttributes() else { return }
        var node = parts.nodes[place]
        if written.icon != nil || written.image != nil, definition.hasBlankWrittenLabel,
           parts.label(node.label, in: bytes) == DiagramLabel(parts.string(node.identifier, in: bytes)) {
            node.label = FlowchartLabelReference(kind: .line, range: .empty)
        }
        var attributes = node.assetIndex >= 0 ? parts.assetAttributes[Int(node.assetIndex)] : FlowchartNodeAssetAttributes()
        attributes.icon = written.icon ?? attributes.icon
        attributes.image = written.image ?? attributes.image
        attributes.form = written.form ?? attributes.form
        attributes.position = written.position ?? attributes.position
        attributes.width = written.width ?? attributes.width
        attributes.height = written.height ?? attributes.height
        attributes.constraint = written.constraint ?? attributes.constraint
        if node.assetIndex >= 0 {
            parts.assetAttributes[Int(node.assetIndex)] = attributes
        } else {
            node.assetIndex = Int32(parts.assetAttributes.count)
            parts.assetAttributes.append(attributes)
        }
        parts.nodes[place] = node
    }
}
