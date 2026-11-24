/**
 * File: MermaidDiagramTrackPreparation.swift
 * ------------------------------------------
 * Layer: Core
 * Description: The preparation of the types laid out along tracks, event models and railroad diagrams: their scenes,
 *              their narrow scenes, and what a screen reader says of them.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

import CoreGraphics

extension MermaidDiagramPreparationContext {
    /// An event model across, and for a narrow column the model down that column, a card per frame, as Pele turns it.
    func prepared(_ diagram: EventModelDiagram) -> PreparedMermaidDiagram {
        let layout = EventModelLayoutEngine.layout(diagram, typography: typography)
        let narrow = turnedNarrowSceneIsWanted(forRegularSize: layout.size)
            ? turnedNarrowScene(of: narrowestColumnWidth.map { width in (diagram, width) }, regularSize: layout.size, laidOut: { diagram, width in
                EventModelLayoutEngine.layout(diagram, typography: typography, columnWidth: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .eventModel, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(eventModel: diagram))
    }

    /// A railroad diagram, and for a narrow column the diagram with Pele's tighter gaps and its long sequences folded
    /// into rows that fit the column.
    func prepared(_ diagram: RailroadDiagram) -> PreparedMermaidDiagram {
        let layout = RailroadLayoutEngine.layout(diagram, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (diagram, width) }, regularSize: layout.size, laidOut: { diagram, width in
                RailroadLayoutEngine.layout(diagram, typography: typography, columnWidth: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .railroad, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(railroad: diagram))
    }
}

extension MermaidDiagramAccessibility {
    /// Each frame by its kind and name, in the order of time: “Command AddItem”.
    init(eventModel diagram: EventModelDiagram) {
        self.init(kind: .eventModel, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription) {
            let frames = diagram.frames.map { frame in Self.spokenKind(frame.kind) + " " + frame.name }
            return frames
        }
    }

    /// Each rule by its name, in the order they are written.
    init(railroad diagram: RailroadDiagram) {
        self.init(kind: .railroad, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription) {
            diagram.rules.map(\.name)
        }
    }

    private static func spokenKind(_ kind: EventModelEntityKind) -> String {
        switch kind {
        case .userInterface: "Interface"
        case .processor: "Processor"
        case .command: "Command"
        case .readModel: "Read model"
        case .event: "Event"
        }
    }
}
