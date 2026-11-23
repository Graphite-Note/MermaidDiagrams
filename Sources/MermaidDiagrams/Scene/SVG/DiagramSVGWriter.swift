/**
 * File: DiagramSVGWriter.swift
 * ----------------------------
 * Layer: Core
 * Description: Writes any diagram's scene as a standalone SVG document in Pele's structure: escaped text, no script and
 *              no external reference, written as UTF-8 into one buffer.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
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
        var body = DiagramSVGBody(colors: colors, identifierPrefix: identifierPrefix,
                                  content: DiagramSVGBuffer(reservingCapacity: Self.estimatedByteCount(of: scene)))
        let title = title.flatMap { title in title.isEmpty ? nil : title }
        let description = description.flatMap { description in description.isEmpty ? nil : description }
        appendRootOpening(of: scene, diagramType: diagramType, colors: colors, isLabelled: (title != nil, description != nil), into: &body.content)
        if let title { appendHeadElement("title", suffix: "-title", text: title, into: &body.content) }
        if let description { appendHeadElement("desc", suffix: "-desc", text: description, into: &body.content) }
        let definitionsOffset = body.content.count
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
        if !body.definitions.isEmpty {
            var definitions = DiagramSVGBuffer(reservingCapacity: body.definitions.count + 13)
            definitions.append("<defs>")
            definitions.append(body.definitions)
            definitions.append("</defs>")
            body.content.insert(definitions, at: definitionsOffset)
        }
        return body.content.text
    }

    /// The root `svg` element's opening tag: Pele's classes, the view box and size, the style with the font and the
    /// colors' declarations, the roles, and the ids of the title and description when there are any.
    private func appendRootOpening(of scene: DiagramScene, diagramType: String, colors: DiagramSVGColors,
                                   isLabelled: (byTitle: Bool, byDescription: Bool), into document: inout DiagramSVGBuffer) {
        let style = colors.rootStyle + "font-family:" + fontFamily(scene.font) + ";font-size:" + DiagramSVGSyntax.number(scene.font.size) + "px"
            + colors.seriesStyle(of: scene)
        document.append("<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" class=\"pele pele-")
        document.appendEscaped(diagramType)
        document.append("\" viewBox=\"0 0 ")
        appendSize(of: scene, separator: " ", into: &document)
        document.append("\" width=\"")
        appendSize(of: scene, separator: "\" height=\"", into: &document)
        document.append("\" style=\"")
        document.appendEscaped(style)
        document.append("\" role=\"graphics-document document\" aria-roledescription=\"")
        document.appendEscaped(diagramType)
        document.append("\"")
        if isLabelled.byTitle { appendIdentifierAttribute("aria-labelledby", suffix: "-title", into: &document) }
        if isLabelled.byDescription { appendIdentifierAttribute("aria-describedby", suffix: "-desc", into: &document) }
        document.append(">")
    }

    /// About how many bytes a scene's SVG takes, so that its buffer seldom grows: a few hundred for the root, and for each
    /// item about what the documentation examples average.
    private static func estimatedByteCount(of scene: DiagramScene) -> Int {
        1_024 + scene.items.count * 160
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
