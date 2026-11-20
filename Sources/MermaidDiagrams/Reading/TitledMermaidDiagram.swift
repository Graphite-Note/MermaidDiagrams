/**
 * File: TitledMermaidDiagram.swift
 * ---------------------------------
 * Layer: Core
 * Description: The diagrams whose title is their own `title` statement's, else the front matter's.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

/// A diagram whose title is its own `title` statement's, else the front matter's: every type `MermaidDiagramReader` reads.
protocol TitledMermaidDiagram {
    var title: String? { get set }
}

extension FlowchartDiagram: TitledMermaidDiagram {}
extension StateDiagram: TitledMermaidDiagram {}
extension ClassDiagram: TitledMermaidDiagram {}
extension SequenceDiagram: TitledMermaidDiagram {}
extension EntityRelationshipDiagram: TitledMermaidDiagram {}
extension MindmapDiagram: TitledMermaidDiagram {}
extension TimelineDiagram: TitledMermaidDiagram {}
extension PieChart: TitledMermaidDiagram {}
extension GanttChart: TitledMermaidDiagram {}
extension GitGraphDiagram: TitledMermaidDiagram {}
extension UserJourneyDiagram: TitledMermaidDiagram {}
extension QuadrantChart: TitledMermaidDiagram {}
extension XYChart: TitledMermaidDiagram {}
extension SankeyDiagram: TitledMermaidDiagram {}
extension InfoDiagram: TitledMermaidDiagram {}
extension PacketDiagram: TitledMermaidDiagram {}
extension RadarChart: TitledMermaidDiagram {}
extension TreemapDiagram: TitledMermaidDiagram {}
extension VennDiagram: TitledMermaidDiagram {}
extension CynefinDiagram: TitledMermaidDiagram {}
extension WardleyMap: TitledMermaidDiagram {}
extension C4Diagram: TitledMermaidDiagram {}
extension BlockDiagram: TitledMermaidDiagram {}
extension ArchitectureDiagram: TitledMermaidDiagram {}
extension UseCaseDiagram: TitledMermaidDiagram {}
