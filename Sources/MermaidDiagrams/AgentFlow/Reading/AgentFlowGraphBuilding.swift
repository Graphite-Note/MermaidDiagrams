/**
 * File: AgentFlowGraphBuilding.swift
 * ----------------------------------
 * Layer: Core
 * Description: Resolves an agent flow's model into what is drawn, as Pele's graph.ts does: collapsed flows standing for
 *              what they hold, the nesting that would close a loop dropped, flows and nodes with their styles, and the
 *              edges between what is still drawn, on names and lists by name.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

/// What the graph's building keeps of a name: whether a collapsed flow hides it, the collapsed flow whose walk hid it
/// last, the outermost collapsed flow it stands in, the flow holding it, its graph node; -1 for none.
struct AgentFlowNameGraphing {
    var isHidden = false
    var owner: Int32 = -1
    var collapsedInto: Int32 = -1
    var parent: Int32 = -1
    var graphNode: Int32 = -1
}

/// What the graph's building keeps by name, in one list, and the flows' members grouped by flow, in the scratch arena.
struct AgentFlowGraphNaming {
    let byName: ScratchSpan<AgentFlowNameGraphing>
    let members: AgentFlowOwnerIndex

    init(nameCount: Int, model: AgentFlowModel, arena: DiagramScratchArena) {
        byName = arena.span(count: nameCount, repeating: AgentFlowNameGraphing())
        let entries = model.members
        members = entries.isEmpty ? AgentFlowOwnerIndex()
            : AgentFlowOwnerIndex(ownerCount: model.flows.count, count: entries.count, arena: arena) { entry in entries[entry].flow }
    }
}

extension AgentFlowDiagramBuilder {
    /// Pele's palette length: the number of its series colors.
    static let paletteLength = 8

    /// The graph drawn and the diagnostics found building it, Pele's `buildAgentGraph`.
    mutating func buildGraph(paletteLength: Int = Self.paletteLength) {
        // A member that a `global` block named after it was gathered is dropped, as 0.7.0 dropped it then.
        if model.members.contains(where: { member in names[member.name].isGlobal }) {
            let names = names
            model.members.removeAll { member in names[member.name].isGlobal }
        }
        // Names made while building (mappings' identifiers, for diagnostics) come after these.
        var naming = AgentFlowGraphNaming(nameCount: names.count, model: model, arena: arena)
        let hiddenInOrder = hideCollapsedFlows(&naming)
        collapse(hiddenInOrder, &naming)
        findFlowParents(&naming)
        let styles = AgentFlowGraphStyles(model: model, arena: arena)
        drawNodes(&naming, styles: styles)
        drawEdges(naming, styles: styles)
        normalizeShapes()
        assignColorSlots(order: containerOrder(naming), paletteLength: paletteLength)
    }

    /// What is hidden inside a collapsed flow, in the order hidden. Mermaid walks the whole inside of each collapsed
    /// flow, in the order the flows closed, and the last walk to reach a thing wins; a thing has one container, so a
    /// later walk can only enter an earlier one through its root, and the root's owner is followed afterwards.
    private func hideCollapsedFlows(_ naming: inout AgentFlowGraphNaming) -> ScratchList<Int32> {
        var hiddenInOrder: ScratchList<Int32> = arena.list(capacity: 8)
        let walked = arena.span(count: naming.byName.count, repeating: false)
        var pending: ScratchList<Int32> = arena.list(capacity: 8)
        for flow in model.flows where flow.isCollapsed && !naming.byName[Int(flow.name)].isHidden {
            pending.append(flow.name)
            while let next = pending.popLast() {
                let holder = names[next].flow
                guard holder >= 0 else { continue }
                for member in naming.members.entries(of: Int(holder)) {
                    let child = model.members[Int(member)].name
                    guard child != flow.name, !naming.byName[Int(child)].isHidden else { continue }
                    naming.byName[Int(child)].isHidden = true
                    hiddenInOrder.append(child)
                    naming.byName[Int(child)].owner = flow.name
                    if !walked[Int(child)] { pending.append(child) }
                }
            }
            walked[Int(flow.name)] = true
        }
        return hiddenInOrder
    }

    /// The outermost collapsed flow each hidden thing stands in, by following owners, each path's steps given its end.
    private func collapse(_ hiddenInOrder: ScratchList<Int32>, _ naming: inout AgentFlowGraphNaming) {
        var path: ScratchList<Int32> = arena.list(capacity: 8)
        for identifier in hiddenInOrder {
            path.removeAll()
            path.append(identifier)
            var top = naming.byName[Int(identifier)].owner >= 0 ? naming.byName[Int(identifier)].owner : identifier
            for _ in 0...hiddenInOrder.count {
                let known = naming.byName[Int(top)].collapsedInto
                let up = known >= 0 ? known : naming.byName[Int(top)].owner
                guard up >= 0 else { break }
                if known < 0 { path.append(top) }
                top = up
                if known >= 0 { break }
            }
            for step in path { naming.byName[Int(step)].collapsedInto = top }
        }
    }

    /// The flow directly holding each node and flow. Two flows can each name the other: the nesting that would close
    /// the loop is dropped, with a diagnostic.
    private mutating func findFlowParents(_ naming: inout AgentFlowGraphNaming) {
        let flowCount = model.flows.count
        for index in model.flows.indices.reversed() where !naming.byName[Int(model.flows[index].name)].isHidden {
            let flow = model.flows[index]
            for member in naming.members.entries(of: index) {
                let child = model.members[Int(member)]
                if closesLoop(child: child.name, parent: flow.name, at: index, byName: naming.byName, flowCount: flowCount) {
                    let flowText = model.text.string(flow.identifier)
                    let childText = model.text.string(child.identifier)
                    emitDiagnostic(.containmentViolation, severity: .warning, name: child.name, nodeIdentifier: childText,
                                   message: "Container \"\(flowText)\" cannot contain \"\(childText)\" because \"\(childText)\" already contains it. The nesting that would close the loop is dropped.")
                    continue
                }
                naming.byName[Int(child.name)].parent = flow.name
            }
        }
    }

    /// Whether `parent` holding `child` closes a loop; only a flow handled earlier in the pass can already be above it.
    private func closesLoop(child: Int32, parent: Int32, at index: Int, byName: ScratchSpan<AgentFlowNameGraphing>, flowCount: Int) -> Bool {
        let childIndex = names[child].flow
        guard childIndex >= 0, Int(childIndex) >= index else { return false }
        var current = parent
        var hops = 0
        while current >= 0, hops <= flowCount {
            if current == child { return true }
            current = byName[Int(current)].parent
            hops += 1
        }
        return false
    }
}
