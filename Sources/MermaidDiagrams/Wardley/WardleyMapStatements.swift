/**
 * File: WardleyMapStatements.swift
 * --------------------------------
 * Layer: Core
 * Description: A Wardley map's statements as Pele's parser.ts collects them, by kind, before Mermaid's builder takes
 *              them in its own order: each with where it starts, for the line of an error the builder finds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A Wardley map's statements by kind, in the order written within each kind, as Pele's syntax tree holds them.
struct WardleyMapStatements {
    struct Stage {
        let name: String
        let boundary: Double?
        let secondName: String?
    }

    /// `label [x, y]`, signs included.
    struct LabelOffset {
        let x: Double
        let y: Double
    }

    struct Component {
        let name: String
        let visibility: Double
        let evolution: Double
        let labelOffset: LabelOffset?
        let sourcing: WardleyMapSourcing?
        let hasInertia: Bool
        /// Where the statement starts in the text, for the line of an error.
        let offset: Int
    }

    struct PipelineComponent {
        let name: String
        let evolution: Double
        let labelOffset: LabelOffset?
        /// Where the statement starts in the text, for the line of an error.
        let offset: Int
    }

    struct Pipeline {
        let parent: String
        let components: [PipelineComponent]
        /// Where the statement starts in the text, for the line of an error.
        let offset: Int
    }

    struct Link {
        let from: String
        let fromPort: String?
        let arrow: String?
        let to: String
        let toPort: String?
        let label: String?
    }

    /// A statement placing a named thing at two coordinates as written: `[first, second]`.
    struct Placed {
        let name: String
        let first: Double
        let second: Double
        /// Where the statement starts in the text, for the line of an error.
        let offset: Int
    }

    struct Annotation {
        let number: Double
        let first: Double
        let second: Double
        let text: String
        /// Where the statement starts in the text, for the line of an error.
        let offset: Int
    }

    var title: String?
    var accessibilityTitle: String?
    var accessibilityDescription: String?
    var size: WardleyMapSize?
    var stages: [Stage]?
    var anchors: [Placed] = []
    var components: [Component] = []
    var links: [Link] = []
    var evolves: [Placed] = []
    var pipelines: [Pipeline] = []
    var notes: [Placed] = []
    var annotationBoxes: [Placed] = []
    var annotations: [Annotation] = []
    var accelerators: [Placed] = []
    var deaccelerators: [Placed] = []
}
