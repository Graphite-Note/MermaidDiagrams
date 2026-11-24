/**
 * File: DiagramSVGWriter.swift
 * ----------------------------
 * Layer: Core
 * Description: Writes any diagram's scene as a standalone SVG document in Pele's structure: escaped text, no script and
 *              no external reference, written as UTF-8 into one buffer reserved from the scene, front to back.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 24/11/2026
 */

import CoreGraphics

/// Writes a scene as a standalone SVG document, as Pele's SVG is built: the root `svg` with Pele's classes (`pele
/// pele-<type>`), its view box the scene's page, its title and description for screen readers, then each item back to
/// front, a `path` per shape and a `text` per placed text, each with Pele's class for its part (`pele-node`,
/// `pele-edge-label`). Every text is escaped; nothing is a script or refers outside the document (a gradient is named
/// within it). Numbers are written to two decimals without trailing zeros. The series colors a diagram's theme variables
/// set are written as Pele writes them, `--pele-series-N` declarations on the root's style, with Pele's variables, and are
/// the series' colors written out with a palette.
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
        let colors = colors.overSeriesColors(of: scene)
        let title = title.flatMap { title in title.isEmpty ? nil : title }
        let description = description.flatMap { description in description.isEmpty ? nil : description }
        let room = Self.estimatedRoom(of: scene)
        let byteCount = min(room.byteCount + (title?.utf8.count ?? 0) + (description?.utf8.count ?? 0), Self.largestReservedByteCount)
        var body = DiagramSVGBody(colors: colors, identifierPrefix: identifierPrefix, content: DiagramSVGBuffer(reservingCapacity: byteCount))
        appendRootOpening(of: scene, diagramType: diagramType, colors: colors, isLabelled: (title != nil, description != nil), into: &body.content)
        if let title { appendHeadElement("title", suffix: "-title", text: title, into: &body.content) }
        if let description { appendHeadElement("desc", suffix: "-desc", text: description, into: &body.content) }
        if room.hasGradientFills { body.appendDefinitions(of: scene.items) }
        if paintsBackground {
            let background = body.text(of: .background)
            body.content.append("<rect width=\"")
            appendSize(of: scene, separator: "\" height=\"", into: &body.content)
            body.content.append("\" fill=\"")
            body.content.append(background.color)
            body.content.append("\"")
            body.content.appendOpacity(background.opacity, attribute: "fill-opacity")
            body.content.append("/>")
        }
        for item in scene.items { body.add(item) }
        body.content.append("</svg>")
        return body.content.text
    }

    /// The root `svg` element's opening tag: Pele's classes, the view box and size, the style with the font and the
    /// colors' declarations, the roles, and the ids of the title and description when there are any. The style's pieces
    /// are escaped one after the other, which escapes them as their joined text would be.
    private func appendRootOpening(of scene: DiagramScene, diagramType: String, colors: DiagramSVGColors,
                                   isLabelled: (byTitle: Bool, byDescription: Bool), into document: inout DiagramSVGBuffer) {
        document.append("<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" class=\"pele pele-")
        document.appendEscaped(diagramType)
        document.append("\" viewBox=\"0 0 ")
        appendSize(of: scene, separator: " ", into: &document)
        document.append("\" width=\"")
        appendSize(of: scene, separator: "\" height=\"", into: &document)
        document.append("\" style=\"")
        document.appendEscaped(colors.rootStyle)
        document.append("font-family:")
        document.appendEscaped(fontFamily(scene.font))
        document.append(";font-size:")
        document.appendNumber(scene.font.size)
        document.append("px")
        if case .peleVariables = colors { appendSeriesDeclarations(scene.seriesColors, into: &document) }
        document.append("\" role=\"graphics-document document\" aria-roledescription=\"")
        document.appendEscaped(diagramType)
        document.append("\"")
        if isLabelled.byTitle { appendIdentifierAttribute("aria-labelledby", suffix: "-title", into: &document) }
        if isLabelled.byDescription { appendIdentifierAttribute("aria-describedby", suffix: "-desc", into: &document) }
        document.append(">")
    }

    /// `DiagramSeriesColors.styleDeclarations`, escaped, written piece by piece: `;--pele-series-N:<color>` for each slot
    /// set.
    private func appendSeriesDeclarations(_ seriesColors: DiagramSeriesColors, into document: inout DiagramSVGBuffer) {
        for (slot, color) in seriesColors.colors.enumerated() {
            guard let color else { continue }
            document.append(";--pele-series-")
            document.appendNumber(CGFloat(slot + 1))
            document.append(":")
            document.appendEscaped(color.cssText)
        }
    }

    /// How many bytes a scene's SVG takes at most on Pele's corpora, so that its buffer does not grow
    /// (`DiagramSVGWriterSpeedTests` checks it on every input): the root, and for each item what its element and
    /// attributes take around its text and path. A path's data is not counted element by element, which would walk it
    /// once more; a diagram's shapes are few, each of everything painted alike (every node's outline, every edge), so its
    /// paths grow with its texts, and each text is allowed its share of them beside its own bytes (an outlined text's
    /// twice). A scene that needs more grows the buffer a few times. The same walk over the items finds whether any is
    /// filled with a gradient, which needs `<defs>`.
    static func estimatedRoom(of scene: DiagramScene) -> (byteCount: Int, hasGradientFills: Bool) {
        var count = rootByteAllowance + scene.seriesColors.colors.count * seriesDeclarationByteAllowance
        var hasGradientFills = false
        for item in scene.items {
            switch item {
            case .shape(let shape):
                count += shapeByteAllowance
                if case .gradientFill = shape.painting { hasGradientFills = true }
            case .text(let text): count += estimatedByteCount(of: text)
            }
        }
        return (count, hasGradientFills)
    }

    /// The most room reserved at once, 4 MiB: a diagram near the limits writes more by growing its buffer, not by
    /// reserving what its estimate says.
    static let largestReservedByteCount = 1 << 22
    private static let rootByteAllowance = 1_024
    private static let seriesDeclarationByteAllowance = 64
    private static let shapeByteAllowance = 320
    private static let textByteAllowance = 704
    private static let lineByteAllowance = 64

    private static func estimatedByteCount(of text: DiagramSceneText) -> Int {
        var textByteCount = 0
        if let lineRuns = text.block.lineRuns {
            for runs in lineRuns { for run in runs { textByteCount += run.text.utf8.count + lineByteAllowance } }
        } else {
            for index in 0..<text.block.lineCount { textByteCount += text.block.withUTF8(ofLine: index) { bytes in bytes.count } }
        }
        textByteCount += text.block.lineCount * lineByteAllowance
        let copies = text.outline == nil ? 1 : 2
        return copies * (textByteAllowance + textByteCount)
    }

    /// The page's width, `separator`, then its height.
    private func appendSize(of scene: DiagramScene, separator: StaticString, into document: inout DiagramSVGBuffer) {
        document.appendNumber(scene.size.width)
        document.append(separator)
        document.appendNumber(scene.size.height)
    }

    /// ` aria-labelledby="<prefix>-title"` and the like.
    private func appendIdentifierAttribute(_ attribute: StaticString, suffix: StaticString, into document: inout DiagramSVGBuffer) {
        document.append(" ")
        document.append(attribute)
        document.append("=\"")
        document.append(identifierPrefix)
        document.append(suffix)
        document.append("\"")
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

    /// The font the text was measured in: by its PostScript name, else the system's, behind Pele's `--pele-font` when the
    /// colors are Pele's variables.
    private func fontFamily(_ font: DiagramFont) -> String {
        let family = font.postScriptName.map { name in "\"\(name.filter { character in character != "\"" && character != "\\" })\",sans-serif" }
            ?? "system-ui,-apple-system,sans-serif"
        switch colors {
        case .palette: return family
        case .peleVariables: return "var(--pele-font,\(family))"
        }
    }

    /// `prefix` when it is made of identifier characters only, else `pele`.
    private static func safeIdentifierPrefix(_ prefix: String) -> String {
        !prefix.isEmpty && prefix.unicodeScalars.allSatisfy(isIdentifierCharacter) ? prefix : "pele"
    }

    /// Letters, digits, `-` and `_` of ASCII: what an SVG id is made of here.
    private static func isIdentifierCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", "-", "_": true
        default: false
        }
    }
}
