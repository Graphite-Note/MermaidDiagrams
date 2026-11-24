/**
 * File: DiagramScenePart.swift
 * ----------------------------
 * Layer: Core
 * Description: What part of a diagram a scene's item paints, by the class Pele's SVG gives it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// What part of a diagram an item paints, by the class Pele's SVG gives it (`pele-` and the raw value).
public enum DiagramScenePart: String, Hashable, Sendable, CaseIterable {
    /// The diagram's title.
    case title
    /// Edges, transitions, messages, links and connectors.
    case edge
    /// The marks at their ends: arrowheads, circles, crosses, cardinalities.
    case marker
    /// The text on edges.
    case edgeLabel = "edge-label"
    /// The patches behind text, which keep lines from running through it.
    case labelBackground = "label-bg"
    /// Nodes and what a chart plots: shapes, states, classes, entities, participants, slices, bars, points, tasks, commits.
    case node
    /// The text in or beside nodes.
    case label
    /// Boxes that hold others: groups, composite states, blocks, sections, lanes, bands.
    case cluster
    /// Their titles.
    case clusterLabel = "cluster-label"
    /// Notes and their text.
    case note
    /// Axes, grids, scales and lifelines.
    case axis
    /// The text along axes.
    case axisLabel = "axis-label"
    /// Legends and their text.
    case legend
    /// A kanban column's count of cards.
    case count
    /// A kanban card's priority mark.
    case priority
    /// A kanban card's ticket.
    case ticket
    /// A kanban card's assignee.
    case assigned
    /// A tree view's lines from each folder to its entries.
    case treeGuides = "tree-guides"
    /// The band behind a highlighted tree view entry.
    case treeHighlight = "tree-highlight"
    /// A tree view entry's description.
    case treeDescription = "tree-description"
    /// An icon drawn from its glyph: a tree view's file and folder icons.
    case icon
    /// An Ishikawa diagram's spine, which runs to its head.
    case ishikawaSpine = "ishikawa-spine"
    /// An Ishikawa diagram's bones, from the spine to each category and cause.
    case ishikawaBones = "ishikawa-bones"
    /// An info diagram's line of the package's version.
    case version
    /// The first and last bit written above a packet diagram's field.
    case bitNumber = "packet-bits"
    /// The rings of a radar chart.
    case graticule
    /// A radar chart's curve.
    case curve
    /// A treemap's section: a box that holds others.
    case section
    /// A treemap's leaf.
    case leaf
    /// The value a treemap writes in a box.
    case value
    /// A Venn diagram's circles, the overlaps a style outlines, and the texts written in its regions.
    case vennSet = "venn-set"
    case vennOverlap = "venn-overlap"
    case vennText = "venn-text"
    /// A Cynefin framework's domains, the dashed boundaries between them, the cliff, and the domains' subtitles.
    case cynefinRegion = "cynefin-region"
    case cynefinBoundary = "cynefin-boundaries"
    case cynefinCliff = "cynefin-cliff"
    case cynefinSubtitle = "cynefin-subtitle"
    /// A Wardley map's frame: its stages, its grid, its axes and their texts.
    case wardleyStage = "wardley-stage"
    case wardleyGrid = "wardley-grid"
    case wardleyAxis = "wardley-axis"
    case wardleyStageLabel = "wardley-stage-label"
    case wardleyAxisLabel = "wardley-axis-label"
    /// A Wardley map's pipelines, evolutions, inertia bars, annotations and their list, notes, and forces.
    case wardleyPipeline = "wardley-pipeline"
    case wardleyTrend = "wardley-trend"
    case wardleyInertia = "wardley-inertia"
    case wardleyAnnotation = "wardley-annotation"
    case wardleyAnnotations = "wardley-annotations"
    case wardleyNote = "wardley-note"
    case wardleyAccelerator = "wardley-accelerator"
    case wardleyDeaccelerator = "wardley-deaccelerator"
    /// A C4 element's kind and a boundary's type, a technology, and a description.
    case c4Type = "c4-type"
    case c4Technology = "c4-techn"
    case c4Description = "c4-descr"
    /// The wider lines of the page's color under lines that cross the border of a filled box.
    case casing = "casings"
    /// The text an architecture diagram's service shows in place of an icon.
    case iconText = "icon-text"
    /// A requirement's or an element's stereotype (`«Requirement»`), a use case diagram's stereotypes (`«Human»`), and the
    /// names of a requirement's fields.
    case stereotype
    case field
    /// A use case diagram's actor figure, the slash of a business actor or use case, a JSON table's lines, keys and values,
    /// and a package boundary's tab.
    case actorFigure = "actor-figure"
    case business
    case jsonLines = "json-lines"
    case jsonKey = "json-key"
    case jsonValue = "json-value"
    case boundaryTab = "boundary-tab"
    /// The three dots of an agent flow's collapsed flow.
    case collapsedMark = "collapsed-mark"
}
