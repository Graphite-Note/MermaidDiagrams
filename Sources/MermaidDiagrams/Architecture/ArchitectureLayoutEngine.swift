/**
 * File: ArchitectureLayoutEngine.swift
 * ------------------------------------
 * Layer: Core
 * Description: Lays an architecture diagram out as Pele's renderArchitecture does: the grid placed, its columns, rows
 *              and gaps sized, the groups' room kept, the edges routed, the groups' heads clear of the edges coming
 *              down through them, the services and junctions, and the page under the title.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Lays an architecture diagram out in Pele's measurements: services in 48-point squares (the options' `iconSize`),
/// their titles below wrapped at 108 points, 36 points between columns and rows (`iconSize` × 0.75, at least 40), 20
/// points round a group's content (`padding`), 8 round the page and the bold title 12 points above; tight, for a host
/// too narrow, 24-point gaps, 12 round a group's content and titles wrapped at 64.
public enum ArchitectureLayoutEngine {
    static let padding: CGFloat = 8
    static let titleGap: CGFloat = 12
    static let groupTitleWidth: CGFloat = 320
    static let tightGroupPadding: CGFloat = 12

    public static func layout(_ diagram: ArchitectureDiagram, typography: DiagramTypography, availableWidth: CGFloat? = nil,
                              isTight: Bool = false) -> ArchitectureLayout {
        let font = typography.font
        return layout(diagram, font: font, availableWidth: availableWidth, isTight: isTight) { fontSize, isBold in
            CoreTextDiagramTextMeasurer(font: font.resized(to: fontSize), isBold: isBold)
        }
    }

    /// `measurer` makes the measurer of a size, in bold or not.
    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: ArchitectureDiagram, font: DiagramFont, availableWidth: CGFloat? = nil,
                                                       isTight: Bool = false,
                                                       measurer: (_ fontSize: CGFloat, _ isBold: Bool) -> Measurer) -> ArchitectureLayout {
        let options = diagram.options
        let fontSize = options.fontSize ?? font.size
        let measurers = ArchitectureMeasurers(titleText: measurer(fontSize, false), edgeText: measurer((fontSize * 0.875).rounded(), false),
                                              diagramTitleText: measurer(fontSize, true), iconText: measurer(max(6, (fontSize * 0.75).rounded()), false))
        let grid = ArchitectureGridPlacement.grid(of: diagram)
        let sizes = ArchitectureGridSizes(diagram, grid: grid, measurers: measurers, iconSize: options.iconSize, isTight: isTight)
        let titleRoom = DiagramWidthFitting.titleRoom(availableWidth: availableWidth)
        let frames = ArchitectureGroupFrames(diagram, grid: grid, sizes: sizes, measurers: measurers,
                                             padding: min(options.padding, isTight ? tightGroupPadding : .infinity), badge: (fontSize * 1.25).rounded(),
                                             titleWidth: isTight ? max(80, titleRoom / 2) : groupTitleWidth)
        let edges = ArchitectureEdgeLayout(diagram, frames: frames, iconSize: options.iconSize)
        let title = PlaneMapLabel.block(diagram.title, measurer: measurers.diagramTitleText, maximumWidth: isTight ? titleRoom : PlaneMapLabel.unwrappedWidth)
        let titleHeight = title.map { block in block.size.height + titleGap } ?? 0
        let extent = edges.extent
        let size = CGSize(width: (max(extent.width, title?.size.width ?? 0) + 2 * padding).rounded(.up),
                          height: (extent.height + titleHeight + 2 * padding).rounded(.up))
        let offset = CGVector(dx: ((size.width - extent.width) / 2 - extent.minX).rounded(), dy: (padding + titleHeight - extent.minY).rounded())
        let nodes = diagram.nodes.indices.map { node in self.node(node, diagram: diagram, frames: frames, measurers: measurers, iconSize: options.iconSize) }
        return ArchitectureLayout(size: size, font: font.resized(to: fontSize),
                                  title: title.map { block in PlaneMapLabel.placed(block, at: CGPoint(x: size.width / 2, y: padding + block.size.height / 2)) },
                                  groups: groups(diagram, frames: frames, edges: edges).map { group in group.translated(by: offset) },
                                  edges: edges.edges.map { edge in edge.translated(by: offset) },
                                  edgeTexts: edges.texts.map { text in text.translated(by: offset) },
                                  nodes: nodes.map { node in node.translated(by: offset) })
    }

    /// Each group's box and head: the head starts at the left, or after the edges that come down through that corner.
    private static func groups(_ diagram: ArchitectureDiagram, frames: ArchitectureGroupFrames, edges: ArchitectureEdgeLayout) -> [ArchitectureLayoutGroup] {
        diagram.groups.indices.map { group in
            let frame = frames.frame(of: group)
            let headWidth = frames.headWidths[group]
            guard headWidth > 0 else { return ArchitectureLayoutGroup(identifier: diagram.groups[group].identifier, frame: frame, icon: nil, title: nil) }
            let band = frame.minY + frames.headHeights[group] + 12
            var crossings = edges.verticalRuns.filter { run in run.top < band && run.bottom > frame.minY && run.x > frame.minX && run.x < frame.maxX }
                .map(\.x).sorted()
            crossings.append(frame.maxX - 4)
            var start = frame.minX + 10
            for crossing in crossings {
                if crossing - 6 - start >= headWidth { break }
                start = max(start, crossing + 6)
            }
            if start + headWidth > frame.maxX - 4 { start = frame.minX + 10 }
            let middle = frame.minY + 6 + frames.headHeights[group] / 2
            var textStart = start
            var icon: ArchitectureLayoutIcon?
            if let name = diagram.groups[group].icon {
                let badge = frames.badge
                icon = ArchitectureLayoutIcon(name: name, frame: CGRect(x: start, y: middle - badge / 2, width: badge, height: badge))
                textStart += badge + 6
            }
            let title = frames.titles[group].map { text in PlaneMapLabel.placed(text, at: CGPoint(x: textStart + text.size.width / 2, y: middle)) }
            return ArchitectureLayoutGroup(identifier: diagram.groups[group].identifier, frame: frame, icon: icon, title: title)
        }
    }

    /// A junction's dot, or a service's square with its icon (or its text, cut to the square) and its title below.
    private static func node<Measurer: DiagramTextMeasuring>(_ node: Int, diagram: ArchitectureDiagram, frames: ArchitectureGroupFrames,
                                                             measurers: ArchitectureMeasurers<Measurer>, iconSize: CGFloat) -> ArchitectureLayoutNode {
        let declared = diagram.nodes[node]
        let anchor = frames.nodeAnchor(node)
        let half = iconSize / 2
        guard declared.kind == .service else {
            return ArchitectureLayoutNode(identifier: declared.identifier, form: .junction(center: CGPoint(x: anchor.x, y: anchor.y + half),
                                                                                         radius: ArchitectureEdgeLayout.junctionRadius))
        }
        let square = CGRect(x: anchor.x - half, y: anchor.y, width: iconSize, height: iconSize)
        let glyph = iconSize * 0.5
        let icon = declared.icon.map { name in
            ArchitectureLayoutIcon(name: name, frame: CGRect(x: anchor.x - glyph / 2, y: anchor.y + (iconSize - glyph) / 2, width: glyph, height: glyph))
        }
        var iconText: DiagramTextBlock?
        if declared.icon == nil, let text = PlaneMapLabel.block(declared.iconText, measurer: measurers.iconText, maximumWidth: iconSize - 8) {
            let lines = max(1, Int(((iconSize - 4) / (text.lineHeight == 0 ? 1 : text.lineHeight)).rounded(.down)))
            let fitted = ArchitectureIcons.fitted(text, maximumWidth: iconSize - 8, maximumLines: lines, measurer: measurers.iconText)
            iconText = PlaneMapLabel.placed(fitted, at: CGPoint(x: anchor.x, y: anchor.y + half))
        }
        let title = frames.sizes.nodeTitles[node].map { text in
            PlaneMapLabel.placed(text, at: CGPoint(x: anchor.x, y: anchor.y + iconSize + ArchitectureGridSizes.titleGap + text.size.height / 2))
        }
        return ArchitectureLayoutNode(identifier: declared.identifier, form: .service(square: square, icon: icon, iconText: iconText, title: title))
    }
}

extension ArchitectureLayoutGroup {
    func translated(by offset: CGVector) -> ArchitectureLayoutGroup {
        ArchitectureLayoutGroup(identifier: identifier, frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), icon: icon?.translated(by: offset),
                                title: title?.translated(by: offset))
    }
}

extension ArchitectureLayoutIcon {
    func translated(by offset: CGVector) -> ArchitectureLayoutIcon {
        ArchitectureLayoutIcon(name: name, frame: frame.offsetBy(dx: offset.dx, dy: offset.dy))
    }
}

extension ArchitectureLayoutEdge {
    func translated(by offset: CGVector) -> ArchitectureLayoutEdge {
        ArchitectureLayoutEdge(sourceIdentifier: sourceIdentifier, targetIdentifier: targetIdentifier, path: path.translated(by: offset),
                               sourceArrow: sourceArrow?.translated(by: offset), targetArrow: targetArrow?.translated(by: offset))
    }
}

extension ArchitectureLayoutNode {
    func translated(by offset: CGVector) -> ArchitectureLayoutNode {
        switch form {
        case .junction(let center, let radius): return ArchitectureLayoutNode(identifier: identifier, form: .junction(center: center.translated(by: offset), radius: radius))
        case .service(let square, let icon, let iconText, let title):
            return ArchitectureLayoutNode(identifier: identifier, form: .service(square: square.offsetBy(dx: offset.dx, dy: offset.dy), icon: icon?.translated(by: offset),
                                                                                 iconText: iconText?.translated(by: offset), title: title?.translated(by: offset)))
        }
    }
}
