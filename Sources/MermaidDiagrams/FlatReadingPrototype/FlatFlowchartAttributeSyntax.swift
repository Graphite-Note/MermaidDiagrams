/**
 * File: FlatFlowchartAttributeSyntax.swift
 * ----------------------------------------
 * Layer: Core (design prototype, not for merging as is)
 * Description: A node's `@{ … }` written on one line as a flow mapping of plain keys to double-quoted or plain text,
 *              read on bytes with YAML's meaning of those scalars; anything else (more lines, escapes, numbers but
 *              `w` and `h`, YAML's words) bails out to the present reader, which reads it as YAML.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension FlatFlowchartReader {
    private enum AttributeKey {
        case shape, label, labelType, view, icon, image, form, position, constraint, width, height, other
    }

    struct AttributeValue {
        var range: Range<Int>
        var isQuoted: Bool
    }

    /// The values of the eleven keys read, without a list.
    struct AttributeValues {
        var shape, label, labelType, view, icon, image, form, position, constraint, width, height: AttributeValue?

        subscript(_ slot: Int) -> AttributeValue? {
            get {
                switch slot {
                case 0: shape
                case 1: label
                case 2: labelType
                case 3: view
                case 4: icon
                case 5: image
                case 6: form
                case 7: position
                case 8: constraint
                case 9: width
                default: height
                }
            }
            set {
                switch slot {
                case 0: shape = newValue
                case 1: label = newValue
                case 2: labelType = newValue
                case 3: view = newValue
                case 4: icon = newValue
                case 5: image = newValue
                case 6: form = newValue
                case 7: position = newValue
                case 8: constraint = newValue
                case 9: width = newValue
                default: height = newValue
                }
            }
        }
    }

    private func attributeKey(from start: Int, to end: Int) -> AttributeKey {
        switch end - start {
        case 1: return bytes[start] == 0x77 ? .width : bytes[start] == 0x68 ? .height : .other
        case 3: return bytes.hasText("img", at: start) ? .image : bytes.hasText("pos", at: start) ? .position : .other
        case 4: return bytes.hasText("view", at: start) ? .view : bytes.hasText("icon", at: start) ? .icon : bytes.hasText("form", at: start) ? .form : .other
        case 5: return bytes.hasText("shape", at: start) ? .shape : bytes.hasText("label", at: start) ? .label : .other
        case 9: return bytes.hasText("labelType", at: start) ? .labelType : .other
        case 10: return bytes.hasText("constraint", at: start) ? .constraint : .other
        default: return .other
        }
    }

    mutating func readAttributes() throws(FlatReadingBailOut) -> FlatNodeDefinition {
        position += 2
        let bodyStart = position
        var isInsideQuotation = false
        while true {
            guard position < bytes.count else { throw FlatReadingBailOut() }
            let byte = bytes.base[position]
            if byte == MermaidByte.newline || byte == MermaidByte.carriageReturn || byte == 0x5C { throw FlatReadingBailOut() }
            if byte == MermaidByte.quotationMark { isInsideQuotation.toggle() }
            if !isInsideQuotation {
                if byte == MermaidByte.closingBrace { break }
                if byte == UInt8(ascii: "^") { throw FlatReadingBailOut() }
            }
            position += 1
        }
        let bodyEnd = position
        position += 1
        var values = AttributeValues()
        var index = bodyStart
        func skipBlanks() { while index < bodyEnd, MermaidByte.isSpace(bytes.base[index]) { index += 1 } }
        skipBlanks()
        guard index < bodyEnd else { throw FlatReadingBailOut() }
        while index < bodyEnd {
            let keyStart = index
            while index < bodyEnd, MermaidByte.isLetter(bytes.base[index]) { index += 1 }
            guard index > keyStart else { throw FlatReadingBailOut() }
            let key = attributeKey(from: keyStart, to: index)
            skipBlanks()
            guard bytes[index] == MermaidByte.colon, index + 1 < bodyEnd, MermaidByte.isSpace(bytes[index + 1]) else { throw FlatReadingBailOut() }
            index += 1
            skipBlanks()
            let value: AttributeValue
            if bytes[index] == MermaidByte.quotationMark {
                let start = index + 1
                index = start
                while index < bodyEnd, bytes.base[index] != MermaidByte.quotationMark { index += 1 }
                guard index < bodyEnd else { throw FlatReadingBailOut() }
                value = AttributeValue(range: start..<index, isQuoted: true)
                index += 1
                skipBlanks()
            } else {
                let start = index
                while index < bodyEnd, bytes.base[index] != MermaidByte.comma { index += 1 }
                var end = index
                while end > start, MermaidByte.isSpace(bytes.base[end - 1]) { end -= 1 }
                guard end > start, isSafePlainScalar(start..<end, isNumberWanted: key == .width || key == .height) else { throw FlatReadingBailOut() }
                value = AttributeValue(range: start..<end, isQuoted: false)
            }
            if key != .other {
                let slot = Self.slot(of: key)
                guard values[slot] == nil else { throw FlatReadingBailOut() }
                values[slot] = value
            }
            guard index == bodyEnd || bytes[index] == MermaidByte.comma else { throw FlatReadingBailOut() }
            if index < bodyEnd {
                index += 1
                skipBlanks()
                guard index < bodyEnd else { throw FlatReadingBailOut() }
            }
        }
        return try definition(from: values)
    }

    private static func slot(of key: AttributeKey) -> Int {
        switch key {
        case .shape: 0
        case .label: 1
        case .labelType: 2
        case .view: 3
        case .icon: 4
        case .image: 5
        case .form: 6
        case .position: 7
        case .constraint: 8
        case .width: 9
        case .height: 10
        case .other: 11
        }
    }

    /// A plain scalar YAML reads as text: none of its indicators first, no `: ` or ` #`, not one of its words or a number
    /// (a number is wanted only for `w` and `h`, and then only digits).
    private func isSafePlainScalar(_ range: Range<Int>, isNumberWanted: Bool) -> Bool {
        let first = bytes.base[range.lowerBound]
        if isNumberWanted { return range.allSatisfy { index in MermaidByte.isDigit(bytes.base[index]) } }
        guard MermaidByte.isLetter(first) else { return false }
        for index in range {
            let byte = bytes.base[index]
            if byte >= 0x80 || byte == UInt8(ascii: "#") || byte == MermaidByte.quotationMark || byte == UInt8(ascii: "'") || byte == MermaidByte.colon
                || byte == MermaidByte.openingBrace || byte == MermaidByte.closingBrace || byte == MermaidByte.openingBracket
                || byte == MermaidByte.closingBracket { return false }
        }
        switch range.count {
        case 4: return !(bytes.hasText("null", at: range.lowerBound) || bytes.hasText("Null", at: range.lowerBound) || bytes.hasText("NULL", at: range.lowerBound)
            || bytes.hasText("true", at: range.lowerBound) || bytes.hasText("True", at: range.lowerBound) || bytes.hasText("TRUE", at: range.lowerBound))
        case 5: return !(bytes.hasText("false", at: range.lowerBound) || bytes.hasText("False", at: range.lowerBound) || bytes.hasText("FALSE", at: range.lowerBound))
        default: return true
        }
    }

    private mutating func definition(from values: AttributeValues) throws(FlatReadingBailOut) -> FlatNodeDefinition {
        var definition = FlatNodeDefinition()
        if let shape = values[0], !shape.range.isEmpty { definition.shape = try shapeNamed(shape.range) }
        if let label = values[1] {
            if !label.range.isEmpty {
                var form = DiagramLabelDecoder.Form.markdown
                if let labelType = values[2] {
                    let type = string(from: labelType.range.lowerBound, to: labelType.range.upperBound)
                    if type == "string" || type == "text" { form = .plain }
                }
                definition.label = writtenLabel(FlatTextRange(start: Int32(label.range.lowerBound), end: Int32(label.range.upperBound)), form: form)
            }
            definition.hasBlankWrittenLabel = label.range.allSatisfy { index in Self.isASCIIWhitespace(bytes.base[index]) }
            if label.range.contains(where: { index in bytes.base[index] >= 0x80 }) { throw FlatReadingBailOut() }
        }
        if let view = values[3] { definition.asksForCollapsedView = string(from: view.range.lowerBound, to: view.range.upperBound) == "collapsed" }
        var attributes = FlowchartNodeAssetAttributes()
        func text(_ slot: Int) -> String? {
            guard let value = values[slot], !value.range.isEmpty else { return nil }
            return string(from: value.range.lowerBound, to: value.range.upperBound)
        }
        func number(_ slot: Int) throws(FlatReadingBailOut) -> Double? {
            guard let value = values[slot] else { return nil }
            guard !value.isQuoted else { throw FlatReadingBailOut() }
            guard let number = Double(string(from: value.range.lowerBound, to: value.range.upperBound)) else { throw FlatReadingBailOut() }
            return number == 0 ? nil : number
        }
        attributes.icon = text(4)
        attributes.image = text(5)
        attributes.form = text(6)
        attributes.position = text(7)
        attributes.constraint = text(8)
        attributes.width = try number(9)
        attributes.height = try number(10)
        if attributes != FlowchartNodeAssetAttributes() {
            writtenAssetAttributes = attributes
            definition.hasAssetAttributes = true
        }
        return definition
    }

    /// FlowchartNodeShape.named: a lowercase name without `_`, by Mermaid's names or its undocumented ones.
    private func shapeNamed(_ range: Range<Int>) throws(FlatReadingBailOut) -> FlowchartNodeShape {
        for index in range {
            let byte = bytes.base[index]
            if byte >= 0x80 || byte == MermaidByte.underscore || (byte >= 0x41 && byte <= 0x5A) { throw FlatReadingBailOut() }
        }
        if let shape = FlatShapeNames.shape(named: bytes.base + range.lowerBound, count: range.count) { return shape }
        let name = string(from: range.lowerBound, to: range.upperBound)
        do { return try FlowchartNodeShape.named(name, line: 0) } catch { throw FlatReadingBailOut() }
    }
}
