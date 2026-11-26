/**
 * File: AgentFlowGraphSlots.swift
 * -------------------------------
 * Layer: Core
 * Description: An agent flow's graph's shapes reduced to those it draws, with their diagnostics, its containers numbered
 *              and given palette slots, each node its kind, as Pele's graph.ts does, on names.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

extension AgentFlowDiagramBuilder {
    /// Every node's shape reduced to one an agent flow draws, the removed and unsupported ones reported.
    mutating func normalizeShapes() {
        for index in model.graph.nodes.indices where !model.graph.nodes[index].isGroup {
            let written = model.graph.nodes[index].shape
            let normalized = AgentFlowShapeNames.normalizedShapes[Int(written)]
            model.graph.nodes[index].shape = normalized.shape
            guard normalized.problem != nil, let problem = AgentFlowShapes.normalized(AgentFlowShapeNames.names[Int(written)]).problem else { continue }
            let node = model.graph.nodes[index]
            emitDiagnostic(problem.identifier, severity: problem.identifier == .shapeRemoved ? .error : .warning, name: node.name,
                           nodeIdentifier: model.text.string(node.identifier), message: problem.message)
        }
    }

    /// Containers numbered in the order they were written: a walk of the nesting, parents first. The flows themselves
    /// are listed in the order their blocks closed, a nested flow before its parent.
    func containerOrder(_ naming: AgentFlowGraphNaming) -> ScratchSpan<Int32> {
        let order = arena.span(count: naming.byName.count, repeating: Int32(-1))
        guard !model.flows.isEmpty else { return order }
        let flows = model.flows
        let children = AgentFlowOwnerIndex(ownerCount: naming.byName.count, count: flows.count, arena: arena) { flow in
            naming.byName[Int(flows[flow].name)].parent
        }
        var count: Int32 = 0
        var pending: ScratchList<Int32> = arena.list(capacity: 8)
        for flow in flows where naming.byName[Int(flow.name)].parent < 0 {
            pending.append(flow.name)
            while let identifier = pending.popLast() {
                guard order[Int(identifier)] < 0 else { continue }
                order[Int(identifier)] = count
                count += 1
                for child in children.entries(of: Int(identifier)).reversed() { pending.append(flows[Int(child)].name) }
            }
        }
        return order
    }

    /// A node takes the color of its kind, from a fixed slot, so that editing the diagram around it never recolors it;
    /// containers count through the slots above the kinds in the order they were declared, a collapsed one keeping its
    /// slot, so that a frame does not take the color of a node inside it.
    mutating func assignColorSlots(order: ScratchSpan<Int32>, paletteLength: Int) {
        var fallback = Int32(order.reduce(0) { count, number in number >= 0 ? count + 1 : count })
        for index in model.graph.nodes.indices {
            let node = model.graph.nodes[index]
            if node.isGroup || node.shape == AgentFlowShapeNames.collapsedGroup {
                var number = order[Int(node.name)]
                if number < 0 {
                    number = fallback
                    fallback += 1
                }
                model.graph.nodes[index].containerNumber = number
                model.graph.nodes[index].colorIndex = Int32(Self.containerSlot(Int(number), paletteLength: paletteLength))
                continue
            }
            let role = names[node.name]
            if role.isConnector {
                model.graph.nodes[index].kind = .connector
            } else if role.vertex >= 0 {
                let type = model.vertices[Int(role.vertex)].type
                model.graph.nodes[index].kind = type >= 0 ? AgentFlowShapeNames.kinds[Int(type)] : .task
            }
        }
    }

    /// The slots containers count through, above the kinds: at least one, so that a palette shorter than the kinds
    /// still gives containers a slot.
    static func containerSlot(_ number: Int, paletteLength: Int) -> Int {
        let kindCount = AgentFlowVertexKind.allCases.count
        let slot = kindCount + number % max(1, paletteLength - kindCount)
        return paletteLength > 0 ? slot % paletteLength : slot
    }

    /// Records a diagnostic once, where the node it is about was first named. The first mapping of each name is found
    /// once, when the first diagnostic is recorded.
    mutating func emitDiagnostic(_ identifier: AgentFlowDiagnostic.Identifier, severity: AgentFlowDiagnostic.Severity, name: Int32,
                                 nodeIdentifier: String, message: String) {
        if firstMappingByName.isEmpty { findFirstMappings() }
        let first = Int(name) < firstMappingByName.count ? firstMappingByName[Int(name)] : -1
        let position = first < 0 ? nil : model.mappings[Int(first)].position
        let diagnostic = AgentFlowDiagnostic(identifier: identifier, severity: severity, message: message,
                                             nodeIdentifier: nodeIdentifier.isEmpty ? nil : nodeIdentifier, position: position)
        if reportedDiagnostics[name]?.contains(diagnostic) == true { return }
        reportedDiagnostics[name, default: []].append(diagnostic)
        model.diagnostics.append(diagnostic)
    }

    /// The first mapping of each name: every mapping's identifier named, an edge's joined one among them.
    private mutating func findFirstMappings() {
        var first: [Int32] = []
        for index in model.mappings.indices {
            let mapping = model.mappings[index]
            let name = mapping.name >= 0 ? mapping.name : self.name(of: mapping.identifier)
            if Int(name) >= first.count { first += repeatElement(-1, count: Int(name) + 1 - first.count) }
            if first[Int(name)] < 0 { first[Int(name)] = Int32(index) }
        }
        firstMappingByName = first.isEmpty ? [-1] : first
    }
}

extension AgentFlowMappingRecord {
    /// Where the statement sits, as the model gives it.
    var position: AgentFlowElementPosition {
        AgentFlowElementPosition(startLine: Int(startLine), startColumn: Int(startColumn), endLine: Int(endLine), endColumn: Int(endColumn))
    }
}
