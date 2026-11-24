/**
 * File: MermaidDiagramPlaneMapPreparation.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: Prepares the diagrams drawn on a fixed plane, Venn diagrams, Cynefin frameworks and Wardley maps, and says
 *              what a screen reader hears of them.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A Venn diagram, its style declarations not drawn counted.
    func prepared(_ venn: VennDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: VennLayout
        do { layout = try VennLayoutEngine.layout(venn, typography: typography, limits: limits) } catch { throw .vennLayout(error) }
        return PreparedMermaidDiagram(kind: .venn, scene: DiagramScene(layout: layout), accessibility: MermaidDiagramAccessibility(venn: venn),
                                      unappliedStatementCount: venn.unappliedDeclarationCount)
    }
}

extension MermaidDiagramPreparationContext {
    func prepared(_ cynefin: CynefinDiagram) -> PreparedMermaidDiagram {
        PreparedMermaidDiagram(kind: .cynefin, scene: DiagramScene(layout: CynefinLayoutEngine.layout(cynefin, typography: typography)),
                               accessibility: MermaidDiagramAccessibility(cynefin: cynefin))
    }

    /// A Wardley map, and for a narrow column the map Pele draws to fit it: tight, its plot narrowed.
    func prepared(_ map: WardleyMap) -> PreparedMermaidDiagram {
        let layout = WardleyMapLayoutEngine.layout(map, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: map, regularSize: layout.size, laidOut: { map in
                WardleyMapLayoutEngine.layout(map, typography: typography, fittingWidth: narrowestColumnWidth)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .wardleyMap, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
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

    /// Each domain that has items, in the order drawn, with its items, then each transition with its label: “Complex:
    /// Investigate root cause, Run chaos experiment; Complex to Complicated: Pattern identified”.
    init(cynefin diagram: CynefinDiagram) {
        self.init(kind: .cynefin, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription, summarySeparator: "; ") {
            let domains = CynefinLayoutEngine.quadrants.map(\.domain) + [.confusion]
            let itemTexts = domains.compactMap { domain -> String? in
                guard let items = diagram.items[domain], !items.isEmpty else { return nil }
                return domain.name + ": " + items.map(Self.spoken).joined(separator: ", ")
            }
            let transitionTexts = diagram.transitions.map { transition in
                let names = transition.from.name + " to " + transition.to.name
                return transition.label.map { label in names + ": " + Self.spoken(label) } ?? names
            }
            return itemTexts + transitionTexts
        }
    }

    /// Each set and stated overlap once, in the order written, with the texts written in it: “Frontend: React, Design
    /// Systems; Backend; Shared: OpenAPI”, an overlap without a label named by its sets (“A and B”). Mermaid's Venn grammar
    /// has no accessibility statements.
    init(venn diagram: VennDiagram) {
        let title = diagram.title.flatMap { title in title.isEmpty ? nil : Self.spoken(title) }
        self.init(kind: .venn, title: title, description: nil, summarySeparator: "; ") {
            var keys: [[String]] = []
            var stated: [[String]: VennSubset] = [:]
            for subset in diagram.subsets {
                if stated[subset.sets] == nil { keys.append(subset.sets) }
                stated[subset.sets] = subset
            }
            let regions = keys.compactMap { key -> String? in
                guard let subset = stated[key] else { return nil }
                let name = Self.spoken(subset.label ?? key.joined(separator: " and "))
                let texts = diagram.texts.filter { text in text.sets == key }.map { text in Self.spoken(text.label ?? text.identifier) }
                return texts.isEmpty ? name : name + ": " + texts.joined(separator: ", ")
            }
            return regions
        }
    }

    /// A text as it is drawn, its lines joined by spaces.
    static func spoken(_ text: String) -> String {
        DiagramLabelDecoder.label(from: text, form: .plain).spokenText
    }
}
