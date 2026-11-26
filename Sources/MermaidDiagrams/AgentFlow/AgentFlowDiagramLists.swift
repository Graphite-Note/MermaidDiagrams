/**
 * File: AgentFlowDiagramLists.swift
 * ---------------------------------
 * Layer: Core
 * Description: An agent flow's nodes, edges, flows and graph made from its flat model when they are asked for, as
 *              0.7.0's reader stored them: each attribute in the order written, each metadata body read again and
 *              merged as JavaScript's `Object.assign` merges them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

extension AgentFlowDiagram {
    /// Every node named, connectors among them, in the order first named.
    public var vertices: [AgentFlowVertex] {
        DiagramScratchArena.withCurrentThread { arena in vertices(AgentFlowGraphStyles.index(model.vertexAttributes, ownerCount: model.vertices.count, arena: arena)) }
    }

    private func vertices(_ attributes: AgentFlowOwnerIndex) -> [AgentFlowVertex] {
        model.vertices.indices.map { index in
            let record = model.vertices[index]
            var vertex = AgentFlowVertex(identifier: model.text.string(record.identifier))
            vertex.text = record.hasText ? model.text.string(record.text) : nil
            vertex.labelType = record.labelType
            vertex.type = record.type >= 0 ? AgentFlowShapeNames.names[Int(record.type)] : nil
            vertex.isConnector = record.isConnector
            vertex.link = model.text.string(orNil: record.link)
            vertex.linkTarget = model.text.string(orNil: record.linkTarget)
            var properties: [String: String] = [:]
            var bodies: [MermaidTextRange] = []
            for entry in attributes.entries(of: index) where entry >= record.firstAttribute {
                let attribute = model.vertexAttributes[Int(entry)]
                switch attribute.kind {
                case .style: vertex.styles.append(model.text.string(attribute.value))
                case .className: vertex.classes.append(model.text.string(attribute.value))
                case .property: properties[model.text.string(attribute.value)] = model.text.string(attribute.detail)
                case .metadata: bodies.append(attribute.value)
                case .textStyle: break
                }
            }
            vertex.properties = record.hasProperties ? properties : nil
            vertex.metadata = record.hasMetadata ? metadata(of: bodies) : nil
            return vertex
        }
    }

    /// Every edge, in the order written.
    public var edges: [AgentFlowEdge] {
        DiagramScratchArena.withCurrentThread { arena in edges(AgentFlowGraphStyles.index(model.edgeAttributes, ownerCount: model.edges.count, arena: arena)) }
    }

    private func edges(_ attributes: AgentFlowOwnerIndex) -> [AgentFlowEdge] {
        model.edges.indices.map { index in
            let record = model.edges[index]
            var edge = AgentFlowEdge(start: model.text.string(record.start), end: model.text.string(record.end), identifier: model.text.string(record.identifier))
            edge.isUserDefinedIdentifier = record.isUserDefinedIdentifier
            edge.type = record.arrow.name
            edge.stroke = record.stroke.name
            edge.semantic = record.semantic
            edge.length = record.length >= 0 ? Int(record.length) : nil
            edge.text = model.text.string(record.text)
            edge.labelType = record.labelType
            edge.interpolation = model.text.string(orNil: record.interpolation)
            edge.style = record.style.map(styleStrings)
            var bodies: [MermaidTextRange] = []
            for entry in attributes.entries(of: index) {
                let attribute = model.edgeAttributes[Int(entry)]
                if attribute.kind == .className { edge.classes.append(model.text.string(attribute.value)) } else if attribute.kind == .metadata { bodies.append(attribute.value) }
            }
            edge.metadata = record.hasMetadata ? metadata(of: bodies) : nil
            return edge
        }
    }

    /// The `flow … end` containers, in the order their `end` closes them: a flow inside another before it.
    public var flows: [AgentFlowFlow] {
        DiagramScratchArena.withCurrentThread { arena in
            let members = AgentFlowOwnerIndex(ownerCount: model.flows.count, count: model.members.count, arena: arena) { entry in model.members[entry].flow }
            return flows(AgentFlowGraphStyles.index(model.flowAttributes, ownerCount: model.flows.count, arena: arena), members: members)
        }
    }

    private func flows(_ attributes: AgentFlowOwnerIndex, members: AgentFlowOwnerIndex) -> [AgentFlowFlow] {
        model.flows.indices.map { index in
            let record = model.flows[index]
            var flow = AgentFlowFlow(identifier: model.text.string(record.identifier),
                                     nodeIdentifiers: members.entries(of: index).map { entry in model.text.string(model.members[Int(entry)].identifier) },
                                     title: model.text.string(record.title), directionKeyword: model.text.string(orNil: record.directionKeyword),
                                     labelType: record.labelType)
            var bodies: [MermaidTextRange] = []
            for entry in attributes.entries(of: index) {
                let attribute = model.flowAttributes[Int(entry)]
                if attribute.kind == .className { flow.classes.append(model.text.string(attribute.value)) } else if attribute.kind == .metadata { bodies.append(attribute.value) }
            }
            flow.metadata = record.hasMetadata ? metadata(of: bodies) : nil
            return flow
        }
    }

    /// The metadata of an element from its bodies in the order written: each read as YAML, a text `shape` given with its
    /// alias resolved, merged into what came before (`AgentFlowMetadataReading.merged`).
    private func metadata(of bodies: [MermaidTextRange]) -> AgentFlowMetadata {
        var metadata: AgentFlowMetadata?
        for body in bodies {
            guard var parsed = AgentFlowMetadataReading.value(of: model.text.string(body)) else { continue }
            if case .mapping(var fields) = parsed, case .text(let name)? = fields["shape"] {
                fields["shape"] = .text(AgentFlowShapes.resolvingAlias(name))
                parsed = .mapping(fields)
            }
            metadata = AgentFlowMetadataReading.merged(metadata, with: parsed)
        }
        return metadata ?? [:]
    }

}
