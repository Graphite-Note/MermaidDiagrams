/**
 * File: MermaidDiagramChartPreparation.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Prepares the charts and the other diagrams laid out without a graph: mindmaps, timelines, pie, Gantt,
 *              quadrant and XY charts, user journeys and Sankey diagrams.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

extension MermaidDiagramPreparationContext {
    func prepared(_ mindmap: MindmapDiagram) -> PreparedMermaidDiagram {
        PreparedMermaidDiagram(kind: .mindmap, scene: DiagramScene(layout: MindmapLayoutEngine.layout(mindmap, typography: typography)),
                               accessibility: MermaidDiagramAccessibility(mindmap: mindmap))
    }

    /// A timeline, and for a narrow column the timeline with its periods one below the other.
    func prepared(_ timeline: TimelineDiagram) -> PreparedMermaidDiagram {
        let layout = TimelineLayoutEngine.layout(timeline, typography: typography)
        let narrow = narrowScene(of: timeline.turnedToRunDown, regularSize: layout.size, laidOut: { turned in
            TimelineLayoutEngine.layout(turned, typography: typography)
        }, scene: DiagramScene.init(layout:))
        return PreparedMermaidDiagram(kind: .timeline, scene: DiagramScene(layout: layout), narrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(timeline: timeline))
    }

    func prepared(_ chart: PieChart) -> PreparedMermaidDiagram {
        let layout = PieChartLayoutEngine.layout(chart, typography: typography)
        return PreparedMermaidDiagram(kind: .pieChart, scene: DiagramScene(layout: layout),
                                      accessibility: MermaidDiagramAccessibility(pieChart: chart, layout: layout))
    }

    /// A Gantt chart scheduled on `now` in `timeZone`.
    func prepared(_ chart: GanttChart) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: GanttLayout
        do {
            layout = try GanttLayoutEngine.layout(chart, typography: typography, now: now, timeZone: timeZone, limits: limits)
        } catch {
            throw .ganttLayout(error)
        }
        return PreparedMermaidDiagram(kind: .ganttChart, scene: DiagramScene(layout: layout), accessibility: MermaidDiagramAccessibility(ganttChart: chart))
    }

    func prepared(_ journey: UserJourneyDiagram) -> PreparedMermaidDiagram {
        let layout = UserJourneyLayoutEngine.layout(journey, typography: typography)
        return PreparedMermaidDiagram(kind: .userJourney, scene: DiagramScene(layout: layout),
                                      accessibility: MermaidDiagramAccessibility(userJourney: journey, layout: layout))
    }

    func prepared(_ chart: QuadrantChart) -> PreparedMermaidDiagram {
        PreparedMermaidDiagram(kind: .quadrantChart, scene: DiagramScene(layout: QuadrantChartLayoutEngine.layout(chart, typography: typography)),
                               accessibility: MermaidDiagramAccessibility(quadrantChart: chart))
    }

    func prepared(_ chart: XYChart) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: XYChartLayout
        do { layout = try XYChartLayoutEngine.layout(chart, typography: typography) } catch { throw .xyChartLayout(error) }
        return PreparedMermaidDiagram(kind: .xyChart, scene: DiagramScene(layout: layout), accessibility: MermaidDiagramAccessibility(xyChart: chart))
    }

    func prepared(_ sankey: SankeyDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: SankeyLayout
        do { layout = try SankeyLayoutEngine.layout(sankey, typography: typography) } catch { throw .sankeyLayout(error) }
        return PreparedMermaidDiagram(kind: .sankey, scene: DiagramScene(layout: layout), accessibility: MermaidDiagramAccessibility(sankey: sankey))
    }
}
