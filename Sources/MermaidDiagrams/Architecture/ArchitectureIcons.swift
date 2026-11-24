/**
 * File: ArchitectureIcons.swift
 * -----------------------------
 * Layer: Core
 * Description: The icons Mermaid's architecture diagrams know without an icon pack, Pele's outlines on a 24 by 24 grid,
 *              and an icon's text cut down to its square with an ellipsis.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// Pele's built-in icons (`icons.ts`): cloud, database, disk, internet and server, stroked in the text color 1.5 grid
/// units wide. Any other name (`logos:aws-ec2`) is left to a host's icon resolver, which this package has none of: its
/// slot is drawn empty.
enum ArchitectureIcons {
    /// The stroke's width on the 24-unit grid.
    static let gridLineWidth: CGFloat = 1.5

    static let pathDataByName: [String: String] = [
        "database": "M4 6a8 3 0 1 0 16 0a8 3 0 1 0-16 0M4 6v12a8 3 0 0 0 16 0V6M4 12a8 3 0 0 0 16 0",
        "server": "M3 4h18v7H3zM3 13h18v7H3zM7 7.5h.01M7 16.5h.01M11 7.5h6M11 16.5h6",
        "disk": "M5 3h14v18H5zM12 6.5a4 4 0 1 0 0 8a4 4 0 1 0 0-8M12 10.5h.01M8 18h3",
        "internet": "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M3 12h18M12 3a13 13 0 0 0 0 18M12 3a13 13 0 0 1 0 18",
        "cloud": "M7 18a4 4 0 0 1-.5-7.97A6 6 0 0 1 18 9.5a4.25 4.25 0 0 1-.5 8.5z",
    ]

    /// The outline of the icon `name` in `frame`'s square, or nil for a name Pele has no outline for.
    static func outline(named name: String, in frame: CGRect) -> CGPath? {
        guard let data = pathDataByName[name], let glyph = DiagramGlyphPath(pathData: data) else { return nil }
        return glyph.path(in: frame)
    }

    /// Pele's `fit`: `block` cut to `maximumWidth` and `maximumLines`, each line too wide (and the last kept, when lines
    /// were left out) ended by an ellipsis after the longest start that fits with it.
    static func fitted(_ block: DiagramTextBlock, maximumWidth: CGFloat, maximumLines: Int, measurer: some DiagramTextMeasuring) -> DiagramTextBlock {
        let isCut = block.lineCount > maximumLines
        guard isCut || block.size.width > maximumWidth else { return block }
        let ellipsis = "…"
        let ellipsisWidth = measurer.width(of: ellipsis)
        var lines: [String] = []
        var widths: [CGFloat] = []
        for index in 0..<min(maximumLines, block.lineCount) {
            var line = block.line(at: index)
            var width = block.lineWidth(at: index)
            if width > maximumWidth || (isCut && index == maximumLines - 1) {
                if ellipsisWidth < maximumWidth {
                    let characters = Array(line)
                    var low = 0
                    var high = characters.count
                    while low < high {
                        let middle = (low + high + 1) / 2
                        if measurer.width(of: String(characters[..<middle])) + ellipsisWidth <= maximumWidth { low = middle } else { high = middle - 1 }
                    }
                    var kept = String(characters[..<low])
                    while kept.last?.isWhitespace == true { kept.removeLast() }
                    line = kept + ellipsis
                    width = measurer.width(of: line)
                } else {
                    line = ellipsis
                    width = ellipsisWidth
                }
            }
            lines.append(line)
            widths.append(width)
        }
        return DiagramTextBlock(lines: lines, lineWidths: widths, fontSize: block.fontSize, lineHeight: block.lineHeight, center: block.center)
    }
}
