# Redesign: text-and-labels

Written 2026-11-24 by the design phase of the 0.8.0 redesign (Graphite issue #223), measured on main de81532 (0.7.0), Apple M5 Max, Release, under load from other work. [M] or MEASURED marks measured numbers; everything else is an estimate.

Area: Text across all types: label decoding (DiagramLabelDecoder, entities, icons, inline markup, line breaks), measuring (CoreTextDiagramTextMeasurer, CoreTextFontFaces, DiagramPrintableASCIIAdvances, DiagramTextMeasurerSet, styled measuring), wrapping and fitting (DiagramTextWrapping, DiagramTextPieces, DiagramTextBreaking, DiagramTextFitting), DiagramTextBlock and its lines, and the accessibility (spoken) text built during preparation.

## Where the time goes now

MEASURED on main de81532, Release, Apple M5 Max. Load average was 5 to 15. The profile loops ran 1 s per stage, and I took sample(1) for 4 s of each loop. Samples were attributed to the outermost text frame by /private/tmp/claude-501/-Users-baheyshalash-Desktop-Graphite/6d72f356-244e-47a1-86bb-e652bab855d4/scratchpad/redesign/text-and-labels/tools/attribute.py; the raw samples are in .../text-and-labels/samples.

Stage times in µs per input (parse / read+layout / prepare with SVG): flowchart examples ('docs: all examples', 114 inputs) 3.55 / 11.44 / 18.23; sequence 3.91 / 9.83 / 22.53; c4 15.74 / 54.59 / 95.36; class 2.65 / 14.07 / 25.77; mindmap 1.65 / 3.81 / 9.86; timeline 4.80 / 9.51 / 31.91; kanban 4.46 / 9.92 / 20.11; journey 3.57 / 8.36 / 31.50; block 3.45 / 9.18 / 15.51.

Share of read+layout samples that is text (decode / measure+wrap / copies of measurer- and text-holding structs):
- flowchart examples 5.7% (2.8 / 1.9 / 0.6), about 0.65 µs
- block 10.6% (3.7 / 3.6 / 3.2)
- class 9.6% (1.6 / 5.2 / 2.9)
- journey 19.5% (2.3 / 14.6 / 2.2)
- mindmap 27.1% (11.4 / 13.5 / 1.9)
- kanban 31.4% (1.6 / 22.8 / 7.0)
- c4 32.0% (decode is inlined; measure+wrap 28.1 / 3.9), about 17.5 µs
- sequence 32.9% (8.5 / 8.1 / 16.3; the copies are SequenceRows and SequenceTextMeasurers, partly measurers)
- timeline 37.6% (14.8 / 16.7 / 5.8)

Share of preparation with SVG that is text, with accessibility / SVG label escaping / SVG text elements:
- flowchart 8.1% (1.5 / 1.3 / 1.1)
- block 11.1% (3.1 / 1.0 / 1.7)
- class 9.0%
- journey 17.1% (6.1 / 0.7 / 4.5)
- mindmap 17.2%
- timeline 22.1% (3.0 / 0.8 / 4.1)
- sequence 24.3% (2.7 / 1.5 / 3.1)
- kanban 27.1% (2.7 / 0.8 / 8.4)
- c4 30.1% (4.1 / 0.4 / 6.6)

The SVG text-element share is mostly number writing, memmove and String bridging, which belongs to the SVG area. Upper bound of the gain from text alone (1/(1-share) on read+layout): flowchart 1.06x, c4 1.47x, timeline 1.6x. Text is not why flowcharts miss 10x. It is a necessary part for the text-heavy types (C4, timeline, kanban, mindmap, journey, sequence).

Self time inside DiagramTextBlock.init (kanban; c4 is similar):
- the measuring arithmetic itself (CoreTextDiagramTextMeasurer.width) is only 11% (c4 9.6%)
- swift_release/retain 13% (c4 11%)
- malloc/free/malloc_size 12% (c4 13%)
- bridgeObject retain/release 9%
- wrapping logic (wrap, append, commit, endTrimmed, endOfASCIIPiece) about 20%
- generic metadata lookup 1.8%

Inside decoding (timeline, mindmap, sequence): DiagramLabelLineBreaks.isUnmarked takes 4 to 17% of decode self time. The rest is Array<Unicode.Scalar> building, String.UnicodeScalarView.distance, UnicodeScalarText.string, malloc/free and swift_release.

Replaying each corpus's recorded text calls on their own (prototype benchmark, 'present' column) agrees with the in-pipeline samples. Measure+wrap / decode per input: flowchart 0.27 / 0.24 µs, c4 11.1 / 4.5, kanban 2.5 / 0.41, timeline 1.97 / 1.30, mindmap 0.60 / 0.52, journey 1.54 / 0.37, block 0.35 / 0.50, sequence 0.74 / 0.41, class 0.75 / 0.09.

Per-label facts:
- flowchart examples have 2.4 text blocks a diagram, 6.6 bytes a block; 374 of their 389 labels have no markup
- c4 has 46 blocks a diagram at 24.4 bytes each, 64 of them wrapped, 50 beyond ASCII (guillemets)
- one label with markup costs 0.5 to 2 µs in today's decoder (flowchart 0.92, block 2.05)
- a measurer copy retains its CoreTextFontFace; DiagramTextBlock holds 2 or 3 arrays plus Strings; DiagramLabel holds an array of Strings and optional spans
- accessibility is built eagerly in every preparation (journey 1.9 µs, c4 3.9 µs, flowchart 0.27 µs)

## Design

GOAL: no String, no per-block or per-label heap list, and no reference-counted measurer on the common path. Every width must be identical to the bit.

1. FONT FACES AS INDICES (package P1).
- CoreTextDiagramTextMeasurer becomes trivially copyable: fontSize, lineHeight, a DiagramFontFaceIndex (Int32) and flags. Copying it retains nothing.
- Faces live in an append-only, never-freed DiagramFontFaceRegistry. Each entry holds the CTFont, the key, and an immortal 256-entry advance table indexed by byte (zero outside 32...126).
- A per-thread overflow table holds faces past the registry's cap (4,096) and is emptied when a preparation starts. Measurers never outlive a preparation, because scenes keep only size and flags.
- Signatures:
  `struct DiagramFontFaceIndex: Hashable { let rawValue: Int32 }`
  `final class DiagramFontFaceRegistry: @unchecked Sendable { static let shared: DiagramFontFaceRegistry; func face(_ key: CoreTextFontFaceKey) -> DiagramFontFaceIndex; func advances(_ face: DiagramFontFaceIndex) -> DiagramFontAdvances; func coreTextFont(_ face: DiagramFontFaceIndex) -> CTFont }`
  `struct DiagramFontAdvances { let byByte: UnsafePointer<CGFloat>; let isExactlySummable: Bool }`
  `struct DiagramFontStyles { let faces: (DiagramFontFaceIndex × 8); func advances(_ style: DiagramTextStyle) -> DiagramFontAdvances }` resolves the eight emphases once. It replaces DiagramStyledMeasuring's dictionary.
  `protocol DiagramByteTextMeasuring: DiagramTextMeasuring { var fontStyles: DiagramFontStyles? { get }; func width(ofUTF8 bytes: UnsafeBufferPointer<UInt8>, style: DiagramTextStyle) -> CGFloat }`. A default implementation makes a String, so the fixed-width test measurers keep working.
- Text beyond printable ASCII goes through `final class DiagramLineWidthCache { static let shared; func width(of bytes: UnsafeBufferPointer<UInt8>, face: DiagramFontFaceIndex) -> CGFloat }`. It is keyed by face and UTF-8 bytes (FNV-1a, open addressing, os_unfair_lock, keys of at most 256 bytes, 8,192 slots, cleared at 70% full). Only a miss makes a String and lays out a CTLine, through the same NSAttributedString path as today.

2. LABELS AS BYTE RANGES (package P2).
- One `final class DiagramLabelStore: @unchecked Sendable` per read. Its bytes start with a copy of the source's UTF-8, and decoded text is appended after it. It holds `ContiguousArray<DiagramLabelLineRecord>`, where `struct DiagramLabelLineRecord { var start, end, firstSpan, spanCount: Int32 }`, and `ContiguousArray<DiagramLabelSpanRecord>`, where `struct DiagramLabelSpanRecord { var start, end: Int32; var style: DiagramTextStyle }`.
- `public struct DiagramLabel: Equatable, Sendable { let store: DiagramLabelStore; let firstLine: Int32; let lineCount: Int32; let flags: DiagramLabelFlags /* hasSpans, isReadWithoutMarkup, isPrintableASCII */; public var lines: [String] { get } /* computed */; public var spokenText: String { get }; public var isEmpty: Bool; func withUTF8<R>(ofLine: Int, _ body: (UnsafeBufferPointer<UInt8>) -> R) -> R }`. Equality is by content, as today.
- Decoding: `func label(sourceRange: Range<Int32>, form: DiagramLabelDecoder.Form, isUnmarked: Bool? = nil) -> DiagramLabel` and `func label(_ written: String) -> DiagramLabel` for synthetic text. Text without markup becomes a trimmed range of the source, with no copy. Text with markup is decoded on bytes into the store: line breaks, Markdown carriage returns and dedent, tags (emphasis and HTML names looked up as packed UInt64), Markdown markers, icon names, and Mermaid and HTML codes in two byte passes. A String is made only for an entity name or a tag name longer than 8 bytes.
- `DiagramLabelDecoder.label(from: String, form:)` keeps its signature as a bridge for readers that have not moved. It appends to `DiagramLabelStore.current` (pthread TLS, set by MermaidDiagramReader.read), or to a private store.
- Readers that move (reading agents) pass source ranges. They also pass isUnmarked, worked out in the scan they already make with a 256-entry byte class table, so decoding text without markup costs about nothing.

3. MEASURING AND WRAPPING INTO ONE STORAGE PER LAYOUT (package P3).
- `final class DiagramTextStorage: @unchecked Sendable` is one growable allocation holding bytes, `DiagramTextLineRecord { firstRun, runCount: Int32; width: CGFloat }` and `DiagramTextRunRecord { start, end: Int32; width: CGFloat; style: DiagramTextStyle }`. It is appended to only on its layout's thread and becomes the scene's text.
- A label's line bytes are copied in when measured (memcpy of tens of bytes), so the scene does not depend on the label store. Synthetic text (a shown soft hyphen as '-', ellipses, numbers) is appended there too.
- `struct DiagramTextRecord { var firstLine, lineCount: Int32; var widestLineWidth, fontSize, lineHeight: CGFloat; var hasEmphasis: Bool }` is POD, for redesigned layouts.
- `extension DiagramTextStorage { func measure<M: DiagramTextMeasuring>(_ label: DiagramLabel, measurer: M, maximumWidth: CGFloat, scratch: inout DiagramTextMeasuringScratch) -> DiagramTextRecord }`, plus the breaking, literal and fitting variants. `DiagramTextMeasuringScratch` holds the line's spans and the line being filled, kept per thread.
- `public struct DiagramTextBlock { let storage: DiagramTextStorage; let record: DiagramTextRecord; public let fontSize, lineHeight; public internal(set) var center; public var size; public var lineCount: Int; public func lineWidth(at: Int) -> CGFloat; public func withUTF8<R>(ofLine: Int, _: (UnsafeBufferPointer<UInt8>) -> R) -> R; public var lines: [String] /* computed */; public var lineWidths: [CGFloat] /* computed */; public var lineRuns: [[DiagramTextRun]]? /* computed */ }`. A copy retains one object, against 2 or 3 arrays plus Strings today.
- The existing initializers (`init(label:measurer:maximumWidth:)`, `fittingWidth:`, `wrappingWidth:breakingWidth:`, `literal:room:`, `lines:lineWidths:`) keep their signatures. They append to `DiagramTextStorage.current` (TLS scope opened by MermaidDiagramPreparation around each layout, the narrow scene included), or to a private storage outside a scope. So all 175 files that use DiagramTextBlock gain without being edited, and redesigned layouts pass the storage and scratch explicitly.

BIT-IDENTICAL WIDTHS.
- (a) Every face's table is checked when it is built: every advance must be a binary fraction of at most 20 bits and below 1,024 pt. The fonts measured here have at most 12 bits: 16 pt 8 bits, 14 pt 11, 13 pt 12. Then any sum of fewer than 2^22 advances is exact in Double (32 + 20 < 53 bits), so every width, continued width, difference and comparison is the exact sum whatever the order.
- For such faces, wrapping reads each byte once: a piece's width comes from its leading, word and trailing parts; a trimmed span's width comes from taking the trailing spaces' advances off; sums use four accumulators.
- (b) Other faces (12.8 pt, 17.3 pt, 9.1 pt are not exact) take a faithful sequential port of DiagramTextWrapping on bytes. It makes the same additions in the same order: from 0, continuing over pieces, `width += last.width - before`.
- (c) Text beyond printable ASCII takes the CTLine width of the same characters through the byte cache.
- Pieces beyond ASCII (CJK, closing punctuation, zero-width space, soft hyphen) keep today's scalar algorithm. It already works on byte positions; only its String measuring calls are replaced.
- Literal lines and breaking between characters get an ASCII fast path where a byte is a Character, except '\r\n'. Everything else keeps the Character path.

4. SCENE, RENDERER AND SVG FROM BYTES (package P4).
- DiagramSceneText keeps `lines`, `styledRuns` and `block.center`, made from the storage when asked.
- The renderer makes CFStrings from line bytes.
- The SVG writer escapes `block.withUTF8(ofLine:)` directly into its byte buffer. The SVG agent owns that change (spec: `DiagramSVGBuffer.appendEscaped(_ bytes: UnsafeBufferPointer<UInt8>)`, a memchr-style scan for the four escaped bytes, then copying the runs between them).

5. ACCESSIBILITY MADE WHEN ASKED (package P5).
- PreparedMermaidDiagram computes `accessibility` on first access from the diagram it already keeps, caches it under a lock, and joins spoken text on bytes into one String per field.
- The preparation itself no longer builds it.

## Prototype measurements

- Prototype (in the library copy, run with `MermaidDiagramsBenchmark --text-prototype <corpus>`). While each input is prepared once, it records every DiagramLabelDecoder.label call and every DiagramTextBlock(label:measurer:maximumWidth:) call. It then checks the flat path against today's on every one and times both: 7 alternating pairs of 0.15-s rounds, median, per input. MEASURED at load average 4 to 9.
- Correctness, measure and wrap: 0 differences, to the bit, in lines, widths (bitPattern), line heights and runs. That covers every block of all 33 documentation corpora, Pele's 114 flowchart examples, agentflow-reference (239 inputs), bench-generated and random-flat, about 9,900 blocks. Beyond printable ASCII, 0 blocks fell back to the old path except 1 in usecase (a wrap beyond ASCII, which the prototype does not port).
- Correctness, stress: the same labels re-measured at 12.8, 17.3 and 9.1 pt (not exactly summable, so the sequential path) and at 16, 14 and 12 pt (exactly summable, so the single-pass path), all wrapped at min(width, 60). 0 differences with 30 to 183 wrapped blocks per corpus, on flowchart examples, c4, sequence, timeline, kanban, mindmap, usecase, requirement and agentflow-reference.
- Correctness, decode: the byte decoder (all markup paths, no String except entity names and tag names longer than 8 bytes) gave the same lines, spans and isReadWithoutMarkup as DiagramLabelDecoder on all about 9,700 recorded labels of every corpus: 0 differences.
- Measure+wrap, µs per input, present then flat (pooled arena, records, no Strings): flowchart examples 0.27 -> 0.063 (4.3x); sequence 0.74 -> 0.15 (4.8x); c4 11.1 -> 2.26 (4.9x); class 0.75 -> 0.163 (4.6x); mindmap 0.60 -> 0.094 (6.4x); timeline 1.97 -> 0.373 (5.3x); kanban 2.48 -> 0.557 (4.5x); journey 1.54 -> 0.288 (5.4x); block 0.346 -> 0.075 (4.6x); state 0.554 -> 0.114 (4.9x); er 1.45 -> 0.38 (3.8x); xychart 2.48 -> 0.52 (4.8x); gantt 1.56 -> 0.29 (5.3x); bench-generated (4 large graphs) 32.1 -> 5.7 (5.6x); random-flat 2.49 -> 0.46 (5.4x).
- Decode, µs per input, present then byte decoder: flowchart examples 0.24 -> 0.08 (3.0x); a label with markup 0.92 -> 0.28 µs each; sequence 0.41 -> 0.107 (3.8x); c4 4.50 -> 1.61 (2.8x); class 0.090 -> 0.038; mindmap 0.52 -> 0.18 (2.9x); timeline 1.30 -> 0.44 (2.9x); kanban 0.41 -> 0.17; journey 0.37 -> 0.13; block 0.50 -> 0.10 (5.1x); agentflow-reference 0.32 -> 0.086 (3.7x); random-flat 2.36 -> 0.71 (3.3x); requirement 3.05 -> 1.32 (2.3x).
- Key negative result: flat measuring followed by Strings and two lists per block, as today's DiagramTextBlock holds them, gains only 1.0x (flowchart 0.264 -> 0.253, sequence, block, class) to 1.6x (c4). So the per-block String and list allocations are the cost, and an internal rewrite that still produces Strings does not pay.
- Naive storage object per input (7 arrays in a class, found through pthread TLS, label bytes copied in, blocks kept in a list): flowchart 0.29 -> 0.32 (0.9x), block 0.9x, class 1.2x, sequence 1.1x, kanban 1.9x, timeline 1.7x, c4 2.9x. The 7 allocations per input and exclusivity checks on class properties eat the gain on small diagrams, so the storage must be one allocation (estimate: flat + about 60 ns per diagram + about 8 ns per block).
- Advance tables: every table used by the corpora has at most 8 to 12 fraction bits, largest advance 16.26 pt, so the exact-sum path applies to Pele's default typography. Sizes such as 12.8 pt are not exact and take the sequential path.
- Samples of the prototype on c4: flat measuring is about 66% in measure and wrapExactly themselves and about 11% in isUniquelyReferenced and replaceSubrange (Array.removeAll keepingCapacity). Raw pointers with counts would remove that.

## Expected after

- Text time per diagram, today -> after, against the 10x budget (Pele / 10). Prototype numbers are MEASURED; values marked (est.) are ESTIMATES that add reader-fused markup classification, SIMD scanning and one-allocation storage. Accessibility goes to 0 in prepare.
- Flowchart examples: decode+measure 0.51 -> 0.14 µs measured, about 0.09 (est.), plus accessibility 0.27 -> 0 and SVG escaping 0.24 -> about 0.05 (est.). Text is about 4% of the 2.2 µs budget. Text is not the flowchart bottleneck: removing it entirely gains 1.06x on read+layout.
- C4: 15.6 -> 3.9 µs measured, about 2.0 to 2.8 (est.), against a 7.3 µs budget, so text stays 30 to 40% of it. The floor is byte-serial: c4 has about 1,120 label bytes per diagram, and at about 0.5 ns per byte for scan plus advance sum the minimum is about 0.6 µs.
- Timeline: 3.3 -> 0.81 µs measured, about 0.5 (est.), budget 1.38. Kanban: 2.9 -> 0.73 measured, about 0.6 (est.), budget 1.68. Mindmap: 1.12 -> 0.27 measured, about 0.15 (est.), budget 0.64. Journey: 1.9 -> 0.42 measured, about 0.33 (est.), budget 0.95.
- Sequence: 1.15 -> 0.26 µs measured, plus measurer copies that go away once measurers are POD (part of 16% of read+layout, about 1.6 µs, est.), budget 1.03. Class: 0.84 -> 0.20 measured, budget 2.33. Block: 0.85 -> 0.175 measured, about 0.1 (est.), budget 0.585.
- 10x on text alone is reached only by the estimates for text-heavy types. The prototype measures 3 to 6x for text. Text still takes 25 to 45% of the 10x budget for c4, timeline, kanban, mindmap and journey, so those types meet 10x only if reading, layout and SVG fit in the rest. The 50x stretch is out of reach for text there: work per byte, not per call, sets the limit at about 30x for c4 text even with decoding fused into the reader's scan.
- Interim gain before any other package lands (the existing DiagramTextBlock and DiagramLabelDecoder signatures bridged through TLS storages): estimated 2 to 4x on text for every type, with no edits to type files. Fully migrated layouts get the measured 4 to 6x on measuring.

## Packages

### P0 Text contracts (do first, about an hour)

Depends on: nothing

Owns: Sources/MermaidDiagrams/Text/DiagramTextRecords.swift (new), Sources/MermaidDiagrams/Text/DiagramLabelRecords.swift (new)

Declares the POD records and signatures from the design so P1 to P5 can build against them in parallel: DiagramFontFaceIndex, DiagramFontAdvances, DiagramFontStyles, DiagramByteTextMeasuring, DiagramLabelLineRecord, DiagramLabelSpanRecord, DiagramLabelFlags, DiagramTextLineRecord, DiagramTextRunRecord, DiagramTextRecord. No behaviour change.

Expected gain: None by itself; lets the other packages run in parallel without touching the same files.

### P1 Font faces without reference counting, byte widths

Depends on: P0

Owns: Sources/MermaidDiagrams/Text/CoreTextDiagramTextMeasurer.swift, Sources/MermaidDiagrams/Text/CoreTextFontFaces.swift, Sources/MermaidDiagrams/Text/DiagramStyledTextMeasuring.swift, Sources/MermaidDiagrams/Text/DiagramTextMeasurerSizes.swift, Sources/MermaidDiagrams/Text/DiagramTextMeasuring.swift, Sources/MermaidDiagrams/Text/DiagramTextMeasurerSet.swift, Sources/MermaidDiagrams/Text/DiagramFontFaceRegistry.swift (new), Sources/MermaidDiagrams/Text/DiagramFontAdvances.swift (new), Sources/MermaidDiagrams/Text/DiagramLineWidthCache.swift (new), Tests/MermaidDiagramsTests/DiagramFontAdvancesTests.swift (new)

Makes CoreTextDiagramTextMeasurer trivially copyable (face index and flags), with faces in an immortal registry and a per-preparation overflow table. Advance tables become 256-entry byte-indexed pointers with an isExactlySummable flag. Adds DiagramFontStyles for the eight emphases, width(ofUTF8:style:), and a CTLine width cache keyed by bytes (String only on a miss, through today's NSAttributedString path) with os_unfair_lock. DiagramTextMeasurerSizes keeps the resized measurers in a small array of indices instead of a [CGFloat: Measurer] dictionary. Tests: exactness check of every face the typographies make; widths from bytes equal width(of: String) to the bit for ASCII, emoji, CJK, guillemets and box drawing; cache eviction.

Expected gain: Removes the retain and release of every measurer copy (sample: copies of measurer-holding structs are 16% of sequence read+layout, partly measurers, 7% kanban, 5.8% timeline, 3.9% c4), and the String hashing of non-ASCII width lookups (c4's 50 blocks with guillemets). Estimated 3 to 8% of read+layout on those types.

### P2 Labels as byte ranges of a label store

Depends on: P0

Owns: Sources/MermaidDiagrams/Text/DiagramLabel.swift, Sources/MermaidDiagrams/Text/DiagramLabelDecoder.swift, Sources/MermaidDiagrams/Text/DiagramLabelLineBreaks.swift, Sources/MermaidDiagrams/Text/DiagramLabelInlineMarkup.swift, Sources/MermaidDiagrams/Text/DiagramLabelEntities.swift, Sources/MermaidDiagrams/Text/DiagramLabelIcons.swift, Sources/MermaidDiagrams/Text/DiagramLabelEntityNames.swift, Sources/MermaidDiagrams/Text/JavaScriptStringTrimming.swift, Sources/MermaidDiagrams/Text/UnicodeScalarText.swift, Sources/MermaidDiagrams/Text/DiagramLabelStore.swift (new), Sources/MermaidDiagrams/Text/DiagramLabelByteDecoder.swift (new), Sources/MermaidDiagrams/Text/DiagramLabelByteMarkup.swift (new), Sources/MermaidDiagrams/Text/DiagramLabelByteEntities.swift (new), Sources/MermaidDiagrams/Text/DiagramLabelMarkdownSource.swift (new), Tests/MermaidDiagramsTests/ReferenceDiagramLabelDecoder.swift (new: today's decoder moved here as the oracle), Tests/MermaidDiagramsTests/DiagramLabelByteDecoderTests.swift (new)

Ports the prototype FlatLabelDecoder (all markup, verified identical on about 9,700 corpus labels) into DiagramLabelStore. DiagramLabel becomes (store, firstLine, lineCount, flags), with public lines and spokenText computed. DiagramLabelDecoder.label(from:form:) keeps its signature and decodes into DiagramLabelStore.current (TLS scope opened by MermaidDiagramReader.read, the only line it touches there) or a private store. New byte entry: label(sourceRange:form:isUnmarked:). Entity names get a perfect hash on bytes. Differential fuzz test against the oracle: random strings over an alphabet of markup characters, br variants, \n, \N, entity codes (valid, invalid, out of range, surrogates), multibyte JS spaces, CJK, soft hyphens, fa: icons, and all three forms.

Expected gain: Decode 2.3 to 5.1x measured standalone (flowchart 0.24 -> 0.08 µs, c4 4.5 -> 1.6, timeline 1.30 -> 0.44, block 0.50 -> 0.10). With readers passing source ranges and their scan's markup flag (P6), estimated a further 2 to 3x, and no String per label in the reader.

### P3 Measuring and wrapping on bytes into one text storage per layout

Depends on: P0, P1, P2

Owns: Sources/MermaidDiagrams/Text/DiagramTextBlock.swift, Sources/MermaidDiagrams/Text/DiagramTextBlockLines.swift, Sources/MermaidDiagrams/Text/DiagramTextWrapping.swift, Sources/MermaidDiagrams/Text/DiagramTextPieces.swift, Sources/MermaidDiagrams/Text/DiagramTextBreaking.swift, Sources/MermaidDiagrams/Text/DiagramTextFitting.swift, Sources/MermaidDiagrams/Text/DiagramTextStyle.swift, Sources/MermaidDiagrams/Text/DiagramTextStorage.swift (new), Sources/MermaidDiagrams/Text/DiagramTextExactWrapping.swift (new), Sources/MermaidDiagrams/Text/DiagramTextSequentialWrapping.swift (new), Sources/MermaidDiagrams/Text/DiagramTextLiteralLines.swift (new), Sources/MermaidDiagrams/Preparation/MermaidDiagramPreparation.swift (only the TLS storage scope around each layout; coordinate with the scene/SVG owner), Tests/MermaidDiagramsTests/ReferenceDiagramTextWrapping.swift (new: today's wrapping as the oracle), Tests/MermaidDiagramsTests/DiagramTextStorageTests.swift (new)

Ports the prototype FlatTextArena (exact single-pass and sequential wrapping, both verified to the bit) into DiagramTextStorage: one allocation for bytes and line and run records, raw pointers with counts, no Array.removeAll in the hot path, and scratch per thread. DiagramTextBlock becomes (storage, record, center) with lines, lineWidths and lineRuns computed, plus lineCount, lineWidth(at:) and withUTF8(ofLine:). All existing initializers keep their signatures and measure into DiagramTextStorage.current or a private storage. Ports the non-ASCII piece algorithm onto byte positions with cached widths, and adds ASCII fast paths for literal lines and breaking between characters ('\r\n' kept as one Character). Fitting uses exact prefix sums so its binary searches make no String. Differential tests against the oracle: random labels, widths 0 to 400, the exact sizes 16, 14 and 12, the inexact sizes 12.8, 17.3 and 9.1, emphasis spans, soft hyphens and CJK; plus the full --output-digest (826 lines, inputs digest ff8a133226b37b4b).

Expected gain: Measure+wrap 4.3 to 6.4x measured with a pooled arena (flowchart 0.27 -> 0.063 µs, c4 11.1 -> 2.26, timeline 1.97 -> 0.37, kanban 2.48 -> 0.56). Blocks retain one object instead of 2 or 3 arrays plus Strings. One storage allocation per layout is estimated at about 60 ns per diagram.

### P4 Scene text, renderer and SVG text from bytes

Depends on: P3

Owns: Sources/MermaidDiagrams/Scene/DiagramSceneTextLine.swift, Sources/MermaidDiagrams/Drawing/DiagramTextDrawing.swift, Sources/MermaidDiagrams/Drawing/SequenceTextInk.swift

DiagramSceneText.lines and styledRuns are made from the block's storage when asked, keeping their public shape. The Core Graphics renderer builds CTLines from CFStrings made from line bytes. Hands the SVG area agent the spec for DiagramSVGBody.addLines: escape block.withUTF8(ofLine:) and run bytes directly through DiagramSVGBuffer.appendEscaped(_ bytes: UnsafeBufferPointer<UInt8>). That edit is theirs, in Scene/SVG/*.

Expected gain: SVG label escaping is 0.4 to 1.9% of prepare+SVG today (flowchart 0.24 µs); estimated 4x cheaper from bytes, without String bridging retains. Painting is not measured here.

### P5 Accessibility made when asked

Depends on: nothing

Owns: Sources/MermaidDiagrams/Preparation/MermaidDiagramAccessibility.swift, Sources/MermaidDiagrams/Preparation/MermaidDiagramGraphAccessibility.swift, Sources/MermaidDiagrams/Preparation/MermaidDiagramChartAccessibility.swift, Sources/MermaidDiagrams/Preparation/PreparedMermaidDiagram.swift, the accessibility arguments only, in Sources/MermaidDiagrams/Preparation/MermaidDiagram*Preparation.swift (coordinate line-level edits with the scene/SVG owner)

PreparedMermaidDiagram keeps the read MermaidDiagram and kind, and computes accessibility on first access. The cache lives in a final class box behind os_unfair_lock, so the struct stays Sendable. Spoken text is joined on label bytes into one String per field. The public init taking a value stays.

Expected gain: Removes from prepare 1.5% (flowchart, 0.27 µs), 3.1% (block), 2.7% (sequence, kanban), 3.0% (timeline), 4.1% (c4, 3.9 µs) and 6.1% (journey, 1.9 µs). The cost moves to the first read, estimated 2 to 4x cheaper.

### P6 Readers hand labels as source ranges (reading agents' packages)

Depends on: P2

Owns: Sources/MermaidDiagrams/Reading/* (owned by the reading packages; listed for the interface only)

Readers create one DiagramLabelStore per read and call label(sourceRange:form:isUnmarked:) with the markup flag from a 256-entry byte class table in the scan that already finds the label's end. They make no String for label text, and none for synthetic default labels (a node's identifier as its label: a range too).

Expected gain: Text without markup costs about nothing to decode (estimated 3 to 10 ns per label instead of about 20 ns standalone). Removes the reader's label Strings, which this design could not measure on their own.

### P7 Type text helpers on byte widths (type layout agents' packages)

Depends on: P1, P3

Owns: C4/Layout/C4TextLabel.swift, C4/Layout/C4LabelPlacement.swift, Timeline/TimelineTextFitting.swift, EventModeling/EventModelText.swift, Architecture/ArchitectureIcons.swift, TreeView/TreeViewRowPlacement.swift, Sankey/*, Gantt/GanttPlotBuilder.swift, Railroad/RailroadText.swift, XYChart/XYChartText.swift, Treemap/TreemapBoxTexts.swift, Sequence/SequenceTextMeasurers.swift (owned by the type packages)

Replaces measurer.width(of: String) loops and Strings made per probe (ellipsis fitting, literal binary searches, event model fitting) with DiagramTextStorage, width(ofUTF8:) and exact prefix sums. Redesigned layouts keep POD DiagramTextRecord values and pass the storage explicitly instead of TLS.

Expected gain: Per type. c4 is the largest: of its 46 blocks per diagram, 64 wrapped labels in the corpus account for most of its remaining 2.3 µs.

## Public API changes

- No change is needed in Graphite. MermaidDiagramPreparation.prepare(source:...) and prepare(_ diagram:...), PreparedMermaidDiagram.scene, narrowScene and kind.peleName, DiagramSceneRenderer, DiagramSVGWriter, DiagramScene.seriesColors, and DiagramSceneText.lines, styledRuns, block.center, rotation, outline, isBold, isItalic and isMonospaced keep their signatures. So do DiagramSceneTextLine.text, center and runs, and DiagramTextRun.text and style, which Graphite's ReadingDiagramScenePainting uses.
- PreparedMermaidDiagram.accessibility changes from a stored let to a computed property, cached on first access; source-compatible. Graphite reads accessibility.label and value in ReadingDiagramView.body on the main thread, and title and description in ReadingDiagramSVGExport. Recommended one-line change in Graphite: read prepared.accessibility once in its background preparation, so the first build of the summary (0.1 to 2 µs, est.) stays off the main thread.
- DiagramTextBlock: lines, lineWidths and lineRuns become computed properties that make Strings and lists when read; size, fontSize, lineHeight and center are unchanged. New public members: lineCount, lineWidth(at:) and withUTF8(ofLine:_:). Equatable stays by content. The value now holds a reference to its layout's DiagramTextStorage. This is a 0.8.0 behaviour change for anyone reading block.lines in a loop. Graphite's main does not.
- DiagramLabel: lines and spokenText become computed; new withUTF8(ofLine:_:). Model types keep a DiagramLabel field of the same type. Equality stays by content.
- CoreTextDiagramTextMeasurer: same public init(font:), fontSize, lineHeight and width(of:); it becomes trivially copyable. DiagramTextMeasuring is unchanged, and a new internal protocol, DiagramByteTextMeasuring, adds byte widths.
- No public type is removed. The library's version moves to 0.8.0 because DiagramTextBlock and DiagramLabel change their stored layout and the cost of the properties above.

## Risks

- Exact-sum assumption: it holds only when advances are short binary fractions. It is guarded by a per-face check, with the sequential port as the fallback. Both paths were verified to the bit on the corpora, including the inexact sizes 12.8, 17.3 and 9.1 pt, but a new font or the user's custom PostScript font must also go through the check. The output digest proves only the default typography.
- On a cache miss, the CTLine width from bytes must use exactly today's NSAttributedString(String) path. A CFString made straight from bytes might differ for malformed UTF-8 (the reader replaces invalid sequences when it makes Strings). The label store must keep String(decoding:)'s replacement semantics, so it should copy the source's UTF-8 from the String (already valid), never raw file bytes.
- TLS current storage and label store are hidden state. They break if a layout ever suspends (await) or hops threads, or if a block made in one preparation is mixed with another's (still safe: each block holds its own storage). Debug assertions should check that the scope's thread is unchanged. Redesigned layouts should pass the storage explicitly.
- Each block copy still costs one atomic retain. Hot layout loops should move to POD DiagramTextRecord values, which only the explicit API gives.
- Unicode edge cases the prototype did not port: wrapping text beyond ASCII (CJK pieces, soft hyphens shown, closing punctuation), breaking between grapheme clusters, literal lines, and '\r\n' as one Character. These keep today's scalar and Character algorithms on byte positions and need the oracle differential tests.
- Per-input fixed costs dominate at about 2 µs. The naive storage object (7 arrays) measured 0.9x on flowcharts and blocks. The storage must be one allocation, sized from the label store's byte count, with scratch kept per thread.
- Face registry growth from hostile input (classes setting thousands of sizes): it is capped, overflow faces are per preparation, and MermaidDiagramLimits already bounds the styles per diagram. The width cache is bounded (8,192 entries, keys of at most 256 bytes). Today's breakBetweenCharacters builds a String per character, quadratic in the line's length; the byte version is linear.
- Lock contention: when Graphite prepares diagrams on several threads at once, all of them take the width cache's lock, on hits too. A small per-thread cache in front may be needed.
- Merge conflicts: P3 and P5 edit lines in Preparation/*.swift, and P4 needs an SVG-side edit owned by the SVG agent. These must be sequenced or limited to clearly separate lines.
- The 10x target for text-heavy types (c4, timeline, kanban, mindmap, journey) needs the estimated, not yet measured, gains: reader-fused classification, SIMD scanning and one-allocation storage. Even then text keeps 25 to 45% of their 10x budget. 50x is not reachable there because the work is per byte.

Prototype: branch `redesign-prototype-text-and-labels` (the copy of main the design measured, with its prototype code and benchmark modes).
