/**
 * File: ReferenceFlowchartAttributeSyntax.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: MermaidDiagrams 0.7.0's FlowchartAttributeSyntax, frozen as the reference the flat reader is proven against
 *              (FlowchartModelEquivalenceTests): reads a flowchart node's or edge's `@{ … }` as Pele reads it: the text its lexer takes up to the brace, read as YAML, then its shape, its label and its view.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

extension ReferenceFlowchartNodeSyntax {
    /// Whether `@{` follows, which opens a node's (or an edge's) attributes.
    static func isAtAttributes(_ cursor: ReferenceMermaidTextCursor) -> Bool {
        cursor.peek() == MermaidByte.atSign && cursor.peek(1) == MermaidByte.openingBrace
    }

    /// Reads `@{ … }` as Pele does: its lexer's shape data state takes the text up to the first `}` outside quotation
    /// marks (a line break inside quotation marks, and the spaces after it, become `<br/>`; a `^` is refused), and
    /// flowchart/db.ts `addVertex` reads it as YAML, wrapped in braces when it is one line; YAML Pele's reader refuses
    /// is refused. A truthy `shape` names the shape (a name Mermaid does not know refused, `FlowchartNodeShape.named`),
    /// a truthy `label` the text, read as Markdown unless `labelType` is `string` or `text`, and `view: collapsed` asks
    /// a group to be drawn as one node; other keys (`icon`, `img`, `pos`, …) are read and left.
    static func readAttributes(_ cursor: inout ReferenceMermaidTextCursor) throws(MermaidDiagramReadError) -> ReferenceFlowchartNodeDefinition {
        let openingLine = cursor.line
        cursor.advance(by: 2)
        let metadata = try readShapeData(&cursor, openingLine: openingLine)
        let document = metadata.contains("\n") ? metadata + "\n" : "{\n" + metadata + "\n}"
        guard let value = MermaidYAMLDocument.value(of: document) else {
            let firstLine = metadata.split(separator: "\n").first { line in !line.allSatisfy(\.isWhitespace) } ?? ""
            throw .invalidSyntax(line: openingLine, problem: .unexpectedText(String(firstLine.trimmingCharacters(in: .whitespaces).prefix(24))))
        }
        var definition = ReferenceFlowchartNodeDefinition()
        guard case .object(let entries) = value else { return definition }
        if let shape = entries["shape"], MermaidYAMLDocument.isTruthy(shape) {
            definition.shape = try FlowchartNodeShape.named(MermaidYAMLDocument.javaScriptText(shape), line: openingLine)
        }
        if let label = entries["label"], MermaidYAMLDocument.isTruthy(label) {
            let labelType = entries["labelType"].map(MermaidYAMLDocument.javaScriptText)
            let form: DiagramLabelDecoder.Form = labelType == "string" || labelType == "text" ? .plain : .markdown
            definition.label = DiagramLabelDecoder.label(from: MermaidYAMLDocument.javaScriptText(label), form: form)
        }
        // Pele keeps the label only when it is text (`typeof doc.label === 'string'`) to test whether it is blank.
        if case .text(let written)? = entries["label"] { definition.hasBlankWrittenLabel = JavaScriptStringTrimming.trimmed(written).isEmpty }
        if let view = entries["view"] { definition.asksForCollapsedView = view == .text("collapsed") }
        readAssetAttributes(entries, into: &definition.assetAttributes)
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
        attributes.icon = text("icon") ?? attributes.icon
        attributes.image = text("img") ?? attributes.image
        attributes.form = text("form") ?? attributes.form
        attributes.position = text("pos") ?? attributes.position
        attributes.constraint = text("constraint") ?? attributes.constraint
        attributes.width = number("w") ?? attributes.width
        attributes.height = number("h") ?? attributes.height
    }

    /// The text of Pele's `SHAPE_DATA` tokens from after `@{` to the closing `}`, which the cursor moves past.
    private static func readShapeData(_ cursor: inout ReferenceMermaidTextCursor, openingLine: Int) throws(MermaidDiagramReadError) -> String {
        var metadata: [UInt8] = []
        while let byte = cursor.peek() {
            switch byte {
            case MermaidByte.closingBrace:
                cursor.advance()
                return String(decoding: metadata, as: UTF8.self)
            case UInt8(ascii: "^"): throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
            case MermaidByte.quotationMark:
                metadata.append(byte)
                cursor.advance()
                while let quoted = cursor.peek(), quoted != MermaidByte.quotationMark {
                    if quoted == MermaidByte.newline {
                        metadata += Array("<br/>".utf8)
                        cursor.advance()
                        while JavaScriptWhitespace.length(in: cursor.bytes, at: cursor.position) > 0 {
                            cursor.advance(by: JavaScriptWhitespace.length(in: cursor.bytes, at: cursor.position))
                        }
                    } else {
                        metadata.append(quoted)
                        cursor.advance()
                    }
                }
                guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedQuotation) }
                metadata.append(MermaidByte.quotationMark)
                cursor.advance()
            default:
                metadata.append(byte)
                cursor.advance()
            }
        }
        throw .invalidSyntax(line: openingLine, problem: .unclosedAttributes)
    }
}
