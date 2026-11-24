/**
 * File: MermaidDiagramEventModelPreparation.swift
 * -----------------------------------------------
 * Layer: Core
 * Description: Prepares an event model, with the model down a narrow column a card per frame, and says what a screen
 *              reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

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
}

extension MermaidDiagramAccessibility {
    /// Each frame by its kind and name, in the order of time: “Command AddItem”.
    init(eventModel diagram: EventModelDiagram) {
        self.init(kind: .eventModel, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription) {
            let frames = diagram.frames.map { frame in Self.spokenKind(frame.kind) + " " + frame.name }
            return frames
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
