/**
 * File: GitGraphScene.swift
 * -------------------------
 * Layer: Core
 * Description: A laid-out Git graph's scene: its drawing parts back to front in the colors' roles, as Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The Git graph's painting: the lanes and their names' boxes in the lanes' series colors, the names, the lines
    /// between lanes, to cherry-picks and along lanes, the rings and symbols and their marks, the ids turned on their
    /// patches, the tags with their text, the title; its shapes recorded into lanes of the thread's scene workspace.
    public init(layout: GitGraphLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The same painting recorded under `limits`: a scene one of whose lanes goes past their element limit says so
    /// (`exceededPathElementLimit`), and the preparation refuses it.
    public init(layout: GitGraphLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            GitGraphScenePaths(layout: layout, making: workspace).addScene(of: layout, to: &builder)
            return builder.scene(size: layout.size, font: layout.font, seriesColors: layout.seriesColors)
        }
    }
}
