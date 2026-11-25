/**
 * File: MermaidDiagramWardleyMapPreparation.swift
 * -----------------------------------------------
 * Layer: Core
 * Description: Prepares a Wardley map, with the map Pele draws tight and narrowed for a narrow column, and says what
 *              a screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A Wardley map, and for a narrow column the map Pele draws to fit it: tight, its plot narrowed.
    func prepared(_ map: WardleyMap) -> PreparedMermaidDiagram {
        let layout = WardleyMapLayoutEngine.layout(map, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: map, regularSize: layout.size, laidOut: { map in
                WardleyMapLayoutEngine.layout(map, typography: typography, fittingWidth: narrowestColumnWidth)
            }, scene: { layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .wardleyMap, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(wardleyMap: map))
    }
}

extension MermaidDiagramAccessibility {
    /// Each anchor and component in the order added, then each link between them: “Business; Cup of Tea; Business to Cup
    /// of Tea”.
    init(wardleyMap map: WardleyMap) {
        self.init(kind: .wardleyMap, title: map.accessibilityTitle ?? map.title, description: map.accessibilityDescription, summarySeparator: "; ") {
            var labelByIdentifier: [String: String] = [:]
            for node in map.nodes { labelByIdentifier[node.identifier] = node.label }
            let links = map.links.map { link in
                (labelByIdentifier[link.source] ?? link.source) + " to " + (labelByIdentifier[link.target] ?? link.target)
            }
            return map.nodes.map(\.label) + links
        }
    }
}
