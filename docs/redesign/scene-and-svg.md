# Redesign: scene-and-svg

Written 2026-11-24 by the design phase of the 0.8.0 redesign (Graphite issue #223), measured on main de81532 (0.7.0), Apple M5 Max, Release, under load from other work. [M] or MEASURED marks measured numbers; everything else is an estimate.

Area: Everything after layout: DiagramScene and its parts, the per-type DrawingParts builders and shape pens, CGPath use, the narrow scene's building, DiagramSVGWriter with its number formatting, DiagramSceneRenderer, and the preparation's accessibility text, which also runs after layout.

## Where the time goes now

How I measured: I built my own copy of main de81532 at …/redesign/scene-and-svg/src in Release, adding ProfilingLoop modes `scene` (scene from a kept layout), `svg` (SVG of a kept PreparedMermaidDiagram), `accessibility` (prepare without SVG) and `parts` (the FlowchartDrawingParts or UserJourneyDrawingParts alone). Machine: Apple M5 Max, load average 6 to 15. Each value is the mean µs per input of a loop, given as the range of 2 or 3 runs. Baseline output of this build: `--output-digest` gives 826 lines, every input 5f44234b8fa913bf. ff8a133226b37b4b is abdf545's digest, not main's.

Per stage and type (µs per input):
- Pele's 114 flowchart examples: read+layout 12.1–13.3. Scene from layout 2.65–3.06, of which the drawing parts' CGPath geometry is 1.86–1.91 and the builder's bounds, merging and joining 0.75–0.80. Accessibility about 0.15 (1% of the preparation's samples). SVG 1.40–1.46. A mean document is 1,591 bytes with 95 path numbers, 2.4 paths and 2.2 texts. After layout about 4.5 in total (the README's 16.12 − 10.63 = 5.5).
- sequence-docs: scene 5.4–6.0, SVG 3.7–3.95.
- journey-docs: scene 9.3–10.0 (parts 5.0–5.25, builder 4.3–4.4), SVG 7.1–7.8. The document is 8,895 bytes with 954 path numbers, 768 of them in 128 cubic curves. Those curves are circles, the mouths' arcs and rounded cards.
- git-docs: scene 13.0–13.9, SVG 7.2–8.3, accessibility about 0.8 (2.4% of samples).
- c4-docs: scene 9.9–10.2, SVG 17.5–19.1 (15.6 KB, 46 texts).
- kanban-docs: scene 2.2, SVG 5.5–6.0.
- block-docs: scene 1.2, SVG 2.6–2.8.
- timeline-docs: scene 9.3–10.7, SVG 8.2–9.4.

`--scenes`, run once on the baseline binary, agrees: flowchart scene 3.02 and SVG 1.62; journey 10.92 and 8.21; c4 9.46 and 17.47; git 14.16 and 7.97.

sample(1) of the scene loop (flowchart / journey, top-of-stack shares without idle):
- Core Graphics path building (CG::Path add_*, append, reserve_space): 21% / 23%
- CF object creation and release: 16% / 10%
- malloc and free: 15% / 12%
- Swift retain and release: 13% / 12%
- trig (atan2, __sincos_stret, from CG's tangent arcs for rounded rects and from addArc): 10% / 8%
- boundingBoxOfPath for the builder's merge test (path_element_bounding_box, get_y_inflections_3): 10% / 25%
- the library's own code: 14% / 9%

sample(1) of the SVG loop (flowchart / journey):
- number writing (writePathElement, writeDigits): 34% / 50%
- escaping and appends: 16% / 8%. The root style and the font family are rebuilt with String interpolation and escaped again for every document.
- memmove: 13% / 22%
- retain and release: 12% / 7%
- CG::Path::apply, which expands held primitives at apply time (add_arc_relative and atan2 show up inside the SVG loop): about 9% / 5%
- Written colours (classDef) build a CGColor and convert it to sRGB for each document, with CFString compares. That was about 15% of the writer's time on flowcharts.

The sample files are in …/scene-and-svg/samples. categorize.py buckets them.

## Design

GOAL AND HONEST LIMIT
The scene keeps no CGPath and makes no allocation per element. The SVG is written straight from the scene into one reused byte block. The output stays byte-identical to 0.7.0.

Two floors come from that constraint:
1. Core Graphics' construction of rounded rectangles and arcs needs atan2 and sincos. Reproducing it bit for bit keeps that trig (27% of the time of my lean exact lanes).
2. 0.7.0's output fixes how many numbers are written: 95 per flowchart and 954 for the journey, at about 2.4 ns each with the branchless writer (measured).

So after layout reaches an estimated 1.1–1.6 µs on Pele's examples, not 0.6 µs. The way past this is to change what is written, for example `<circle>` and rx rectangles or arcs as Pele writes them. That is a product decision, not part of this design.

A. PATHS WITHOUT CGPATH (Scene/Path/)

`public enum DiagramPathVerb: UInt8, Sendable { case move, line, quadraticCurve, cubicCurve, close }`, with `var pointCount: Int`.

DiagramPathLane is a recording handle with CGMutablePath's reference semantics. Its methods are nonmutating, so drawing code changes only where its paths are made. It is a pointer to a DiagramPathLaneState kept in the thread's workspace, so it has no exclusivity checks and no retains.

```swift
struct DiagramPathLane {
  let state: UnsafeMutablePointer<DiagramPathLaneState>
  var isEmpty: Bool { get }
  var currentPoint: CGPoint { get }
  func move(to: CGPoint)
  func addLine(to: CGPoint)
  func addQuadCurve(to: CGPoint, control: CGPoint)
  func addCurve(to: CGPoint, control1: CGPoint, control2: CGPoint)
  func closeSubpath()
  func addLines(between: [CGPoint])
  func addRect(_: CGRect)
  func addRoundedRect(in: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: CGAffineTransform? = nil)
  func addEllipse(in: CGRect)
  func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool, transform: CGAffineTransform? = nil)
  func addPath(_ other: DiagramPathLane)
  func addPath(_ other: DiagramPathLane, transform: CGAffineTransform)
  var boundsOfPath: CGRect { get }  // CG-exact, computed on first ask and cached
}

struct DiagramPathLaneState {
  var verbs: UnsafeMutablePointer<DiagramPathVerb>; var verbCount, verbCapacity: Int32
  var points: UnsafeMutablePointer<CGPoint>; var pointCount, pointCapacity: Int32
  var subpathStart: CGPoint
  var held: DiagramPathPrimitive?   // the one rectangle, rounded rectangle, ellipse or arc added to an empty lane, as CG holds it
  var cachedBounds: CGRect?
}
```

Construction is CG's own arithmetic, ported from origin/speed-scene-paths' DiagramScenePath{Arcs,TangentArcs,Arithmetic,Shapes,Bounds}.swift:
- fused multiply-adds in CG's order
- Annex F exact atan2 along the axes
- sin and cos looked up at 0, ±π/2, ±π and π/4
- held primitives as unit-square transforms
- a held arc's last curve as CGPathApply gives it out
- addPath rules: into an empty path the other is copied whole and stays held; otherwise a held shape is expanded and its first move replaces a trailing move.

I ran the WIP's seven equivalence tests standalone on this Mac: 479,994 bit-exact checks of elements and boundingBoxOfPath against CG, 0 failures. Those files go in as written. Their hot paths are rewritten lean, without arrays per path, computed properties that build arrays, or eager bounds. My lean port of addPath(CGPath(roundedRect:)) matched CG on 20,000 random rectangles.

```swift
final class DiagramSceneWorkspace {
  static var current: DiagramSceneWorkspace { get }  // pthread_getspecific, one per thread; a depth counter hands a temporary workspace to a reentrant build
  func makeLane() -> DiagramPathLane                   // pops a pooled state, capacity kept
  func rectangle(_: CGRect) -> DiagramPathLane          // CGPath(rect:transform:nil)
  func roundedRectangle(_: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat) -> DiagramPathLane  // CGPath(roundedRect:…)
  func ellipse(in: CGRect) -> DiagramPathLane           // CGPath(ellipseIn:)
}
```
Lanes are valid only while a scene records: debug builds check a generation counter. Capacity above 1 MiB is trimmed after a scene. Verb and point counts are capped below Int32 by a limit derived from MermaidDiagramLimits; past it the preparation fails with `.tooLargeToDraw` and never traps.

B. THE BUILDER AND THE STORAGE

```swift
struct DiagramSceneBuilder: ~Copyable {
  init(workspace: DiagramSceneWorkspace = .current)
  mutating func fill(_: DiagramPathLane, _: DiagramPaint, part: DiagramScenePart)
  mutating func stroke(_: DiagramPathLane, _: DiagramPaint, _: DiagramStroke, part: DiagramScenePart)
  mutating func fillAndStroke(_: DiagramPathLane, fill: DiagramPaint, stroke: DiagramPaint, _: DiagramStroke, part: DiagramScenePart)
  mutating func fill(_: DiagramPathLane, _: DiagramLinearGradient, part: DiagramScenePart)
  // migration overloads taking CGPath, with 0.7.0's semantics: the run is joined by a CGMutablePath, then applied once into the storage
  mutating func text(...); mutating func texts(...); mutating func title(_:); mutating func keepNextShapeApart()
  consuming func scene(size: CGSize, font: DiagramFont, seriesColors: DiagramSeriesColors = .none) -> DiagramScene
}
```

Merge rules are 0.7.0's: same painting, same part, opaque, bounds widened by the smoothing reach and half the stroke do not meet; a fill followed by the stroke of the same path becomes fillAndStroke. Bounds are now asked only when a candidate for merging arrives, and the fill-then-stroke test compares handles first, then elements with memcmp. The open run is a short list of lane handles. When it finishes, its elements are copied once into the scene's block, following CG's join of the run: the first lane as it is applied (a held arc in its applied form), later lanes expanded.

```swift
final class DiagramSceneStorage: ManagedBuffer<DiagramSceneStorageHeader, UInt64>, @unchecked Sendable
// one allocation: item records, then verbs, then points (16-byte aligned)
struct DiagramSceneStorageHeader { var itemCount, verbCount, pointCount, verbsOffset, pointsOffset: Int32 }
struct DiagramSceneItemRecord { var kind: UInt8; var partIndex: UInt8; var paintingIndex: UInt16; var firstVerb: Int32; var verbCount: Int32; var firstPoint: Int32 }  // 16 bytes; for a text, firstVerb is its index in texts

public struct DiagramScene: Sendable {
  public let size: CGSize; public let font: DiagramFont; public let seriesColors: DiagramSeriesColors
  let storage: DiagramSceneStorage
  let texts: [DiagramSceneText]
  let paintings: [DiagramShapePainting]  // interned; the strokes' dash arrays shared
}
```
A scene costs three allocations, against a CGPath, a CF object and a DiagramPathStorage per shape today. DiagramScenePart gets an internal `index: UInt8` and a static table of `pele-<part>` class names checked against rawValue by a test. DiagramTextBlock is not changed here; it belongs to layout. If layout moves text to byte ranges of the source, DiagramSceneText carries those ranges and the writer copies the bytes.

C. THE SVG WRITER (Scene/SVG/; prototyped)

The writer walks the storage's records with unsafe pointers. Room is reserved once per element: a path's room is verbCount × 102 bytes, after which every write is unchecked (debug builds assert).

Numbers use 0.7.0's rule: hundredths = Int((v*100).rounded()); 0 for a non-finite value or one of 1e12 or more in size; trailing zeros trimmed. JavaScript and Pele use Math.round(v*100), which rounds ties toward +∞, then integer + FRACTION[i]. So Pele writes −0.125 as −0.12 where we write −0.13, and NaN as "NaN". Those differences are kept, since identity with 0.7.0 is the requirement. Below 10,000 in size, no branch depends on the digits:
- the whole part from two 2-digit table lookups packed into one UInt32 and shifted by its length
- the decimals packed into a second UInt32
- both stored unaligned, the cursor moved by computed lengths

The general writer handles larger values and NaN.

Per document:
- The escaped root style plus font family are cached by (colour mode, postScriptName).
- A painting's attribute tail (` fill="none" stroke="var(--_l)" stroke-width="1" …/>`) is cached per painting index. This is not prototyped yet.
- A written colour is spelled from its own sRGB components without making a CGColor.
- The scratch block is per thread and kept between documents (a fresh 4 KB block costs about 0.35 µs per document, measured).
- The result is made a String once with String(copying: UTF8Span(unchecked:)).

Signatures stay the same: `DiagramSVGWriter.document(of:diagramType:title:description:)` and `PreparedMermaidDiagram.svgDocument(colors:identifierPrefix:)`.

D. THE RENDERER
For each record, the renderer sets the paint and stroke and replays the verbs into the context with move, addLine, addQuadCurve, addCurve and closePath, then fills or strokes. These are exactly the applied elements the CGPath had, so pixels stay identical (DiagramSceneParityTests demands 0 differing pixels). Colours are cached in an array by painting index instead of a dictionary. A gradient clips as today. Painting time is set by rasterization (191 µs for a flowchart), so the replay costs nothing that shows.

E. NARROW SCENE AND ACCESSIBILITY
The narrow scene stays laid out on first read. It records through the reading thread's workspace with the same builder. MermaidDiagramAccessibility keeps title and description eager, since the SVG needs them, and builds its summary on first read from the diagram model, behind a lock as PreparedNarrowScene does. When a narrow scene is wanted, the narrow closure already retains that model.

F. HOW IDENTITY IS KEPT
1. Lanes compute CG's own construction and bounds. The WIP tests are ported as DiagramPathLaneEquivalenceTests (480k random cases) and run on iOS too.
2. Types not yet migrated go through builder overloads that keep 0.7.0's CGPath joins and read them once.
3. Each package must give `--output-digest` = 5f44234b8fa913bf (826 lines), keep DiagramSceneParityTests at 0 pixels, and add an SVG identity check (my --prototype-svg check: 2,246 documents, 0 differ). A change is checked by running both builds and comparing with diff.

## Prototype measurements

- SVG writer prototype (DiagramFlatScene, DiagramSVGByteWriter, DiagramFlatSVGWriter in the library copy, driven by `--prototype-svg`): byte-identical to 0.7.0's writer on every document of every corpus (`--prototype-svg check`: 2,246 documents = 825 inputs × (Pele variables with title and description, fixed palette with background) plus the narrow scenes at 280, 390 and 600; 0 differ).
- SVG time per input, mean of a loop, median of 11 alternating pairs (old 0.7.0 svgDocument() against the flat writer on the same scenes, scratch reused; load 6–7; the small documents carry harness copies, so they are upper bounds): Pele's 114 examples 1.445 → 0.722 µs (2.01×); flowchart-docs 1.604 → 0.814 (1.94×); sequence 3.697 → 1.964 (1.88×); journey 7.488 → 4.183 (1.78×; best run 3.40); git 7.553 → 3.680 (2.06×); c4 18.94 → 7.17 (2.65×); kanban 5.463 → 2.101 (2.64×); block 2.773 → 0.905 (3.02×); timeline 8.593 → 3.678 (2.38×); class 3.103 → 1.725; state 2.833 → 1.549; er 4.240 → 2.362; gantt 4.175 → 2.214; mindmap 1.705 → 0.799; pie 2.688 → 1.577; sankey 7.735 → 3.403; treemap 4.683 → 2.021.
- The same writer with a fresh 4 KB scratch per document: 0.35–0.55 µs slower (Pele's examples 1.06–1.09 against 0.70–0.73), so per-thread reuse of the scratch is required.
- Fixed cost per document: info-docs (692 bytes, 1 item) 0.465 → 0.275 µs, harness copies included.
- Number writing microbenchmark (…/microbench/numbers.swift, swiftc -O, 1.2 M values: coordinates, quarters, eighths, ties, ±0, NaN, ±∞, 1e11, 1e12, a 200k sweep of k/200): the branchless writer gives identical bytes on all 1,200,021 values, at 2.6–3.1 ns a number against 0.7.0's 5.7–6.3 ns, through an indirect call. Inside the writer's path loop the sample gives about 2.4 ns a number.
- Core Graphics exactness (…/cg-exactness, the WIP's equivalence tests run standalone): 479,994 checks of elements and boundingBoxOfPath bit-exact against Core Graphics on macOS 27.2.1 (rounded rectangles, rectangles, ellipses, arcs, transformed shapes, curve bounds, paths added to paths, moved glyphs), 0 failures, 0.69 s.
- Path construction microbenchmark (…/cg-exactness/speed, 8 nodes: 24 addPath(CGPath(roundedRect:)), curves and triangles, read back): Core Graphics 10.4–10.6 µs; the WIP's value paths 9.3–9.9 µs (arrays reallocated, eager bounds); a lean allocation-free lane with the same exact arithmetic 3.87–3.98 µs (2.7×), and 0 of 20,000 random rounded rectangles differ from CG. Lean-lane profile: 27% trig (atan2, sincos, sin) and 32% the tangent arc's own arithmetic, about 150 ns per rounded rectangle, a floor set by CG exactness.
- Today's scene split (my `parts` mode against `scene`, 3 runs): Pele's examples drawing parts 1.86–1.91 µs, whole scene 2.65–2.70 (builder about 0.8); journey parts 5.03–5.25, scene 9.30–9.50 (builder about 4.4, mostly boundingBoxOfPath of curves).
- Accessibility's share (sample of prepare without SVG): flowchart 23 of 2,607 samples (about 0.15 µs), git 61 of 2,498 (about 0.8 µs).

## Expected after

- Pele's 114 flowchart examples, after layout (scene + SVG + accessibility): about 4.5 µs today (README 5.5). Expected 1.2–1.6 µs: scene 0.5–0.8 (estimate: lean lanes, builder about 0.1), SVG 0.72 (measured prototype; 0.55–0.65 estimated once painting tails are cached), accessibility about 0.02 (lazy, estimate), glue about 0.1. The 0.6 µs target is not reached; the floors are CG-exact rounded rectangles (about 0.3 µs of trig per flowchart today) and about 95 numbers per document.
- The same with the whole preparation: if reading and layout reach 2.2 µs, preparation with SVG is about 3.4–3.8 µs, 5.8–6.5× Pele's 22.13 µs render (estimate). With today's reading and layout (10.6) it is about 11.8–12.2 (1.8×).
- sequence-docs: scene 5.4–6.0 → 1.2–2.0 (estimate), SVG 3.7 → 1.96 (measured); after layout about 9.6 → 3.3–4.2. Pele's render is 10.25.
- journey-docs: scene 9.3–10.0 → 1.5–2.5 (estimate: the builder's 4.4 drops to about 0.2 because no merge needs curve bounds; parts 5.0 → 1.3–2.3), SVG 7.5 → 4.2 (measured; 3.4 best run); after layout about 19 → 6–7. Pele's render is 9.54; a 10× target (0.95 µs for everything) is impossible while the output keeps 0.7.0's 954 path numbers.
- git-docs: scene 13–14 → 3–4.5 (estimate), SVG 7.2–7.6 → 3.7 (measured), accessibility 0.8 → about 0.02; after layout 21–23 → 7–8.5. Pele's render is 24.63.
- c4-docs: scene 9.9–10.2 → 2.5–3.5 (estimate), SVG 18–19 → 7.2 (measured); after layout 28–35 → 10–11. Pele's render is 73.37.
- kanban-docs: scene 2.2 → 0.6–0.9 (estimate), SVG 5.5 → 2.1 (measured); after layout about 8 → 2.8–3.1. Pele's render is 16.79.
- block-docs: scene 1.2 → 0.3–0.5 (estimate), SVG 2.8 → 0.9 (measured); after layout about 4.4 → 1.3–1.6. Pele's render is 5.85.
- timeline-docs: scene 9.3–10.7 → 2.5–3.5 (estimate), SVG 8.6 → 3.7 (measured); after layout about 19 → 6.5–7.5. Pele's render is 13.77.
- Graphite's own path (paint, no SVG, narrow scene read): it gains the scene part only, an estimated 3–5×. Painting stays dominated by rasterization (191 µs for a flowchart).

## Packages

### path-lanes

Depends on: nothing

Owns: Sources/MermaidDiagrams/Scene/Path/DiagramPathVerb.swift (new), Sources/MermaidDiagrams/Scene/Path/DiagramPathLane.swift (new), Sources/MermaidDiagrams/Scene/Path/DiagramPathLaneState.swift (new), Sources/MermaidDiagrams/Scene/Path/DiagramPathPrimitive.swift (new), Sources/MermaidDiagrams/Scene/Path/DiagramPathShapes.swift (new), Sources/MermaidDiagrams/Scene/Path/DiagramPathArcs.swift (new), Sources/MermaidDiagrams/Scene/Path/DiagramPathTangentArcs.swift (new), Sources/MermaidDiagrams/Scene/Path/DiagramPathArithmetic.swift (new), Sources/MermaidDiagrams/Scene/Path/DiagramPathBounds.swift (new), Sources/MermaidDiagrams/Scene/Path/DiagramSceneWorkspace.swift (new), Tests/MermaidDiagramsTests/DiagramPathLaneEquivalenceTests.swift (new), Tests/MermaidDiagramsTests/DiagramPathLaneSamples.swift (new)

Ports origin/speed-scene-paths' CG-exact construction and bounds (DiagramScenePath{Arcs,TangentArcs,Arithmetic,Shapes,Bounds}.swift) into pointer-backed lanes held in a per-thread workspace (pthread key, a depth counter for reentrant builds, capacity trimmed above 1 MiB, element counts capped by a limit taken from MermaidDiagramLimits). Bounds are computed on first ask and cached. Held primitives and addPath follow CG's rules. The WIP's equivalence tests are ported against the lanes, plus the lean speed check (…/cg-exactness/speed/lean.swift). No production code uses the lanes yet.

Expected gain: None by itself; it is the base of everything else. Measurable: 480k bit-exact checks against CG, and lean construction about 2.7× faster than CG on a rounded-rectangle-heavy scene (measured 3.9 against 10.5 µs).

### scene-storage-and-builder

Depends on: path-lanes

Owns: Sources/MermaidDiagrams/Scene/DiagramScene.swift, Sources/MermaidDiagrams/Scene/DiagramSceneBuilder.swift, Sources/MermaidDiagrams/Scene/DiagramSceneShapeRun.swift, Sources/MermaidDiagrams/Scene/DiagramSceneTextLine.swift, Sources/MermaidDiagrams/Scene/DiagramSceneStorage.swift (new), Sources/MermaidDiagrams/Scene/DiagramSceneItemRecord.swift (new), Sources/MermaidDiagrams/Scene/DiagramSceneItemView.swift (new), Sources/MermaidDiagrams/Scene/DiagramScenePartNames.swift (new), Tests/MermaidDiagramsTests/DiagramSceneBuilderTests.swift, Tests/MermaidDiagramsTests/DiagramSceneStorageTests.swift (new)

DiagramScene keeps a ManagedBuffer storage (item records, verbs, points), interned paintings and texts. The builder takes lanes and, during migration, CGPaths with 0.7.0's join semantics. Runs are lists of lane handles; bounds are computed only for a merge candidate; elements are copied into the storage once when a run ends. Compatibility views: items, shapes, texts and DiagramSceneShape.path, which makes a CGPath on read. Fast API: itemCount, forEachItem, DiagramSceneShapeView.forEachElement. DiagramScenePart gets an index and a class-name table.

Expected gain: For types not yet migrated, about 1.1× on the scene (no DiagramPathStorage class, enum boxing or per-shape CGPath copy; estimate). Digest and pixels unchanged.

### svg-byte-writer

Depends on: scene-storage-and-builder (interface only; can start first behind the adapter)

Owns: Sources/MermaidDiagrams/Scene/SVG/DiagramSVGWriter.swift, Sources/MermaidDiagrams/Scene/SVG/DiagramSVGBody.swift, Sources/MermaidDiagrams/Scene/SVG/DiagramSVGBuffer.swift, Sources/MermaidDiagrams/Scene/SVG/DiagramSVGColors.swift, Sources/MermaidDiagrams/Scene/SVG/DiagramSVGSyntax.swift, Sources/MermaidDiagrams/Scene/SVG/DiagramSVGScratch.swift (new), Sources/MermaidDiagrams/Scene/SVG/DiagramSVGNumberWriting.swift (new, split from the buffer), Tests/MermaidDiagramsTests/DiagramSVGWriterSpeedTests.swift, Tests/MermaidDiagramsTests/DiagramSVGNumberWritingTests.swift (new)

Builds the prototype (…/src/Sources/MermaidDiagrams/Scene/SVG/Prototype) into the real writer: room reserved once per element with unchecked writes, the branchless number writer (the old one kept for NaN and values of 10,000 or more), per-thread scratch reused, root style and font family cached per font and mode, written colours spelled from their sRGB components, painting tails cached per painting index, one String at the end. It can start at once against the prototype's DiagramFlatScene adapter and switch to the storage when scene-storage-and-builder lands. Tests: identity on every corpus document (the prototype's check), the 1.2 M-value number test, room never exceeded.

Expected gain: SVG 1.7–3.0× (measured prototype): Pele's examples 1.45 → 0.72 µs, journey 7.5 → 4.2, c4 18.9 → 7.2, kanban 5.5 → 2.1, timeline 8.6 → 3.7, block 2.8 → 0.9. A further 10–20% from cached painting tails (estimate).

### scene-renderer

Depends on: scene-storage-and-builder

Owns: Sources/MermaidDiagrams/Scene/DiagramSceneRenderer.swift, Sources/MermaidDiagrams/Scene/DiagramPaint.swift

Replays each record's verbs into the context (move, addLine, addQuadCurve, addCurve, closePath) and fills, strokes, fills and strokes, or clips for gradients, with no CGPath. Colours are cached by painting index in an array.

Expected gain: No measurable painting speed-up (rasterization dominates). Removes the last CGPath objects from the scene path. DiagramSceneParityTests stays at 0 pixels.

### shared-drawing-helpers

Depends on: path-lanes

Owns: Sources/MermaidDiagrams/Drawing/DiagramEdgeDrawing.swift, Sources/MermaidDiagrams/Drawing/DiagramEllipticalArc.swift, Sources/MermaidDiagrams/Drawing/DiagramGlyphPath.swift, Sources/MermaidDiagrams/Drawing/DiagramGlyphPathNumbers.swift

Adds lane-taking versions of edge paths, marks, SVG elliptical arcs and glyph paths beside the CGPath ones, which are removed in remove-core-graphics-adapters.

Expected gain: Enables the type packages; no gain alone.

### flowchart-lanes

Depends on: path-lanes, scene-storage-and-builder, shared-drawing-helpers

Owns: Sources/MermaidDiagrams/Drawing/FlowchartDrawingParts.swift, Sources/MermaidDiagrams/Drawing/FlowchartScene.swift, Sources/MermaidDiagrams/Drawing/FlowchartShapeDrawing.swift, Sources/MermaidDiagrams/Drawing/FlowchartExtendedShapeDrawing.swift, Sources/MermaidDiagrams/Drawing/FlowchartCurvedShapeDrawing.swift, Sources/MermaidDiagrams/Drawing/FlowchartLayeredShapeDrawing.swift, Sources/MermaidDiagrams/Drawing/FlowchartNodeAssetDrawing.swift, Sources/MermaidDiagrams/Drawing/FlowchartShapePen.swift, Sources/MermaidDiagrams/Drawing/FlowchartClusterDrawingParts.swift, Sources/MermaidDiagrams/Drawing/FlowchartStyledParts.swift, Sources/MermaidDiagrams/Drawing/FlowchartRenderer.swift

Records the flowchart's geometry into lanes. The public FlowchartDrawingParts keeps its CGPath properties as computed compatibility properties made from the lanes. The scene uses the lane builder.

Expected gain: Flowchart scene 2.7 → 0.5–0.8 µs on Pele's examples (estimate). The same layout code serves narrow scenes.

### sequence-lanes

Depends on: path-lanes, scene-storage-and-builder, shared-drawing-helpers

Owns: Sources/MermaidDiagrams/Drawing/SequenceDrawingParts.swift, Sources/MermaidDiagrams/Drawing/SequenceScene.swift, Sources/MermaidDiagrams/Drawing/SequenceMessagePaths.swift, Sources/MermaidDiagrams/Drawing/SequenceParticipantShapeDrawing.swift, Sources/MermaidDiagrams/Drawing/SequenceRenderer.swift, Sources/MermaidDiagrams/Drawing/SequenceTextInk.swift

As flowchart-lanes, for sequence diagrams.

Expected gain: Sequence scene 5.4–6.0 → 1.2–2.0 µs (estimate).

### state-and-class-lanes

Depends on: path-lanes, scene-storage-and-builder, shared-drawing-helpers

Owns: Sources/MermaidDiagrams/Drawing/StateDiagramDrawingParts.swift, Sources/MermaidDiagrams/Drawing/StateDiagramScene.swift, Sources/MermaidDiagrams/Drawing/StateDiagramShapeDrawing.swift, Sources/MermaidDiagrams/Drawing/StateDiagramRenderer.swift, Sources/MermaidDiagrams/Drawing/ClassDiagramDrawingParts.swift, Sources/MermaidDiagrams/Drawing/ClassDiagramMarkDrawing.swift, Sources/MermaidDiagrams/Drawing/ClassDiagramScene.swift, Sources/MermaidDiagrams/Drawing/ClassDiagramRenderer.swift

As flowchart-lanes, for state and class diagrams.

Expected gain: State scene about 7.0 → 1.5–2.5 µs, class 5.8 → 1.3–2.0 (estimates from --scenes).

### graph-family-lanes

Depends on: path-lanes, scene-storage-and-builder, shared-drawing-helpers

Owns: Sources/MermaidDiagrams/EntityRelationship/Drawing/*, Sources/MermaidDiagrams/Requirement/RequirementDrawingParts.swift, Sources/MermaidDiagrams/UseCase/Drawing/*, Sources/MermaidDiagrams/AgentFlow/Drawing/AgentFlowScene.swift, Sources/MermaidDiagrams/Swimlane/SwimlaneDrawingParts.swift

As flowchart-lanes, for the ER, requirement, use case, agent flow and swimlane scenes.

Expected gain: ER scene 7.8 → 1.8–2.6, requirement 6.0 → 1.5–2.2, swimlane 7.2 → 1.8–2.5, agent flow 3.4 → 0.9–1.3 µs (estimates).

### charts-lanes-a

Depends on: path-lanes, scene-storage-and-builder, shared-drawing-helpers

Owns: Sources/MermaidDiagrams/GitGraph/GitGraphDrawingParts.swift, Sources/MermaidDiagrams/GitGraph/GitGraphScene.swift, Sources/MermaidDiagrams/GitGraph/GitGraphSymbolDrawing.swift, Sources/MermaidDiagrams/GitGraph/GitGraphRenderer.swift, Sources/MermaidDiagrams/Timeline/TimelineDrawingParts.swift, Sources/MermaidDiagrams/Timeline/TimelineScene.swift, Sources/MermaidDiagrams/Timeline/TimelineRenderer.swift, Sources/MermaidDiagrams/UserJourney/UserJourneyDrawingParts.swift, Sources/MermaidDiagrams/UserJourney/UserJourneyScene.swift, Sources/MermaidDiagrams/UserJourney/UserJourneyColumnScene.swift, Sources/MermaidDiagrams/UserJourney/UserJourneyFaceShape.swift, Sources/MermaidDiagrams/UserJourney/UserJourneyRenderer.swift, Sources/MermaidDiagrams/Gantt/GanttDrawingParts.swift, Sources/MermaidDiagrams/Gantt/GanttScene.swift, Sources/MermaidDiagrams/Gantt/GanttRenderer.swift

As flowchart-lanes, for the Git graph, timeline, user journey and Gantt scenes. These are the heaviest on curves (circles, arcs, rounded cards); bounds are computed only for merge candidates.

Expected gain: Journey scene 9.4 → 1.5–2.5, git 13.5 → 3–4.5, timeline 10 → 2.5–3.5, Gantt 7 → 1.8–2.5 µs (estimates).

### charts-lanes-b

Depends on: path-lanes, scene-storage-and-builder, shared-drawing-helpers

Owns: Sources/MermaidDiagrams/Pie/*Scene.swift, *DrawingParts.swift, *Renderer.swift, Sources/MermaidDiagrams/Quadrant/ (same three), Sources/MermaidDiagrams/XYChart/ (same three), Sources/MermaidDiagrams/Sankey/ (same three), Sources/MermaidDiagrams/Radar/ (the three and RadarCurveSpline.swift), Sources/MermaidDiagrams/Treemap/ (same three), Sources/MermaidDiagrams/Packet/ (same three), Sources/MermaidDiagrams/Info/InfoDiagramScene.swift, InfoDiagramRenderer.swift, Sources/MermaidDiagrams/Mindmap/MindmapScene.swift, MindmapDrawingParts.swift, MindmapShapeDrawing.swift, MindmapRenderer.swift

As flowchart-lanes, for the chart types and mind maps.

Expected gain: Scenes 2.5–4× faster (estimate): pie 4.5 → 1.2–1.8, sankey 12 → 3–4.5, mindmap 3.0 → 0.7–1.1 µs.

### boards-and-maps-lanes

Depends on: path-lanes, scene-storage-and-builder, shared-drawing-helpers

Owns: Sources/MermaidDiagrams/Kanban/KanbanScene.swift, Sources/MermaidDiagrams/TreeView/TreeViewScene.swift, Sources/MermaidDiagrams/Ishikawa/IshikawaScene.swift, Sources/MermaidDiagrams/Venn/VennScene.swift, VennRegionOutline.swift, VennRenderer.swift, Sources/MermaidDiagrams/Cynefin/CynefinScene.swift, CynefinRenderer.swift, Sources/MermaidDiagrams/Wardley/WardleyMapScene.swift, WardleyMapRenderer.swift, Sources/MermaidDiagrams/EventModeling/EventModelDrawingParts.swift, Sources/MermaidDiagrams/Railroad/RailroadDrawingParts.swift, Sources/MermaidDiagrams/C4/Drawing/C4Scene.swift, C4Renderer.swift, Sources/MermaidDiagrams/Block/BlockScene.swift, Sources/MermaidDiagrams/Architecture/ArchitectureScene.swift, ArchitectureIcons.swift

As flowchart-lanes, for these scenes. It can be split again by folder if more agents are free, since every listed file has a single owner.

Expected gain: C4 scene 10 → 2.5–3.5, kanban 2.2 → 0.6–0.9, block 1.2 → 0.3–0.5, railroad 11.4 → 3–4, architecture 9.9 → 2.5–3.5 µs (estimates).

### lazy-accessibility

Depends on: nothing

Owns: Sources/MermaidDiagrams/Preparation/MermaidDiagramAccessibility.swift, Sources/MermaidDiagrams/Preparation/MermaidDiagramGraphAccessibility.swift, Sources/MermaidDiagrams/Preparation/MermaidDiagramChartAccessibility.swift, Sources/MermaidDiagrams/Preparation/PreparedMermaidDiagram.swift, Sources/MermaidDiagrams/Preparation/Mermaid*Preparation.swift (their accessibility initializer calls only)

Title and description stay eager. The summary is built on first read from a retained Sendable closure over the diagram model, behind a lock as PreparedNarrowScene does it. Equatable compares the computed summaries.

Expected gain: Flowchart about 0.15 → 0.02 µs, git about 0.8 → 0.02 µs (from sample shares).

### remove-core-graphics-adapters

Depends on: flowchart-lanes, sequence-lanes, state-and-class-lanes, graph-family-lanes, charts-lanes-a, charts-lanes-b, boards-and-maps-lanes

Owns: Sources/MermaidDiagrams/Scene/DiagramSceneBuilder.swift (CGPath overloads), Sources/MermaidDiagrams/Drawing/DiagramEdgeDrawing.swift, DiagramEllipticalArc.swift, DiagramGlyphPath*.swift (CGPath versions), README.md (Tests and benchmark, Beside Pele)

Removes the CGPath builder overloads and helper versions once every type records into lanes. Re-measures --pele-comparison and --scenes and updates the README.

Expected gain: No CGPath left on the preparation path. The final measured numbers per corpus.

## Public API changes

- Nothing Graphite uses changes signature: MermaidDiagramPreparation.prepare(source:…) and prepare(_ diagram:…), PreparedMermaidDiagram.scene, narrowScene, svgDocument(colors:identifierPrefix:), DiagramSceneRenderer.draw(_:in:palette:), DiagramSVGWriter (init, colors, identifierPrefix, paintsBackground, document(of:diagramType:title:description:)), DiagramScene.seriesColors and palette(over:).
- DiagramScene's stored layout changes (storage-backed), hence 0.8.0. size, font and seriesColors stay stored. items, shapes and texts stay but become computed compatibility views that make a new CGPath for each shape on every read: correct, but O(elements) and allocating. A host that walks items in a hot path should move to the new API.
- New fast reading API: DiagramScene.itemCount; DiagramScene.forEachItem(_ body: (DiagramSceneItemView) throws -> Void) rethrows; enum DiagramSceneItemView { case shape(DiagramSceneShapeView), text(DiagramSceneText) }; DiagramSceneShapeView with painting, part, forEachElement(_ body: (DiagramPathVerb, UnsafeBufferPointer<CGPoint>) -> Void) and makePath() -> CGPath; public enum DiagramPathVerb: UInt8.
- DiagramScene.init(size:font:items:seriesColors:) and DiagramSceneShape.init(path:painting:part:) stay, for hosts and tests that make scenes; they read each CGPath once into the storage.
- The public per-type DrawingParts (FlowchartDrawingParts.solidEdges and the like, used by Graphite's vendored copy in Packages/MermaidDiagrams, ReadingDiagram*.swift and 39 test files) keep their names and CGPath types as computed properties made from lanes, with the same element values; init(layout:) is unchanged.
- MermaidDiagramAccessibility.summary (and value) change from a stored let to a lazily computed property: source-compatible for readers; Equatable kept.
- Optional addition: DiagramSVGWriter.withDocumentBytes(of:diagramType:title:description:_:) for hosts that write files, skipping the String copy (about 50–80 ns a document).

## Risks

- The 0.6 µs target after layout on Pele's examples is out of reach while the output must match 0.7.0 byte for byte; my estimate is 1.1–1.6 µs. Two floors: CG-exact rounded rectangles and arcs need atan2 and sincos (about 0.3 µs per flowchart today, 27% of the lean lane's time), and 0.7.0's output fixes the number count (95 per flowchart, 954 for the journey, at about 2.4 ns each, measured). Going further means a deliberate output change: closed-form corners, or circles and rectangles written as Pele writes them. That is an owner decision with a digest diff.
- Core Graphics exactness is checked on macOS 27.2.1 only (480k cases). iOS or a later OS may build CG paths differently; 0.7.0's output would then differ per OS while the lanes stay fixed. The equivalence tests must also run on an iOS simulator and a device, and a mismatch is a decision, not a test to loosen.
- Merging depends on CG-exact boundingBoxOfPath. Lanes reproduce it with the WIP's collector (bit-exact on 40k random curves), but a bounds difference changes how many path elements a scene has. The digest guards the corpora only; hostile input may legitimately merge differently, which is acceptable as long as nothing crashes.
- Lane handles are unsafe pointers into a per-thread workspace. A lane kept past its scene, or a reentrant scene build on the same thread (a narrow scene read while another scene records), corrupts memory unless recording is scoped, a depth counter hands out a temporary workspace, and debug generation checks are on. Each per-thread workspace keeps the largest scene's capacity: it must be trimmed, and its element counts capped by MermaidDiagramLimits, refusing with tooLargeToDraw instead of overflowing Int32.
- Pele differs from 0.7.0 at negative half-hundredth ties (Math.round rounds toward +∞, Swift's rounded() away from zero) and for NaN ("NaN" against "0"). The design keeps 0.7.0's behaviour; aligning with Pele is a separate, named change.
- The compatibility views (items, DrawingParts' CGPath properties) become slower, since they allocate on every read. A host or test that reads them in a loop gets slower; Graphite's vendored copy uses DrawingParts directly.
- Measurement noise: load average 6–15 during my runs, numbers are means per input of a loop rather than per-diagram medians, and the prototype harness copies PreparedMermaidDiagram and scene values each iteration, so small-document results are upper bounds. Every scene number after the change is an estimate, from a 2.7× microbenchmark and removed sample shares; only the SVG writer was measured on real scenes.
- Parallel packages share no file, but all type packages depend on path-lanes, scene-storage-and-builder and shared-drawing-helpers. A change to the lane or builder interface after the type packages start ripples into all of them, so freeze those interfaces first, with the signatures in this design.

Prototype: branch `redesign-prototype-scene-and-svg` (the copy of main the design measured, with its prototype code and benchmark modes).
