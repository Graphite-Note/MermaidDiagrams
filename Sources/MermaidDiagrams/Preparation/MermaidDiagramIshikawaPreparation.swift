/**
 * File: MermaidDiagramIshikawaPreparation.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: Prepares an Ishikawa diagram, with the diagram running down as an indented list for a narrow column,
 *              and says what a screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// An Ishikawa diagram, and for a narrow column the diagram running down as an indented list.
    func prepared(_ diagram: IshikawaDiagram) -> PreparedMermaidDiagram {
        let layout = IshikawaLayoutEngine.layout(diagram, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: diagram, regularSize: layout.size, laidOut: { diagram in
                IshikawaLayoutEngine.layout(diagram, typography: typography, maximumWidth: narrowestColumnWidth)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .ishikawa, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(ishikawa: diagram))
    }
}

extension MermaidDiagramAccessibility {
    /// The effect, then each category with its causes in the order written: “Blurry photo; Process: Out of focus, Too slow”.
    init(ishikawa diagram: IshikawaDiagram) {
        self.init(kind: .ishikawa, title: diagram.title, description: nil, summarySeparator: "; ") {
            var summary: [String] = []
            if let effect = diagram.nodes.first {
                summary.append(effect.text)
                for categoryIndex in effect.childIndices {
                    var causes: [String] = []
                    var pending = Array(diagram.nodes[categoryIndex].childIndices.reversed())
                    while let index = pending.popLast() {
                        causes.append(diagram.nodes[index].text)
                        pending += diagram.nodes[index].childIndices.reversed()
                    }
                    let category = diagram.nodes[categoryIndex].text
                    summary.append(causes.isEmpty ? category : category + ": " + causes.joined(separator: ", "))
                }
            }
            return summary
        }
    }
}
