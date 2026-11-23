/**
 * File: MermaidDiagramChartPreparation.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Prepares the charts and the other diagrams laid out without a graph: mindmaps, timelines, pie, Gantt,
 *              quadrant and XY charts, user journeys and Sankey diagrams.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A mindmap, and for a narrow column the mindmap as an outline running down (Pele's `turnToFit`).
    func prepared(_ mindmap: MindmapDiagram) -> PreparedMermaidDiagram {
        let layout = MindmapLayoutEngine.layout(mindmap, typography: typography)
        let narrow = narrowScene(of: mindmap, regularSize: layout.size, laidOut: { mindmap in
            MindmapLayoutEngine.layout(mindmap, typography: typography, availableWidth: narrowestColumnWidth)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .mindmap, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(mindmap: mindmap))
    }

    /// A timeline, and for a narrow column the timeline with its periods one below the other, its columns sharing the
    /// column's width.
    func prepared(_ timeline: TimelineDiagram) -> PreparedMermaidDiagram {
        let layout = TimelineLayoutEngine.layout(timeline, typography: typography)
        let narrow = narrowScene(of: narrowestColumnWidth.map { width in (timeline, width) }, regularSize: layout.size, laidOut: { timeline, width in
            TimelineLayoutEngine.layout(timeline, typography: typography, availableWidth: width)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .timeline, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(timeline: timeline))
    }

    func prepared(_ chart: PieChart) -> PreparedMermaidDiagram {
        let layout = PieChartLayoutEngine.layout(chart, typography: typography)
        let narrow = narrowScene(of: narrowestColumnWidth.map { width in (chart, width) }, regularSize: layout.size, laidOut: { chart, width in
            PieChartLayoutEngine.layout(chart, typography: typography, availableWidth: width)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .pieChart, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(pieChart: chart, layout: layout))
    }

    /// A Gantt chart scheduled on `now` in `timeZone`, and for a narrow column the chart on a page as wide as the column.
    func prepared(_ chart: GanttChart) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: GanttLayout
        do {
            layout = try GanttLayoutEngine.layout(chart, typography: typography, now: now, timeZone: timeZone, limits: limits)
        } catch {
            throw .ganttLayout(error)
        }
        let narrow = narrowScene(of: chart, regularSize: layout.size, laidOut: { chart in
            try GanttLayoutEngine.layout(chart, typography: typography, now: now, timeZone: timeZone, limits: limits, availableWidth: narrowestColumnWidth)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .ganttChart, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(ganttChart: chart))
    }

    /// A user journey, and for a narrow column the journey as a column of cards (Pele's `turnToFit`).
    func prepared(_ journey: UserJourneyDiagram) -> PreparedMermaidDiagram {
        let layout = UserJourneyLayoutEngine.layout(journey, typography: typography)
        let narrow = narrowScene(of: journey, regularSize: layout.size, laidOut: { journey in
            guard let column = UserJourneyLayoutEngine.columnLayout(journey, typography: typography, availableWidth: narrowestColumnWidth) else {
                throw NoColumnLayout()
            }
            return column
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .userJourney, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(userJourney: journey, layout: layout))
    }

    /// A quadrant chart, and for a narrow column the chart on a page as wide as the column (Pele's `capWidth`).
    func prepared(_ chart: QuadrantChart) -> PreparedMermaidDiagram {
        let layout = QuadrantChartLayoutEngine.layout(chart, typography: typography)
        let narrow = narrowScene(of: chart, regularSize: layout.size, laidOut: { chart in
            QuadrantChartLayoutEngine.layout(chart, typography: typography, availableWidth: narrowestColumnWidth)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .quadrantChart, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(quadrantChart: chart))
    }

    /// An XY chart, and for a narrow column the chart on a page as wide as the column (Pele's `capWidth`).
    func prepared(_ chart: XYChart) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: XYChartLayout
        do { layout = try XYChartLayoutEngine.layout(chart, typography: typography) } catch { throw .xyChartLayout(error) }
        let narrow = narrowScene(of: chart, regularSize: layout.size, laidOut: { chart in
            try XYChartLayoutEngine.layout(chart, typography: typography, availableWidth: narrowestColumnWidth)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .xyChart, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(xyChart: chart))
    }

    /// A Sankey diagram, and for a narrow column the chart narrowed to fit it with its labels smaller (Pele's `fitWidth`).
    func prepared(_ sankey: SankeyDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: SankeyLayout
        do { layout = try SankeyLayoutEngine.layout(sankey, typography: typography) } catch { throw .sankeyLayout(error) }
        let narrow = narrowScene(of: sankey, regularSize: layout.size, laidOut: { sankey in
            try SankeyLayoutEngine.layout(sankey, typography: typography, availableWidth: narrowestColumnWidth)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .sankey, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(sankey: sankey))
    }
}

/// A journey's cards stay side by side in the narrowest column: no column layout is made.
private struct NoColumnLayout: Error {}
