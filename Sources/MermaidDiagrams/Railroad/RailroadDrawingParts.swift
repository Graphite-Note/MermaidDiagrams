/**
 * File: RailroadDrawingParts.swift
 * --------------------------------
 * Layer: Core
 * Description: A laid-out railroad diagram's geometry grouped by how it is painted, its scene in Pele's colors and
 *              order, and its renderer.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics

/// A laid-out railroad diagram's geometry grouped by how it is painted, back to front as Pele draws a rule: its name,
/// its track and arrows in the line color, the dots at its ends, then its boxes (terminals as pills on the surface
/// color, names of rules on the background, special sequences on the background in a dashed outline, each outlined in
/// the border color) and their text, the counts in the muted color. Rules do not overlap, so each group holds every
/// rule's.
public struct RailroadDrawingParts {
    public let title: DiagramTextBlock?
    public let ruleNames: [DiagramTextBlock]
    public let track: CGPath
    public let arrows: CGPath
    public let markers: CGPath
    public let terminals: CGPath
    public let nonterminals: CGPath
    public let specials: CGPath
    /// Drawn in the system's monospaced font.
    public let terminalTexts: [DiagramTextBlock]
    public let nonterminalTexts: [DiagramTextBlock]
    /// Drawn in italics, the question marks around them in the muted color.
    public let specialTexts: [DiagramTextBlock]
    public let specialQuestionMarks: [DiagramTextBlock]
    public let counts: [DiagramTextBlock]
    public let lineWidth: CGFloat

    /// Pele's dashes of a special sequence's outline, and the corner of a name's box.
    public static let specialDashLengths: [CGFloat] = [4, 3]
    static let cornerRadius: CGFloat = 4

    public init(layout: RailroadLayout) {
        title = layout.title
        ruleNames = layout.rules.map(\.name)
        let paths = RailroadDrawingPaths(layout: layout, making: DiagramCoreGraphicsPaths())
        track = paths.track.path
        arrows = paths.arrows.path
        markers = paths.markers.path
        terminals = paths.terminals.path
        nonterminals = paths.nonterminals.path
        specials = paths.specials.path
        let boxes = layout.rules.flatMap(\.boxes)
        terminalTexts = boxes.filter { box in box.kind == .terminal }.map(\.text)
        nonterminalTexts = boxes.filter { box in box.kind == .nonterminal }.map(\.text)
        specialTexts = boxes.filter { box in box.kind == .special }.map(\.text)
        specialQuestionMarks = boxes.flatMap(\.questionMarks)
        counts = layout.rules.flatMap(\.counts)
        lineWidth = layout.lineWidth
    }
}

/// A railroad diagram's paths, grouped as `RailroadDrawingParts` groups them, recorded into the paths a maker makes:
/// Core Graphics paths for the drawing parts, lanes of the thread's scene workspace for the scene, the same elements.
struct RailroadDrawingPaths<Path: DiagramCurvedPathRecording> {
    let track: Path
    let arrows: Path
    let markers: Path
    let terminals: Path
    let nonterminals: Path
    let specials: Path

    init<Maker: DiagramPathMaking>(layout: RailroadLayout, making maker: Maker) where Maker.Path == Path {
        track = maker.makePath()
        arrows = maker.makePath()
        markers = maker.makePath()
        terminals = maker.makePath()
        nonterminals = maker.makePath()
        specials = maker.makePath()
        let radius = layout.markerRadius
        for rule in layout.rules {
            for piece in rule.track {
                let madeCount = maker.madePathCount
                let drawn = maker.makePath()
                DiagramEdgeDrawing.record(piece, into: drawn)
                track.addPath(drawn)
                maker.givePathsBack(downTo: madeCount)
            }
            for arrow in rule.arrows {
                arrows.addLines(between: arrow.points)
                arrows.closeSubpath()
            }
            for center in rule.markerCenters {
                markers.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
            }
        }
        for rule in layout.rules {
            for box in rule.boxes {
                let outlines: Path
                let corner: CGFloat
                switch box.kind {
                case .terminal: (outlines, corner) = (terminals, box.frame.height / 2)
                case .nonterminal: (outlines, corner) = (nonterminals, RailroadDrawingParts.cornerRadius)
                case .special: (outlines, corner) = (specials, RailroadDrawingParts.cornerRadius)
                }
                let clamped = min(corner, box.frame.width / 2, box.frame.height / 2)
                outlines.addRoundedRect(in: box.frame, cornerWidth: clamped, cornerHeight: clamped)
            }
        }
    }
}

extension DiagramScene {
    /// The railroad diagram's painting, in Pele's order and colors, its paths recorded into lanes of the thread's scene
    /// workspace.
    public init(layout: RailroadLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The scene with each of its lanes bounded as `limits` bound them (`DiagramSceneWorkspace.elementLimit(for:)`): a
    /// lane past its limit is emptied and the scene says so (`exceededPathElementLimit`), which the preparation refuses.
    public init(layout: RailroadLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            let paths = RailroadDrawingPaths(layout: layout, making: workspace)
            let line = DiagramStroke(lineWidth: layout.lineWidth)
            builder.title(layout.title)
            for rule in layout.rules { builder.text(rule.name, .foreground, isBold: true, part: .clusterLabel) }
            builder.stroke(paths.track, .line, line, part: .edge)
            builder.fill(paths.arrows, .line, part: .marker)
            builder.fill(paths.markers, .line, part: .marker)
            builder.fillAndStroke(paths.terminals, fill: .surface, stroke: .border, line, part: .node)
            builder.fillAndStroke(paths.nonterminals, fill: .background, stroke: .border, line, part: .node)
            builder.fillAndStroke(paths.specials, fill: .background, stroke: .border,
                                  DiagramStroke(lineWidth: layout.lineWidth, dashLengths: RailroadDrawingParts.specialDashLengths), part: .node)
            Self.addBoxTexts(of: layout, to: &builder)
            for rule in layout.rules { builder.texts(rule.counts, .muted, part: .edgeLabel) }
            return builder.scene(size: layout.size, font: layout.font)
        }
    }

    /// The boxes' text: the terminals' in the monospaced font, the names', the special sequences' question marks in the
    /// muted color, then their text in italics.
    private static func addBoxTexts(of layout: RailroadLayout, to builder: inout DiagramSceneBuilder) {
        for rule in layout.rules {
            for box in rule.boxes where box.kind == .terminal { builder.text(box.text, .foreground, isMonospaced: true, part: .label) }
        }
        for rule in layout.rules {
            for box in rule.boxes where box.kind == .nonterminal { builder.text(box.text, .foreground, part: .label) }
        }
        for rule in layout.rules {
            for box in rule.boxes { builder.texts(box.questionMarks, .muted, isItalic: true, part: .label) }
        }
        for rule in layout.rules {
            for box in rule.boxes where box.kind == .special { builder.text(box.text, .foreground, isItalic: true, part: .label) }
        }
    }
}

/// Draws a laid-out railroad diagram into a Core Graphics context whose origin is the layout's top left and whose y
/// runs down, by painting its scene with `DiagramSceneRenderer`.
public enum RailroadRenderer {
    public static func draw(_ layout: RailroadLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
