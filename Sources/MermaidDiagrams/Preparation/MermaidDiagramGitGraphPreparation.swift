/**
 * File: MermaidDiagramGitGraphPreparation.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: Prepares a Git graph, with the graph running down for a narrow column, and says what a screen reader
 *              hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A Git graph, and for a narrow column the graph with its commits from the top down.
    func prepared(_ gitGraph: GitGraphDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: GitGraphLayout
        do { layout = try GitGraphLayoutEngine.layout(gitGraph, typography: typography) } catch { throw .gitGraphLayout(error) }
        let narrow = turnedNarrowSceneIsWanted(forRegularSize: layout.size)
            ? turnedNarrowScene(of: gitGraph.turnedToRunDown, regularSize: layout.size, laidOut: { turned in
                try GitGraphLayoutEngine.layout(turned, typography: typography)
            }, scene: { layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .gitGraph, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(gitGraph: gitGraph))
    }
}

extension MermaidDiagramAccessibility {
    /// Each branch with the ids written for its commits and their tags, in the order of the lanes: “main: init, v1.0”.
    init(gitGraph diagram: GitGraphDiagram) {
        self.init(kind: .gitGraph, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription, summarySeparator: "; ") {
            var commitTextsByBranch = diagram.branches.map { _ in [String]() }
            for commit in diagram.commits {
                commitTextsByBranch[commit.branchIndex] += (commit.hasWrittenIdentifier ? [commit.identifier] : []) + commit.tags.map(\.spokenText)
            }
            let branchTexts = zip(diagram.branches, commitTextsByBranch).map { branch, commitTexts in
                commitTexts.isEmpty ? branch.label.spokenText : branch.label.spokenText + ": " + commitTexts.joined(separator: ", ")
            }
            return branchTexts
        }
    }
}
