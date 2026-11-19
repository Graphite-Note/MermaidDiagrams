/**
 * File: ArchitectureDiagramBuilder.swift
 * --------------------------------------
 * Layer: Core
 * Description: Checks an architecture diagram's statements as Pele's database does, in Mermaid's order (every group,
 *              then services, junctions, edges and alignments), and refuses what it refuses with the statement's line.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Pele's `populate` and `ArchitectureDb`: identifiers used once, parents declared before and groups, edges between
/// nodes declared before (a group named on an edge is refused where Mermaid fails with a TypeError), `{group}` only on
/// an edge that leaves its group, alignments of nodes each named once. Groups, services and junctions count as nodes,
/// and edges and the members of alignments as edges, checked before any is made.
struct ArchitectureDiagramBuilder {
    let bytes: [UInt8]
    let limits: MermaidDiagramLimits
    /// Each identifier declared, and whether it is a group's.
    private var isGroupByIdentifier: [String: Bool] = [:]
    private var groupIndices: [String: Int] = [:]
    private var nodeIndices: [String: Int] = [:]

    init(bytes: [UInt8], limits: MermaidDiagramLimits) {
        self.bytes = bytes
        self.limits = limits
    }

    mutating func diagram(of statements: ArchitectureStatements) throws(MermaidDiagramReadError) -> ArchitectureDiagram {
        let nodeCount = statements.groups.count + statements.services.count + statements.junctions.count
        guard nodeCount <= limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        let edgeCount = statements.links.count + statements.alignments.reduce(0) { count, alignment in count + alignment.members.count }
        guard edgeCount <= limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        var diagram = ArchitectureDiagram()
        diagram.title = statements.title.flatMap { title in title.isEmpty ? nil : title }
        diagram.accessibilityTitle = statements.accessibilityTitle.map(Self.withoutLeadingWhitespace)
        diagram.accessibilityDescription = statements.accessibilityDescription.map(Self.withoutIndentedLineStarts)
        for group in statements.groups {
            let parentIndex = try register(group, isGroup: true)
            groupIndices[group.identifier] = diagram.groups.count
            diagram.groups.append(ArchitectureGroup(identifier: group.identifier, icon: group.icon, title: group.title, parentIndex: parentIndex))
        }
        for (declarations, kind) in [(statements.services, ArchitectureNode.Kind.service), (statements.junctions, .junction)] {
            for node in declarations {
                let groupIndex = try register(node, isGroup: false)
                nodeIndices[node.identifier] = diagram.nodes.count
                diagram.nodes.append(ArchitectureNode(identifier: node.identifier, kind: kind, icon: node.icon, iconText: node.iconText, title: node.title,
                                                      groupIndex: groupIndex))
            }
        }
        diagram.edges = try statements.links.map { link throws(MermaidDiagramReadError) in try edge(link, nodes: diagram.nodes) }
        diagram.alignments = try statements.alignments.map { alignment throws(MermaidDiagramReadError) in
            try self.alignment(isRow: alignment.isRow, members: alignment.members, start: alignment.start)
        }
        return diagram
    }

    /// Pele's `register`: the parent's place among the groups, or nil without one.
    private mutating func register(_ declaration: ArchitectureStatements.Declaration, isGroup: Bool) throws(MermaidDiagramReadError) -> Int? {
        let identifier = declaration.identifier
        guard isGroupByIdentifier[identifier] == nil else { throw failure(.identifierInUse(identifier), at: declaration.start) }
        var parentIndex: Int?
        if let parent = declaration.parent {
            guard parent != identifier else { throw failure(.placedInItself(identifier), at: declaration.start) }
            guard let parentIsGroup = isGroupByIdentifier[parent] else { throw failure(.parentMissing(identifier), at: declaration.start) }
            guard parentIsGroup else { throw failure(.parentNotAGroup(identifier), at: declaration.start) }
            parentIndex = groupIndices[parent]
        }
        isGroupByIdentifier[identifier] = isGroup
        return parentIndex
    }

    private func edge(_ link: ArchitectureStatements.Link, nodes: [ArchitectureNode]) throws(MermaidDiagramReadError) -> ArchitectureEdge {
        for identifier in [link.source, link.target] where isGroupByIdentifier[identifier] == nil {
            throw failure(.edgeEndMissing(identifier), at: link.start)
        }
        guard let source = nodeIndices[link.source] else { throw failure(.edgeEndIsAGroup(link.source), at: link.start) }
        guard let target = nodeIndices[link.target] else { throw failure(.edgeEndIsAGroup(link.target), at: link.start) }
        if let group = nodes[source].groupIndex, group == nodes[target].groupIndex {
            for (identifier, crosses) in [(link.source, link.leavesSourceGroup), (link.target, link.entersTargetGroup)] where crosses {
                throw failure(.groupModifierWithinOneGroup(identifier), at: link.start)
            }
        }
        return ArchitectureEdge(sourceIndex: source, sourceSide: link.sourceSide, hasSourceArrow: link.hasSourceArrow, leavesSourceGroup: link.leavesSourceGroup,
                                targetIndex: target, targetSide: link.targetSide, hasTargetArrow: link.hasTargetArrow, entersTargetGroup: link.entersTargetGroup,
                                title: link.title)
    }

    private func alignment(isRow: Bool, members: [String], start: Int) throws(MermaidDiagramReadError) -> ArchitectureAlignment {
        var seen: Set<String> = []
        var indices: [Int] = []
        for member in members {
            guard isGroupByIdentifier[member] == false, let index = nodeIndices[member] else { throw failure(.alignmentMemberNotANode(member), at: start) }
            guard seen.insert(member).inserted else { throw failure(.alignmentMemberRepeated(member), at: start) }
            indices.append(index)
        }
        return ArchitectureAlignment(isRow: isRow, memberIndices: indices)
    }

    private func failure(_ problem: ArchitectureSyntaxProblem, at start: Int) -> MermaidDiagramReadError {
        .invalidSyntax(line: PlaneMapByte.line(of: start, in: bytes), problem: .architecture(problem))
    }

    private static func withoutLeadingWhitespace(_ text: String) -> String {
        String(text.drop { character in character.isWhitespace })
    }

    /// Pele's `replace(/\n\s+/g, '\n')`: the white space after each line break, line breaks among it, left out.
    private static func withoutIndentedLineStarts(_ text: String) -> String {
        var result = ""
        var isAfterLineBreak = false
        for character in text {
            if isAfterLineBreak, character.isWhitespace { continue }
            isAfterLineBreak = character == "\n"
            result.append(character)
        }
        return result
    }
}
