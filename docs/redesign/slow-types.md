# Redesign: slow-types

Written 2026-11-24 by the design phase of the 0.8.0 redesign (Graphite issue #223), measured on main de81532 (0.7.0), Apple M5 Max, Release, under load from other work. [M] or MEASURED marks measured numbers; everything else is an estimate.

Area: Slow types: C4, agent flow, swimlane, use case, block, quadrant, XY chart, user journey, Gantt, requirement, kanban. This covers their readers, their own layouts (C4 grid and routing, the lane layout, Gantt scheduling, chart plots), their text measuring and what their preparation adds. The layered layout under agent flow, use case and requirement, the flowchart reader under swimlane, and the scene and SVG writer are other areas' work; this design names what it needs from them.

## Where the time goes now

How it was measured: baseline binary /private/tmp/claude-501/-Users-baheyshalash-Desktop-Graphite/6d72f356-244e-47a1-86bb-e652bab855d4/scratchpad/redesign/build/release/MermaidDiagramsBenchmark (main de81532), run with `--profile <corpus> parsing|reading|preparation|narrow 1`, two runs each at load average 7 to 16. The numbers are the profile loop's mean per input in µs. `--scenes` gave the scene and SVG costs. sample(1) of each corpus's reading and preparation loop (4 s, 1 ms) is in slow-types/samples/*.txt, analysed with slow-types/analyze.py (inclusive share, self share by category) and slow-types/subtree.py. The corpus names are <type>-docs: c4-docs, agentflow-docs, swimlane-docs, usecase-docs, block-docs, quadrant-docs, xychart-docs, journey-docs, gantt-docs, requirement-docs, kanban-docs. 'agent-flow-docs' and 'user-journey-docs' do not exist.

Per corpus: Pele render median / parse only / read+layout / prepared with SVG / narrow, in µs; then the dominant costs, as shares of read+layout from the samples:

- C4 (6 inputs, median 2,261 bytes; Pele 73.37): 15.5 / 52.8-54.8 / 91.6 / 123-130. Layout is 65% and reading 29%.
  - Text measuring costs 15.7 µs a diagram, measured directly: 46 texts a diagram at 330-340 ns each. C4TextLabel.block goes through DiagramLabelDecoder and DiagramTextBlock: [String] lines, arrays and wrapping.
  - Other costs: C4GridPlacement.placed 28% (most of it the text), routeRelations 11.6%, placeLabels 9.2%, assembled 11.5% (placed labels, a CGPath per relation), and C4ElementLook building VennAppearance arrays for every element even without colors (3.2%).
  - Reader: C4Lexer.run 7.8%, readMacro 17% (addShape 8% of the macro time, readArguments 6.3%).
  - Preparation adds the scene (9.0 µs) and the SVG (17.9 µs for 15.5 KB, 1,203 numbers).
  - The narrow scene runs up to 4 tight drawing passes, each measuring every text again.
- Agent flow (12 inputs, median 278 bytes; Pele 45.72): 16.7-17.5 / 41.5-43.1 / 53.9-56.3. Reading is 40%: about 60 ns a byte, from the UTF-16 lexer (AgentFlowLexer on [UInt16]), the parser and builder, dictionaries keyed by String, YAML metadata (AgentFlowMetadataReading 3.6%) and unspecialized generics (_swift_getGenericMetadata 3.6%). The layered FlowchartLayoutEngine takes 38%, AgentFlowMeasurement 7% and AgentFlowClusterGraph 6.6%.
- Swimlane (13 inputs, median 312 bytes; Pele 35.45): 10.9-11.3 / 35.9-38.8 / 51.6-56.0 / 150-165 (narrow). FlowchartParser takes 31%. LaneLayout.place takes 46%: LanePass.init 20.6%, placeAcross 9.9%, LaneHandoffRouting 7.6%. Up to roundCount+2 full passes run, plus SwimlaneGraph 6% and LaneLayoutItems 5.9%. The narrow scene costs about 4 times the regular layout.
- Use case (24 inputs, median 256 bytes; Pele 49.54): 7.8-8.4 / 38.6-38.9 / 49.5-54.1. The layered cluster layout takes 33% and UseCaseLayoutPass 23%: node measurement 14.5%, UseCaseTextLabel.mermaidCodesRead using Foundation StringProtocol.contains/range at about 3% each, UseCaseLook.init 3.8%. The parser takes 24%.
- Block (30 inputs, median 47 bytes; Pele 5.85): 3.2-3.4 / 8.4-8.5 / 15.2-16.6. Reading 39% (BlockLexer.tokens 7.3%, BlockHierarchy.set 15%). BlockViews.measured 21%, and in it BlockMeasurerCache.appearance and BlockAppearance.applyDeclaration take 10-12% for every block, styled or not. Fixed per-diagram costs dominate inputs this small.
- Quadrant (3 inputs, median 433 bytes; Pele 13.01): 6.8-7.4 / 10.6-11.9 / 21.0-23.4. Reading is 60%: QuadrantChartLexer.readToken 23% of the loop (readKeywordWithSpaces and readRunOrCharacter make Strings), point style syntax 7.4%, preprocessing 6.2%. Layout: point placement 10.9%, text blocks 9.5%.
- XY chart (8 inputs, median 285 bytes; Pele 12.30): 6.5-8.0 / 12.8-14.8 / 24.5-29.1. Reading is 49%: readStatements 16%, readSeries 8.7%, MermaidThemeSeriesPalette.seriesColors 6.4% (resolving the theme palette), preprocessing 5.6%. XYChartFrame.init takes 22% (label measuring, 12% text blocks) and value scale tick labels 6.5%.
- Journey (1 input, 198 bytes; Pele 9.54): 3.3-4.2 / 7.5-9.8 / 28.8-41.9.
  - Reading is 43%, mostly model building: addTask 31.5% (Substring split, a [String] of actors per task, Unicode-property trimming 7%).
  - UserJourneyDiagram.actorNames getter 6%, UserJourneyPlacement 19.5%, text blocks 13%.
  - Preparation: the scene costs 8.9 µs (DrawingParts build CGPath circles, CGPath append_rounded_rect, path bounding boxes) and the SVG 7.0 µs for 8.8 KB with about 1,000 numbers. CGPathApply is 15% of preparation and MermaidDiagramAccessibility 6.6%.
- Gantt (11 inputs, median 235 bytes; Pele 23.28): 3.6-4.8 / 18.8-21.0 / 34.0-35.4. Layout is 76%:
  - GanttSchedule.init 30%: startTime and endTime parse task data per task with String split, trimmingCharacters and Character.isWhitespace; GanttDateFormat.init and parse repeated; GanttDuration.isDecimalNumber on Strings.
  - GanttAxisFormat.format 13% (String padding and compares) and GanttExcludedDays 6.4%.
  - Its own civil-date arithmetic already avoids Calendar.
- Requirement (9 inputs, median 269 bytes; Pele 27.71): 5.5-5.9 / 23.2-25.9 / 39.2-43.2. RequirementMeasurement.box 25% (DiagramLabelDecoder 10.9%, DiagramTextBlock 10.9%), the layered layout 21%, the parser 20%.
- Kanban (3 inputs, median 106 bytes; Pele 16.79): 3.9-4.3 / 9.6-9.9 / 19.8-20.9. MermaidOutlineReader takes 33% (KanbanCardMetadata and KanbanFlowReader YAML 9-13%). KanbanMeasuredCard text takes 20-21%: wrapping with a character-breaking width.

What the samples show for every type: self time is 23-29% reference counting (swift_retain/release/bridgeObject, doDecrementSlow, dealloc, arrayDestroy), 12-23% malloc/free, 3-11% memmove and array growth, and 2-10% hashing. That is 45-55% of all time spent on objects and arrays rather than work.

Preprocessing and front matter are small: 0.7-6.4% (at most 0.7 µs, quadrant).

The SVG writer is already a byte writer. Its number writing costs 3.5-3.7 ns a number on real documents (measured, below), so an SVG's own numbers set a floor on preparation.

Graphite note: Graphite's main checkout (747b79ef) still draws through its vendored Packages/MermaidDiagrams. GraphiteUI/ReadingDiagram.swift calls UserJourneyLayoutEngine, QuadrantChartLayoutEngine, XYChartLayoutEngine and GanttLayoutEngine and their DrawingParts directly, not MermaidDiagramPreparation.

## Design

Principle: each slow type becomes one vertical slice (reader, flat model, layout, scene builder) on shared flat foundations. Hot paths hold no String, no per-item array or class, no CGPath and no String-keyed dictionary. Output stays byte-identical because every arithmetic step is kept in its old order.

A. What these types need from the shared areas (other agents define them; listed so these packages can build against them):

1. Source bytes in the model. MermaidTextCursor already holds the preprocessed [UInt8] and a position, so readers keep the signature `XParser.parse(_ cursor: MermaidTextCursor, limits:)`. Each flat model stores `let source: [UInt8]`, which is the cursor's own array: a retain, no copy. That way MermaidDiagramReader.swift's dispatch needs no edits and type packages do not conflict there.
   - `struct TextRange: Hashable, Sendable { var start: Int32; var end: Int32 }`. A range with the high bit set points into a per-diagram `derived: [UInt8]`, which holds decoded escapes and generated text such as "[type]" or tick labels.
   - `struct InternedNames { mutating func intern(_ range: TextRange, in bytes: UnsafeBufferPointer<UInt8>) -> Int32; func range(of id: Int32) -> TextRange }`: open addressing on FNV-1a of the bytes, a linear scan under 8 names.
2. One workspace per thread: `final class DiagramWorkspace` holding reusable lists (`var integers: [Int32]`, `var numbers: [CGFloat]`, `var measuredLines: DiagramMeasuredLines`, the SVG buffer) and released when larger than 1 MB.
   - `MermaidDiagramPreparation.prepare(..., workspace: DiagramWorkspace? = nil)`; nil takes the calling thread's workspace through a pthread key.
   - A model read into workspace lists is compacted into exact-size arrays when the read ends (an estimated 0.05-0.15 µs per diagram).
3. A flat scene path (an opcode byte list plus a CGFloat point list instead of CGPath; see origin/speed-scene-paths 7180c5b, unfinished), a builder taking measured text by range (`addText(_ text: DiagramMeasuredText, lines: borrowing DiagramMeasuredLines, bytes: UnsafeBufferPointer<UInt8>, style:)`), and lazy accessibility.
4. A flat layered layout (agent flow, use case, requirement) and the flat flowchart reader (swimlane).

B. Flat text measuring: a package in this area, shared with every type. It is the costliest piece found, and it is prototyped.
```swift
struct DiagramMeasuredText: Equatable, Sendable { var firstLine: Int32; var lineCount: Int32; var width: CGFloat; var height: CGFloat; var lineHeight: CGFloat; var fontSize: CGFloat; var center: CGPoint }
struct DiagramMeasuredLines { var starts: [Int32]; var ends: [Int32]; var widths: [CGFloat]; var runs: [DiagramTextRun]? /* only for emphasis */ }
struct DiagramFlatMeasurer { let advances: UnsafePointer<CGFloat> /* 95 printable ASCII, from CoreTextFontFace */; let fontSize: CGFloat; let singleLineHeight: CGFloat; let fallback: CoreTextDiagramTextMeasurer }
enum DiagramFlatTextMeasuring {
  static func measure(_ bytes: UnsafeBufferPointer<UInt8>, _ range: TextRange, form: DiagramLabelDecoder.Form, measurer: DiagramFlatMeasurer, maximumWidth: CGFloat, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText
  static func measureBreakingCharacters(_ bytes: UnsafeBufferPointer<UInt8>, _ range: TextRange, measurer: DiagramFlatMeasurer, wrappingWidth: CGFloat, breakingWidth: CGFloat, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText // kanban
}
struct DiagramConstantTextWidths { /* per face: widths of a closed set (C4ShapeKind.guillemetedName, «include»/«extend», requirement stereotypes), filled once */ }
```
- Fast path: a text whose bytes are all ASCII, split at Pele's RE_BREAK (`<br\s*/?>` in any case, written `\n`, a line feed). Each line is trimmed of ASCII white space, must be printable and must pass DiagramLabelLineBreaks.isUnmarked, which is called only when a markup byte (#&*:\_<) is present. Each line is wrapped at spaces exactly as DiagramTextWrapping does.
- Anything else takes the existing DiagramLabelDecoder and DiagramTextBlock path, and its lines are copied into the arena as derived bytes.
- Bit identity: widths are summed left to right in the same order as `DiagramPrintableASCIIAdvances.width(continuing:over:)`: no SIMD and no reassociation. A single-pass wrap runs the line chain and the piece chain as two independent addition chains, so it is bound by addition latency (an estimated 0.7 ns a byte).

C. Per-type flat models (examples; the others follow the same pattern):
```swift
public struct C4Diagram: Equatable, Sendable { let source: [UInt8]; let derived: [UInt8]; public let level: C4DiagramLevel; var title: TextRange; var elements: [C4FlatElement]; var shapes: [C4FlatShape]; var boundaries: [C4FlatBoundary]; var relations: [C4FlatRelation]; var aliases: InternedNames; var styleUpdates: [C4FlatStyleUpdate]; public var title: String? { get } /* views made on access */ }
struct C4FlatElement { var alias: Int32; var label, type, technology, description, sprite, tags, link, backgroundColor, borderColor, fontColor: TextRange; var line: Int32 }
struct C4FlatShape { var element: Int32; var kind: C4ShapeKind; var boundary: Int32 }
struct C4FlatBoundary { var element: Int32; var parent: Int32; var deploymentKind: Int8; var firstChild: Int32; var childCount: Int32 }
struct C4FlatRelation { var kind: C4RelationKind; var from, to: Int32; var label, technology, description, textColor, lineColor: TextRange; var offsetX, offsetY: Int32 }
public struct UserJourneyDiagram { let source: [UInt8]; var title: TextRange; var sections: [TextRange]; var tasks: [UserJourneyFlatTask]; var actorMentions: [Int32]; var actorNames: [TextRange] /* interned in first-named order */ }
struct UserJourneyFlatTask { var label: TextRange; var score: Double; var hasScore: Bool; var firstActorMention: Int32; var actorMentionCount: Int32; var sectionIndex: Int32 }
```
- Equatable compares decoded content, not offsets, so `==` keeps its meaning.
- Public read accessors return the old value types made on access (for tests and hosts).

Flat layouts keep geometry in lists: frames as [CGRect], all route points in one [CGFloat] with (first, count) per edge, every text a DiagramMeasuredText into the layout's own DiagramMeasuredLines. The scene builder reads them directly.

D. Per type, beyond the shared directions:
- C4:
  - Reader: one byte pass; macro names dispatched by length and first bytes; arguments as ranges; JavaScript-style escapes into derived bytes; `$name=value` arguments; aliases interned; UpdateElementStyle and UpdateRelStyle as index lists.
  - Layout:
    - C4TextLabel becomes flat measuring.
    - Kind names, a closed set of non-ASCII names now measured by Core Text each time, come from DiagramConstantTextWidths.
    - C4ElementLook is built only when a color is written.
    - The tight layout's retries (gaps 36 to 108) reuse the measured texts, because the room is the same across retries.
    - Routes and detours write points into one list, with no CGPath per relation.
- Agent flow:
  - The lexer moves from UTF-16 to UTF-8. UTF-16 columns (Jison's) are computed only when a position is read (a diagnostic, an element position): the byte offset on an ASCII line, otherwise counted on demand, 2 for a 4-byte sequence.
  - `@{ … }` metadata uses a one-line flow-map reader on bytes, falling back to MermaidYAMLDocument for block YAML.
  - The unspecialized generic behind _swift_getGenericMetadata is found and made concrete.
  - Builder dictionaries switch to interned ids.
- Swimlane:
  - The reader is the shared flat flowchart reader.
  - LaneLayout: the pass-invariant work (LaneLayoutItems, ordering) is computed once instead of in every re-pass. Which parts depend on isPlain and keepsMargin must be verified before splitting the pass.
  - Routes become flat [LanePoint] slices.
  - The narrow re-layout reuses measured texts.
- Use case: mermaidCodesRead becomes a byte scan (no Foundation contains/range); UseCaseLook is built only when styled; JSON tables are read on bytes; the layered layout is shared.
- Block: appearances are built only for blocks with classes or styles; BlockMeasurerCache gets interned keys; BlockHierarchy becomes parent and child Int32 lists; lexer tokens become ranges.
- Quadrant: the Jison-like token Strings become byte tokens; point styles are read on bytes; point label placement uses flat candidate rectangles.
- XY chart: numbers through a byte JavaScript Number reader; the theme palette is resolved only when written; each label is measured once; tick labels go into the derived byte arena.
- Journey: the measured reader below; interned actors make actorNames free; faces and legend become flat.
- Gantt: dateFormat and axisFormat are compiled once per chart; task fields, durations and dates are read on byte ranges; axis texts go into the derived bytes; excluded days are computed once.
- Requirement: byte lexer; box fields measured flat; the style copy cap is kept.
- Kanban: a flat outline reader in a new file (mindmap keeps MermaidOutlineReader until its own area adopts the new one); metadata YAML read on bytes; character-breaking flat measuring.

E. Keeping output byte-identical:
1. Reader equivalence tests convert the flat model to the old model, test-side only, as the prototype does, and require `==` and identical MermaidDiagramReadError (line numbers included). They run on every corpus input, Pele's spec inputs, PeleDifferential, and cut and mutated inputs, with fast paths forced off and on.
2. Text: every label of every corpus at three widths, plus random ASCII fuzz, compared bitwise with DiagramTextBlock (lines, widths, lineHeight, runs nil).
3. Layout: the same operation order for every coordinate (CGFloat, no reassociation, no -Ounchecked).
4. Every merge: `--output-digest` diffed against the baseline build run the same way (826 lines), `--layout-memory`, the whole suite, size-report.py, alternating timings.

Hostile input: Int32 ranges are ample under the 50 KB limit. Every list growth is checked against MermaidDiagramLimits before appending, and fast paths never loop without consuming a byte.

## Prototype measurements

- Prototype folder: /private/tmp/claude-501/-Users-baheyshalash-Desktop-Graphite/6d72f356-244e-47a1-86bb-e652bab855d4/scratchpad/redesign/slow-types/src. It is a copy of main de81532 with three additions: Sources/MermaidDiagrams/Prototype/*.swift, Sources/SlowTypesPrototype/main.swift, and a recording hook in C4/Layout/C4TextLabel.swift. Built with `swift build -c release -j 4 --product SlowTypesPrototype --scratch-path .../slow-types/build` and run as `.../slow-types/build/release/SlowTypesPrototype <corpus.json> text|journey`, or `<file.svg> numbers`. Old and new paths alternate in 9 pairs in the same binary, medians taken; load average 5 to 9.
- MEASURED, C4 text measuring (the costliest single piece in the costliest type). The C4 layout measures 276 texts over the 6 C4 documentation diagrams, 46 a diagram. The flat path takes 272 of them, with 0 mismatches against C4TextLabel.block in lines, line widths (bitwise), size and line height. The 4 it leaves have &, * or ***: 'Read & write to', '3: select * from users…'. Two runs: C4TextLabel.block 15.76 and 15.18 µs a diagram (330-343 ns a text); flat with full-path fallback 4.17 and 3.79 µs a diagram (82-91 ns a text): 3.8-4.0x. On the 222 recorded texts the flat path takes directly (the rest are kind names served from the constant table), from one byte buffer as the redesign holds them: 70-73 ns a text, against 327-343 ns. Average text 26.7 bytes; 66 texts wrap, 53 bytes on average.
- MEASURED, journey reader. The flat user journey reader (UserJourneyFlatReader.swift) produces a model that, converted back, equals MermaidDiagramReader's UserJourneyDiagram on the documentation example and on 3 generated journeys (2, 5 and 10 sections of 6 tasks). journey-docs: 3.15 and 3.14 µs (old) against 0.255 and 0.251 µs (flat, counting the copy into a reused buffer, MermaidPreprocessing.bytesFound and the keyword): 12.4-12.5x. Generated: 31.7 against 2.07-2.11 µs: 15.0-15.3x. That is about 1.2-1.3 ns a source byte. Scores beyond plain integers, accessibility statements and non-ASCII trimming fall back in the prototype; the design handles them on bytes.
- MEASURED, the SVG number floor (SlowTypesNumberFloor.swift). Writing a real document's numbers with the package's own DiagramSVGNumberWriting into one buffer: journey 1,057 numbers in 3.86 µs (3.7 ns a number); C4 1,203 in 4.25 µs; quadrant 379 in 1.31 µs; block 183 in 0.49 µs. Copying the document's bytes once costs 0.03-0.24 µs. So journey's preparation with SVG cannot reach Pele/10 = 0.95 µs: its own numbers take 4x that.
- MEASURED baseline, profile loop means in µs (parse / read+layout / prepared with SVG / narrow): c4 15.4-15.5 / 52.8-54.8 / 91.6-91.8 / 123-130; agentflow 16.7-17.5 / 41.5-43.1 / 53.9-56.3 / 51.6-53.5; swimlane 10.9-11.3 / 35.9-38.8 / 51.6-56.0 / 150-165; usecase 7.8-8.4 / 38.6-38.9 / 49.5-54.1 / 74-85; block 3.2-3.4 / 8.4-8.5 / 15.2-16.6 / 17.4-18.9; quadrant 6.8-7.4 / 10.6-11.9 / 21.0-23.4 / 25-29; xychart 6.5-8.0 / 12.8-14.8 / 24.5-29.1 / 29-37; journey 3.3-4.2 / 7.5-9.8 / 28.8-41.9 / 40-60; gantt 3.6-4.8 / 18.8-21.0 / 34.0-35.4 / 49-53; requirement 5.5-5.9 / 23.2-25.9 / 39.2-43.2 / 33-37; kanban 3.9-4.3 / 9.6-9.9 / 19.8-20.9 / 19-20. From `--scenes` (scene from layout / SVG / SVG bytes): c4 9.03 / 17.86 / 15,514; agentflow 3.07 / 4.01; swimlane 6.97 / 3.17; block 1.13 / 2.57; quadrant 3.44 / 4.18; xychart 3.64 / 4.46; journey 8.92 / 7.00 / 8,821; gantt 6.37 / 3.74; requirement 5.73 / 5.31; kanban 1.88 / 5.40. The full output is in slow-types/baseline-run.txt and baseline-scenes.txt.
- Digest note: running the baseline binary's `--output-digest` here prints 'every input (825): 5f44234b8fa913bf' (826 lines, saved in slow-types/baseline-digest.txt with every SVG in slow-types/baseline-svg/). The brief quotes inputs digest ff8a133226b37b4b. Compare builds by diffing the 826 lines produced the same way, in the same time zone.

## Expected after

- How to read these: Pele/10 is the target; [M] is measured, [E] is an estimate. The estimates assume a reader at about 1.3 ns a byte plus 0.15 µs fixed [M on journey], about 30 ns a text after the single-pass wrap (70-80 ns [M] today), layouts 3-6x faster once their reference counting, malloc and array growth (45-55% of samples [M]) and repeated passes are gone [E], and the shared layered layout and flowchart reader at about 4x [E, other areas]. Preparation with SVG includes the measured number floor.
- C4 (Pele 73.37, target 7.34): read 15.5 to 2.5-3.5 [E]; text 15.7 to 3.8 [M], then about 1.5 [E]; other layout about 17 to 3-5 [E]. Read+layout 8-11 µs: 6.5-9x Pele, so 10x is likely just missed unless grid and routing go below 3 µs. Prepared with SVG about 15-18 µs (4.3 µs of numbers [M]): 4-5x. Narrow about 25-35 µs (now 123-130).
- Agent flow (Pele 45.72, target 4.57): read 17 to 0.8-1.2 [E]; layered 16 to about 3-4 [E, shared]; measurement and cluster graph 6 to about 0.8 [E]. Read+layout 4.6-6: 7.5-10x. Prepared with SVG about 6.5-7.5: 6-7x.
- Swimlane (Pele 35.45, target 3.55): read 11 to about 0.7 [E, shared reader]; lane layout 17 to 3-4 [E]; the rest 5 to about 1 [E]. Read+layout 4.5-5.7: 6-8x, so 10x is not reached unless the lane passes are cut algorithmically. Narrow 150 to about 20 [E].
- Use case (Pele 49.54, target 4.95): read 8 to about 0.5 [E]; layered 12.7 to about 3 [E, shared]; pass, measurement and assembly 12 to about 1.5 [E]. About 5 µs: about 10x, borderline.
- Block (Pele 5.85, target 0.585): read 3.2 to about 0.15 [E]; layout 5.2 to about 0.4-0.6 [E]. 0.55-0.8 µs: 7-10x; fixed per-diagram costs decide. Prepared with SVG about 1.3-1.6 (0.49 µs of numbers [M]): about 4x.
- Quadrant (Pele 13.01, target 1.30): read 7 to about 0.6 [E]; layout 4 to about 0.7 [E]. About 1.3: about 10x. Prepared with SVG about 3 (1.31 µs of numbers [M]): about 4.5x.
- XY chart (Pele 12.30, target 1.23): read 7.2 to about 0.45 [E], with the palette lazy; layout 6 to about 0.8 [E]. 1.25-1.5: 8-10x. Prepared with SVG about 4 (671 numbers): about 3x.
- Journey (Pele 9.54, target 0.95): read 3.15 to 0.25 [M]; layout 4.3 to about 0.6 [E]. About 0.85: about 11x. Prepared with SVG 5 or more (3.86 µs of numbers [M]): about 2x; 10x is impossible by arithmetic.
- Gantt (Pele 23.28, target 2.33): read 4 to about 0.4 [E]; schedule 5.7 to about 0.8 [E]; axis format 2.8 to about 0.4 [E]; the rest 4 to about 0.6 [E]. About 2.2: about 10x. Prepared with SVG about 4: about 6x.
- Requirement (Pele 27.71, target 2.77): read 5.7 to about 0.4 [E]; measurement 7 to about 0.6 [E]; layered 4.4 to about 1 [E, shared]; assembly to about 0.4 [E]. About 2.4: about 11x. Prepared with SVG about 4: about 7x.
- Kanban (Pele 16.79, target 1.68): read 4 to about 0.25 [E]; layout 4.5 to about 0.6 [E]. About 0.9: about 18x. Prepared with SVG about 2.6: about 6.5x.
- Summary: the 30 µs ceiling is met by every type [E]. Reading and layout at 10x Pele is reachable or borderline for journey, kanban, requirement, Gantt, quadrant, use case, XY and block [E], and likely missed by 10-35% for C4, swimlane and agent flow [E]. The 50x stretch is not reachable for any of these types. Preparation with SVG at 10x is out of reach for every type here: the SVG's own number count, fixed by byte-identical output, costs 0.5-4.3 µs at the measured 2.7-3.7 ns a number. 3-7x is the reachable range.

## Packages

### slow-types-0-split-shared-preparation

Depends on: nothing

Owns: Sources/MermaidDiagrams/Preparation/MermaidDiagramChartPreparation.swift, Sources/MermaidDiagrams/Preparation/MermaidDiagramGridPreparation.swift, Sources/MermaidDiagrams/Preparation/MermaidDiagramLayeredPreparation.swift, Sources/MermaidDiagrams/Preparation/MermaidDiagramOutlinePreparation.swift, Sources/MermaidDiagrams/Preparation/MermaidDiagramChartAccessibility.swift, Sources/MermaidDiagrams/Preparation/MermaidDiagramGraphAccessibility.swift, new Sources/MermaidDiagrams/Preparation/MermaidDiagram{Quadrant,XYChart,UserJourney,Gantt,Block,Requirement,Kanban}Preparation.swift

Mechanical only, no behaviour change. Moves each slow type's prepared(_:) overload and its MermaidDiagramAccessibility initializer out of the shared Chart, Grid, Layered and Outline files into one file per type, so the later type packages never edit the same file. Pie, Sankey, timeline, architecture, mindmap, tree view and Ishikawa keep theirs where they are. Checked by identical --output-digest and the whole suite.

Expected gain: None. It lets packages 2 to 13 run in parallel.

### slow-types-1-flat-text-measuring

Depends on: nothing

Owns: new Sources/MermaidDiagrams/Text/DiagramMeasuredText.swift, new Sources/MermaidDiagrams/Text/DiagramFlatTextMeasuring.swift, new Sources/MermaidDiagrams/Text/DiagramFlatTextWrapping.swift, new Sources/MermaidDiagrams/Text/DiagramConstantTextWidths.swift, new Tests/MermaidDiagramsTests/DiagramFlatTextMeasuringTests.swift

Adds the prototype's measuring (slow-types/src/Sources/MermaidDiagrams/Prototype/DiagramFlatTextMeasuring.swift) as product code:
- the ASCII fast path with breaks, isUnmarked only when a markup byte is present, and the old addition order;
- a single-pass wrap running two independent addition chains;
- character breaking for kanban;
- emphasis runs kept only when present;
- a fallback that runs DiagramLabelDecoder and DiagramTextBlock and copies their lines into the arena;
- per-face constant widths for closed sets of names.
It edits no existing file. If the text area does not want CoreTextFontFaces.swift touched, DiagramFlatMeasurer reads printableASCIIAdvances through the existing accessor.
Tests compare it bitwise with DiagramTextBlock on every label of every corpus at three widths, plus ASCII fuzz, with the fast path forced on and off.

Expected gain: Measured: C4 texts 15.7 to 3.8-4.2 µs a diagram (330-343 to 70-91 ns a text). Estimated: about 30 ns a text with the single-pass wrap. Similar per-text savings for kanban (about 2 µs of text now), requirement (about 5), journey, XY, quadrant (about 1 each) and use case (about 3.5).

### slow-types-2-c4-flat-reader

Depends on: shared: source bytes in the model (TextRange, InternedNames)

Owns: Sources/MermaidDiagrams/C4/Reading/*, Sources/MermaidDiagrams/C4/C4Diagram.swift, Tests/MermaidDiagramsTests/C4ParserTests.swift, new Tests/MermaidDiagramsTests/C4FlatReaderEquivalenceTests.swift

Replaces C4Lexer, C4Parser and C4DiagramBuilder with one byte pass into the flat C4Diagram of the design: macro dispatch on the name's bytes, arguments as ranges, escapes and generated text in derived bytes, interned aliases, style updates as index lists. Public read views of the old shape are made on access. C4Diagram.init(converting:) is kept for the layout package's development. The equivalence tests compare the flat model, converted, with the old reader's model on c4-docs, Pele's C4 compat inputs, C4CorpusTests' generated diagrams, and cut and mutated texts, errors included.

Expected gain: C4 parse 15.5 µs to 2.5-3.5 µs (estimate from the journey prototype's 1.2-1.3 ns a byte).

### slow-types-3-c4-flat-layout

Depends on: slow-types-1-flat-text-measuring, slow-types-2-c4-flat-reader (model interface only), shared: flat scene paths and text-by-range scene builder, shared: DiagramWorkspace

Owns: Sources/MermaidDiagrams/C4/Layout/*, Sources/MermaidDiagrams/C4/Drawing/*, Sources/MermaidDiagrams/Preparation/MermaidDiagramC4Preparation.swift, Tests/MermaidDiagramsTests/C4LayoutEngineTests.swift, Tests/MermaidDiagramsTests/C4StyleAndPlacementTests.swift, Tests/MermaidDiagramsTests/C4RoutingNumbersTests.swift, Tests/MermaidDiagramsTests/C4ScenePaintingTests.swift, Tests/MermaidDiagramsTests/C4CorpusTests.swift

The C4 layout on the flat model and flat measuring:
- shape kind names from the constant widths;
- C4ElementLook only when a color is written;
- grid boxes, routes, detours and lanes as flat lists with points in one list and no CGPath;
- labels as DiagramMeasuredText;
- the tight layout's up to four gap retries reuse one measurement of the texts, whose room is constant.
C4Scene writes through the shared scene builder. It can start from C4Diagram(converting:) before package 2 lands.

Expected gain: Read+layout 48-53 µs to 8-11 µs, combined with package 2 (estimate; about 6.5-9x Pele). Prepared with SVG 81.6 to about 15-18 µs (estimate). Narrow 123-130 to about 25-35 µs (estimate).

### slow-types-4-agentflow-flat-reader

Depends on: shared: source bytes in the model

Owns: Sources/MermaidDiagrams/AgentFlow/Reading/*, Sources/MermaidDiagrams/AgentFlow/AgentFlowDiagram.swift, Sources/MermaidDiagrams/AgentFlow/AgentFlowGraph.swift, Tests/MermaidDiagramsTests/AgentFlowParserTests.swift, Tests/MermaidDiagramsTests/AgentFlowDiagnosticsTests.swift, Tests/MermaidDiagramsTests/AgentFlowReferenceTests.swift

A UTF-8 byte lexer and parser in place of the UTF-16 one.
- Statement places are stored as byte offsets. The UTF-16 columns that Jison, and so Pele, report are computed when read: the byte column on an ASCII line, otherwise counted on demand, a 4-byte sequence counting 2. The values stay the same, so AgentFlowReferenceTests' 239 inputs and the diagnostics keep their positions.
- `@{ … }` metadata uses a one-line flow-map reader on bytes, with MermaidYAMLDocument for multi-line YAML.
- Builder maps use interned ids.
- The unspecialized generic behind _swift_getGenericMetadata (3.6% of samples) is made concrete.

Expected gain: Agent flow parse 16.7-17.5 µs to 0.8-1.2 µs (estimate).

### slow-types-5-agentflow-flat-layout

Depends on: slow-types-1-flat-text-measuring, slow-types-4-agentflow-flat-reader (model interface), shared: flat layered layout, shared: flat scene paths

Owns: Sources/MermaidDiagrams/AgentFlow/Layout/*, Sources/MermaidDiagrams/AgentFlow/Drawing/*, Sources/MermaidDiagrams/Preparation/MermaidDiagramAgentFlowPreparation.swift, Tests/MermaidDiagramsTests/AgentFlowLayoutEngineTests.swift, Tests/MermaidDiagramsTests/AgentFlowCorpusTests.swift

AgentFlowMeasurement uses flat measuring. AgentFlowClusterGraph becomes flat parent and child lists feeding the shared flat layered layout. The assembly writes route points to one list. The scene goes through the shared builder.

Expected gain: Agent flow layout about 25 µs to about 4 µs (estimate, half of it the shared layered layout). Read+layout 4.6-6 µs (7.5-10x Pele).

### slow-types-6-swimlane-lane-layout

Depends on: shared: flat flowchart reader and model, slow-types-1-flat-text-measuring, shared: DiagramWorkspace, shared: flat scene paths

Owns: Sources/MermaidDiagrams/Layout/LaneBands.swift, Sources/MermaidDiagrams/Layout/LaneHandoffAttempt.swift, Sources/MermaidDiagrams/Layout/LaneHandoffRouting.swift, Sources/MermaidDiagrams/Layout/LaneLayout.swift, Sources/MermaidDiagrams/Layout/LaneLayoutGraph.swift, Sources/MermaidDiagrams/Layout/LaneLayoutItems.swift, Sources/MermaidDiagrams/Layout/LanePass.swift, Sources/MermaidDiagrams/Layout/LanePlacedPass.swift, Sources/MermaidDiagrams/Swimlane/*, Tests/MermaidDiagramsTests/LaneLayoutTests.swift, Tests/MermaidDiagramsTests/LaneLayoutRandomTests.swift, Tests/MermaidDiagramsTests/SwimlaneLayoutEngineTests.swift, Tests/MermaidDiagramsTests/SwimlaneCorpusTests.swift

LaneLayout.place's passes become flat. First measure how many passes each corpus input runs and which LanePass steps depend on isPlain and keepsMargin. The invariant steps (LaneLayoutItems, ordering, setup) are computed once instead of per pass; bands and routes go into reused workspace lists; routes become slices of one point list in place of [[LanePoint]] per edge. SwimlaneGraph reads the shared flat flowchart model. The narrow re-layout reuses measured texts.

Expected gain: Lane layout about 17 µs to 3-4 µs (estimate). Swimlane read+layout 34-39 µs to 4.5-5.7 µs (estimate, 6-8x Pele). Narrow 150-165 µs to about 20 µs (estimate).

### slow-types-7-usecase-flat

Depends on: slow-types-1-flat-text-measuring, shared: source bytes in the model, shared: flat layered layout, shared: flat scene paths

Owns: Sources/MermaidDiagrams/UseCase/**, Sources/MermaidDiagrams/Preparation/MermaidDiagramUseCasePreparation.swift, Tests/MermaidDiagramsTests/UseCase*Tests.swift

Byte lexer, grammar and builder with interned names, and a JSON reader on bytes with the depth bound kept. mermaidCodesRead becomes a byte scan instead of Foundation contains/range. UseCaseLook is built only when styled. Node measurement uses flat measuring, with constant widths for «include» and «extend». The graph is fed to the shared flat layered layout. If the layered package lands later, the reader half can merge first, with an adapter to the old model.

Expected gain: Use case read+layout 31.9-38.9 µs to about 5 µs (estimate, about 10x Pele). The reader alone goes from 8 to about 0.5 µs.

### slow-types-8-block-flat

Depends on: slow-types-1-flat-text-measuring, shared: source bytes in the model, shared: DiagramWorkspace

Owns: Sources/MermaidDiagrams/Block/*, Sources/MermaidDiagrams/Preparation/MermaidDiagramBlockPreparation.swift (made by package 0), Tests/MermaidDiagramsTests/Block*Tests.swift

Byte tokens as ranges. BlockHierarchy becomes Int32 parent and child lists. BlockAppearance and applyDeclaration run only for blocks with classes or styles, where today they run for every block. The measurer cache gets interned keys. Measuring is flat. The per-diagram fixed cost is made small: measurers taken from the workspace, no per-diagram dictionaries.

Expected gain: Block read+layout 7.4-8.5 µs to 0.55-0.8 µs (estimate, 7-10x Pele). Prepared with SVG about 1.3-1.6 µs (estimate, about 4x).

### slow-types-9-quadrant-flat

Depends on: slow-types-1-flat-text-measuring, shared: source bytes in the model, shared: flat scene paths

Owns: Sources/MermaidDiagrams/Quadrant/*, Sources/MermaidDiagrams/Preparation/MermaidDiagramQuadrantPreparation.swift (made by package 0), Tests/MermaidDiagramsTests/QuadrantChart*Tests.swift

A byte lexer in place of the Jison-like token Strings (readKeywordWithSpaces, readRunOrCharacter), with point and style syntax on bytes. The flat model keeps points as numbers and ranges. Point label placement works over flat candidate rectangles. Texts are measured flat.

Expected gain: Quadrant read+layout 10.2-11.9 µs to about 1.3 µs (estimate, about 10x Pele). Prepared with SVG about 3 µs (estimate).

### slow-types-10-xychart-flat

Depends on: slow-types-1-flat-text-measuring, shared: source bytes in the model, shared: flat scene paths

Owns: Sources/MermaidDiagrams/XYChart/*, Sources/MermaidDiagrams/Preparation/MermaidDiagramXYChartPreparation.swift (made by package 0), Tests/MermaidDiagramsTests/XYChart*Tests.swift

Byte lexer and parser. Values go through a byte JavaScript Number reader whose fallback is the existing one. The theme series palette is resolved only when xyChart.plotColorPalette is written: today MermaidThemeSeriesPalette.seriesColors runs on every read (6.4%). XYChartFrame measures each label once. Tick and value labels go into derived bytes. The series are flat.

Expected gain: XY read+layout 11.4-14.8 µs to 1.25-1.5 µs (estimate, 8-10x Pele). Prepared with SVG about 4 µs (estimate).

### slow-types-11-journey-flat

Depends on: slow-types-1-flat-text-measuring, shared: source bytes in the model, shared: flat scene paths, shared: lazy accessibility

Owns: Sources/MermaidDiagrams/UserJourney/*, Sources/MermaidDiagrams/Preparation/MermaidDiagramUserJourneyPreparation.swift (made by package 0), Tests/MermaidDiagramsTests/UserJourney*Tests.swift

The prototype reader (slow-types/src/Sources/MermaidDiagrams/Prototype/UserJourneyFlatReader.swift), completed: accessibility statements, JavaScript Number scores on bytes, and Unicode white-space trimming on bytes as JavaScriptWhitespace does. Actors are interned, so actorNames costs nothing. Placement, legend and column layout use flat lists and flat measuring. Faces and stems are written as path templates through the shared builder; today they are CGPath circles.

Expected gain: Measured: reader 3.15 to 0.25 µs (12.4x). Estimated: read+layout 6.8-9.8 to about 0.85 µs (about 11x Pele); prepared with SVG 25-42 to 5 µs or more (about 2x; floor 3.86 µs of numbers, measured).

### slow-types-12-gantt-flat

Depends on: slow-types-1-flat-text-measuring, shared: source bytes in the model, shared: flat scene paths

Owns: Sources/MermaidDiagrams/Gantt/*, Sources/MermaidDiagrams/Preparation/MermaidDiagramGanttPreparation.swift (made by package 0), Tests/MermaidDiagramsTests/Gantt*Tests.swift, Tests/MermaidDiagramsTests/JavaScriptDateDifferentialTests.swift (read only)

Task fields split on bytes. dateFormat and axisFormat are compiled once per chart into token lists: GanttDateFormat.init is about 4% and runs repeatedly. GanttDuration and the date readers work on byte ranges, with V8's legacy date fallback kept. Excluded days are computed once. Axis texts are formatted into derived bytes. Rows and bars become flat.

Expected gain: Gantt read+layout 16.2-21.0 µs to about 2.2 µs (estimate, about 10x Pele). Prepared with SVG about 4 µs (estimate).

### slow-types-13-requirement-flat

Depends on: slow-types-1-flat-text-measuring, shared: source bytes in the model, shared: flat layered layout, shared: flat scene paths

Owns: Sources/MermaidDiagrams/Requirement/*, Sources/MermaidDiagrams/Preparation/MermaidDiagramRequirementPreparation.swift (made by package 0), Tests/MermaidDiagramsTests/Requirement*Tests.swift

Byte lexer; the parser keeps the quirks of Pele's port and Mermaid's database. The flat model uses interned names and style copies as index lists, with the million cap kept. RequirementMeasurement.box measures stereotype, name and field rows flat, with constant stereotype widths. Relations feed the shared flat layered layout. Assembly writes points to one list.

Expected gain: Requirement read+layout 21.2-25.9 µs to about 2.4 µs (estimate, about 11x Pele). Prepared with SVG about 4 µs (estimate).

### slow-types-14-kanban-flat

Depends on: slow-types-1-flat-text-measuring, shared: source bytes in the model, shared: flat scene paths

Owns: Sources/MermaidDiagrams/Kanban/*, new Sources/MermaidDiagrams/Reading/MermaidFlatOutlineReader.swift, Sources/MermaidDiagrams/Preparation/MermaidDiagramKanbanPreparation.swift (made by package 0), Tests/MermaidDiagramsTests/Kanban*Tests.swift

A flat outline reader in a new file. MermaidOutlineReader stays, because mindmap shares it and can adopt the new reader in its own area. Card metadata and its YAML flow collections are read on bytes, with the JavaScript String form of values kept. Columns and cards become flat. Cards use character-breaking flat measuring.

Expected gain: Kanban read+layout 8.5-9.9 µs to about 0.9 µs (estimate, about 18x Pele). Prepared with SVG about 2.6 µs (estimate).

## Public API changes

- Through the prepare path, nothing changes for Graphite. MermaidDiagramPreparation.prepare(source:typography:limits:narrowestColumnWidth:now:timeZone:), prepare(_ diagram: MermaidDiagram, …), PreparedMermaidDiagram.scene/narrowScene/accessibility/svgDocument, DiagramSceneRenderer, DiagramSVGWriter and DiagramScene.seriesColors keep their signatures and output. MermaidDiagram keeps its cases, so prepare(_ diagram:) lays out again without reading: the flat model holds the source bytes.
- 0.8.0 changes the payload models of MermaidDiagram's cases: C4Diagram, AgentFlowDiagram, UseCaseDiagram, BlockDiagram, QuadrantChart, XYChart, UserJourneyDiagram, GanttChart, RequirementDiagram, KanbanBoard, and swimlane's FlowchartDiagram (from the flowchart area). They become flat structs of byte ranges into the retained source. Their public stored properties become read-only computed views that make the old value types on access (for example UserJourneyDiagram.tasks returns [UserJourneyTask] built when read). `public internal(set)` setters disappear and Equatable compares decoded content.
- The per-type layout structs C4Layout, AgentFlowLayout, UseCaseLayout, BlockLayout, QuadrantChartLayout, XYChartLayout, UserJourneyLayout, UserJourneyColumnLayout, GanttLayout, RequirementLayout, KanbanLayout and SwimlaneLayout hold DiagramMeasuredText (ranges into the layout's own DiagramMeasuredLines) and point lists instead of DiagramTextBlock with [String] lines and CGPath. Their *DrawingParts and *Renderer initializers take the new layouts.

Graphite impact: Graphite's current main (747b79ef) draws journey, quadrant, XY and Gantt through Packages/MermaidDiagrams with UserJourneyLayoutEngine, QuadrantChartLayoutEngine, XYChartLayoutEngine, GanttLayoutEngine and their DrawingParts (GraphiteUI/ReadingDiagram.swift, ReadingUserJourney.swift, ReadingQuadrantChart.swift, ReadingXYChart.swift and the Gantt reading files). If that path is still live when Graphite moves to 0.8.0, those files must switch to PreparedMermaidDiagram.scene, or 0.8.0 keeps a deprecated `legacyTextBlocks` shim on those four layouts.
- New types, internal unless a host needs them: DiagramMeasuredText, DiagramMeasuredLines, TextRange, InternedNames, DiagramConstantTextWidths. The shared area may add an optional `workspace: DiagramWorkspace? = nil` parameter to prepare; the default keeps calls source-compatible.
- Agent flow element positions and diagnostics keep their UTF-16 column values, now computed on read; the type of the position API stays.

## Risks

- Bit identity of text widths. Pele's left-to-right sums must be kept exactly. Any SIMD or reassociated summation, FMA contraction or a different trimming order changes widths in the last bit, and with them the SVG digits. The prototype agrees bitwise on 272 of 272 fast-path C4 texts. Keep an exhaustive comparison test with DiagramTextBlock running.
- Fast-path coverage and its fallback. Correctness depends on isUnmarked being the exact markup test and on the fallback being today's code. Test with the fast path forced off and on, with fuzz, and with texts near width limits. Soft hyphens, tabs, non-ASCII spaces and CJK all go through the fallback.
- The layout estimates are not prototyped. They rest on 45-55% of self time being reference counting, malloc and array growth, which removal alone halves, plus hoisting repeated passes. The C4 grid and routing and the lane layout's passes are the largest unknowns; 10x for C4, swimlane and agent flow read+layout may be missed by 10-35%.
- Dependence on the shared areas. Agent flow, use case and requirement get half their gain from the shared flat layered layout; swimlane depends on the flat flowchart reader; every type's preparation depends on flat scene paths. If those slip, the per-type gains in reading and text still land, but the totals above do not.
- Preparation with SVG at 10x is arithmetically out of reach for these types, as long as the output is byte-identical. The SVG's own numbers cost 0.5-4.3 µs at 2.7-3.7 ns each (measured with the package's writer), and journey's are 4x its whole 0.95 µs budget. A faster number writer (two-digit tables) might reach about 1.5-2 ns a number, but no more than that.
- Lifetime and threads. Ranges point into the model's source array, and that array must outlive every layout and scene made from it. The scene must not keep references into workspace lists after prepare returns. PreparedMermaidDiagram.narrowScene is laid out lazily from any thread, so it must use the calling thread's workspace and never the preparing thread's. Workspaces must release capacity after a hostile 50 KB diagram.
- Hostile input. Every flat list's growth must be checked against MermaidDiagramLimits before appending, including interned names, derived bytes, actor mentions and style copies. Fast paths must consume at least one byte per step. The JSON, YAML and outline readers keep their depth bounds.
- File conflicts. MermaidDiagramReader.swift's dispatch is left untouched because readers keep the MermaidTextCursor signature. The shared Chart, Grid, Layered and Outline preparation and accessibility files are split first (package 0). Kanban must not edit MermaidOutlineReader, which mindmap shares.
- Digest baseline. The baseline binary prints 'every input (825): 5f44234b8fa913bf' here, where the brief quotes ff8a133226b37b4b. Compare builds by diffing the 826 lines produced the same way and in the same time zone (Gantt's dates depend on it), not by a quoted constant.
- Measurement noise. The baselines were taken at load average 5 to 24; the prototypes alternate old and new paths in one binary, in 9 pairs with medians. Repeat the final numbers quiet (load under 4) before claiming them.

Prototype: branch `redesign-prototype-slow-types` (the copy of main the design measured, with its prototype code and benchmark modes).
