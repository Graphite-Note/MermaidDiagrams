/**
 * File: InfoDiagramLayoutEngine.swift
 * -----------------------------------
 * Layer: Core
 * Description: Lays an info diagram out with Pele's measurements.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Lays an info diagram out in Pele's style: the title in bold, centered, then the version line in the text's size and
/// the muted color, 8 points apart, 8 points of page around them. Pele prints its own name and version; this prints the
/// package's (`MermaidDiagramsVersion`).
public enum InfoDiagramLayoutEngine {
    /// Around the text.
    static let padding: CGFloat = 8
    /// Between the title and the version line.
    static let titleGap: CGFloat = 8
    /// The widest a line is before it wraps: wide enough that it does not.
    static let wrappingWidth: CGFloat = 4_000

    public static func layout(_ diagram: InfoDiagram, typography: DiagramTypography) -> InfoDiagramLayout {
        layout(diagram, text: typography.nodeText, boldText: typography.boldNodeText, font: typography.font)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: InfoDiagram, text: Measurer, boldText: Measurer, font: DiagramFont) -> InfoDiagramLayout {
        let title = diagram.title.map { title in
            DiagramTextBlock(label: DiagramLabelDecoder.label(from: title, form: .plain), measurer: boldText, maximumWidth: wrappingWidth)
        }.flatMap { block in block.lines.isEmpty ? nil : block }
        let version = DiagramTextBlock(label: DiagramLabel(MermaidDiagramsVersion.text), measurer: text, maximumWidth: wrappingWidth)
        let titleHeight = title.map { title in title.size.height + titleGap } ?? 0
        let size = CGSize(width: (max(title?.size.width ?? 0, version.size.width) + 2 * padding).rounded(.up),
                          height: (titleHeight + version.size.height + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + (title?.size.height ?? 0) / 2)
        var placedVersion = version
        placedVersion.center = CGPoint(x: size.width / 2, y: padding + titleHeight + version.size.height / 2)
        return InfoDiagramLayout(size: size, font: font, title: placedTitle, version: placedVersion)
    }
}
