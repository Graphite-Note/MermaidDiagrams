/**
 * File: InfoDiagramScene.swift
 * ----------------------------
 * Layer: Core
 * Description: A laid-out info diagram's scene: its title and the version line in the colors' roles, as Pele paints them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

extension DiagramScene {
    /// The info diagram's painting: the title in bold, then the version line in the muted color.
    public init(layout: InfoDiagramLayout) {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        builder.text(layout.version, .muted, part: .version)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}
