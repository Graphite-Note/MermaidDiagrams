/**
 * File: InfoDiagramLayout.swift
 * -----------------------------
 * Layer: Core
 * Description: A laid-out info diagram: its title and the line of the package's version, centered on a small page.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// An info diagram laid out on a page whose origin is the top left corner and whose y runs down, in points.
public struct InfoDiagramLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the text was measured in.
    public let font: DiagramFont
    /// The title, in bold above the version, or nil.
    public let title: DiagramTextBlock?
    /// The package's name and version.
    public let version: DiagramTextBlock
}
