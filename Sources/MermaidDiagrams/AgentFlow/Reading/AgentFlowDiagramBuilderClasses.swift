/**
 * File: AgentFlowDiagramBuilderClasses.swift
 * ------------------------------------------
 * Layer: Core
 * Description: An agent flow's class definitions, classes, clicks and direction as Pele's db.ts records them, on names
 *              and ranges, with 0.7.0's Foundation steps on Strings kept for texts beyond ASCII.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

extension AgentFlowDiagramBuilder {
    /// `classDef a,b styles`: escaped commas kept, the others (and semicolons) separating styles; a style that sets a
    /// color is also a style of the text, its `fill` read as `bgFill`.
    mutating func addClass(_ identifiers: MermaidTextRange, styles: [MermaidTextRange]) {
        let split = classStyles(styles)
        pieces.removeAll()
        model.text.appendCommaPieces(of: identifiers, to: &pieces)
        let identifierPieces = pieces.elements
        for identifier in identifierPieces {
            let name = name(of: identifier)
            var index = names[name].classDefinition
            if index < 0 {
                index = Int32(model.classDefinitions.count)
                names[name].classDefinition = index
                model.classDefinitions.append(AgentFlowClassRecord(identifier: identifier, name: name))
            }
            for style in split {
                if containsColor(style) {
                    model.classAttributes.append(AgentFlowAttribute(owner: index, kind: .textStyle, value: replacingFirstFill(style)))
                }
                model.classAttributes.append(AgentFlowAttribute(owner: index, kind: .style, value: style))
            }
        }
    }

    /// The styles joined by commas, then split at each comma not escaped and each semicolon, an escaped comma kept as a
    /// comma: 0.7.0's replacements on the joined String. Styles without a backslash or a semicolon are their own pieces.
    private mutating func classStyles(_ styles: [MermaidTextRange]) -> [MermaidTextRange] {
        let isPlain = styles.allSatisfy { style in
            model.text.isASCII(style) && !model.text.contains(style, byte: UInt8(ascii: "\\")) && !model.text.contains(style, byte: UInt8(ascii: ";"))
                && !model.text.contains(style, byte: UInt8(ascii: ","))
        }
        if isPlain { return styles }
        let joined = styles.map(model.text.string).joined(separator: ",").replacingOccurrences(of: "\\,", with: "\u{0}")
        let split = joined.replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\u{0}", with: ",")
            .split(separator: ";", omittingEmptySubsequences: false)
        return split.map { piece in model.text.append(piece.utf8) }
    }

    /// Whether a style holds `color`, as 0.7.0's `contains` found it.
    private func containsColor(_ style: MermaidTextRange) -> Bool {
        guard model.text.isASCII(style) else { return model.text.string(style).contains("color") }
        let bytes = model.text.bytes[style.lowerBound..<style.upperBound]
        return bytes.firstRange(of: Self.colorWord) != nil
    }

    /// The style with its first `fill` made `bgFill`.
    private mutating func replacingFirstFill(_ style: MermaidTextRange) -> MermaidTextRange {
        let text = model.text.string(style)
        let replaced = Self.replacingFirst("fill", with: "bgFill", in: text)
        return replaced == text ? style : model.text.append(replaced.utf8)
    }

    private static let colorWord = Array("color".utf8)

    static func replacingFirst(_ target: String, with replacement: String, in text: String) -> String {
        guard let range = text.range(of: target) else { return text }
        return text.replacingCharacters(in: range, with: replacement)
    }

    /// `class a,b name` and `a:::name`: the class on each node, edge and flow of those identifiers.
    mutating func setClass(_ identifiers: MermaidTextRange, className: MermaidTextRange) {
        pieces.removeAll()
        model.text.appendCommaPieces(of: identifiers, to: &pieces)
        let identifierPieces = pieces.elements
        for identifier in identifierPieces {
            let name = name(of: identifier)
            let role = names[name]
            if role.vertex >= 0 { model.vertexAttributes.append(AgentFlowAttribute(owner: role.vertex, kind: .className, value: className)) }
            let edge = edgeIndex(of: name, identifier: identifier)
            if edge >= 0 { model.edgeAttributes.append(AgentFlowAttribute(owner: Int32(edge), kind: .className, value: className)) }
            if role.flow >= 0 { model.flowAttributes.append(AgentFlowAttribute(owner: role.flow, kind: .className, value: className)) }
        }
    }

    mutating func setTooltip(_ identifiers: MermaidTextRange, tooltip: MermaidTextRange) {
        pieces.removeAll()
        model.text.appendCommaPieces(of: identifiers, to: &pieces)
        let identifierPieces = pieces.elements
        for identifier in identifierPieces { names[name(of: identifier)].tooltip = tooltip }
    }

    /// `click a href "url"`: the link kept as written (the scene draws no links), the node marked clickable.
    mutating func setLink(_ identifiers: MermaidTextRange, url: MermaidTextRange, target: MermaidTextRange? = nil) {
        let link = model.text.trimmed(url)
        pieces.removeAll()
        model.text.appendCommaPieces(of: identifiers, to: &pieces)
        let identifierPieces = pieces.elements
        for identifier in identifierPieces {
            let vertex = names[name(of: identifier)].vertex
            guard vertex >= 0 else { continue }
            model.vertices[Int(vertex)].link = link.isEmpty ? nil : link
            model.vertices[Int(vertex)].linkTarget = target
        }
        setClass(identifiers, className: constant(.clickable))
    }

    /// The direction written after the keyword, as Mermaid normalizes it: an arrow names one, `TD` is `TB`.
    mutating func setDirection(_ written: MermaidTextRange) {
        var direction = model.text.trimmed(written)
        if model.text.contains(direction, byte: MermaidByte.lessThan) { direction = constant(.rightToLeft) }
        if model.text.contains(direction, byte: UInt8(ascii: "^")) { direction = constant(.bottomToTop) }
        if model.text.contains(direction, byte: MermaidByte.greaterThan) { direction = constant(.leftToRight) }
        if model.text.contains(direction, byte: UInt8(ascii: "v")) { direction = constant(.topToBottom) }
        if model.text.equals(direction, AgentFlowConstantText.topDown.bytes) { direction = constant(.topToBottom) }
        model.directionKeyword = direction
    }
}
