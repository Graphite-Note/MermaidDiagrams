/**
 * File: ReadmePictures.swift
 * --------------------------
 * Layer: Benchmark
 * Description: Paints one documentation example of every diagram type with DiagramSceneRenderer as PNG pictures
 *              of at most 256 colors (IndexedPNGWriter), in the light and the dark palette Obsidian's default theme
 *              gives Pele, cropped to the diagram, and prints the README's gallery that shows them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import Foundation
import MermaidDiagrams

/// `--readme-pictures <folder>` writes `<type>-light.png` and `<type>-dark.png` for the example of each type chosen
/// here, then prints the README's gallery (the type's name, a `<picture>` that follows the reader's appearance, and the
/// example's text in a collapsed `<details>`). `--readme-pictures <folder> --every-example` writes instead every example
/// of every corpus (`<type>-<index>-light.png` and `-dark.png`), to choose from.
enum ReadmePictures {
    /// The documentation example a type's picture shows: its corpus and the example's place in it.
    struct ChosenExample {
        let kind: MermaidDiagramKind
        let corpus: String
        let exampleIndex: Int
    }

    /// Pixels per point, as a Retina screen shows the README.
    static let pixelsPerPoint: CGFloat = 2
    /// The widest a picture is, in pixels: twice the column GitHub shows a README in. A wider diagram is painted smaller.
    static let maximumPixelWidth: CGFloat = 1_760
    /// The page left around the diagram's painted pixels, in points.
    static let marginPoints: CGFloat = 12
    /// The day a Gantt chart's today line is drawn at, so that the pictures do not change from one run to the next.
    static let ganttToday = Date(timeIntervalSince1970: 1_706_745_600) // 2024-02-01, inside the documentation's charts.

    /// The example of each type the README shows, in the README's order.
    static let chosenExamples: [ChosenExample] = [
        ChosenExample(kind: .flowchart, corpus: "flowchart-docs", exampleIndex: 113),
        ChosenExample(kind: .sequence, corpus: "sequence-docs", exampleIndex: 1),
        ChosenExample(kind: .classDiagram, corpus: "class-docs", exampleIndex: 0),
        ChosenExample(kind: .stateDiagram, corpus: "state-docs", exampleIndex: 10),
        ChosenExample(kind: .entityRelationship, corpus: "er-docs", exampleIndex: 2),
        ChosenExample(kind: .userJourney, corpus: "journey-docs", exampleIndex: 0),
        ChosenExample(kind: .ganttChart, corpus: "gantt-docs", exampleIndex: 1),
        ChosenExample(kind: .pieChart, corpus: "pie-docs", exampleIndex: 0),
        ChosenExample(kind: .quadrantChart, corpus: "quadrant-docs", exampleIndex: 0),
        ChosenExample(kind: .requirement, corpus: "requirement-docs", exampleIndex: 1),
        ChosenExample(kind: .gitGraph, corpus: "git-docs", exampleIndex: 9),
        ChosenExample(kind: .c4, corpus: "c4-docs", exampleIndex: 4),
        ChosenExample(kind: .mindmap, corpus: "mindmap-docs", exampleIndex: 0),
        ChosenExample(kind: .timeline, corpus: "timeline-docs", exampleIndex: 3),
        ChosenExample(kind: .sankey, corpus: "sankey-docs", exampleIndex: 2),
        ChosenExample(kind: .xyChart, corpus: "xychart-docs", exampleIndex: 0),
        ChosenExample(kind: .block, corpus: "block-docs", exampleIndex: 26),
        ChosenExample(kind: .packet, corpus: "packet-docs", exampleIndex: 0),
        ChosenExample(kind: .kanban, corpus: "kanban-docs", exampleIndex: 2),
        ChosenExample(kind: .architecture, corpus: "architecture-docs", exampleIndex: 3),
        ChosenExample(kind: .radar, corpus: "radar-docs", exampleIndex: 1),
        ChosenExample(kind: .treemap, corpus: "treemap-docs", exampleIndex: 5),
        ChosenExample(kind: .venn, corpus: "venn-docs", exampleIndex: 0),
        ChosenExample(kind: .ishikawa, corpus: "ishikawa-docs", exampleIndex: 0),
        ChosenExample(kind: .treeView, corpus: "treeview-docs", exampleIndex: 9),
        ChosenExample(kind: .eventModel, corpus: "eventmodeling-docs", exampleIndex: 3),
        ChosenExample(kind: .railroad, corpus: "railroad-docs", exampleIndex: 8),
        ChosenExample(kind: .cynefin, corpus: "cynefin-docs", exampleIndex: 0),
        ChosenExample(kind: .wardleyMap, corpus: "wardley-docs", exampleIndex: 0),
        ChosenExample(kind: .swimlane, corpus: "swimlane-docs", exampleIndex: 5),
        ChosenExample(kind: .useCase, corpus: "usecase-docs", exampleIndex: 1),
        ChosenExample(kind: .agentFlow, corpus: "agentflow-docs", exampleIndex: 1),
        ChosenExample(kind: .info, corpus: "info-docs", exampleIndex: 0),
    ]

    /// An appearance the pictures are painted in, and the suffix of their names.
    struct Appearance {
        let name: String
        let palette: DiagramPalette
    }

    /// Obsidian's default theme on the desktop, as its `app.css` (1.15.1) maps Pele's roles: `--pele-bg` to
    /// `--background-primary`, `--pele-fg` and `--pele-line` to `--text-normal`, `--pele-muted` to `--text-muted`,
    /// `--pele-surface` to `--background-secondary`, `--pele-surface-alt` to `--background-primary-alt`, `--pele-border`
    /// to `--background-modifier-border-hover`, `--pele-accent` to `--interactive-accent`, `--pele-critical` to
    /// `--color-red`, and the series to blue, orange, green, red, cyan, yellow, purple and pink.
    static let appearances: [Appearance] = [
        Appearance(name: "light", palette: DiagramPalette(
            background: color(0xFFFFFF), foreground: color(0x222222), line: color(0x222222), surface: color(0xF6F6F6), border: color(0xDADADA),
            series: [0x086DDD, 0xEC7500, 0x08B94E, 0xE93147, 0x00BFBC, 0xE0AC00, 0x7852EE, 0xD53984].map(color),
            accent: color(0x9873F7), critical: color(0xE93147), muted: color(0x5C5C5C), alternateSurface: color(0xFAFAFA))),
        Appearance(name: "dark", palette: DiagramPalette(
            background: color(0x1C1C1C), foreground: color(0xDADADA), line: color(0xDADADA), surface: color(0x282828), border: color(0x3F3F3F),
            series: [0x027AFF, 0xE9973F, 0x44CF6E, 0xFB464C, 0x53DFDD, 0xE0DE71, 0xA882FF, 0xFA99CD].map(color),
            accent: color(0x8A5CF5), critical: color(0xFB464C), muted: color(0xB3B3B3), alternateSurface: color(0x232323))),
    ]

    struct PictureFailure: Error, CustomStringConvertible {
        let description: String
    }

    static func run(arguments: [String], typography: DiagramTypography) throws {
        guard let folderPath = arguments.first, !folderPath.hasPrefix("--") else {
            throw PictureFailure(description: "--readme-pictures needs the folder to write the pictures into")
        }
        let folder = URL(fileURLWithPath: folderPath, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if arguments.contains("--every-example") {
            try writeEveryExample(into: folder, typography: typography)
            return
        }
        var gallery: [String] = []
        for chosen in chosenExamples {
            let sources = try PeleResults.sources(ofCorpus: chosen.corpus)
            guard sources.indices.contains(chosen.exampleIndex) else {
                throw PictureFailure(description: "\(chosen.corpus) has no example \(chosen.exampleIndex)")
            }
            let source = sources[chosen.exampleIndex]
            let pixelWidth = try write(source, named: chosen.kind.peleName, into: folder, typography: typography)
            gallery.append(galleryEntry(for: chosen.kind, source: source, pointWidth: Int((CGFloat(pixelWidth) / pixelsPerPoint).rounded(.up))))
        }
        print(gallery.joined(separator: "\n"))
    }

    private static func writeEveryExample(into folder: URL, typography: DiagramTypography) throws {
        let corpora = Set(chosenExamples.map(\.corpus)).sorted()
        for corpus in corpora {
            for (exampleIndex, source) in try PeleResults.sources(ofCorpus: corpus).enumerated() {
                do {
                    _ = try write(source, named: "\(corpus)-\(exampleIndex)", into: folder, typography: typography)
                } catch {
                    print("\(corpus) \(exampleIndex): \(error)")
                }
            }
        }
    }

    /// The source prepared and painted in each appearance into `<name>-<appearance>.png`; the widest picture's pixels.
    private static func write(_ source: String, named name: String, into folder: URL, typography: DiagramTypography) throws -> Int {
        let prepared = try MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: nil, now: ganttToday,
                                                             timeZone: TimeZone(identifier: "UTC") ?? .current)
        var widestPixelWidth = 0
        for appearance in appearances {
            guard let image = picture(of: prepared.scene, palette: appearance.palette) else {
                throw PictureFailure(description: "\(name) could not be painted")
            }
            let fileURL = folder.appendingPathComponent("\(name)-\(appearance.name).png")
            try IndexedPNGWriter.pngData(of: image).write(to: fileURL)
            widestPixelWidth = max(widestPixelWidth, image.width)
        }
        return widestPixelWidth
    }

    /// The scene painted on its palette's background, cropped to the pixels the diagram painted and a margin.
    static func picture(of scene: DiagramScene, palette: DiagramPalette) -> CGImage? {
        let scale = min(pixelsPerPoint, maximumPixelWidth / max(1, scene.size.width + 2 * marginPoints))
        let margin = marginPoints * scale
        let width = max(1, Int((scene.size.width * scale + 2 * margin).rounded(.up)))
        let height = max(1, Int((scene.size.height * scale + 2 * margin).rounded(.up)))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(palette.background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: margin, y: CGFloat(height) - margin)
        context.scaleBy(x: scale, y: -scale)
        DiagramSceneRenderer.draw(scene, in: context, palette: palette)
        guard let image = context.makeImage() else { return nil }
        guard let painted = paintedBounds(of: context, width: width, height: height) else { return image }
        let cropped = painted.insetBy(dx: -margin.rounded(), dy: -margin.rounded()).intersection(CGRect(x: 0, y: 0, width: width, height: height))
        return image.cropping(to: cropped) ?? image
    }

    /// The smallest rectangle, in the image's pixels from its top left, holding every pixel unlike the top left one.
    private static func paintedBounds(of context: CGContext, width: Int, height: Int) -> CGRect? {
        guard let pixels = context.data?.bindMemory(to: UInt32.self, capacity: width * height) else { return nil }
        let colorBits: UInt32 = 0x00FF_FFFF // The red, green and blue bytes; the fourth is skipped and holds anything.
        let background = pixels[0] & colorBits
        var top = height, bottom = -1, left = width, right = -1
        for row in 0..<height {
            let rowStart = row * width
            for column in 0..<width where pixels[rowStart + column] & colorBits != background {
                top = min(top, row)
                bottom = max(bottom, row)
                left = min(left, column)
                right = max(right, column)
            }
        }
        guard bottom >= top, right >= left else { return nil }
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }

    /// The README's entry for one type: its name, the picture in the reader's appearance at its size in points (a page
    /// narrower than that shrinks it), the example's text.
    private static func galleryEntry(for kind: MermaidDiagramKind, source: String, pointWidth: Int) -> String {
        let name = kind.peleName
        let shownSource = source.trimmingCharacters(in: .newlines)
        return """
        ### \(kind.spokenName)

        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="docs/pictures/\(name)-dark.png">
          <img alt="\(kind.spokenName), drawn by the package" width="\(pointWidth)" src="docs/pictures/\(name)-light.png">
        </picture>

        <details><summary>Source</summary>

        ```text
        \(shownSource)
        ```

        </details>

        """
    }

    private static func color(_ value: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
