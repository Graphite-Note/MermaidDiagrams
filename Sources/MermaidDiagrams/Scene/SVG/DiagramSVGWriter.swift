/**
 * File: DiagramSVGWriter.swift
 * ----------------------------
 * Layer: Core
 * Description: Writes any diagram's scene as a standalone SVG document in Pele's structure: escaped text, no script and
 *              no external reference.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Writes a scene as a standalone SVG document, as Pele's SVG is built: the root `svg` with Pele's classes (`pele
/// pele-<type>`), its view box the scene's page, its title and description for screen readers, then each item back to
/// front, a `path` per shape and a `text` per placed text, each with Pele's class for its part (`pele-node`,
/// `pele-edge-label`). Every text is escaped; nothing is a script or refers outside the document (a gradient is named
/// within it). Numbers are written to two decimals without trailing zeros.
public struct DiagramSVGWriter: Sendable {
    public var colors: DiagramSVGColors
    /// What the document's ids start with (`<prefix>-title`, `<prefix>-gradient-1`), so that several documents can share
    /// a page: letters, digits, `-` and `_` only, else `pele`.
    public var identifierPrefix: String
    /// Whether the page is filled in the background color first; Pele leaves it to the page behind the drawing.
    public var paintsBackground: Bool

    public init(colors: DiagramSVGColors = .peleVariables, identifierPrefix: String = "pele", paintsBackground: Bool = false) {
        self.colors = colors
        let isSafe = !identifierPrefix.isEmpty && identifierPrefix.unicodeScalars.allSatisfy(Self.isIdentifierCharacter)
        self.identifierPrefix = isSafe ? identifierPrefix : "pele"
        self.paintsBackground = paintsBackground
    }

    /// The document. `diagramType` is Pele's name of the type (`flowchart`, `er`, `gitGraph`), given to the root's class
    /// and role description; `title` and `description` are what a screen reader reads (`accTitle`, `accDescr`).
    public func document(of scene: DiagramScene, diagramType: String, title: String? = nil, description: String? = nil) -> String {
        let width = DiagramSVGSyntax.number(scene.size.width)
        let height = DiagramSVGSyntax.number(scene.size.height)
        let type = DiagramSVGSyntax.escaped(diagramType)
        var head = ""
        var labelling = ""
        if let title, !title.isEmpty {
            head += "<title id=\"\(identifierPrefix)-title\">\(DiagramSVGSyntax.escaped(title))</title>"
            labelling += " aria-labelledby=\"\(identifierPrefix)-title\""
        }
        if let description, !description.isEmpty {
            head += "<desc id=\"\(identifierPrefix)-desc\">\(DiagramSVGSyntax.escaped(description))</desc>"
            labelling += " aria-describedby=\"\(identifierPrefix)-desc\""
        }
        var body = DiagramSVGBody(colors: colors, identifierPrefix: identifierPrefix)
        if paintsBackground {
            let background = colors.text(of: .background)
            body.content += "<rect width=\"\(width)\" height=\"\(height)\" fill=\"\(background.color)\"\(Self.opacity(background.opacity, "fill-opacity"))/>"
        }
        for item in scene.items { body.add(item) }
        let definitions = body.definitions.isEmpty ? "" : "<defs>" + body.definitions + "</defs>"
        let style = colors.rootStyle + "font-family:" + fontFamily(scene.font) + ";font-size:" + DiagramSVGSyntax.number(scene.font.size) + "px"
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" class=\"pele pele-\(type)\" viewBox=\"0 0 \(width) \(height)\" "
            + "width=\"\(width)\" height=\"\(height)\" style=\"\(DiagramSVGSyntax.escaped(style))\" role=\"graphics-document document\" "
            + "aria-roledescription=\"\(type)\"\(labelling)>" + head + definitions + body.content + "</svg>"
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

    /// Letters, digits, `-` and `_` of ASCII: what an SVG id is made of here.
    private static func isIdentifierCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", "-", "_": true
        default: false
        }
    }

    /// An opacity attribute, or nothing for full opacity.
    static func opacity(_ opacity: CGFloat, _ attribute: String) -> String {
        opacity >= 1 ? "" : " \(attribute)=\"\(DiagramSVGSyntax.number(max(0, opacity)))\""
    }
}

