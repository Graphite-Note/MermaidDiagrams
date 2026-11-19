/**
 * File: MermaidDiagramGraphAccessibility.swift
 * --------------------------------------------
 * Layer: Core
 * Description: What a screen reader says of flowcharts, state, class, sequence and entity relationship diagrams,
 *              mindmaps and Git graphs, as the reading view says it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

extension MermaidDiagramAccessibility {
    /// The text of each node drawn, in the order the diagram names them, then each group's title.
    init(flowchart diagram: FlowchartDiagram) {
        let groupNodes = Set(diagram.subgraphs.compactMap(\.representingNodeIndex))
        let nodeTexts = diagram.nodes.indices.filter { node in !groupNodes.contains(node) }.map { node in diagram.nodes[node].label.spokenText }
        self.init(kind: .flowchart, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription,
                  summary: nodeTexts + diagram.subgraphs.map(\.title.spokenText).filter { title in !title.isEmpty })
    }

    /// The names of the composite states, then of the states drawn as boxes, in the order the diagram names them: a
    /// composite state is named by its box's title, before the states it holds.
    init(stateDiagram diagram: StateDiagram, layout: StateDiagramLayout) {
        let compositeNames = layout.composites.compactMap { composite in composite.title?.lines.joined(separator: " ") }
        let stateNames = layout.states.compactMap { state in state.name?.lines.joined(separator: " ") }
        self.init(kind: .stateDiagram, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription,
                  summary: compositeNames + stateNames)
    }

    /// The name of each class as its box shows it, in the order the diagram names them.
    init(classDiagram diagram: ClassDiagram) {
        self.init(kind: .classDiagram, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription,
                  summary: diagram.classes.map(\.displayedName.spokenText))
    }

    /// The participants' names, then each message as who sends it to whom and its text: “Alice to Bob: Hello”.
    init(sequence diagram: SequenceDiagram) {
        let names = diagram.participants.map(\.label.spokenText)
        let messages = diagram.events.compactMap { event -> String? in
            guard case .message(let message) = event else { return nil }
            let text = message.text.spokenText
            let route = "\(names[message.sourceIndex]) to \(names[message.targetIndex])"
            return text.isEmpty ? route : "\(route): \(text)"
        }
        self.init(kind: .sequence, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription,
                  summary: [names.joined(separator: ", ")] + messages, summarySeparator: ". ")
    }

    /// Each entity's text, then each relationship as its two entities around its label: “CUSTOMER places ORDER”.
    init(entityRelationship diagram: EntityRelationshipDiagram) {
        let entityTexts = diagram.entities.map(\.label.spokenText)
        let relationships = diagram.relationships.map { relationship in
            [entityTexts[relationship.firstEntityIndex], relationship.label.spokenText, entityTexts[relationship.secondEntityIndex]]
                .filter { part in !part.isEmpty }.joined(separator: " ")
        }
        self.init(kind: .entityRelationship, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription,
                  summary: entityTexts + relationships)
    }

    /// The text of each node, the root first, in the order the diagram writes them.
    init(mindmap diagram: MindmapDiagram) {
        self.init(kind: .mindmap, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription,
                  summary: diagram.nodes.map(\.label.spokenText))
    }

    /// Each branch with the ids written for its commits and their tags, in the order of the lanes: “main: init, v1.0”.
    init(gitGraph diagram: GitGraphDiagram) {
        var commitTextsByBranch = diagram.branches.map { _ in [String]() }
        for commit in diagram.commits {
            commitTextsByBranch[commit.branchIndex] += (commit.hasWrittenIdentifier ? [commit.identifier] : []) + commit.tags.map(\.spokenText)
        }
        let branchTexts = zip(diagram.branches, commitTextsByBranch).map { branch, commitTexts in
            commitTexts.isEmpty ? branch.label.spokenText : branch.label.spokenText + ": " + commitTexts.joined(separator: ", ")
        }
        self.init(kind: .gitGraph, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription,
                  summary: branchTexts, summarySeparator: "; ")
    }
}
