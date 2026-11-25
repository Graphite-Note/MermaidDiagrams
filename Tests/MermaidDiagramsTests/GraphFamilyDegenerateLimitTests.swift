/**
 * File: GraphFamilyDegenerateLimitTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The state, class, entity relationship and requirement readers given limits of zero and below, which
 *              MermaidDiagramLimits' public initializer takes as written, refuse or read as 0.7.0's readers did; the
 *              room the readers make from the text's length and the limits is never asked for below zero.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class GraphFamilyDegenerateLimitTests: XCTestCase {
    /// Limits of 0 and -1 for nodes and edges, alone and together, and a source limit of 0 and -1.
    private static let degenerateLimits: [MermaidDiagramLimits] = {
        let standard = MermaidDiagramLimits.standard
        var limits: [MermaidDiagramLimits] = []
        for nodes in [-1, 0, 1, standard.maximumNodeCount] {
            for edges in [-1, 0, 1, standard.maximumEdgeCount] {
                limits.append(MermaidDiagramLimits(maximumSourceBytes: standard.maximumSourceBytes, maximumNodeCount: nodes, maximumEdgeCount: edges,
                                                   maximumLayoutPointCount: standard.maximumLayoutPointCount))
            }
        }
        for bytes in [-1, 0] {
            limits.append(MermaidDiagramLimits(maximumSourceBytes: bytes, maximumNodeCount: standard.maximumNodeCount,
                                               maximumEdgeCount: standard.maximumEdgeCount, maximumLayoutPointCount: standard.maximumLayoutPointCount))
        }
        return limits
    }()

    func testStateDiagramsUnderDegenerateLimitsAreReadAsTheReferenceReadsThem() throws {
        let sources = try PeleResults.sources(ofCorpus: "state-docs").prefix(8) + [StateDiagramCorpus.machine(stateCount: 30, extraTransitionCount: 10)]
        for limits in Self.degenerateLimits { StateReadingEquivalenceTests.assertReadAlike(Array(sources), limits: limits) }
    }

    func testClassDiagramsUnderDegenerateLimitsAreReadAsTheReferenceReadsThem() throws {
        let sources = try PeleResults.sources(ofCorpus: "class-docs").prefix(8) + [ClassDiagramCorpus.hierarchy(classCount: 30, fan: 3)]
        for limits in Self.degenerateLimits { ClassReadingEquivalenceTests.assertReadAlike(Array(sources), limits: limits) }
    }

    func testEntityRelationshipDiagramsUnderDegenerateLimitsAreReadAsTheReferenceReadsThem() throws {
        let sources = try PeleResults.sources(ofCorpus: "er-docs").prefix(8) + [EntityRelationshipCorpus.schema(entityCount: 30)]
        for limits in Self.degenerateLimits { EntityRelationshipReadingEquivalenceTests.assertReadAlike(Array(sources), limits: limits) }
    }

    func testRequirementDiagramsUnderDegenerateLimitsAreReadAsTheReferenceReadsThem() throws {
        let sources = try PeleResults.sources(ofCorpus: "requirement-docs").prefix(8)
        for limits in Self.degenerateLimits { RequirementReadingEquivalenceTests.assertReadAlike(Array(sources), limits: limits) }
    }
}
