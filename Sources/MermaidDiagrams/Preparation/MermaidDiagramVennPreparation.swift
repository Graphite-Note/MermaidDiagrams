/**
 * File: MermaidDiagramVennPreparation.swift
 * -----------------------------------------
 * Layer: Core
 * Description: Prepares a Venn diagram, its style declarations not drawn counted, and says what a screen reader hears
 *              of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
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

extension MermaidDiagramAccessibility {
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
}
