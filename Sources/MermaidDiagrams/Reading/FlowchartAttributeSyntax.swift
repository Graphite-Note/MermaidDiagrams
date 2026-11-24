/**
 * File: FlowchartAttributeSyntax.swift
 * ------------------------------------
 * Layer: Core
 * Description: Reads a node's or an edge's attributes (`@{ … }`) as Pele does: its shape data token, read as YAML; a
 *              one-line mapping of plain words and quoted strings is read on bytes, as YAML reads it, and anything else
 *              by the YAML reader.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import Foundation

extension FlowchartParser {
    /// Reads `@{ … }` as Pele does: its lexer's shape data state takes the text up to the first `}` outside quotation
    /// marks (a line break inside quotation marks, and the spaces after it, become `<br/>`; a `^` is refused), and
    /// flowchart/db.ts `addVertex` reads it as YAML, wrapped in braces when it is one line; YAML Pele's reader refuses
    /// is refused. A truthy `shape` names the shape (a name Mermaid does not know refused, `FlowchartNodeShape.named`),
    /// a truthy `label` the text, read as Markdown unless `labelType` is `string` or `text`, and `view: collapsed` asks
    /// a group to be drawn as one node; other keys (`icon`, `img`, `pos`, …) are read and left.
    mutating func readAttributes() throws(MermaidDiagramReadError) -> FlowchartNodeDefinition {
        let opening = position
        position += 2
        let bodyStart = position
        if let bodyEnd = endOfOneLineBody(from: bodyStart), let values = FlowchartAttributeValues(in: bytes, from: bodyStart, to: bodyEnd) {
            position = bodyEnd + 1
            return try definition(from: values, openedAt: opening)
        }
        let metadata = try readShapeData(openedAt: opening)
        let document = metadata.contains("\n") ? metadata + "\n" : "{\n" + metadata + "\n}"
        guard let value = MermaidYAMLDocument.value(of: document) else {
            let firstLine = metadata.split(separator: "\n").first { line in !line.allSatisfy(\.isWhitespace) } ?? ""
            throw .invalidSyntax(line: bytes.line(at: opening), problem: .unexpectedText(String(firstLine.trimmingCharacters(in: .whitespaces).prefix(24))))
        }
        guard case .object(let entries) = value else { return FlowchartNodeDefinition() }
        return try definition(from: entries, openedAt: opening)
    }

    /// The position of the `}` that ends a body of one line from `start`, with no backslash, `^` or line break before it
    /// outside or inside quotation marks; nil for any other body, which the YAML reader reads.
    private func endOfOneLineBody(from start: Int) -> Int? {
        var index = start
        var isInsideQuotation = false
        while index < bytes.count {
            let byte = bytes.base[index]
            if byte == MermaidByte.newline || byte == MermaidByte.carriageReturn || byte == UInt8(ascii: "\\") || byte == UInt8(ascii: "^") { return nil }
            if byte == MermaidByte.quotationMark { isInsideQuotation.toggle() }
            if !isInsideQuotation, byte == MermaidByte.closingBrace { return index }
            index += 1
        }
        return nil
    }

    /// What the values read on bytes set, as `definition(from: entries)` makes it of the YAML's mapping.
    private mutating func definition(from values: FlowchartAttributeValues, openedAt opening: Int) throws(MermaidDiagramReadError) -> FlowchartNodeDefinition {
        var definition = FlowchartNodeDefinition()
        if let shape = values.shape, !shape.isEmpty { definition.shape = try shapeNamed(shape, openedAt: opening) }
        if let label = values.label {
            if !label.isEmpty {
                let labelType = values.labelType.map { range in bytes.string(from: range.lowerBound, to: range.upperBound) }
                definition.label = writtenLabel(label, form: labelType == "string" || labelType == "text" ? .plain : .markdown)
            }
            definition.hasBlankWrittenLabel = label.allSatisfy { index in Self.isASCIIWhitespace(bytes.base[index]) }
        }
        if let view = values.view { definition.asksForCollapsedView = bytes.string(from: view.lowerBound, to: view.upperBound) == "collapsed" }
        guard values.hasAssetAttributes else { return definition }
        func text(_ range: Range<Int>?) -> String? {
            guard let range, !range.isEmpty else { return nil }
            return bytes.string(from: range.lowerBound, to: range.upperBound)
        }
        func number(_ range: Range<Int>?) -> Double? {
            guard let range, let number = Double(bytes.string(from: range.lowerBound, to: range.upperBound)), number != 0 else { return nil }
            return number
        }
        let attributes = FlowchartNodeAssetAttributes(icon: text(values.icon), image: text(values.image), form: text(values.form),
                                                      position: text(values.position), width: number(values.width), height: number(values.height),
                                                      constraint: text(values.constraint))
        if attributes != FlowchartNodeAssetAttributes() {
            writtenAssetAttributes = attributes
            definition.hasAssetAttributes = true
        }
        return definition
    }

    /// The shape `range` names: a documented name found by its bytes, else as `FlowchartNodeShape.named` reads it.
    private func shapeNamed(_ range: Range<Int>, openedAt opening: Int) throws(MermaidDiagramReadError) -> FlowchartNodeShape {
        if let shape = FlowchartShapeNameTable.shape(named: UnsafeBufferPointer(rebasing: bytes.buffer[range])) { return shape }
        return try FlowchartNodeShape.named(bytes.string(from: range.lowerBound, to: range.upperBound), line: bytes.line(at: opening))
    }

    /// What the YAML's mapping sets.
    private mutating func definition(from entries: [String: DirectiveValue], openedAt opening: Int) throws(MermaidDiagramReadError) -> FlowchartNodeDefinition {
        var definition = FlowchartNodeDefinition()
        if let shape = entries["shape"], MermaidYAMLDocument.isTruthy(shape) {
            definition.shape = try FlowchartNodeShape.named(MermaidYAMLDocument.javaScriptText(shape), line: bytes.line(at: opening))
        }
        if let label = entries["label"], MermaidYAMLDocument.isTruthy(label) {
            let labelType = entries["labelType"].map(MermaidYAMLDocument.javaScriptText)
            let form: DiagramLabelDecoder.Form = labelType == "string" || labelType == "text" ? .plain : .markdown
            definition.label = decoded(DiagramLabelDecoder.label(from: MermaidYAMLDocument.javaScriptText(label), form: form))
        }
        // Pele keeps the label only when it is text (`typeof doc.label === 'string'`) to test whether it is blank.
        if case .text(let written)? = entries["label"] { definition.hasBlankWrittenLabel = JavaScriptStringTrimming.trimmed(written).isEmpty }
        if let view = entries["view"] { definition.asksForCollapsedView = view == .text("collapsed") }
        var attributes = FlowchartNodeAssetAttributes()
        Self.readAssetAttributes(entries, into: &attributes)
        if attributes != FlowchartNodeAssetAttributes() {
            writtenAssetAttributes = attributes
            definition.hasAssetAttributes = true
        }
        return definition
    }

    /// An icon's or a picture's attributes, each kept as Pele's database keeps it when its value is truthy (`if (doc.icon)`):
    /// `String(value)`, and `Number(value)` for `w` and `h`. Keys are read as written: `Icon:` is no icon.
    private static func readAssetAttributes(_ entries: [String: DirectiveValue], into attributes: inout FlowchartNodeAssetAttributes) {
        func text(_ key: String) -> String? {
            entries[key].flatMap { value in MermaidYAMLDocument.isTruthy(value) ? MermaidYAMLDocument.javaScriptText(value) : nil }
        }
        func number(_ key: String) -> Double? {
            guard let value = entries[key], MermaidYAMLDocument.isTruthy(value) else { return nil }
            switch value {
            case .number(let number): return number
            case .boolean: return 1
            default: return JavaScriptNumber.value(of: Substring(MermaidYAMLDocument.javaScriptText(value))) ?? .nan
            }
        }
        attributes.icon = text("icon")
        attributes.image = text("img")
        attributes.form = text("form")
        attributes.position = text("pos")
        attributes.constraint = text("constraint")
        attributes.width = number("w")
        attributes.height = number("h")
    }

    /// The text of Pele's `SHAPE_DATA` tokens from after `@{` to the closing `}`, which the position moves past.
    private mutating func readShapeData(openedAt opening: Int) throws(MermaidDiagramReadError) -> String {
        var metadata: [UInt8] = []
        while position < bytes.count {
            let byte = bytes.base[position]
            switch byte {
            case MermaidByte.closingBrace:
                position += 1
                return String(decoding: metadata, as: UTF8.self)
            case UInt8(ascii: "^"): throw .invalidSyntax(line: bytes.line(at: position), problem: .unexpectedText(bytes.excerpt(at: position)))
            case MermaidByte.quotationMark:
                metadata.append(byte)
                position += 1
                while position < bytes.count, case let quoted = bytes.base[position], quoted != MermaidByte.quotationMark {
                    if quoted == MermaidByte.newline {
                        metadata.append(contentsOf: "<br/>".utf8)
                        position += 1
                        position = bytes.endOfSpaces(from: position)
                    } else {
                        metadata.append(quoted)
                        position += 1
                    }
                }
                guard position < bytes.count else { throw .invalidSyntax(line: bytes.line(at: opening), problem: .unclosedQuotation) }
                metadata.append(MermaidByte.quotationMark)
                position += 1
            default:
                metadata.append(byte)
                position += 1
            }
        }
        throw .invalidSyntax(line: bytes.line(at: opening), problem: .unclosedAttributes)
    }
}
