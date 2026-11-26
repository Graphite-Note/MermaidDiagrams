/**
 * File: AgentFlowNames.swift
 * --------------------------
 * Layer: Core
 * Description: The names an agent flow's reader meets, interned to numbers as 0.7.0's String keys made them one, and
 *              what each name is: a node, a flow, a class, an edge, a connector, a node kept out of flows.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// What a name stands for, in place of 0.7.0's dictionaries and sets keyed by Strings: the node, flow, class definition
/// and first edge of that identifier (-1 for none), its tooltip, and whether it is a connector, in a `global` block, or
/// held by a flow.
struct AgentFlowNameRole {
    var vertex: Int32 = -1
    var flow: Int32 = -1
    var classDefinition: Int32 = -1
    var edge: Int32 = -1
    var tooltip: MermaidTextRange?
    var isConnector = false
    var isGlobal = false
    var isMember = false
    /// The last mapping of a node of this name that is still a node's, or -1.
    var lastVertexMapping: Int32 = -1
    /// The flow whose members are being gathered when this name was last met among them (`AgentFlowDiagramBuilder.addFlow`).
    var gatheredInFlow: Int32 = -1
}

/// Names interned by their bytes (`GraphDiagramNameTable`: by bytes in an ASCII text, as Strings beyond it, so that two
/// names are one exactly when 0.7.0's Strings were equal), with the role of each.
struct AgentFlowNames {
    private var table: GraphDiagramNameTable
    var roles: [AgentFlowNameRole] = []

    init(isASCII: Bool) {
        table = GraphDiagramNameTable(isASCII: isASCII)
    }

    mutating func reserveCapacity(_ count: Int) {
        table.reserveCapacity(count)
        roles.reserveCapacity(count)
    }

    var count: Int { roles.count }

    /// The number of the name `range` of `text` spells, made when it is new.
    mutating func name(of range: MermaidTextRange, in text: AgentFlowTextBytes) -> Int32 {
        let interned = text.bytes.withUnsafeBufferPointer { bytes in table.intern(bytes, range) }
        if interned.isNew { roles.append(AgentFlowNameRole()) }
        return Int32(truncatingIfNeeded: interned.number)
    }

    subscript(name: Int32) -> AgentFlowNameRole {
        get { roles[Int(name)] }
        set { roles[Int(name)] = newValue }
    }
}
