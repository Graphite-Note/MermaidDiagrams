/**
 * File: OutlineDiagramBenchmarks.swift
 * ------------------------------------
 * Layer: Benchmark
 * Description: Times reading, laying out, making the scene of and painting kanban boards, tree views and Ishikawa
 *              diagrams, on their documentation examples and generated diagrams, and the memory a layout holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import MermaidDiagrams

/// Times one type as the mindmap's benchmark does, with the median and the 99th percentile per diagram: reading, laying
/// out, both, the scene from a kept layout and the painting, then the heap one layout holds.
struct OutlineDiagramBenchmark<Diagram, Layout> {
    let typeName: String
    let read: (String) throws -> Diagram
    let layout: (Diagram) -> Layout
    let scene: (Layout) -> DiagramScene

    func run(cases: [(name: String, sources: [String])], measuredForMemory source: String) throws {
        for (name, sources) in cases { try report(name, sources: sources) }
        let diagram = try read(source)
        print("memory of one laid-out \(typeName): \(BenchmarkHeap.growth { layout(diagram) }) bytes")
    }

    private func report(_ name: String, sources: [String]) throws {
        let diagrams = try sources.map(read)
        let layouts = diagrams.map(layout)
        let count = sources.count
        let measure = MermaidDiagramsBenchmark.measure
        let reading = measure(count) { for source in sources { _ = try? read(source) } }
        let layingOut = measure(count) { for diagram in diagrams { _ = layout(diagram) } }
        let both = measure(count) { for source in sources { _ = (try? read(source)).map(layout) } }
        let scenes = measure(count) { for laidOut in layouts { _ = scene(laidOut) } }
        let contexts = layouts.map { laidOut in BenchmarkBitmap.context(size: scene(laidOut).size) }
        let painting = measure(count) {
            for (laidOut, context) in zip(layouts, contexts) {
                if let context { DiagramSceneRenderer.draw(scene(laidOut), in: context, palette: MermaidDiagramsBenchmark.palette) }
            }
        }
        print("\(name): read \(reading); layout \(layingOut); read and layout \(both); scene \(scenes); scene and painting \(painting)")
    }

    /// A text of a corpus that reads as another type.
    struct WrongType: Error {}
}

/// The kanban, tree view and Ishikawa benchmarks, one after the other.
enum OutlineDiagramBenchmarks {
    static func run(typography: DiagramTypography) throws {
        try KanbanBenchmark.run(typography: typography)
        try TreeViewBenchmark.run(typography: typography)
        try IshikawaBenchmark.run(typography: typography)
    }
}

enum KanbanBenchmark {
    static func run(typography: DiagramTypography) throws {
        let benchmark = OutlineDiagramBenchmark(typeName: "kanban board of 4 columns of 10 cards", read: { source in
            guard case .kanban(let board) = try MermaidDiagramReader.read(source, limits: .standard) else { throw OutlineDiagramBenchmark<KanbanBoard, KanbanLayout>.WrongType() }
            return board
        }, layout: { board in KanbanLayoutEngine.layout(board, typography: typography) }, scene: DiagramScene.init(layout:))
        try benchmark.run(cases: [("kanban documentation examples", try KanbanCorpus.documentationExamples()),
                                  ("kanban board, 4 columns of 10 cards", [KanbanCorpus.board(columnCount: 4, cardsPerColumn: 10)]),
                                  ("kanban board, 10 columns of 50 cards", [KanbanCorpus.board(columnCount: 10, cardsPerColumn: 50)])],
                          measuredForMemory: KanbanCorpus.board(columnCount: 4, cardsPerColumn: 10))
    }
}

enum TreeViewBenchmark {
    static func run(typography: DiagramTypography) throws {
        let benchmark = OutlineDiagramBenchmark(typeName: "tree view of 50 entries", read: { source in
            guard case .treeView(let tree) = try MermaidDiagramReader.read(source, limits: .standard) else {
                throw OutlineDiagramBenchmark<TreeViewDiagram, TreeViewLayout>.WrongType()
            }
            return tree
        }, layout: { tree in TreeViewLayoutEngine.layout(tree, typography: typography) }, scene: DiagramScene.init(layout:))
        try benchmark.run(cases: [("tree view documentation examples", try TreeViewCorpus.documentationExamples()),
                                  ("tree view, 50 entries", [TreeViewCorpus.tree(entryCount: 50)]),
                                  ("tree view, 500 entries", [TreeViewCorpus.tree(entryCount: 500)])],
                          measuredForMemory: TreeViewCorpus.tree(entryCount: 50))
    }
}

enum IshikawaBenchmark {
    static func run(typography: DiagramTypography) throws {
        let benchmark = OutlineDiagramBenchmark(typeName: "Ishikawa diagram of 6 categories of 4 causes", read: { source in
            guard case .ishikawa(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else {
                throw OutlineDiagramBenchmark<IshikawaDiagram, IshikawaLayout>.WrongType()
            }
            return diagram
        }, layout: { diagram in IshikawaLayoutEngine.layout(diagram, typography: typography) }, scene: DiagramScene.init(layout:))
        try benchmark.run(cases: [("Ishikawa documentation example", try IshikawaCorpus.documentationExamples()),
                                  ("Ishikawa diagram, 6 categories of 4 causes", [IshikawaCorpus.fishbone(categoryCount: 6, causesPerCategory: 4)]),
                                  ("Ishikawa diagram, 20 categories of 10 causes", [IshikawaCorpus.fishbone(categoryCount: 20, causesPerCategory: 10)])],
                          measuredForMemory: IshikawaCorpus.fishbone(categoryCount: 6, causesPerCategory: 4))
    }
}
