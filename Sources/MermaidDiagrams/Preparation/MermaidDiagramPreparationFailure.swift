/**
 * File: MermaidDiagramPreparationFailure.swift
 * --------------------------------------------
 * Layer: Core
 * Description: Why a diagram text was not prepared for drawing: its reading or its layout refused it, it draws nothing,
 *              or it is too large to draw, with the kind of refusal.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Why a diagram's text was not prepared for drawing, with the error that refused it, so that a reader can show the
/// source and say why instead of an empty or a giant view.
public enum MermaidDiagramPreparationFailure: Error, Equatable, Sendable {
    case reading(MermaidDiagramReadError)
    /// The diagram declares nothing that is drawn (`MermaidDiagram.hasNothingToDraw`).
    case nothingToDraw
    /// Its layout is longer than `maximumSideLength` points on a side (`MermaidDiagramLimits.maximumDrawingSideLength`).
    case tooLargeToDraw(maximumSideLength: CGFloat)
    case flowchartLayout(FlowchartLayoutError)
    case sequenceLayout(SequenceLayoutError)
    case stateDiagramLayout(StateDiagramLayoutError)
    case classDiagramLayout(ClassDiagramLayoutError)
    case entityRelationshipLayout(EntityRelationshipLayoutError)
    case ganttLayout(GanttLayoutError)
    case gitGraphLayout(GitGraphLayoutError)
    case xyChartLayout(XYChartLayoutError)
    case sankeyLayout(SankeyLayoutError)

    /// What kind of refusal it is.
    public enum Category: Equatable, Sendable {
        /// The text is not a diagram as written: a syntax problem on a line, or no type keyword.
        case unreadable
        /// The text names a type that is not drawn yet (`MermaidDiagramReadError.unsupportedDiagramType`).
        case typeNotDrawn
        /// The diagram holds statements or options its type does not draw yet, or draws nothing.
        case notDrawnYet
        /// The text or the layout is past a limit (`MermaidDiagramLimits`).
        case beyondLimits
        /// The diagram is well formed and refused for what it says: links in a circle, a date not in its format, no series.
        case refusedContent
    }

    public var category: Category {
        switch self {
        case .reading(let error): Self.category(of: error)
        case .nothingToDraw: .notDrawnYet
        case .tooLargeToDraw: .beyondLimits
        case .flowchartLayout(.subgraphsNotLaidOut), .stateDiagramLayout(.compositeStatesNotLaidOut), .classDiagramLayout(.namespacesNotLaidOut),
             .entityRelationshipLayout(.subgraphsNotLaidOut), .sequenceLayout(.statementsNotLaidOut), .ganttLayout(.statementNotDrawn),
             .gitGraphLayout(.optionsNotApplied), .sankeyLayout(.optionsNotDrawn): .notDrawnYet
        case .flowchartLayout(.tooManyLayoutPoints), .stateDiagramLayout(.tooManyLayoutPoints), .classDiagramLayout(.tooManyLayoutPoints),
             .entityRelationshipLayout(.tooManyLayoutPoints), .ganttLayout(.tooManyScheduledDays): .beyondLimits
        case .ganttLayout(.unreadableDate), .ganttLayout(.noDayLeftAfterExclusions), .xyChartLayout(.noSeries), .sankeyLayout(.circularLinks): .refusedContent
        }
    }

    private static func category(of error: MermaidDiagramReadError) -> Category {
        switch error {
        case .noDiagram, .invalidSyntax: .unreadable
        case .unsupportedDiagramType: .typeNotDrawn
        case .sourceTooLarge, .tooManyNodes, .tooManyEdges, .tooManyParticipants, .tooManySequenceStatements, .tooManyChartValues: .beyondLimits
        }
    }
}
