/**
 * File: PreparedMermaidDiagram.swift
 * ----------------------------------
 * Layer: Core
 * Description: A diagram read, laid out and turned into its scene, with its scene for a narrow column where its type has
 *              one, what a screen reader says of it, and its SVG.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A diagram ready to draw: its scene, its scene for a narrow column where its type turns to run down, what a screen
/// reader says of it, and how many of its statements are read and not applied. It holds no color: any palette paints it.
public struct PreparedMermaidDiagram: Sendable {
    /// The width past which a diagram is laid out a second time for a narrow column: an iPhone's in portrait, the
    /// narrowest column a reading view has. A diagram no wider fits every column as it is.
    public static let standardNarrowestColumnWidth: CGFloat = 280

    public let kind: MermaidDiagramKind
    /// The diagram laid out as it is written.
    public let scene: DiagramScene
    /// The diagram turned to run down where it runs across (and, for a flowchart, with Pele's tighter gaps), as Pele lays
    /// out one too wide for its container; nil when its type has no such layout, it is no wider than the narrowest
    /// column, or turned it is no narrower.
    public let narrowScene: DiagramScene?
    public let accessibility: MermaidDiagramAccessibility
    /// Statements read and not applied (styling a type does not draw yet, `click`): the drawing may differ from Obsidian's.
    public let unappliedStatementCount: Int

    public init(kind: MermaidDiagramKind, scene: DiagramScene, narrowScene: DiagramScene? = nil, accessibility: MermaidDiagramAccessibility,
                unappliedStatementCount: Int = 0) {
        self.kind = kind
        self.scene = scene
        self.narrowScene = narrowScene
        self.accessibility = accessibility
        self.unappliedStatementCount = unappliedStatementCount
    }

    /// Whether a column `columnWidth` wide shows the narrow scene: when the regular one, at `scale` times its size, is
    /// wider than the column and the narrow one is narrower than it. A column not measured yet (0) shows the regular one.
    public func showsNarrowScene(inColumnWidth columnWidth: CGFloat, scale: CGFloat = 1) -> Bool {
        guard let narrowScene, columnWidth > 0 else { return false }
        let regularWidth = scene.size.width * scale
        return regularWidth > columnWidth && narrowScene.size.width * scale < regularWidth
    }

    /// The scene a column `columnWidth` wide shows (`showsNarrowScene(inColumnWidth:scale:)`).
    public func scene(inColumnWidth columnWidth: CGFloat, scale: CGFloat = 1) -> DiagramScene {
        showsNarrowScene(inColumnWidth: columnWidth, scale: scale) ? narrowScene ?? scene : scene
    }

    /// The regular scene as a standalone SVG document, with the diagram's title and description for screen readers.
    public func svgDocument(colors: DiagramSVGColors = .peleVariables, identifierPrefix: String = "pele") -> String {
        DiagramSVGWriter(colors: colors, identifierPrefix: identifierPrefix)
            .document(of: scene, diagramType: kind.peleName, title: accessibility.title, description: accessibility.description)
    }
}
