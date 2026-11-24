/**
 * File: FlowchartAttributeSyntax.swift
 * ------------------------------------
 * Layer: Core
 * Description: Reads a flowchart node's or edge's `@{ … }` as Pele reads it: the text its lexer takes up to the brace,
 *              read as YAML, then its shape, its label and its view.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

extension FlowchartNodeSyntax {
    /// Whether `@{` follows, which opens a node's (or an edge's) attributes.
    static func isAtAttributes(_ cursor: MermaidTextCursor) -> Bool {
        cursor.peek() == MermaidByte.atSign && cursor.peek(1) == MermaidByte.openingBrace
    }

    /// Reads `@{ … }` as Pele does: its lexer's shape data state takes the text up to the first `}` outside quotation
    /// marks (a line break inside quotation marks, and the spaces after it, become `<br/>`; a `^` is refused), and
    /// flowchart/db.ts `addVertex` reads it as YAML, wrapped in braces when it is one line; YAML Pele's reader refuses
    /// is refused. A truthy `shape` names the shape (a name Mermaid does not know refused, `FlowchartNodeShape.named`),
    /// a truthy `label` the text, read as Markdown unless `labelType` is `string` or `text`, and `view: collapsed` asks
    /// a group to be drawn as one node; other keys (`icon`, `img`, `pos`, …) are read and left.
    static func readAttributes(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> FlowchartNodeDefinition {
        let openingLine = cursor.line
        cursor.advance(by: 2)
        let metadataBytes = try readShapeData(&cursor, openingLine: openingLine)
        let value: DirectiveValue?
        if metadataBytes.contains(MermaidByte.carriageReturn) {
            // A carriage return, which a preprocessed text no longer holds, and a line feed are one character in Swift's
            // strings: the text is tested as one.
            let metadata = String(decoding: metadataBytes, as: UTF8.self)
            value = MermaidYAMLDocument.value(of: metadata.contains("\n") ? metadata + "\n" : "{\n" + metadata + "\n}")
        } else {
            value = MermaidYAMLDocument.value(of: yamlDocument(metadataBytes))
        }
        guard let value else {
            let metadata = String(decoding: metadataBytes, as: UTF8.self)
            let firstLine = metadata.split(separator: "\n").first { line in !line.allSatisfy(\.isWhitespace) } ?? ""
            throw .invalidSyntax(line: openingLine, problem: .unexpectedText(String(firstLine.trimmingCharacters(in: .whitespaces).prefix(24))))
        }
        var definition = FlowchartNodeDefinition()
        guard case .object(let entries) = value else { return definition }
        let written = WrittenAttributes(entries)
        if let shape = written.shape, MermaidYAMLDocument.isTruthy(shape) {
            definition.shape = try FlowchartNodeShape.named(MermaidYAMLDocument.javaScriptText(shape), line: openingLine)
        }
        if let label = written.label, MermaidYAMLDocument.isTruthy(label) {
            let labelType = written.labelType.map(MermaidYAMLDocument.javaScriptText)
            let form: DiagramLabelDecoder.Form = labelType == "string" || labelType == "text" ? .plain : .markdown
            definition.label = DiagramLabelDecoder.label(from: MermaidYAMLDocument.javaScriptText(label), form: form)
        }
        // Pele keeps the label only when it is text (`typeof doc.label === 'string'`) to test whether it is blank.
        if case .text(let writtenLabel)? = written.label { definition.hasBlankWrittenLabel = JavaScriptStringTrimming.trimmed(writtenLabel).isEmpty }
        if let view = written.view { definition.asksForCollapsedView = view == .text("collapsed") }
        readAssetAttributes(written, into: &definition.assetAttributes)
        return definition
    }

    /// The values of the keys a node's attributes are read from, found in one pass over the attributes written. Keys are
    /// read as written: `Icon:` is no icon.
    private struct WrittenAttributes {
        var shape: DirectiveValue?
        var label: DirectiveValue?
        var labelType: DirectiveValue?
        var view: DirectiveValue?
        var icon: DirectiveValue?
        var image: DirectiveValue?
        var form: DirectiveValue?
        var position: DirectiveValue?
        var constraint: DirectiveValue?
        var width: DirectiveValue?
        var height: DirectiveValue?

        init(_ entries: [String: DirectiveValue]) {
            for (key, value) in entries {
                switch key {
                case "shape": shape = value
                case "label": label = value
                case "labelType": labelType = value
                case "view": view = value
                case "icon": icon = value
                case "img": image = value
                case "form": form = value
                case "pos": position = value
                case "constraint": constraint = value
                case "w": width = value
                case "h": height = value
                default: break
                }
            }
        }
    }

    /// An icon's or a picture's attributes, each kept as Pele's database keeps it when its value is truthy (`if (doc.icon)`):
    /// `String(value)`, and `Number(value)` for `w` and `h`.
    private static func readAssetAttributes(_ written: WrittenAttributes, into attributes: inout FlowchartNodeAssetAttributes) {
        func text(_ value: DirectiveValue?) -> String? {
            value.flatMap { value in MermaidYAMLDocument.isTruthy(value) ? MermaidYAMLDocument.javaScriptText(value) : nil }
        }
        func number(_ value: DirectiveValue?) -> Double? {
            guard let value, MermaidYAMLDocument.isTruthy(value) else { return nil }
            switch value {
            case .number(let number): return number
            case .boolean: return 1
            default: return JavaScriptNumber.value(of: Substring(MermaidYAMLDocument.javaScriptText(value))) ?? .nan
            }
        }
        attributes.icon = text(written.icon) ?? attributes.icon
        attributes.image = text(written.image) ?? attributes.image
        attributes.form = text(written.form) ?? attributes.form
        attributes.position = text(written.position) ?? attributes.position
        attributes.constraint = text(written.constraint) ?? attributes.constraint
        attributes.width = number(written.width) ?? attributes.width
        attributes.height = number(written.height) ?? attributes.height
    }

    /// The YAML text Pele's database reads the attributes' text as (flowchart/db.ts `addVertex`): the text and a line
    /// break when it holds one, else the text in braces, one on each line around it.
    private static func yamlDocument(_ metadata: [UInt8]) -> [UInt8] {
        var document: [UInt8] = []
        if metadata.contains(MermaidByte.newline) {
            document.reserveCapacity(metadata.count + 1)
            document += metadata
            document.append(MermaidByte.newline)
        } else {
            document.reserveCapacity(metadata.count + 4)
            document += [MermaidByte.openingBrace, MermaidByte.newline]
            document += metadata
            document += [MermaidByte.newline, MermaidByte.closingBrace]
        }
        return document
    }

    /// The UTF-8 bytes of Pele's `SHAPE_DATA` tokens from after `@{` to the closing `}`, which the cursor moves past.
    private static func readShapeData(_ cursor: inout MermaidTextCursor, openingLine: Int) throws(MermaidDiagramReadError) -> [UInt8] {
        var metadata: [UInt8] = []
        metadata.reserveCapacity(64)
        while let byte = cursor.peek() {
            switch byte {
            case MermaidByte.closingBrace:
                cursor.advance()
                return metadata
            case UInt8(ascii: "^"): throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
            case MermaidByte.quotationMark:
                metadata.append(byte)
                cursor.advance()
                while let quoted = cursor.peek(), quoted != MermaidByte.quotationMark {
                    if quoted == MermaidByte.newline {
                        metadata += lineBreakTag
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

    private static let lineBreakTag = Array("<br/>".utf8)
}
