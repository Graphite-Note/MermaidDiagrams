# Redesign: flowchart-and-scene

What the flowchart's layout hands its scene, and what every type's scene builder pays per shape (wave 3, package flowchart-and-scene, branch `redesign-flowchart-and-scene` from main ba176e5).

## Where the time went

sample(1) of the flowchart documentation examples (Pele's 114) on main ba176e5, Release:

- Read and layout: 42% of the round was malloc, free, retain, release and copies. Each edge made a list of route points, a `DiagramPath` with its own list of segments, and a translated copy of both. The layout's lists held `FlowchartLayoutNode` and `FlowchartLayoutEdge` values, each with a `DiagramTextBlock` (a storage reference) and a style. The measurement kept five lists of blocks, and freeing them took 2.3% of the round. The measurement and the flowchart were also copied into closures.
- Prepared with SVG: reading 17%, layout 34%, scene 21%, SVG 9%, freeing the prepared diagram 4%.
- The scene: 22% in `DiagramSceneBuilder.add`. Copying the run's painting in and out took about 3% of the scene, and comparing a lane's elements with the run's (`holdsSamePath`) about 2%, even when the paintings' kinds ruled the comparison out.

## What changed

1. **The layout's records** (`Flowchart/FlowchartLayoutRecords.swift`, `FlowchartLayoutRecordBlock.swift`). `FlowchartLayout` keeps one `FlowchartLayoutRecordBlock`, a `ManagedBuffer`. It holds:
   - every node record (`FlowchartPlacedNode`);
   - every edge record (`FlowchartPlacedEdge`: a start and a run of segments);
   - every segment.

   Its header holds the text storages the texts were written in (`DiagramPlacedTextStorages`, `Text/DiagramPlacedTexts.swift`), plus the styles and icons of the few nodes and edges that have them. A layout is one allocation and copies as one reference. `nodes` and `edges` are made as values when read.

   The ranked and boxed layouts write each piece once, already moved onto the page, into lists of the thread's arena (`FlowchartLayoutRecording`, `FlowchartPagePieces.append…`). Routes are put on the page in arena spans and drawn straight into the segment list (`DiagramRouteDrawing.appendPath`, `Layout/DiagramRouteDrawingRecording.swift`).

   Two earlier versions were slower:
   - Three Swift arrays made from the arena lists: each cost a generic metadata lookup and an allocation.
   - Records holding their storages and styles as separate fields: every copy of a layout cost five retains, and the scene was 7% slower.

   `FlowchartLayout(size:font:nodes:edges:title:clusters:)` writes values straight into the block. Swimlanes and the reference engines use it.
2. **The measurement** (`FlowchartMeasurement`, `FlowchartMeasuredRecords.swift`):
   - A node is one record: a placed text, a shape size and a text offset. An edge's text is a placed text.
   - The measurement is two lists of plain values. The layout's records start from its storages, so a text goes from measurement to layout to scene as numbers, and becomes a block only when the scene draws it.
   - Readers that index blocks, sizes or offsets (a swimlane) get views with the old subscripts.
3. **The model and the parse result**:
   - `FlowchartModel` keeps its text and lists in one immutable box (`FlowchartModelStorage`).
   - `FlowchartParser.parse` writes the diagram where it is kept, instead of returning it through four closures in a `Result`.
4. **The scene builder** (`Scene/DiagramSceneShapeRun.swift`):
   - The run's painting is the builder's last one, read in place.
   - The cheap tests (part, the paintings' kinds, equality, opacity) come before the run lane's elements are compared or any bounds are asked.

   Every type's scene gains from this.

## Measured

All runs are against main ba176e5 Release, under load from other builds on the machine (load average 8 to 20).

Pele comparison (`--pele-comparison`), two runs each, alternated, on commit ab4c6bd (items 1 to 3):

| Case | Read and layout | Prepared with SVG |
|---|---|---|
| Flowchart examples | 2.70 → 2.33 µs (8.2× → 9.5× Pele's 22.13) | 4.59 → 4.00 µs (4.8× → 5.5×) |
| flowchart-docs | 2.66 → 2.48 | 4.52 → 4.14 |
| Tree, 50 nodes | 32.4 → 22.9 | — |
| Tree, 500 nodes | 332 → 245 | — |

Types this package did not change moved by ±7% between those runs, so smaller differences there are noise.

Alternated pairs of `--profile <case> <work>`, medians of the pairs' ratios:

| Case | Work | Speedup | Pairs |
|---|---|---|---|
| Flowchart examples | read and layout | 1.127× | 7 |
| Flowchart examples | prepared with SVG | 1.070× | 7 |
| Flowchart examples | narrow | 1.057× | 5 |
| Flowchart examples | scene from a kept layout | 1.064× (with item 4) | 5 |
| journey-docs | scene | 1.076× | 5 |
| c4-docs | scene | 1.118× | 5 |
| class-docs | scene | 1.035× | 5 |
| swimlane-docs | prepared with SVG | 1.054× | 5 |

Agent flows read the shared layout's nodes and edges as values. Making them takes 0.8% of agentflow-docs' preparation (sampled). Its pairs ran at load 20 and are inconclusive.

The target for the examples' read and layout is 2.2 µs; this package reaches about 2.33 µs, so the target is missed. Most of what is left is algorithmic:

- the layered layouts' passes: positions, end settling, bands, crossing reduction, and the compound layout's second flat run for its ordering keys;
- CG-exact rounded rectangles in the scene;
- the parser's per-node work.

None of those can change while the output must stay the same.

## Proof

- `--output-digest` gives the same 826 lines as main ba176e5 at every commit: every input (825): 5f44234b8fa913bf.
- `FlowchartLayoutEquivalenceTests` compares against the 0.7.0 engine frozen in Tests/Reference.
- `FlowchartLayoutRecordsTests` checks that:
  - a layout made again from its values gives the same values, layout and SVG;
  - layouts differing in one piece are not equal;
  - twelve threads at once lay out as the reference does;
  - hostile flowcharts (texts of 6,000 bytes in storages of their own, 400 loops, 40 nested groups, a 1,500-node tree, a 400-node mesh) match the reference;
  - 400 texts spread over more than a hundred storages, placed in shuffled order, read back as their blocks.
- The scene lane tests of every type, the builder tests and `DiagramSceneParityTests` (0 differing pixels) cover item 4.

## Not done

- **The builder's middle copy.** The run lane still copies each shape's elements before the record buffers do. Deferring the copy until a merge would keep a lane after its drawing gave it back. Recording the first lane straight into the buffers would need its bounds and held shape kept, or asked for, on every shape. Neither is safe without a check on every lane mutation.
- **Scene destruction.** The scene's texts (block storage references) and paintings (dash lists) are still lists to free. Two other approaches were slower and were taken out:
  - Keeping them in thread-owned blocks and copying them out at their length cost more in retains and releases than the lists' growth saves (C4 1.118× → 1.025×, flowchart 1.064× → 1.008×).
  - Reserving the flowchart's lists from a count of its records cost more than the growth it saved.
- **The measured-text bridge.** `DiagramTextBlock(_:of:source:)` still copies each measured text's bytes into the thread's text storage. Taking the measured lines directly would need a scene text that keeps the layout's lines and the source alive.
- **Flat measuring** of literal, fitted and `lines:lineWidths:` texts.
- **The underscore fast path.** Keeping a word-internal underscore off the full Markdown decoder in `DiagramLabelDecoder` would change the label's `isReadWithoutMarkup` flag, which the decoding observation tests compare. It needs its own named change.
- **Layered layout data.** `LayeredFlatOptions.groupOfNode` and `parentOfGroup` are still Swift arrays; they cost two allocations per compound layout, which the profile puts under 1%.
- Not checked in Graphite, on iOS or on a device.
