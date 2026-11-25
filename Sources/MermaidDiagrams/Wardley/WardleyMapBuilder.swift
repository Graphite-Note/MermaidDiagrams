/**
 * File: WardleyMapBuilder.swift
 * -----------------------------
 * Layer: Core
 * Description: Fills a Wardley map from its statements in Mermaid's order, as Pele's model.ts and builder.ts do: the
 *              coordinates in percent, nodes merged by identifier, pipelines, links resolved by identifier or label.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

/// Mermaid's `populateDb`: the size and the stages, then anchors, components, notes, pipelines, links, evolutions, the
/// annotations' box and the annotations, and the forces, in that order whatever the order written. A coordinate up to 1
/// is a fraction and is turned into percent; one from 1 to 100 is already one; any other is refused.
struct WardleyMapBuilder {
    private var map = WardleyMap()
    private var indexByIdentifier: [String: Int] = [:]
    private var indexByTrend: [String: Int] = [:]
    private var indexByPipeline: [String: Int] = [:]
    private let bytes: [UInt8]

    static func map(of statements: WardleyMapStatements, bytes: [UInt8]) throws(MermaidDiagramReadError) -> WardleyMap {
        var builder = WardleyMapBuilder(bytes: bytes)
        try builder.populate(statements)
        return builder.map
    }

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    private mutating func populate(_ statements: WardleyMapStatements) throws(MermaidDiagramReadError) {
        map.title = statements.title
        map.accessibilityTitle = statements.accessibilityTitle
        map.accessibilityDescription = statements.accessibilityDescription
        map.size = statements.size
        if let stages = statements.stages {
            map.stages = stages.map { stage in
                stage.secondName.map { second in PlaneMapText.trimmed(stage.name) + " / " + PlaneMapText.trimmed(second) } ?? PlaneMapText.trimmed(stage.name)
            }
            map.stageBoundaries = stages.compactMap(\.boundary)
        }
        for anchor in statements.anchors {
            let point = try self.point(anchor.first, anchor.second, at: anchor.offset)
            add(WardleyMapNode(identifier: anchor.name, label: anchor.name, point: point, kind: .anchor), keepsSourcing: true)
        }
        for component in statements.components {
            let point = try self.point(component.visibility, component.evolution, at: component.offset)
            add(WardleyMapNode(identifier: component.name, label: component.name, point: point, kind: .component, labelOffsetX: component.labelOffset?.x,
                               labelOffsetY: component.labelOffset?.y, hasInertia: component.hasInertia, sourcing: component.sourcing), keepsSourcing: false)
        }
        for note in statements.notes { map.notes.append(WardleyMapNote(text: note.name, point: try point(note.first, note.second, at: note.offset))) }
        for pipeline in statements.pipelines { try addPipeline(pipeline) }
        addLinks(statements.links)
        for evolve in statements.evolves { try addTrend(evolve) }
        if let box = statements.annotationBoxes.first { map.annotationsBox = try point(box.first, box.second, at: box.offset) }
        for annotation in statements.annotations {
            map.annotations.append(WardleyMapAnnotation(number: annotation.number, point: try point(annotation.first, annotation.second, at: annotation.offset),
                                                        text: annotation.text))
        }
        for force in statements.accelerators { map.accelerators.append(WardleyMapForce(name: force.name, point: try point(force.first, force.second, at: force.offset))) }
        for force in statements.deaccelerators {
            map.deaccelerators.append(WardleyMapForce(name: force.name, point: try point(force.first, force.second, at: force.offset)))
        }
    }

    /// `[visibility, evolution]` as written, as a point in percent: x the evolution, y the visibility.
    private func point(_ visibility: Double, _ evolution: Double, at offset: Int) throws(MermaidDiagramReadError) -> WardleyMapPoint {
        let x = try percent(evolution, at: offset)
        return WardleyMapPoint(x: x, y: try percent(visibility, at: offset))
    }

    /// A value up to 1 times 100, else the value, which must be from 0 to 100.
    private func percent(_ value: Double, at offset: Int) throws(MermaidDiagramReadError) -> Double {
        let normalized = value <= 1 ? value * 100 : value
        guard !(normalized < 0 || normalized > 100) else {
            throw .invalidSyntax(line: PlaneMapByte.line(of: offset, in: bytes), problem: .wardleyMap(.coordinateOutOfRange(value)))
        }
        return normalized
    }

    /// Adds `node`, or merges it into the node of its identifier: the label, the point and the kind are the new node's,
    /// the label offsets the new node's where it gives them, and the inertia and sourcing the new node's unless
    /// `keepsSourcing` (an anchor sets neither).
    private mutating func add(_ node: WardleyMapNode, keepsSourcing: Bool) {
        guard let index = indexByIdentifier[node.identifier] else {
            indexByIdentifier[node.identifier] = map.nodes.count
            map.nodes.append(node)
            return
        }
        var merged = map.nodes[index]
        merged.label = node.label
        merged.point = node.point
        merged.kind = node.kind
        merged.labelOffsetX = node.labelOffsetX ?? merged.labelOffsetX
        merged.labelOffsetY = node.labelOffsetY ?? merged.labelOffsetY
        if !keepsSourcing {
            merged.hasInertia = node.hasInertia
            merged.sourcing = node.sourcing
        }
        map.nodes[index] = merged
    }

    /// A pipeline under an existing component, its components at the parent's visibility with identifiers
    /// `Parent_Name`; a later pipeline under the same parent starts its components again.
    private mutating func addPipeline(_ pipeline: WardleyMapStatements.Pipeline) throws(MermaidDiagramReadError) {
        guard let parentIndex = indexByIdentifier[pipeline.parent] else {
            throw .invalidSyntax(line: PlaneMapByte.line(of: pipeline.offset, in: bytes), problem: .wardleyMap(.pipelineWithoutComponent(pipeline.parent)))
        }
        let visibility = map.nodes[parentIndex].point.y
        if let existing = indexByPipeline[pipeline.parent] {
            map.pipelines[existing].componentIdentifiers = []
        } else {
            indexByPipeline[pipeline.parent] = map.pipelines.count
            map.pipelines.append(WardleyMapPipeline(nodeIdentifier: pipeline.parent, componentIdentifiers: []))
        }
        map.nodes[parentIndex].isPipelineParent = true
        for component in pipeline.components {
            let identifier = pipeline.parent + "_" + component.name
            let point = WardleyMapPoint(x: try percent(component.evolution, at: component.offset), y: visibility)
            add(WardleyMapNode(identifier: identifier, label: component.name, point: point, kind: .pipelineComponent, labelOffsetX: component.labelOffset?.x,
                               labelOffsetY: component.labelOffset?.y), keepsSourcing: false)
            if let index = indexByPipeline[pipeline.parent] { map.pipelines[index].componentIdentifiers.append(identifier) }
            if let index = indexByIdentifier[identifier] { map.nodes[index].isInPipeline = true }
        }
    }

    /// Each link with its ends resolved, by identifier, else by the first node with that label, else as written.
    private mutating func addLinks(_ links: [WardleyMapStatements.Link]) {
        guard !links.isEmpty else { return }
        var identifierByLabel: [String: String] = [:]
        for node in map.nodes where identifierByLabel[node.label] == nil { identifierByLabel[node.label] = node.identifier }
        func resolved(_ name: String) -> String {
            indexByIdentifier[name] != nil ? name : identifierByLabel[name] ?? name
        }
        for link in links {
            let isDashed = link.arrow.map { arrow in PlaneMapText.contains(arrow, "-.->") || PlaneMapText.contains(arrow, ".-.") } ?? false
            let fromArrow = Self.flowAndLabel(of: link.arrow)
            let flow = Self.flow(ofPort: link.fromPort) ?? Self.flow(ofPort: link.toPort) ?? fromArrow.flow
            map.links.append(WardleyMapLink(source: resolved(link.from), target: resolved(link.to), isDashed: isDashed, label: fromArrow.label ?? link.label,
                                            flow: flow))
        }
    }

    /// `evolve Component 0.8`, for a component found by its identifier.
    private mutating func addTrend(_ evolve: WardleyMapStatements.Placed) throws(MermaidDiagramReadError) {
        guard let index = indexByIdentifier[evolve.name] else { return }
        let trend = WardleyMapTrend(nodeIdentifier: evolve.name, target: WardleyMapPoint(x: try percent(evolve.first, at: evolve.offset), y: map.nodes[index].point.y))
        if let existing = indexByTrend[evolve.name] {
            map.trends[existing] = trend
        } else {
            indexByTrend[evolve.name] = map.trends.count
            map.trends.append(trend)
        }
    }

    private static func flow(ofPort port: String?) -> WardleyMapFlow? {
        switch port {
        case "+<>": .bidirectional
        case "+<": .backward
        case "+>": .forward
        default: nil
        }
    }

    /// A labelled arrow's flow and label (`+'label'>`): its label between apostrophes, its flow by its end.
    private static func flowAndLabel(of arrow: String?) -> (flow: WardleyMapFlow?, label: String?) {
        guard let arrow, arrow.hasPrefix("+") else { return (nil, nil) }
        var label: String?
        let afterPlus = arrow.dropFirst()
        if afterPlus.first == "'", let closing = afterPlus.dropFirst().firstIndex(of: "'") {
            label = String(afterPlus[afterPlus.index(after: afterPlus.startIndex)..<closing])
        }
        if PlaneMapText.contains(arrow, "<>") { return (.bidirectional, label) }
        if PlaneMapText.contains(arrow, "<") { return (.backward, label) }
        if PlaneMapText.contains(arrow, ">") { return (.forward, label) }
        return (nil, label)
    }
}
