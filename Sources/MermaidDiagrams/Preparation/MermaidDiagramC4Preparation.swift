/**
 * File: MermaidDiagramC4Preparation.swift
 * ---------------------------------------
 * Layer: Core
 * Description: Prepares a C4 diagram, with the tight drawing Pele makes for a narrow column, and says what a screen
 *              reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A C4 diagram, and for a narrow column the diagram drawn tight to fit it, as Pele's `tighten` draws it.
    func prepared(_ diagram: C4Diagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: C4Layout
        do { layout = try C4LayoutEngine.layout(diagram, typography: typography) } catch { throw .c4Layout(error) }
        let narrow = narrowScene(of: diagram, regularSize: layout.size, laidOut: { diagram in
            try C4LayoutEngine.tightLayout(diagram, typography: typography, columnWidth: narrowestColumnWidth)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .c4, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(c4: diagram))
    }
}

extension MermaidDiagramAccessibility {
    /// Each shape with its kind, in the order written, then each relation with its label: “Banking Customer A, person;
    /// Internet Banking System, system; Banking Customer A to Internet Banking System: Uses”.
    init(c4 diagram: C4Diagram) {
        var nameByAlias: [String: String] = [:]
        for shape in diagram.shapes where shape.element.aliasArgument == nil { nameByAlias[shape.element.alias] = Self.c4Name(of: shape.element) }
        for boundary in diagram.boundaries.dropFirst() where boundary.element.aliasArgument == nil && nameByAlias[boundary.element.alias] == nil {
            nameByAlias[boundary.element.alias] = Self.c4Name(of: boundary.element)
        }
        let shapes = diagram.shapes.map { shape in Self.c4Name(of: shape.element) + ", " + shape.kind.rawValue.replacingOccurrences(of: "_", with: " ") }
        let relations = diagram.relations.map { relation in
            let names = (nameByAlias[relation.from] ?? relation.from) + " to " + (nameByAlias[relation.to] ?? relation.to)
            let label = Self.spoken(relation.label)
            return label.isEmpty ? names : names + ": " + label
        }
        self.init(kind: .c4, title: diagram.title.flatMap { title in title.isEmpty ? nil : Self.spoken(title) },
                  description: diagram.accessibilityDescription, summary: shapes + relations, summarySeparator: "; ")
    }

    /// An element's label as drawn, else its alias.
    private static func c4Name(of element: C4Element) -> String {
        let label = spoken(element.label)
        return label.isEmpty ? element.alias : label
    }
}
