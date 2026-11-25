/**
 * File: MermaidDiagramC4Preparation.swift
 * ---------------------------------------
 * Layer: Core
 * Description: Prepares a C4 diagram, with the tight drawing Pele makes for a narrow column, and says what a screen
 *              reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 25/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A C4 diagram, and for a narrow column the diagram drawn tight to fit it, as Pele's `tighten` draws it.
    func prepared(_ diagram: C4Diagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: C4Layout
        do { layout = try C4LayoutEngine.layout(diagram, typography: typography) } catch { throw .c4Layout(error) }
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: diagram, regularSize: layout.size, laidOut: { diagram in
                try C4LayoutEngine.tightLayout(diagram, typography: typography, columnWidth: narrowestColumnWidth)
            }, scene: { layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .c4, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(c4: diagram))
    }
}

extension MermaidDiagramAccessibility {
    /// Each shape with its kind, in the order written, then each relation with its label: “Banking Customer A, person;
    /// Internet Banking System, system; Banking Customer A to Internet Banking System: Uses”. Each element's label is
    /// read once.
    init(c4 diagram: C4Diagram) {
        self.init(kind: .c4, title: diagram.title.flatMap { title in title.isEmpty ? nil : Self.spoken(title) },
                  description: diagram.accessibilityDescription, summarySeparator: "; ") {
            let shapes = diagram.shapes
            let shapeNames = shapes.indices.map { index in Self.c4Name(of: shapes[index].element) }
            var nameByAlias: [String: String] = [:]
            nameByAlias.reserveCapacity(shapes.count + diagram.boundaries.count)
            for index in shapes.indices where shapes[index].element.aliasArgument == nil {
                nameByAlias[shapes[index].element.alias] = shapeNames[index]
            }
            for boundary in diagram.boundaries.dropFirst() where boundary.element.aliasArgument == nil && nameByAlias[boundary.element.alias] == nil {
                nameByAlias[boundary.element.alias] = Self.c4Name(of: boundary.element)
            }
            var summary: [String] = []
            summary.reserveCapacity(shapes.count + diagram.relations.count)
            for index in shapes.indices { summary.append(Self.joined(shapeNames[index], ", ", Self.spokenName(of: shapes[index].kind))) }
            for relation in diagram.relations {
                let from = nameByAlias[relation.from] ?? relation.from
                let to = nameByAlias[relation.to] ?? relation.to
                let label = Self.spoken(relation.label)
                summary.append(label.isEmpty ? Self.joined(from, " to ", to) : Self.joined(from, " to ", to, ": ", label))
            }
            return summary
        }
    }

    /// An element's label as drawn, else its alias.
    private static func c4Name(of element: C4Element) -> String {
        let label = spoken(element.label)
        return label.isEmpty ? element.alias : label
    }

    /// The kind's name as a screen reader says it: its macro's name in words, `external system db`.
    static func spokenName(of kind: C4ShapeKind) -> String {
        switch kind {
        case .person: "person"
        case .externalPerson: "external person"
        case .system: "system"
        case .systemDatabase: "system db"
        case .systemQueue: "system queue"
        case .externalSystem: "external system"
        case .externalSystemDatabase: "external system db"
        case .externalSystemQueue: "external system queue"
        case .container: "container"
        case .containerDatabase: "container db"
        case .containerQueue: "container queue"
        case .externalContainer: "external container"
        case .externalContainerDatabase: "external container db"
        case .externalContainerQueue: "external container queue"
        case .component: "component"
        case .componentDatabase: "component db"
        case .componentQueue: "component queue"
        case .externalComponent: "external component"
        case .externalComponentDatabase: "external component db"
        case .externalComponentQueue: "external component queue"
        }
    }
}
