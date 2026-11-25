/**
 * File: DiagramSVGWriter.swift
 * ----------------------------
 * Layer: Core
 * Description: Writes any diagram's scene as a standalone SVG document in Pele's structure: escaped text, no script and
 *              no external reference, written as UTF-8 front to back into the thread's reused block of bytes, handed
 *              to a host as those bytes or made a String once.
 *
 * Authors: Bahey Shalash
 * Version: 0.8
 * Date: 25/11/2026
 */

import CoreGraphics

/// Writes a scene as a standalone SVG document, as Pele's SVG is built: the root `svg` with Pele's classes (`pele
/// pele-<type>`), its view box the scene's page, its title and description for screen readers, then each item back to
/// front, a `path` per shape and a `text` per placed text, each with Pele's class for its part (`pele-node`,
/// `pele-edge-label`). Every text is escaped; nothing is a script or refers outside the document (a gradient is named
/// within it). Numbers are written to two decimals without trailing zeros. The series colors a diagram's theme variables
/// set are written as Pele writes them, `--pele-series-N` declarations on the root's style, with Pele's variables, and are
/// the series' colors written out with a palette. The document is written into a block of bytes the thread keeps from
/// one document to the next (`DiagramSVGScratch`), so that writing allocates nothing but the String it returns, or
/// nothing at all for a host that takes the bytes (`withDocumentBytes`).
public struct DiagramSVGWriter: Sendable {
    public var colors: DiagramSVGColors
    /// What the document's ids start with (`<prefix>-title`, `<prefix>-gradient-1`), so that several documents can share
    /// a page: letters, digits, `-` and `_` only, else `pele`, whether it is given to `init` or set afterwards, as it is
    /// written into attributes unescaped.
    public var identifierPrefix: String {
        get { safeIdentifierPrefix }
        set { safeIdentifierPrefix = Self.safeIdentifierPrefix(newValue) }
    }
    /// Whether the page is filled in the background color first; Pele leaves it to the page behind the drawing.
    public var paintsBackground: Bool
    private var safeIdentifierPrefix: String

    public init(colors: DiagramSVGColors = .peleVariables, identifierPrefix: String = "pele", paintsBackground: Bool = false) {
        self.colors = colors
        safeIdentifierPrefix = Self.safeIdentifierPrefix(identifierPrefix)
        self.paintsBackground = paintsBackground
    }

    /// The document. `diagramType` is Pele's name of the type (`flowchart`, `er`, `gitGraph`), given to the root's class
    /// and role description; `title` and `description` are what a screen reader reads (`accTitle`, `accDescr`).
    public func document(of scene: DiagramScene, diagramType: String, title: String? = nil, description: String? = nil) -> String {
        withDocumentBytes(of: scene, diagramType: diagramType, title: title, description: description) { bytes in DiagramSVGBuffer.string(of: bytes) }
    }

    /// Calls `body` with the document's UTF-8 bytes, the bytes `document(of:diagramType:title:description:)` makes a
    /// String of, without that String: for a host that writes the document to a file or a stream. The bytes are valid
    /// only while `body` runs; a document written from inside `body` is written into a block of its own.
    public func withDocumentBytes<Result>(of scene: DiagramScene, diagramType: String, title: String? = nil, description: String? = nil,
                                          _ body: (UnsafeBufferPointer<UInt8>) throws -> Result) rethrows -> Result {
        try DiagramSVGScratch.withThreadScratch { scratch in
            let colors = colors.overSeriesColors(of: scene)
            var document = DiagramSVGBody(colors: colors, identifierPrefix: identifierPrefix, content: DiagramSVGBuffer(lentBy: scratch))
            write(scene, diagramType: diagramType, title: title.flatMap(Self.nonEmpty), description: description.flatMap(Self.nonEmpty),
                  colors: colors, scratch: scratch, into: &document)
            return try body(document.content.bytes)
        }
    }

    private static func nonEmpty(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }

    private func write(_ scene: DiagramScene, diagramType: String, title: String?, description: String?, colors: DiagramSVGColors,
                       scratch: DiagramSVGScratch, into document: inout DiagramSVGBody) {
        appendRootOpening(of: scene, diagramType: diagramType, colors: colors, scratch: scratch,
                          isLabelled: (title != nil, description != nil), into: &document.content)
        if let title { appendHeadElement("title", suffix: "-title", text: title, into: &document.content) }
        if let description { appendHeadElement("desc", suffix: "-desc", text: description, into: &document.content) }
        if DiagramSVGBody.hasGradientFills(scene) { document.appendDefinitions(of: scene) }
        if paintsBackground { appendBackground(of: scene, into: &document) }
        document.addItems(of: scene)
        document.content.append("</svg>")
    }

    /// The root `svg` element's opening tag: Pele's classes, the view box and size, the style with the font and the
    /// colors' declarations, the roles, and the ids of the title and description when there are any.
    private func appendRootOpening(of scene: DiagramScene, diagramType: String, colors: DiagramSVGColors, scratch: DiagramSVGScratch,
                                   isLabelled: (byTitle: Bool, byDescription: Bool), into document: inout DiagramSVGBuffer) {
        document.append("<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" class=\"pele pele-")
        document.appendEscaped(diagramType)
        document.reserve(64 + 4 * DiagramSVGNumberWriting.largestNumberByteCount)
        document.write("\" viewBox=\"0 0 ")
        writeSize(of: scene, separator: " ", into: &document)
        document.write("\" width=\"")
        writeSize(of: scene, separator: "\" height=\"", into: &document)
        document.write("\" style=\"")
        appendRootStyleAndFontFamily(scene.font, colors: colors, scratch: scratch, into: &document)
        document.reserve(16 + DiagramSVGNumberWriting.largestNumberByteCount)
        document.write(";font-size:")
        document.write(number: scene.font.size)
        document.write("px")
        if case .peleVariables = colors { appendSeriesDeclarations(scene.seriesColors, into: &document) }
        document.append("\" role=\"graphics-document document\" aria-roledescription=\"")
        document.appendEscaped(diagramType)
        document.append("\"")
        if isLabelled.byTitle { appendIdentifierAttribute(" aria-labelledby=\"", suffix: "-title\"", into: &document) }
        if isLabelled.byDescription { appendIdentifierAttribute(" aria-describedby=\"", suffix: "-desc\"", into: &document) }
        document.append(">")
    }

    /// The colors' root style and `font-family:` with the font's family, escaped, as 0.7.0 wrote them piece by piece
    /// (which escapes them as their joined text would be): made once for these colors and this font and kept in the
    /// thread's scratch, as a host writes the same few again and again.
    private func appendRootStyleAndFontFamily(_ font: DiagramFont, colors: DiagramSVGColors, scratch: DiagramSVGScratch,
                                              into document: inout DiagramSVGBuffer) {
        let isPeleVariables: Bool
        if case .peleVariables = colors { isPeleVariables = true } else { isPeleVariables = false }
        if !scratch.hasRootStyle(isPeleVariables: isPeleVariables, postScriptName: font.postScriptName) {
            var style = DiagramSVGBuffer(reservingCapacity: 1_024)
            style.appendEscaped(colors.rootStyle)
            style.append("font-family:")
            style.appendEscaped(Self.fontFamily(font, isPeleVariables: isPeleVariables))
            scratch.keepRootStyle(Array(style.bytes), isPeleVariables: isPeleVariables, postScriptName: font.postScriptName)
        }
        scratch.rootStyle.withUnsafeBufferPointer { bytes in document.append(bytes) }
    }

    /// `DiagramSeriesColors.styleDeclarations`, escaped, written piece by piece: `;--pele-series-N:<color>` for each slot
    /// set.
    private func appendSeriesDeclarations(_ seriesColors: DiagramSeriesColors, into document: inout DiagramSVGBuffer) {
        let colors = seriesColors.colors
        for slot in colors.indices {
            guard let color = colors[slot] else { continue }
            document.reserve(16 + DiagramSVGNumberWriting.largestNumberByteCount)
            document.write(";--pele-series-")
            document.write(number: CGFloat(slot + 1))
            document.write(byte: UInt8(ascii: ":"))
            document.appendEscaped(color.cssText)
        }
    }

    /// The page's width, `separator`, then its height, within the room reserved.
    private func writeSize(of scene: DiagramScene, separator: StaticString, into document: inout DiagramSVGBuffer) {
        document.write(number: scene.size.width)
        document.write(separator)
        document.write(number: scene.size.height)
    }

    /// ` aria-labelledby="<prefix>-title"` and the like: `opening` and `suffix` hold the quotes.
    private func appendIdentifierAttribute(_ opening: StaticString, suffix: StaticString, into document: inout DiagramSVGBuffer) {
        document.append(opening)
        document.append(identifierPrefix)
        document.append(suffix)
    }

    /// `<title id="<prefix>-title">…</title>` and the like.
    private func appendHeadElement(_ name: StaticString, suffix: StaticString, text: String, into document: inout DiagramSVGBuffer) {
        document.append("<")
        document.append(name)
        document.append(" id=\"")
        document.append(identifierPrefix)
        document.append(suffix)
        document.append("\">")
        document.appendEscaped(text)
        document.append("</")
        document.append(name)
        document.append(">")
    }

    /// The page filled in the background's color.
    private func appendBackground(of scene: DiagramScene, into document: inout DiagramSVGBody) {
        document.content.reserve(DiagramSVGBody.fillRoom + 2 * DiagramSVGNumberWriting.largestNumberByteCount + 32)
        document.content.write("<rect width=\"")
        writeSize(of: scene, separator: "\" height=\"", into: &document.content)
        document.content.write("\" fill=\"")
        let opacity = document.paints.writeColor(of: .background, into: &document.content)
        document.content.write(byte: UInt8(ascii: "\""))
        document.content.write(opacity: opacity, attribute: " fill-opacity=\"")
        document.content.write("/>")
    }

    /// The font the text was measured in: by its PostScript name, else the system's, behind Pele's `--pele-font` when the
    /// colors are Pele's variables.
    private static func fontFamily(_ font: DiagramFont, isPeleVariables: Bool) -> String {
        let family = font.postScriptName.map { name in "\"\(name.filter { character in character != "\"" && character != "\\" })\",sans-serif" }
            ?? "system-ui,-apple-system,sans-serif"
        return isPeleVariables ? "var(--pele-font,\(family))" : family
    }

    /// `prefix` when it is made of identifier characters only, else `pele`: Pele's own, which nearly every document is
    /// written with, is known to be.
    private static func safeIdentifierPrefix(_ prefix: String) -> String {
        if prefix == "pele" { return prefix }
        return !prefix.isEmpty && prefix.unicodeScalars.allSatisfy(isIdentifierCharacter) ? prefix : "pele"
    }

    /// Letters, digits, `-` and `_` of ASCII: what an SVG id is made of here.
    private static func isIdentifierCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", "-", "_": true
        default: false
        }
    }
}
