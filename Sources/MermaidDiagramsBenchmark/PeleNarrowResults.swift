/**
 * File: PeleNarrowResults.swift
 * -----------------------------
 * Layer: Benchmark
 * Description: What Pele shows of every documentation example in a container 280, 390 and 600 points wide, as
 *              scripts/pele/run.sh --max-width recorded it, for the package's narrow-column differential tests.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import Foundation

/// One documentation example as Pele's mount shows it in a container `maxWidth` wide (mount.ts `fit`): drawn without a
/// width when it fits or when the width changes nothing of it (`narrowed` false), else drawn for that width.
struct PeleNarrowInput: Decodable {
    /// The width of the container, in points (Pele's pixels).
    let maxWidth: Double
    /// Whether Pele drew it for the container's width rather than at its own.
    let narrowed: Bool?
    /// What Pele drew, counted as `pele-corpus.json` counts it (no time).
    let rendered: PeleRenderedInput

    private enum CodingKeys: String, CodingKey {
        case maxWidth
        case narrowed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxWidth = try container.decode(Double.self, forKey: .maxWidth)
        narrowed = try container.decodeIfPresent(Bool.self, forKey: .narrowed)
        rendered = try PeleRenderedInput(from: decoder)
    }
}

/// How the narrow run was made, and the container widths it drew for.
struct PeleNarrowRun: Decodable {
    let pele: String
    let measurer: String
    let maxWidths: [Double]
}

struct PeleNarrowResults: Decodable {
    let run: PeleNarrowRun
    let inputs: [PeleNarrowInput]
}

extension PeleResults {
    /// Pele's drawings of every documentation example for narrow containers (`pele-narrow.json`).
    static func narrow() throws -> PeleNarrowResults {
        try JSONDecoder().decode(PeleNarrowResults.self, from: resource(named: "pele-narrow", extension: "json"))
    }
}
