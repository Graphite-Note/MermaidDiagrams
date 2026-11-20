/**
 * File: PeleKnownDifferenceList.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Reads PeleKnownDifferences.md: the inputs differing from Pele with what differs, and the reasons named.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

@testable import MermaidDiagramsBenchmark

/// The rows of PeleKnownDifferences.md's tables: under `## Inputs`, an input (`corpus#index`) with what differs and the
/// reasons; under `## Mermaid's flowchart specs`, a spec text by its index; under `## Compat files`, a spec file with what
/// covers it. Each reason row names one reason code.
struct PeleKnownDifferenceList {
    private(set) var inputs: [String: Set<String>] = [:]
    private(set) var specTexts: [Int: Set<String>] = [:]
    private(set) var reasons: Set<String> = []
    /// Compat spec files none of whose diagram texts the package's tests copy, with what covers them or why nothing does.
    private(set) var compatFilesWithoutCopies: [String: String] = [:]
    /// Every reason code an input or a spec text names.
    private(set) var namedReasons: Set<String> = []

    init() throws {
        var section = ""
        for line in try PeleResults.knownDifferences().split(separator: "\n") {
            if line.hasPrefix("## ") { section = String(line) }
            let cells = line.split(separator: "|").map { cell in cell.trimmingCharacters(in: .whitespaces) }
            guard line.hasPrefix("| "), cells.count >= 2, !cells[0].hasPrefix("---") else { continue }
            if cells.count == 2, section.hasPrefix("## Compat"), cells[0].contains("/") { compatFilesWithoutCopies[cells[0]] = cells[1] }
            if cells.count == 2, !section.hasPrefix("## Compat"), cells[0] != "Reason" { reasons.insert(cells[0]) }
            guard cells.count >= 3 else { continue }
            let differences = Set(cells[1].split(separator: ",").map { word in word.trimmingCharacters(in: .whitespaces) })
            let named = cells[2].split(separator: ",").map { word in word.trimmingCharacters(in: .whitespaces) }
            if section == "## Inputs", cells[0].contains("#") {
                inputs[cells[0]] = differences
                namedReasons.formUnion(named)
            } else if section.hasPrefix("## Mermaid"), let index = Int(cells[0]) {
                specTexts[index] = differences
                namedReasons.formUnion(named)
            }
        }
    }
}
