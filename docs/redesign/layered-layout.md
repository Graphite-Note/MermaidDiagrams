# Redesign: layered-layout

Written 2026-11-24 by the design phase of the 0.8.0 redesign (Graphite issue #223), measured on main de81532 (0.7.0), Apple M5 Max, Release, under load from other work. [M] or MEASURED marks measured numbers; everything else is an estimate.

Area: Layered layout and the flowchart layout engine. Covers LayeredLayout, LayeredFlatLayout and its 25 pass files, LayeredClusterLayout, LayeredCompoundLayout and LayeredRoute*, LayeredFlatWorkspace and its pools, FlowchartLayoutEngine, FlowchartMeasurement, FlowchartEdgePorts, FlowchartPageAssembly, FlowchartBorderCrossings, route ends and self loops. These sit under flowcharts, agent flows, state, class, ER, requirement and use case diagrams.

## Where the time goes now

All numbers below are MEASURED on the Apple M5 Max, Release build of main de81532, with load average 6 to 16. Benchmark means are per input. Profiling tools are in the prototype folder: --layout-stages, --layered-replay and a malloc-counting dylib.

LAYOUT ALONE (reading minus parsing):
- Baseline benchmark, --profile parsing vs reading, µs per input:
  - Pele's 114 examples: 3.80 / 12.55
  - tree 50: 50.8 / 121.2
  - mesh 50: 49.2 / 308.3
  - tree 500: 515 / 1161
  - state-docs: 2.69 / 21.7
  - class-docs: 2.81 / 14.5
  - er-docs: 4.66 / 21.9
  - requirement-docs: 6.07 / 25.8
- Layout loop alone (pre-read diagrams, no clock), µs per diagram:
  - Pele's 114 examples: 7.25 to 8.3
  - state: 16.2 to 17.0
  - class: 10.7
  - ER: 14.9 to 15.7
  - requirement: 17.9
  - tree 50: 66 to 72
  - mesh 50: 235 to 296

PELE'S 114 EXAMPLES, PER STAGE (µs per diagram averaged over all 114, clock on):
- collapsing 0.06
- FlowchartMeasurement 0.62 (20 allocations)
- LayeredGraph building 0.12
- flat LayeredLayout.place 2.61 (106 calls; 50.5 allocations per diagram)
- FlowchartClusterGraph 0.20
- LayeredClusterLayout.place 2.96 (only 8 calls; 42.5 allocations per diagram, so 606 per clustered graph)
- FlowchartPageAssembly 1.40 (32.5 allocations)
- Whole layout: 162 allocations per diagram. Reading: 68.

BY KIND OF DIAGRAM (each laid out 1,000 times):
- 65 single-node diagrams (the shape examples): 0.99 µs each, 9% of the time. Measurement, the placement wrappers and page assembly make about 25 to 30 allocations for one node.
- 40 flat diagrams with edges: 8.55 µs each, 45% of the time.
- 9 diagrams with subgraphs: 38.7 µs each, 46% of the time.

The idea that "a flat flowchart pays for compound layout" is NOT true for flowcharts. FlowchartLayoutEngine.swift line 93 sends a flowchart without subgraphs straight to LayeredFlatLayout. The compound frames seen in the docs sample come from the 9 subgraph diagrams, which are 8% of inputs and 46% of layout time. The use case engine does pay it: it always calls LayeredClusterLayout, including for its 0-cluster graphs (5.5 to 8 µs for 3 to 6 nodes; 17 µs for 4 nodes and 7 edges).

FLAT LAYERED GRAPHS OF THE DOCS (replayed alone):
- 65 of 106 graphs are a single node, which takes the fast path (0.07 µs).
- The 41 others have 2 to 6 nodes and cost 4.6 to 9.7 µs each (median 4.6 for 2 to 3 nodes, 7.7 for 4 to 6).
- That is about 20,000 to 40,000 cycles for a handful of nodes: fixed cost dominates.
- A 2-node, 1-edge graph makes 122 to 124 heap allocations. The workspace is created per layout, so every pooled list is a fresh malloc for small graphs.

PER-PASS COST, PER NON-TRIVIAL FLAT GRAPH (µs):
- orient 0.21
- rank 0.34
- graph building 1.07
- crossing reduction 0.26
- end spreading 0.13
- Brandes-Köpf positioning 0.46
- end settling, snapping and label alignment 1.22
- rest of routing (straighten, pieces, bands, places) 1.28
- recycling 0.12
- entry and LayeredLayout.place wrapping about 1.0

sample(1), share of top-of-stack samples:
- Flat replay of the docs: ARC (retain/release/bridgeObject/isUniquelyReferenced/dealloc) 36%, malloc/free 23%, array growth/memmove/replaceSubrange 10%, LayeredListPool take/keep 8%, generic metadata lookups 8% (the value-generic pools and InlineArray), algorithm self time 14%.
- Cluster replay: ARC 38%, malloc 17%, growth 13%, pools 9%, metadata 3%, algorithm 20%.
- Whole docs layout: ARC 37%, malloc 22%, growth 11%, pools 6%, metadata 5%, algorithm 18%.

CLUSTERED GRAPHS:
- 11.5 to 70 µs each for 3 to 6 nodes (mean 38 µs).
- Each runs 5 flat layouts (one orders-only keyed layout plus one per level): 26.5 µs in total.
- The compound layout's own work costs another 12 µs and about 400 allocations: levels with item, edge and port arrays, Dictionary portIndex and routes, [LayeredRoutePoint] per route, snapshot/restore copies, route crossing count.

LARGER GRAPHS:
- Tree 50 flat: algorithm share 34%. Mesh 50 flat: algorithm share 67%, mostly crossing reduction (sweep, crossings(between:and:), fillTargets, attemptOrder, measureBarycenters, about 44% of samples).
- Flat core per graph:
  - tree 50: 29.6 µs
  - tree 500: 228 µs
  - mesh 50: 182 µs (crossing reduction 115)
  - mesh 500: 2,546 µs (crossing reduction 1,053, positioning 526, end settling 453)
- Mesh vertex counts: 263 and 7,487 (labels force step 2 and bends).
- No quadratic pass found: tree 50 to 500 is 7.7x for 10x nodes, and mesh is 14x time for 28x vertices. Crossing counting already uses an accumulator tree.

STATE, CLASS, ER, REQUIREMENT:
- The layered part (flat plus cluster place) is:
  - state: 11.7 of 16.2 µs
  - class: 4.5 of 10.8
  - ER: 5.3 of 15.7
  - requirement: 4.7 of 17.9
- The rest is each type's own measurement and page assembly.
- Clustered graphs: state 7 of 22, class 5 of 38, ER 6 of 25.

## Design

GOAL
Steady-state layout with zero heap allocations and no reference counting. Every working list is a span of one per-thread scratch arena, laid out as flat structs of arrays with Int32 indices. Every pass is ported statement for statement, so every Double is computed by the same operations in the same order.

1. SCRATCH ARENA (Layout/Scratch)

```swift
struct ScratchSpan<Element: BitwiseCopyable> {
    let base: UnsafeMutablePointer<Element>; let count: Int
    subscript(index: Int) -> Element { get nonmutating set }   // checked when SCRATCH_BOUNDS_CHECKED
    func fill(_ value: Element)
    func copy(from other: ScratchSpan<Element>)
    var buffer: UnsafeMutableBufferPointer<Element> { get }     // stdlib sort: same algorithm as Array.sort
}

struct ScratchList<Element: BitwiseCopyable>: ~Copyable {        // single owner; grows inside the arena, never traps
    mutating func append(_ element: Element)
    mutating func removeLast() -> Element
    mutating func removeAll()
    var span: ScratchSpan<Element> { get }
}

final class LayoutScratchArena {
    func span<E: BitwiseCopyable>(_ count: Int, repeating value: E) -> ScratchSpan<E>
    func uninitializedSpan<E: BitwiseCopyable>(_ count: Int) -> ScratchSpan<E>
    func list<E: BitwiseCopyable>(capacity: Int, of type: E.Type) -> ScratchList<E>
    func copy<E: BitwiseCopyable>(_ span: ScratchSpan<E>) -> ScratchSpan<E>
    func mark() -> LayoutScratchMark
    func release(to mark: LayoutScratchMark)
    func reset()   // one chunk kept at the high-water mark, capped at 256 KiB; larger chunks freed
    static func withCurrentThread<Result>(_ body: (LayoutScratchArena) throws -> Result) rethrows -> Result
        // pthread key; a nested call (agent flow into flowchart, narrow fitting) takes a mark
    static func trimCurrentThread()
}
```

- Chunked: growth adds a chunk, so spans already taken stay valid until reset.
- Debug builds poison released regions.

2. FLAT CORE (Layout/Span, new files beside the old ones until the switch)

```swift
struct LayeredSpanInput {
    let nodeCount: Int, edgeCount: Int
    let nodeAcross, nodeAlong, nodeSideSpan, nodePortHint, nodeOrderKey: ScratchSpan<Double>
    let nodeKind: ScratchSpan<LayeredVertexKind>; let nodePin: ScratchSpan<Int8>
    let edgeTail, edgeHead, edgeMinimumLength: ScratchSpan<Int32>
    let edgeLabelAcross, edgeLabelAlong, edgeTailOffset, edgeHeadOffset: ScratchSpan<Double>
    let edgeEndHeld: ScratchSpan<UInt8>
    static func make(nodeCount: Int, edgeCount: Int, in arena: LayoutScratchArena) -> LayeredSpanInput
}

struct LayeredSpanOptions {
    // LayeredFlatOptions' numbers and flags
    var groupOfNode: ScratchSpan<Int32>?; var parentOfGroup: ScratchSpan<Int32>; var ordersOnly: Bool
}

struct LayeredSpanGraph {   // every field a span: copied freely, never copy-on-write
    let vertexCount, nodeCount, maximumRank: Int; let hasOffsets: Bool
    vertexWidth, vertexHeight, vertexKey: ScratchSpan<Double>
    vertexKind: ScratchSpan<LayeredVertexKind>; vertexRank: ScratchSpan<Int32>
    segmentFrom, segmentTo: ScratchSpan<Int32>
    segmentFromOffset, segmentToOffset: ScratchSpan<Double>
    segmentFromEnd, segmentToEnd: ScratchSpan<LayeredSegmentEnd>?
    successorStart, successorSegments, predecessorStart, predecessorSegments, rankStart, order, position: ScratchSpan<Int32>
    isRankFixed: ScratchSpan<Bool>; vertexGroup: ScratchSpan<Int32>?; parentOfGroup: ScratchSpan<Int32>
    edgeRankSpan, firstBend, labelVertex, firstSegment, lastSegment: ScratchSpan<Int32>
    isDirect: ScratchSpan<Bool>; labelHeadings: ScratchSpan<UInt8>
}

struct LayeredSpanPlacement {
    let width, height: Double; let crossings, declaredCrossings: Int
    let nodeX, nodeY: ScratchSpan<Double>; let nodeRank: ScratchSpan<Int32>
    let edgeIsReversed: ScratchSpan<Bool>; let edgeTailOffset, edgeHeadOffset: ScratchSpan<Double>
    let edgePointStart: ScratchSpan<Int32>   // edgeCount + 1, into pointX/pointY (side to side, flow space)
    let pointX, pointY: ScratchSpan<Double>
    let edgeLabelX, edgeLabelY: ScratchSpan<Double>
}

enum LayeredSpanLayout {
    static func place(_ input: LayeredSpanInput, options: LayeredSpanOptions, maximumVertexCount: Int,
                      arena: LayoutScratchArena) -> LayeredSpanPlacement?
}
```

- Each pass becomes `static func <pass>(_ graph: LayeredSpanGraph, ..., arena: LayoutScratchArena)`. It takes a mark on entry and releases it on exit.
- Every place that relied on an array copy staying unchanged becomes an explicit `arena.copy`. Examples: crossing reduction's initial and foundOrder, the compound snapshot/restore, any `let x = graph.field` held across a mutation of that field.
- LayeredPositioningWork's buffers come from the arena.
- The old single-node fast path stays.
- The prototype (LayeredArenaRanking.swift) is the template for porting a pass.

3. COMPOUND LAYOUT (Layout/Span/LayeredSpanCompound*)

```swift
struct LayeredSpanCompoundInput {
    // nodes: width, height, parent Int32, isGroup, direction UInt8, three paddings, minimumWidth, sequence, sideSpan
    // edges: source, target, minimumLength, labelWidth, labelHeight
}

struct LayeredSpanCompoundState {
    levelItemStart / levelItems
    levelEdgeStart + levelEdgeIndex / levelEdgeFirst / levelEdgeSecond
    ports as structs of arrays: edge, inner, isOutgoing, side, hint, borderX, borderY, routeStart, routeCount
    firstPortOfEdgeEnd [2E] + nextPortOfSameEnd       // replaces Dictionary portIndex; lookup O(nesting depth)
    levelRouteStart per level edge into routeX / routeY / routeRunsHorizontally   // replaces [Int: [LayeredRoutePoint]]
    node x / y / width / height spans
}

struct LayeredSpanClusterPlacement {
    nodeX, nodeY; clusterX, clusterY, clusterWidth, clusterHeight
    edgeRouteStart + routeX / routeY / segmentRunsVertically
    edgeLabelX, edgeLabelY, hasLabel; isStray
    width, height
}
```

- snapshot() and restore() become memcpy of the mutable spans.
- Each level's flat graph is written straight into a LayeredSpanInput.
- Zero-cluster fast path (use case): a cluster graph without clusters goes straight to LayeredSpanLayout and its result is converted. This is kept only if the placement bit-identity test passes. My reading of the code says it should: one level, no ports, group nil, so the box offsets are 0 and isFlat is false.

4. BOUNDARY: kept during migration, removed at the end
- LayeredLayout.place(_ LayeredGraph...) -> LayeredPlacement? and LayeredClusterLayout.place(...) -> LayeredClusterPlacement keep their signatures as adapters: they fill the arena input, run the span layout and copy out. So every engine gains before it migrates.
- Engines then build LayeredSpanInput directly and read the span placements. Page assembly reads only the first and last point of each path, as today.

5. FLOWCHART ENGINE
- FlowchartSpanMeasurement holds the sizes as spans:
  - shape sizes, text offset, layout size with loops, top/left side spans
  - an isAsset flag span instead of Set<Int>
  - edge text sizes (0 for none)
  - self-loop ranges
- The DiagramTextBlocks stay owned arrays, measured once per diagram and reused across the 2 to 4 narrow fittings (today each fitting measures again).
- FlowchartPageAssembly computes the page offset first (extent and title are known before edges are placed) and writes each point as computed value + offset. That is the same arithmetic as translated(by:) today, so there are no translated copies.
- One DiagramPath per edge.
- FlowchartEdgePorts runs on spans: side ranges sorted with the same comparator through buffer.sort; keptClear is a side-keyed range table instead of [Int: [CGFloat]].
- FlowchartLayout (public) is written once at its final coordinates. If the scene area moves FlowchartLayout to flat storage, page assembly writes that instead.

6. BYTE IDENTITY (measured proof plan)
1. Port statement for statement: same Double expressions, the same min/max argument order (NaN), Int32 only for indices and ranks (exact in Double). Swift does not fuse a*b+c.
2. Sorts: buffer.sort is the stdlib's MutableCollection sort, the same as Array.sort. LayeredStableSorting and middleTwo are ported verbatim with their LayeredSortingEquivalenceTests.
3. Per-pass bit-identity tests: the new pass against the 0.7.0 pass, on graphs captured from every corpus plus Pele's 60 random flat graphs and 300 random compound graphs. Use the LayeredStageReplay capture from the prototype.
4. ReferenceLayeredLayouts: a test-only copy of the 0.7.0 layered layouts (like ReferenceRenderers), comparing LayeredPlacement and LayeredClusterPlacement bit for bit. This is stronger than the SVG, which rounds.
5. --output-digest diff against the de81532 build (826 lines) after every package.

The 0.7.0 corpus speed tests and LayeredLayoutWorstCaseTests bound hostile input, together with:
- MermaidDiagramLimits (50,000 layout points, so Int32 is ample)
- arena growth with no trap
- SCRATCH_BOUNDS_CHECKED in debug and tests, plus an Address Sanitizer run.

## Prototype measurements

- MEASURED, prototype 1: one LayeredFlatWorkspace per thread instead of one per layout (pthread key; --thread-workspace flag in LayeredStageClock.swift).
- Prototype 1, allocations: a 2-node flat graph 122-124 -> 32-34; a clustered graph 605 -> 559; whole docs layout 162 -> 127 per diagram.
- Prototype 1, flat replay of the docs' 106 graphs, 3 alternating pairs: 2.51/2.37/2.46 -> 1.77/1.70/1.73 µs per graph (1.42x).
- Prototype 1, cluster replay: 36.1/36.0 -> 34.2/34.2 µs per graph (1.06x).
- Prototype 1, reading+layout against the baseline binary, 3 alternating pairs each: docs 11.35/10.84/10.79 -> 10.32/10.47/10.70 µs (about 1.04x); state 18.8-20.5 -> 17.3-17.8 (1.1x); class 12.9-13.7 -> 11.8-12.6 (1.08x); ER 18.3-19.4 -> 16.9-18.8 (about 1.05x).
- Prototype 1, output: --output-digest identical to the baseline binary (826 lines; de81532 prints every input (825): 5f44234b8fa913bf on this machine, not the ff8a133226b37b4b the brief quotes).
- MEASURED, prototype 2: arena orient+rank (Prototype/LayeredScratchArena.swift, LayeredArenaRanking.swift) checked against LayeredFlatRanking.orient+rank. Ranks and reversals are identical on every captured graph (docs 41, state 12, class 21, ER 16, trees 50/500, meshes 50/500): 0 disagreeing.
- Prototype 2 timing method: µs per graph, median of 5 repeats, 3 runs. 'Today' means a new pooled workspace per layout; the arena time includes filling the inputs as structs of arrays.
- Prototype 2, docs graphs: 0.83-0.85 today -> 0.087-0.091 in the arena (9.4x). Against a kept pooled workspace (0.345-0.351, of which 0.075-0.079 is copying the inputs) it is 3x.
- Prototype 2, state 0.91 -> 0.127 (7.2x); class 0.85 -> 0.109 (7.8x); ER 0.85 -> 0.097 (8.8x).
- Prototype 2, larger graphs: tree 50 2.29 -> 0.70 (3.3x); mesh 50 2.74 -> 0.95 (2.9x); tree 500 16.2 -> 6.5 (2.5x); mesh 500 21.6 -> 9.8 (2.2x).
- MEASURED with the stage clock (adds about 0.2 µs per diagram); full per-stage numbers are in currentBreakdown.
- Stage clock, docs: flat placement 2.61 µs of 7.25-8.3, cluster placement 2.96, page assembly 1.40, measurement 0.62 (µs per diagram).
- Stage clock, flat stages per non-trivial docs graph: graph building 1.07 µs, end settling 1.22, rest of routing 1.28, positioning 0.46, rank 0.34, orient 0.21.
- Stage clock, clustered graphs: 5 flat layouts per graph (26.5 µs) plus 12 µs of the compound layout's own work.

## Expected after

- ESTIMATE, Pele's 114 flowchart examples, layout alone: 7.25 -> 1.3 to 2.0 µs per diagram (3.6x to 5.6x). The target of 1.5 µs is reachable only if measurement and page assembly reach the same overhead share as the core.
- Docs, by kind: flat with edges 8.55 -> about 1.8 µs (the flat core 6.8 -> about 1.0 per graph, from the ranking prototype's 9.4x discounted to about 6x for the float-heavy passes); with subgraphs 38.7 -> about 8 to 9 µs (5 flat layouts at about 1 µs plus about 3 µs of compound work); single node 0.99 -> about 0.2.
- Docs, reading plus layout (ESTIMATE): today 10.6. It reaches the 2.2 µs needed for 10x Pele only if reading (3.5 µs today, another area) drops to about 0.5 to 0.7.
- ESTIMATE, state-docs layout alone 16.2 -> about 4 (layered part 11.7 -> about 2.3; the type's own measurement and assembly 4.5 -> about 1.5 once ported).
- ESTIMATE, class-docs 10.8 -> about 3 (layered 4.5 -> 0.9; the class-specific 6.3 needs text and assembly work).
- ESTIMATE, er-docs 15.7 -> about 4 (layered 5.3 -> 1.0; ER rows and assembly 10.4 -> about 3).
- ESTIMATE, requirement-docs 17.9 -> about 5 (layered 4.7 -> 0.9; the rest is the requirement engine's own).
- Without the type-specific work in package P4, these types gain only about 1.4x to 1.6x.
- ESTIMATE, tree 50 layout alone 66-72 -> about 20 to 25 µs (about 3x; algorithm share 34%). Tree 500 about 645 -> about 230 µs.
- ESTIMATE, mesh 50 235 -> about 120 to 140 µs (1.7x to 2x; algorithm share 67%, mostly Pele's crossing reduction sweeps). Mesh 500 about 1.8x.
- 10x on trees and meshes is out of reach without changing Pele's crossing reduction and positioning, which would change the output.
- ESTIMATE, narrow scene: the 2 to 4 fittings share one measurement, so the narrow column's extra layouts each cost about the core alone (about 1 µs for docs instead of about 7).
- ESTIMATE, memory: steady state allocates 0 bytes in the core. The per-thread arena keeps at most 256 KiB, which covers Graphite's 64 kB per typical diagram with headroom. Graphs past that free their extra chunks at reset.

## Packages

### P0 scratch arena

Depends on: nothing

Owns: Sources/MermaidDiagrams/Layout/Scratch/LayoutScratchArena.swift, Sources/MermaidDiagrams/Layout/Scratch/LayoutScratchArenaThread.swift, Sources/MermaidDiagrams/Layout/Scratch/ScratchSpan.swift, Sources/MermaidDiagrams/Layout/Scratch/ScratchList.swift, Sources/MermaidDiagrams/Layout/Scratch/ScratchSorting.swift, Tests/MermaidDiagramsTests/LayoutScratchArenaTests.swift, Tests/MermaidDiagramsTests/ScratchSortingEquivalenceTests.swift, Package.swift (define SCRATCH_BOUNDS_CHECKED for debug and tests only)

Adds the arena, spans, the ~Copyable growing list, marks, the per-thread arena with nesting, trim, and debug poisoning. ScratchSorting holds LayeredStableSorting's stable merge and the stdlib sort on buffers. Tests cover chunk growth with stable spans, mark/release, nested use, the retained cap, and sort equivalence with the Array versions (ported from LayeredSortingEquivalenceTests). The template is the prototype's Prototype/LayeredScratchArena.swift.

Expected gain: None by itself: it is the base for every other package. Builds and tests alone in a day.

### P0b per-thread workspace (optional interim, shippable now as 0.7.1)

Depends on: nothing

Owns: Sources/MermaidDiagrams/Layout/LayeredFlatWorkspace.swift, Sources/MermaidDiagrams/Layout/LayeredFlatLayout.swift (line 56 only), Sources/MermaidDiagrams/Layout/LayeredCompoundLayout.swift (line 44 only)

LayeredFlatWorkspace.forCurrentThread() through a pthread key replaces the new workspace per layout, as prototyped. After each layout, lists longer than the retained cap are dropped.

Expected gain: MEASURED: flat layered graphs 1.42x, clustered graphs 1.06x, reading+layout 1.04x to 1.1x, digest identical. P1e removes it.

### P1a span graph, building, ranking, initial order, entry

Depends on: P0 scratch arena

Owns: Sources/MermaidDiagrams/Layout/Span/LayeredSpanInput.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanOptions.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanGraph.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanGraphBuilding.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanRanking.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanBalancedRanking.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanInitialOrder.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanPlacement.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanLayout.swift, Tests/MermaidDiagramsTests/Reference/ReferenceLayeredFlatLayout (copy of 0.7.0 Layout/LayeredFlat*.swift renamed), Tests/MermaidDiagramsTests/LayeredSpanPassIdentityTests.swift, Tests/MermaidDiagramsTests/LayeredPlacementBitIdentityTests.swift

Freezes on day one the interfaces in design sections 2 and 4 (push a stub first so P1b to P1d compile against it). Ports orient, rank, balance, stepOf, chooseDirectEdges, cutEdges, vertexGroups, adjacency, rank starts, depthFirstOrder and orderInitially to spans; the prototype's LayeredArenaRanking.swift is the ranking. LayeredSpanLayout.place runs the pass sequence and calls the P1b to P1d passes. The tests' graph capture comes from the prototype's LayeredStageReplay: every corpus, Pele's random flat graphs and the 300 random compound graphs. Each new pass is checked bit for bit against the reference copy.

Expected gain: MEASURED for ranking: 9.4x per pass on docs graphs. ESTIMATE: graph building 1.07 -> about 0.15 µs and orient+rank 0.55 -> about 0.06 µs per non-trivial graph.

### P1b crossing reduction on spans

Depends on: P0 scratch arena, P1a interfaces (LayeredSpanGraph)

Owns: Sources/MermaidDiagrams/Layout/Span/LayeredSpanCrossingReduction.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanCrossingCount.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanGroupArrangement.swift, Tests/MermaidDiagramsTests/LayeredSpanCrossingIdentityTests.swift

Ports LayeredFlatCrossingReduction, LayeredFlatCrossingCount and LayeredFlatGroupArrangement: sweeps, barycenters, stable sort, transpose, accumulator-tree count, attempt and mirror, groups. initial and foundOrder become explicit arena copies. Each graph's order and crossing counts are checked bit for bit against the reference.

Expected gain: ESTIMATE: small graphs 0.26 -> about 0.05 µs. Mesh 50 115 -> about 60 to 75 µs (the pass is 67% algorithm). Mesh 500 1,053 -> about 550.

### P1c positioning and ends on spans

Depends on: P0 scratch arena, P1a interfaces (LayeredSpanGraph)

Owns: Sources/MermaidDiagrams/Layout/Span/LayeredSpanPositioning.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanCompaction.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanEndSpreading.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanEndSettling.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanSnapping.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanLabelAlignment.swift, Tests/MermaidDiagramsTests/LayeredSpanPositioningIdentityTests.swift

Ports Brandes-Köpf: LayeredPositioningWork's buffers come from the arena; sortNeighbours, conflictingSegments, balanced and middleTwo are verbatim. Also ports spreadEnds/fillSideEnds, freeEnds, label alignment, settling (fit, wanted, sides), snapping and the offsets written back.

Expected gain: ESTIMATE: positioning 0.46 -> about 0.15 µs and settling, snapping and alignment 1.22 -> about 0.2 µs per non-trivial graph. Tree 50 about 2.5x on these passes.

### P1d routing, tracks and bands on spans

Depends on: P0 scratch arena, P1a interfaces (LayeredSpanGraph, LayeredSpanPlacement)

Owns: Sources/MermaidDiagrams/Layout/Span/LayeredSpanStraightening.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanTracks.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanTrackLaying.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanBands.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanPlaces.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanRouting.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanCurveNearness.swift, Tests/MermaidDiagramsTests/LayeredSpanRoutingIdentityTests.swift

Ports emptyRanks, alignPorts, straighten, passLabels, cutPieces/LayeredEdgePieces, bands and their sizing, tracks and track laying, curve nearness, writePlaces/writeRoute and writeOrderPositions. Writes LayeredSpanPlacement: one shared point buffer with per-edge ranges, instead of [CGPoint] per edge.

Expected gain: ESTIMATE: rest of routing 1.28 -> about 0.2 µs per non-trivial graph; the output's per-edge arrays (9 allocations per diagram) disappear.

### P1e switch-over of the flat layout

Depends on: P1a span graph, building, ranking, initial order, entry, P1b crossing reduction on spans, P1c positioning and ends on spans, P1d routing, tracks and bands on spans

Owns: Sources/MermaidDiagrams/Layout/LayeredLayout.swift, Sources/MermaidDiagrams/Layout/LayeredFlatLayout.swift, Sources/MermaidDiagrams/Layout/LayeredFlatWorkspace.swift, Sources/MermaidDiagrams/Layout/LayeredFlatWorkspaceLinkLists.swift, every other Sources/MermaidDiagrams/Layout/LayeredFlat*.swift (deleted)

LayeredLayout.place keeps its signature as an adapter: it fills LayeredSpanInput, runs LayeredSpanLayout.place and copies out to LayeredPlacement. Deletes the pooled flat layout and LayeredListPool. Runs the digest diff, the whole suite, size-report.py, and a sample showing no swift_retain or swift_getGenericMetadata in the core.

Expected gain: ESTIMATE: flat placement on the docs 2.61 -> about 0.45 µs per diagram (flat diagrams with edges 8.55 -> about 3.0 before P3); state, class, ER and requirement read+layout about 1.2x to 1.3x without engine changes.

### P2 compound and cluster layout on spans

Depends on: P0 scratch arena, P1a interfaces (LayeredSpanInput, LayeredSpanOptions, LayeredSpanPlacement); full gain after P1e

Owns: Sources/MermaidDiagrams/Layout/Span/LayeredSpanCompound*.swift (levels, ports, placing, flat keys, routes, edges, box), Sources/MermaidDiagrams/Layout/Span/LayeredSpanRouteCrossings.swift, Sources/MermaidDiagrams/Layout/Span/LayeredSpanRouteCutting.swift, Sources/MermaidDiagrams/Layout/LayeredClusterLayout.swift, Sources/MermaidDiagrams/Layout/LayeredCompound*.swift (deleted at the end), Sources/MermaidDiagrams/Layout/LayeredRouteCrossings.swift, LayeredRouteCrossingCount.swift, LayeredRouteCutting.swift (deleted at the end), Tests/MermaidDiagramsTests/Reference/ReferenceLayeredCompoundLayout (copy of 0.7.0), Tests/MermaidDiagramsTests/LayeredClusterPlacementBitIdentityTests.swift

Design section 3: levels, ports and routes as ranges; Dictionary portIndex replaced by per-edge-end port chains; snapshot/restore as span copies; keyByFlatLayout and every level layout through LayeredSpanLayout with groups and ordersOnly. LayeredClusterLayout.place keeps its signature as an adapter. Adds the zero-cluster fast path, kept only if the bit-identity test on use case and random graphs passes.

Expected gain: ESTIMATE: a clustered graph 38 -> about 7 to 9 µs (docs 2.96 -> about 0.6 µs per diagram); use case's 0-cluster graphs 5.5-8 -> about 1 µs; state's clustered graphs (15-35 µs) about 4x.

### P3 flowchart engine, measurement and page assembly on spans

Depends on: P0 scratch arena, P1a interfaces, P2 compound and cluster layout on spans (for the boxed path), text-and-labels area for how DiagramTextBlock is stored, scene-and-svg area if FlowchartLayout changes shape

Owns: Sources/MermaidDiagrams/Flowchart/FlowchartLayoutEngine.swift, Sources/MermaidDiagrams/Flowchart/FlowchartMeasurement.swift, Sources/MermaidDiagrams/Flowchart/FlowchartPageAssembly.swift, Sources/MermaidDiagrams/Flowchart/FlowchartEdgePorts.swift, Sources/MermaidDiagrams/Flowchart/FlowchartBorderCrossings.swift, Sources/MermaidDiagrams/Flowchart/FlowchartRouteEnds.swift, Sources/MermaidDiagrams/Flowchart/FlowchartSelfLoops.swift, Sources/MermaidDiagrams/Flowchart/FlowchartClusterGraph.swift, Sources/MermaidDiagrams/Flowchart/FlowchartClusterTitles.swift, Sources/MermaidDiagrams/Flowchart/FlowchartCollapsedGroups.swift, Sources/MermaidDiagrams/Flowchart/FlowchartFlowAxes.swift, Sources/MermaidDiagrams/Layout/DiagramRouteDrawing.swift (adds a buffer variant; the existing signatures stay for the other types)

Design section 5: the flowchart builds LayeredSpanInput and LayeredSpanCompoundInput directly; one measurement per diagram, reused across the narrow fittings; page assembly applies the offset first and writes FlowchartLayout once with exact capacities; ports and border crossings on spans; collapsing returns the diagram as it is when no group collapses. Also covers agent flows, which call FlowchartLayoutEngine.layout(measured:).

Expected gain: ESTIMATE: page assembly 1.40 -> about 0.35 µs; measurement, graph building and collapsing 0.80 -> about 0.35; single-node diagrams 0.99 -> about 0.2; wrapping 0.19 -> 0. All together, docs layout reaches about 1.3 to 2.0 µs.

### P4a-e other layered engines on spans (one package per type)

Depends on: P1e switch-over of the flat layout, P2 compound and cluster layout on spans, P3 for the DiagramRouteDrawing buffer variant

Owns: P4a: Sources/MermaidDiagrams/State/StateDiagramLayoutEngine.swift, StateDiagramClusterGraph.swift, StateDiagramPageAssembly.swift, State measurement, P4b: Sources/MermaidDiagrams/Class/ClassDiagramLayoutEngine.swift, ClassDiagramClusterGraph.swift, ClassDiagramPageAssembly.swift, ClassDiagramBorderRuns.swift, Class measurement, P4c: Sources/MermaidDiagrams/EntityRelationship/Layout/* (engine, cluster graph, cluster placement, page assembly), P4d: Sources/MermaidDiagrams/Requirement/RequirementLayoutEngine.swift and its assembly, P4e: Sources/MermaidDiagrams/UseCase/Layout/UseCaseLayoutEngine.swift, UseCasePageAssembly.swift

Each engine builds the span inputs directly, reads the span placements, and moves its own measurement and assembly onto spans with exact capacities, as P3 does. Use case takes P2's zero-cluster fast path. When all are done, the LayeredGraph, LayeredPlacement, LayeredClusterGraph and LayeredClusterPlacement adapters are deleted (last one to land).

Expected gain: ESTIMATE, layout alone: state 16.2 -> about 4 µs, class 10.8 -> about 3, ER 15.7 -> about 4, requirement 17.9 -> about 5, use case about 3x.

## Public API changes

- None required for Graphite. prepare(source:...), prepare(_ diagram:...), PreparedMermaidDiagram.scene/narrowScene, DiagramSceneRenderer, DiagramSVGWriter and DiagramScene.seriesColors are untouched by this area.
- All new types (ScratchSpan, LayoutScratchArena, LayeredSpan*) are internal. FlowchartLayoutEngine.layout and FlowchartLayout keep their public signatures; FlowchartLayout is written once at its final coordinates instead of being built and then translated.
- Optional 0.8.0 addition: public static func MermaidDiagramPreparation.releaseScratchMemory(). It trims the calling thread's layout arena, for a host handling a memory warning; preparing never needs it.
- If the scene-and-svg area turns FlowchartLayout into flat storage, P3 writes that type instead. Graphite does not use FlowchartLayout directly.

## Risks

- The 10x target is not assured: layout alone on Pele's examples is estimated at 1.3 to 2.0 µs against the 1.5 µs target. The flat ranking prototype gives a measured 9.4x on one integer pass; the float-heavy passes (settling, bands, positioning) have larger algorithm shares and are estimated at about 5x to 6x.
- Trees and meshes reach only about 3x and 1.7x to 2x. Pele's crossing reduction and positioning dominate them (67% algorithm self time on mesh 50), and changing those algorithms would change the output.
- Aliasing: spans drop Array's copy-on-write. Every place that relied on a copy staying unchanged must take an explicit arena copy: crossing reduction's initial and foundOrder, compound snapshot/restore, and copies held across a mutation. Missing one changes numbers silently; the per-pass bit-identity tests and the reference-copy placement tests are the guard.
- Unsafe memory: release builds do no bounds checks, so a bug corrupts memory instead of trapping, which matters for hostile input.
- Mitigations for unsafe memory: SCRATCH_BOUNDS_CHECKED in debug and tests; an Address Sanitizer run of the corpus, worst-case and random-graph tests; capacities taken from proven bounds; ScratchList growing in the arena instead of trapping; poisoning of released marks in debug.
- Lifetimes: a span used after its mark is released, or after the outer reset (for example a result kept past a nested agent-flow layout), reads stale memory. Results must be copied to owned arrays at the engine boundary before the outer scope ends; ScratchList is ~Copyable.
- Per-thread memory: each Grand Central Dispatch thread that prepares a diagram keeps up to the retained cap (256 KiB). With many worker threads this is N x 256 KiB at worst. Hence the trim call, the cap, and freeing chunks beyond the cap at reset.
- Generic code: unspecialized generics in hot paths bring back runtime metadata lookups (today 8% of flat samples come from the value-generic LayeredListPool and InlineArray). Keep ScratchSpan specialized under whole-module optimization, and check with sample(1) that no swift_getGenericMetadata or swift_retain appears in the core.
- Migration size: about 3,800 lines of flat layout, 1,200 of compound layout and 6 engines. P1b to P1d can run in parallel only if P1a freezes LayeredSpanGraph and LayeredSpanPlacement on day one; the old and new files coexist until P1e, which roughly doubles the layout code's size for a while (size-report.py thresholds).
- Text and output model are outside this area. The type-specific measurement and assembly of class, ER and requirement are 55% to 75% of their layout time and depend on the text-and-labels area (DiagramTextBlock holds [String] per line, about 20 allocations per docs diagram). Without that work those types stop at about 1.4x to 1.6x.
- Digest discrepancy: on this machine de81532's --output-digest ends 'every input (825): 5f44234b8fa913bf', not the ff8a133226b37b4b the brief quotes. Packages should diff against a build of de81532 made on the same machine, not against a quoted hash.
- The zero-cluster fast path for use case (and any rewrite of LayeredClusterLayout's adapter) must be proven bit-identical. The compound route conversion (box.route with runsHorizontally) and stray/loop handling differ in form from the flat path.

Prototype: branch `redesign-prototype-layered-layout` (the copy of main the design measured, with its prototype code and benchmark modes).
