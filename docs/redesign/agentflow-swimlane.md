# Redesign: agent flow and swimlane, last pass of wave 3

What package agentflow-swimlane (branch redesign-agentflow-swimlane) changed in the agent flow and swimlane layouts, what it measured, and what it left.

## Swimlane

- `SwimlaneGraph` is written into the calling thread's scratch arena. It reads the flowchart's group, member and edge records directly. Its boxes and edges are `ScratchSpan`s (`LaneLayoutSpanGraph`), and so are each group's and node's box and where each sits among the groups (`SwimlaneGroupNesting`, -1 for none). No list of subgraphs, edge drawings or boxes is made. `FlowchartClusterNesting` is not worked out: a swimlane never reads its crossed groups, directions or closing order.
- `LaneLayout.placed(_:spacing:arena:)` lays out a graph given as spans without copying it. `LaneLayoutGraph.spans(in:)` copies a graph of lists into the arena, which the tests and `LaneLayout.place` use.
- The page's size and offset are known once the lanes are placed (`SwimlanePageFrame`). So `SwimlanePageAssembly` makes each edge, routed or a loop, once and in edge order, already on the page. Its path's points are moved where they lie, with the same additions `DiagramPath.translated(by:)` makes. There is no list of optional edges, no second copy of each path, and no per-edge lists of points and axes: the route's axes are read through `LaneRouteSegmentAxes`, and its points are copied once into the arena.
- Proof: the 0.7.0 graph, assembly and engine are frozen in `Tests/MermaidDiagramsTests/Reference/ReferenceSwimlaneLayout`. `SwimlaneLayoutEquivalenceTests` compares layouts to the bit for:
  - every corpus swimlane, regular and tight, as written and turned, and fitted to four column widths;
  - 600 random and 600 changed swimlanes;
  - hostile ones: long labels, 24 lanes of 20 steps, groups 60 deep, 180 groups, and many visible and invisible loops.

  It also checks the graph box for box against the frozen lists, and runs the layout on twelve threads at once.

## Agent flow

- `AgentFlowClusterGraph` reads the graph's nodes and edges where they lie in their lists, instead of copying each struct out (with its Strings and arrays) in every loop. It looks each edge's ends up once and reserves its lists.
- `AgentFlowMeasurement` decodes only the flows' titles for the subgraphs, instead of every node's label twice. It works out styles and text looks only for nodes that have styles. It builds its node texts in order, without a list of placeholder blocks first.
- `AgentFlowLayoutAssembly` makes the frames list and the shape dictionary of the held-edge routing only when an edge is held.
- A vertex's first metadata mapping is kept whole instead of rebuilt key by key. Metadata keys are only looked up, never listed in order.
- Proof: `AgentFlowLayoutEquivalenceTests`, against the frozen 0.7.0 engine (`Tests/Reference/ReferenceAgentFlowLayout`), now covers:
  - every corpus input;
  - Pele's 239 reference inputs and 900 changed texts, of which 359 diagrams are drawn;
  - five hostile texts: long labels, 300 nodes, flows 40 deep, 60 flows, and held and collapsed flows with styles;
  - twelve threads.

## Measured

Mac Release, `--profile <corpus>`, five alternated pairs of 1.5 s runs against main b2efcf2's Release build, medians of the pairs' ratios, load 4 to 5:

| Case | Main b2efcf2 | This branch | Ratio |
|---|---|---|---|
| swimlane read and layout | 10.09 µs | 7.47 µs | 1.35x |
| swimlane prepared with SVG | 14.22 µs | 11.32 µs | 1.26x |
| swimlane narrow preparation | 37.2 µs | 27.3 µs | 1.37x |
| agent flow reading alone | 13.88 µs | 13.31 µs | 1.04x |
| agent flow read and layout | 24.69 µs | 21.64 µs | 1.15x |
| agent flow prepared with SVG | 28.97 µs | 26.01 µs | 1.11x |
| agent flow narrow preparation | 29.26 µs | 26.29 µs | 1.12x |

`--pele-comparison`: swimlane-docs read and layout 7.34 µs (4.8x Pele; main 3.6x), prepared with SVG 11.38 µs (3.1x; main 2.6x). agentflow-docs read and layout 20.86 µs (2.2x; main 2.0x), prepared with SVG 25.04 µs (1.8x; main 1.7x).

## Not done

- Agent flow reading (slow-types-4) is not started. It is still the UTF-16 lexer, the String-keyed builder and the String model. It is about 60% of read and layout (about 13 µs of 21.6), and it is what stands between agent flow and its 4.6 µs target. The layout still goes through a `FlowchartDiagram` and the shared `FlowchartLayoutEngine` (about 3 µs). No agent flow text is measured through `DiagramMeasuredText`.
- The swimlane target of 3.5 µs is not reached:
  - The shared flowchart reader takes about 2.3 µs.
  - The lane passes (`LanePass`, `LaneHandoffRouting`, unchanged) take about 2.9 µs. How many passes each input runs was not measured.
  - Texts are still measured by `FlowchartMeasurement` as blocks.
  - `DiagramTurningRouteDrawing.path`, which is shared, still makes its own lists.
  - `LaneLayoutBox` keeps its optional parent.
- None of this was checked in Graphite, on iOS or on a device.
