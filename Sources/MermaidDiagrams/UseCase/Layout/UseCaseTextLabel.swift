/**
 * File: UseCaseTextLabel.swift
 * ----------------------------
 * Layer: Core
 * Description: A use case diagram's texts measured as Pele's layoutLabel measures them: a plain label shown as written
 *              (only Mermaid's entity codes read), a Markdown one read, wrapped at spaces past its room, and lines set
 *              closer once there are several; and the measurers of the sizes and styles they are drawn in.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

import CoreGraphics

/// The measurers of a use case diagram's text: the diagram's font at any size, bold and italic or not, each made once.
struct UseCaseTextMeasurers<Measurer: DiagramTextMeasuring> {
    let font: DiagramFont
    private let make: (CGFloat, Bool, Bool) -> Measurer
    private var made: [UseCaseMeasurerKey: Measurer] = [:]

    private struct UseCaseMeasurerKey: Hashable {
        let size: CGFloat
        let isBold: Bool
        let isItalic: Bool
    }

    init(font: DiagramFont, make: @escaping (_ size: CGFloat, _ isBold: Bool, _ isItalic: Bool) -> Measurer) {
        self.font = font
        self.make = make
    }

    /// The font at `size`, bold or italic.
    mutating func measurer(size: CGFloat, isBold: Bool = false, isItalic: Bool = false) -> Measurer {
        let key = UseCaseMeasurerKey(size: size, isBold: isBold, isItalic: isItalic)
        if let measurer = made[key] { return measurer }
        let measurer = make(size, isBold, isItalic)
        made[key] = measurer
        return measurer
    }
}

extension UseCaseTextMeasurers where Measurer == CoreTextDiagramTextMeasurer {
    init(typography: DiagramTypography) {
        self.init(font: typography.font) { size, isBold, isItalic in typography.measurer(size: size, isBold: isBold, isItalic: isItalic) }
    }
}

enum UseCaseTextLabel {
    /// `text` measured in `measurer`, wrapped at `room`: no lines for no text. A plain text is one line as written, its
    /// ends trimmed and only Mermaid's codes (`#quot;`, `#40;`) read; a Markdown one keeps its bold and italic pieces
    /// and breaks where it breaks. Several lines are 1.3 times the size apart, rounded, as Pele sets them.
    static func block(_ text: String?, labelType: UseCaseLabelType = .text, measurer: some DiagramTextMeasuring, room: CGFloat) -> DiagramTextBlock {
        guard let text, !text.isEmpty else { return empty(measurer) }
        let label: DiagramLabel = labelType == .markdown ? DiagramLabelDecoder.label(from: text, form: .markdown)
            : DiagramLabel(lines: [UseCaseCharacters.trimmed(mermaidCodesRead(text))])
        guard !label.isEmpty else {
            return DiagramTextBlock(lines: [""], lineWidths: [0], fontSize: measurer.fontSize, lineHeight: measurer.lineHeight)
        }
        return DiagramTextBlock(label: label, measurer: measurer, maximumWidth: room)
    }

    /// A title, whose tags, line breaks and entity codes are read as a node's are (Pele's `titleLabel`), in bold.
    static func titleBlock(_ text: String, measurer: some DiagramTextMeasuring, room: CGFloat) -> DiagramTextBlock? {
        let label = DiagramLabelDecoder.label(from: text, form: .plain)
        guard !label.isEmpty else { return nil }
        return DiagramTextBlock(label: label, measurer: measurer, maximumWidth: room)
    }

    static func empty(_ measurer: some DiagramTextMeasuring) -> DiagramTextBlock {
        DiagramTextBlock(lines: [], lineWidths: [], fontSize: measurer.fontSize, lineHeight: measurer.lineHeight)
    }

    /// `text` with each of Mermaid's codes (`#name;`, `#123;`) as its character, HTML's (`&amp;`) left as written, as
    /// Pele shows a plain label.
    static func mermaidCodesRead(_ text: String) -> String {
        // A text without the bytes of `#` and `;` holds no code; one with them is read character by character, which
        // keeps it as it is unless a code stands alone.
        guard text.utf8.contains(UInt8(ascii: "#")), text.utf8.contains(UInt8(ascii: ";")) else { return text }
        let characters = Array(text)
        var result = ""
        var index = 0
        while index < characters.count {
            if characters[index] == "#", let semicolon = characters[index...].prefix(12).firstIndex(of: ";") {
                let code = String(characters[index...semicolon])
                let decoded = DiagramLabelDecoder.decodingEntities(code)
                if decoded != code {
                    result += decoded
                    index = semicolon + 1
                    continue
                }
            }
            result.append(characters[index])
            index += 1
        }
        return result
    }
}
