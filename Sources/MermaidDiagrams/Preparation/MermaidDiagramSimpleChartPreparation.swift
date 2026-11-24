/**
 * File: MermaidDiagramSimpleChartPreparation.swift
 * ------------------------------------------------
 * Layer: Core
 * Description: Prepares the info diagram, the packet diagram, the radar chart and the treemap, and says what a screen reader
 *              hears of them.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

import Foundation

extension MermaidDiagramPreparationContext {
    func prepared(_ info: InfoDiagram) -> PreparedMermaidDiagram {
        PreparedMermaidDiagram(kind: .info, scene: DiagramScene(layout: InfoDiagramLayoutEngine.layout(info, typography: typography)),
                               accessibility: MermaidDiagramAccessibility(info: info))
    }

    func prepared(_ packet: PacketDiagram) -> PreparedMermaidDiagram {
        let layout = PacketDiagramLayoutEngine.layout(packet, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (packet, width) }, regularSize: layout.size, laidOut: { packet, width in
                PacketDiagramLayoutEngine.layout(packet, typography: typography, availableWidth: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .packet, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(packet: packet))
    }

    func prepared(_ radar: RadarChart) -> PreparedMermaidDiagram {
        let layout = RadarChartLayoutEngine.layout(radar, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (radar, width) }, regularSize: layout.size, laidOut: { radar, width in
                RadarChartLayoutEngine.layout(radar, typography: typography, availableWidth: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .radar, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(radar: radar))
    }

    func prepared(_ treemap: TreemapDiagram) -> PreparedMermaidDiagram {
        let layout = TreemapLayoutEngine.layout(treemap, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (treemap, width) }, regularSize: layout.size, laidOut: { treemap, width in
                TreemapLayoutEngine.layout(treemap, typography: typography, availableWidth: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .treemap, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(treemap: treemap), unappliedStatementCount: treemap.unappliedStatementCount)
    }
}

extension MermaidDiagramAccessibility {
    /// The package's name and version, which is all an info diagram shows besides its title.
    init(info diagram: InfoDiagram) {
        self.init(kind: .info, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription) {
            [MermaidDiagramsVersion.text]
        }
    }

    /// Each field with its bits, in the order the fields are written: “Source Port: bits 0 to 15”, “URG: bit 106”.
    init(packet diagram: PacketDiagram) {
        self.init(kind: .packet, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription, summarySeparator: "; ") {
            let fields = diagram.fields.map { field in
                let label = DiagramLabelDecoder.decodingEntities(field.label).trimmingCharacters(in: .whitespacesAndNewlines)
                let bits = field.firstBit == field.lastBit ? "bit \(field.firstBit)" : "bits \(field.firstBit) to \(field.lastBit)"
                return label.isEmpty ? bits : "\(label): \(bits)"
            }
            return fields
        }
    }

    /// Each curve with its value on each axis, when it is drawn: “Alice: Math 85, Science 90”; a curve that is not drawn is
    /// named alone.
    init(radar chart: RadarChart) {
        self.init(kind: .radar, title: chart.accessibilityTitle ?? chart.title, description: chart.accessibilityDescription, summarySeparator: "; ") {
            let curves = chart.curves.map { curve in
                let name = curve.label.spokenText
                guard curve.values.count == chart.axes.count, !chart.axes.isEmpty else { return name }
                let values = zip(chart.axes, curve.values).map { axis, value in "\(axis.label.spokenText) \(Self.written(value))" }
                return name + ": " + values.joined(separator: ", ")
            }
            return curves
        }
    }

    /// Each node in the order it is written: a section by its name, a leaf with its value as the treemap writes it
    /// (“Item A1: 10”).
    init(treemap diagram: TreemapDiagram) {
        self.init(kind: .treemap, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription, summarySeparator: "; ") {
            let format = TreemapValueFormat(specifier: diagram.options.valueFormat)
            let nodes = diagram.nodes.map { node in
                let name = DiagramLabelDecoder.decodingEntities(node.name).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !node.isSection, node.size > 0, diagram.options.showsValues else { return name }
                return "\(name): \(format.text(node.size))"
            }
            return nodes
        }
    }
}
