/**
 * File: GridDiagramCorpora.swift
 * ------------------------------
 * Layer: Benchmark
 * Description: The block diagram and architecture inputs of the benchmark and the tests: Mermaid's documentation
 *              examples, as Pele collects them, and generated grids and architectures.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Mermaid's 30 block diagram examples, and generated grids of blocks with composites and edges.
enum BlockCorpus {
    static func documentationExamples() throws -> [String] {
        try DocumentationCorpus.examples(named: "block")
    }

    /// A grid of `blockCount` blocks in `columns` columns, every seventh a composite of three blocks, every fifth in a
    /// bracket shape, and an edge from each block to the one `stride` after it, every third labelled.
    static func grid(blockCount: Int, columns: Int = 6, stride: Int = 6) -> String {
        let shapes = ["[\"%\"]", "(\"%\")", "((\"%\"))", "{\"%\"}", "[(\"%\")]", "([\"%\"])"]
        var source = "block\n  columns \(columns)\n"
        for block in 0..<blockCount {
            if block % 7 == 3 {
                source += "  block:group\(block)\n    columns 3\n    b\(block) c\(block) d\(block)\n  end\n"
            } else if block % 5 == 0 {
                source += "  b\(block)" + shapes[block / 5 % shapes.count].replacingOccurrences(of: "%", with: "Block \(block)") + "\n"
            } else {
                source += "  b\(block)\n"
            }
        }
        for block in 0..<max(blockCount - stride, 0) {
            source += block % 3 == 0 ? "  b\(block) -- \"to \(block + stride)\" --> b\(block + stride)\n" : "  b\(block) --> b\(block + stride)\n"
        }
        return source
    }
}
