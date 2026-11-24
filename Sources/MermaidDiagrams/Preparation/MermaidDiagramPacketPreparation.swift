/**
 * File: MermaidDiagramPacketPreparation.swift
 * -------------------------------------------
 * Layer: Core
 * Description: Prepares a packet diagram, with its layout for a narrow column, and says what a screen reader hears of
 *              it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation

extension MermaidDiagramPreparationContext {
    func prepared(_ packet: PacketDiagram) -> PreparedMermaidDiagram {
        let layout = PacketDiagramLayoutEngine.layout(packet, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (packet, width) }, regularSize: layout.size, laidOut: { packet, width in
                PacketDiagramLayoutEngine.layout(packet, typography: typography, availableWidth: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .packet, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(packet: packet))
    }
}

extension MermaidDiagramAccessibility {
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
}
