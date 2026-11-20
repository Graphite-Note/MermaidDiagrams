/**
 * File: NarrowColumnBenchmark.swift
 * ---------------------------------
 * Layer: Benchmark
 * Description: Times, per type that narrows for a column, the layout at its own width and at the narrowest column's, on the
 *              type's documentation examples, and the Gantt chart's JavaScript date forms.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation
import MermaidDiagrams

/// Times what a narrow column adds to a layout, per type, on its documentation examples: the layout at the chart's own
/// width, and again at the narrowest column's width (a mindmap's outline, a journey's column of cards, a chart on a narrower
/// page, a Sankey chart drawn again until its labels fit), and what reading a date in V8's legacy forms costs.
enum NarrowColumnBenchmark {
    /// A type's name, its documentation examples, and how to lay one out for a column of a width (nil: its own).
    private typealias Corpus = (name: String, sources: [String], layOut: (MermaidDiagram, CGFloat?) -> Bool)

    static func run(typography: DiagramTypography) throws {
        let measure = MermaidDiagramsBenchmark.measure
        let narrowestColumn = PreparedMermaidDiagram.standardNarrowestColumnWidth
        for (name, sources, layOut) in try corpora(typography: typography) {
            let diagrams = sources.compactMap { source in try? MermaidDiagramReader.read(source, limits: .standard) }
            guard !diagrams.isEmpty else { continue }
            let own = measure(diagrams.count) { for diagram in diagrams { _ = layOut(diagram, nil) } }
            let narrow = measure(diagrams.count) { for diagram in diagrams { _ = layOut(diagram, narrowestColumn) } }
            print("\(name) narrow column (\(diagrams.count) examples): layout at its own width \(own); at \(Int(narrowestColumn)) points \(narrow)")
        }
        try reportDates(typography: typography)
    }

    private static func corpora(typography: DiagramTypography) throws -> [Corpus] {
        [
            ("mindmap", try MindmapCorpus.documentationExamples(), { diagram, width in
                guard case .mindmap(let mindmap) = diagram else { return false }
                return MindmapLayoutEngine.layout(mindmap, typography: typography, availableWidth: width).size.width > 0
            }),
            ("journey", try UserJourneyCorpus.documentationExamples(), { diagram, width in
                guard case .userJourney(let journey) = diagram else { return false }
                return UserJourneyLayoutEngine.columnLayout(journey, typography: typography, availableWidth: width) != nil
                    || UserJourneyLayoutEngine.layout(journey, typography: typography).size.width > 0
            }),
            ("quadrantChart", try QuadrantChartCorpus.documentationExamples(), { diagram, width in
                guard case .quadrantChart(let chart) = diagram else { return false }
                return QuadrantChartLayoutEngine.layout(chart, typography: typography, availableWidth: width).size.width > 0
            }),
            ("xychart", try XYChartCorpus.documentationExamples(), { diagram, width in
                guard case .xyChart(let chart) = diagram else { return false }
                return (try? XYChartLayoutEngine.layout(chart, typography: typography, availableWidth: width))?.size.width ?? 0 > 0
            }),
            ("sankey", try SankeyCorpus.documentationExamples() + ["sankey-beta\n\n " + SankeyCorpus.energyRows()], { diagram, width in
                guard case .sankey(let sankey) = diagram else { return false }
                return (try? SankeyLayoutEngine.layout(sankey, typography: typography, availableWidth: width))?.size.width ?? 0 > 0
            }),
            ("gantt", try GanttChartCorpus.documentationExamples(), { diagram, width in
                guard case .ganttChart(let chart) = diagram else { return false }
                return (try? GanttLayoutEngine.layout(chart, typography: typography, now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone,
                                                      limits: .standard, availableWidth: width))?.size.width ?? 0 > 0
            }),
            ("c4", try C4Corpus.documentationExamples(), { diagram, width in
                guard case .c4(let c4) = diagram else { return false }
                return (try? C4LayoutEngine.layout(c4, typography: typography, fittingWidth: width))?.size.width ?? 0 > 0
            }),
            ("agentflow", try AgentFlowCorpus.documentationExamples(), { diagram, _ in
                guard case .agentFlow(let agentFlow) = diagram else { return false }
                return (try? AgentFlowLayoutEngine.layout(agentFlow, typography: typography, isTurnedToRunDown: true))?.size.width ?? 0 > 0
            }),
        ]
    }

    /// What a Gantt chart whose start is a date in JavaScript's legacy forms costs to read and lay out.
    private static func reportDates(typography: DiagramTypography) throws {
        let measure = MermaidDiagramsBenchmark.measure
        let dates = ["7 March 2014", "Mar 7 2014 10:30 PM", "3/7/2014", "Fri 07 Mar 2014 10:00:00 GMT", "Fri Mar 07 2014 10:00:00 GMT+0100"]
        let charts = try dates.map { date in
            let source = "gantt\ndateFormat YYYY-MM-DD\nA : a, \(date), 3d\nB : b, after a, 5d"
            guard case .ganttChart(let chart) = try MermaidDiagramReader.read(source, limits: .standard) else { throw NotAGanttChart() }
            return chart
        }
        let layout = { (chart: GanttChart) in
            _ = try? GanttLayoutEngine.layout(chart, typography: typography, now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone, limits: .standard)
        }
        let scheduling = measure(charts.count) { for chart in charts { layout(chart) } }
        print("gantt charts whose start is a date in JavaScript's legacy forms (\(charts.count) charts, two tasks): read as dates and laid out \(scheduling)")
    }

    private struct NotAGanttChart: Error {}
}
