/**
 * File: SVGWritingLoop.swift
 * --------------------------
 * Layer: Benchmark
 * Description: The work of `--profile <case> svg`, `svg-bytes` and `svg-flat`: the SVG documents of a case's inputs,
 *              prepared once, written again and again as a String, as bytes a host takes, or from scenes whose paths
 *              hold their elements, so that a sampler sees only the writing.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import MermaidDiagrams

enum SVGWritingLoop {
    /// How the documents are written.
    enum Form {
        /// `PreparedMermaidDiagram.svgDocument()`: Pele's variables, the title and the description, as a String.
        case string
        /// The same document's bytes handed to a host (`DiagramSVGWriter.withDocumentBytes`), which counts them.
        case bytes
        /// The same document as a String, of scenes whose paths are made again from their elements: Core Graphics then
        /// gives each path's elements out as it holds them, without working out a rounded rectangle, an ellipse or an
        /// arc it holds whole, as the scene's own storage of elements will give them out.
        case flatPaths
    }

    static func round(sources: [String], typography: DiagramTypography, form: Form) -> () -> Void {
        let prepared = sources.compactMap { source in
            try? MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: nil,
                                                   now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone)
        }
        let writer = DiagramSVGWriter()
        switch form {
        case .string:
            return { for diagram in prepared { _ = diagram.svgDocument() } }
        case .bytes:
            return {
                for diagram in prepared {
                    _ = writer.withDocumentBytes(of: diagram.scene, diagramType: diagram.kind.peleName, title: diagram.accessibility.title,
                                                 description: diagram.accessibility.description) { bytes in bytes.count }
                }
            }
        case .flatPaths:
            let scenes = prepared.map { diagram in (flattened(diagram.scene), diagram.kind.peleName, diagram.accessibility) }
            return {
                for (scene, type, accessibility) in scenes {
                    _ = writer.document(of: scene, diagramType: type, title: accessibility.title, description: accessibility.description)
                }
            }
        }
    }

    /// The scene with each shape's path made again from its elements.
    private static func flattened(_ scene: DiagramScene) -> DiagramScene {
        let items = scene.items.map { item -> DiagramSceneItem in
            guard case .shape(let shape) = item else { return item }
            let path = CGMutablePath()
            shape.path.applyWithBlock { element in
                let points = element.pointee.points
                switch element.pointee.type {
                case .moveToPoint: path.move(to: points[0])
                case .addLineToPoint: path.addLine(to: points[0])
                case .addQuadCurveToPoint: path.addQuadCurve(to: points[1], control: points[0])
                case .addCurveToPoint: path.addCurve(to: points[2], control1: points[0], control2: points[1])
                case .closeSubpath: path.closeSubpath()
                @unknown default: break
                }
            }
            return .shape(DiagramSceneShape(path: path, painting: shape.painting, part: shape.part))
        }
        return DiagramScene(size: scene.size, font: scene.font, items: items, seriesColors: scene.seriesColors)
    }
}
