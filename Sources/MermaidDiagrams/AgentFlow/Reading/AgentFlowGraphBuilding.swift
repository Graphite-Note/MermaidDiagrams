/**
 * File: AgentFlowGraphBuilding.swift
 * ----------------------------------
 * Layer: Core
 * Description: Resolves an agent flow's model into what is drawn, as Pele's graph.ts does: collapsed flows standing for
 *              what they hold, the nesting that would close a loop dropped, flows and nodes with their styles, and the
 *              edges between what is still drawn.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

extension AgentFlowDiagramBuilder {
    /// Pele's palette length: the number of its series colors.
    static let paletteLength = 8

    /// The graph drawn and the diagnostics found building it, Pele's `buildAgentGraph`.
    mutating func buildGraph(paletteLength: Int = Self.paletteLength, defaultCurve: String? = nil) {
        let collapsing = collapsedFlows()
        let parents = flowParents(hidden: collapsing.hidden)
        var graph = AgentFlowGraph()
        graph.nodes.reserveCapacity(diagram.flows.count + diagram.vertices.count)
        var nodeIndices: [String: Int] = [:]
        nodeIndices.reserveCapacity(diagram.flows.count + diagram.vertices.count)
        for flow in diagram.flows.reversed() where !collapsing.hidden.contains(flow.identifier) {
            nodeIndices[flow.identifier] = graph.nodes.count
            graph.nodes.append(groupNode(of: flow, parent: parents[flow.identifier]))
        }
        for vertex in diagram.vertices where !collapsing.hidden.contains(vertex.identifier) {
            if let existing = nodeIndices[vertex.identifier] {
                graph.nodes[existing].styles = vertex.styles
                graph.nodes[existing].compiledStyles = compiledStyles(of: vertex.classes)
                graph.nodes[existing].classes = vertex.classes.joined(separator: " ")
                continue
            }
            nodeIndices[vertex.identifier] = graph.nodes.count
            graph.nodes.append(node(of: vertex, parent: parents[vertex.identifier]))
        }
        graph.edges = drawnEdges(collapsedInto: collapsing.collapsedInto, defaultCurve: defaultCurve)
        normalizeShapes(of: &graph)
        assignColorSlots(to: &graph, order: containerOrder(parents: parents), paletteLength: paletteLength)
        diagram.graph = graph
    }

    /// The styles of the classes named, each trimmed, the text styles of each after its styles.
    func compiledStyles(of classNames: [String]) -> [String] {
        var styles: [String] = []
        for name in classNames {
            guard let index = classIndices[name] else { continue }
            let definition = diagram.classDefinitions[index]
            styles += definition.styles.map(C4Characters.trimmed) + definition.textStyles.map(C4Characters.trimmed)
        }
        return styles
    }

    /// What is hidden inside a collapsed flow, and the outermost collapsed flow each stands for. Mermaid walks the whole
    /// inside of each collapsed flow, in the order the flows closed, and the last walk to reach a thing wins; a thing has
    /// one container, so a later walk can only enter an earlier one through its root, and the root's owner is followed
    /// afterwards.
    private func collapsedFlows() -> (hidden: Set<String>, collapsedInto: [String: String]) {
        var hidden: Set<String> = []
        var hiddenInOrder: [String] = []
        var owner: [String: String] = [:]
        var walked: Set<String> = []
        for flow in diagram.flows where flow.isCollapsed && !hidden.contains(flow.identifier) {
            var pending = [flow.identifier]
            while let next = pending.popLast() {
                guard let members = flowIndices[next].map({ index in diagram.flows[index].nodeIdentifiers }) else { continue }
                for child in members where child != flow.identifier && !hidden.contains(child) {
                    hidden.insert(child)
                    hiddenInOrder.append(child)
                    owner[child] = flow.identifier
                    if !walked.contains(child) { pending.append(child) }
                }
            }
            walked.insert(flow.identifier)
        }
        var collapsedInto: [String: String] = [:]
        for identifier in hiddenInOrder {
            var path = [identifier]
            var top = owner[identifier] ?? identifier
            for _ in 0...hiddenInOrder.count {
                let known = collapsedInto[top]
                guard let up = known ?? owner[top] else { break }
                if known == nil { path.append(top) }
                top = up
                if known != nil { break }
            }
            for step in path { collapsedInto[step] = top }
        }
        return (hidden, collapsedInto)
    }

    /// The flow directly holding each node and flow. Two flows can each name the other: the nesting that would close
    /// the loop is dropped, with a diagnostic.
    private mutating func flowParents(hidden: Set<String>) -> [String: String] {
        var parents: [String: String] = [:]
        let flowCount = diagram.flows.count
        func closesLoop(child: String, parent: String, at index: Int) -> Bool {
            // Only a flow handled earlier in this pass can already be above the parent.
            guard let childIndex = flowIndices[child], childIndex >= index else { return false }
            var current: String? = parent
            var hops = 0
            while let ancestor = current, hops <= flowCount {
                if ancestor == child { return true }
                current = parents[ancestor]
                hops += 1
            }
            return false
        }
        for index in diagram.flows.indices.reversed() where !hidden.contains(diagram.flows[index].identifier) {
            let flow = diagram.flows[index]
            for child in flow.nodeIdentifiers {
                if closesLoop(child: child, parent: flow.identifier, at: index) {
                    emitDiagnostic(.containmentViolation, severity: .warning, nodeIdentifier: child,
                                   message: "Container \"\(flow.identifier)\" cannot contain \"\(child)\" because \"\(child)\" already contains it. The nesting that would close the loop is dropped.")
                    continue
                }
                parents[child] = flow.identifier
            }
        }
        return parents
    }

    private func groupNode(of flow: AgentFlowFlow, parent: String?) -> AgentFlowGraphNode {
        AgentFlowGraphNode(identifier: flow.identifier, label: flow.title, labelType: flow.labelType,
                           shape: flow.isCollapsed ? "collapsedGroup" : "flowGroup", isGroup: !flow.isCollapsed, parentIdentifier: parent,
                           styles: [], compiledStyles: compiledStyles(of: flow.classes), classes: flow.classes.joined(separator: " "),
                           directionKeyword: flow.directionKeyword)
    }

    private func node(of vertex: AgentFlowVertex, parent: String?) -> AgentFlowGraphNode {
        let type = vertex.type.map(AgentFlowShapes.resolvingAlias)
        return AgentFlowGraphNode(identifier: vertex.identifier, label: vertex.text, labelType: vertex.labelType,
                                  shape: type == nil || type == "square" ? "squareRect" : type ?? "squareRect", isGroup: false,
                                  parentIdentifier: parent, styles: vertex.styles, compiledStyles: compiledStyles(of: ["default", "node"] + vertex.classes),
                                  classes: "default " + vertex.classes.joined(separator: " "), link: vertex.link, linkTarget: vertex.linkTarget,
                                  tooltip: tooltips[vertex.identifier])
    }

    /// Each edge between what is still drawn: an end inside a collapsed flow meets the flow, and an edge between two
    /// things inside one collapsed flow has nothing left to connect.
    private func drawnEdges(collapsedInto: [String: String], defaultCurve: String?) -> [AgentFlowGraphEdge] {
        var edges: [AgentFlowGraphEdge] = []
        edges.reserveCapacity(diagram.edges.count)
        for (index, raw) in diagram.edges.enumerated() {
            let start = collapsedInto[raw.start] ?? raw.start
            let end = collapsedInto[raw.end] ?? raw.end
            if start == end, raw.start != raw.end { continue }
            let arrow = raw.type == "arrow_open" ? "none" : raw.type == "arrow_cross" || raw.type == "arrow_point" ? raw.type ?? "arrow_point" : "arrow_point"
            let curve = raw.interpolation.flatMap { curve in curve.isEmpty ? nil : curve }
                ?? diagram.defaultInterpolation.flatMap { curve in curve.isEmpty ? nil : curve } ?? defaultCurve
            edges.append(AgentFlowGraphEdge(identifier: raw.identifier.isEmpty ? "L_\(start)_\(end)_\(index)" : raw.identifier,
                                            isUserDefinedIdentifier: raw.isUserDefinedIdentifier, start: start, end: end, type: raw.type ?? "normal",
                                            label: raw.text, labelType: raw.labelType, thickness: raw.stroke, minimumLength: raw.length,
                                            arrowTypeEnd: arrow, compiledStyles: compiledStyles(of: raw.classes),
                                            style: (diagram.defaultEdgeStyle ?? []) + (raw.style ?? []), curve: curve))
        }
        return edges
    }
}
