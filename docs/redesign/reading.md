# Redesign: reading

Written 2026-11-24 by the design phase of the 0.8.0 redesign (Graphite issue #223), measured on main de81532 (0.7.0), Apple M5 Max, Release, under load from other work. [M] or MEASURED marks measured numbers; everything else is an estimate.

Area: Reading: the shared front end (MermaidDiagramReader.read/diagram, preprocessing, front matter and its YAML, %%{init}%% directives, configuration options, theme series colours, type keyword, titles and accessibility) and the flowchart reader (FlowchartParser and its syntaxes, FlowchartLookAheadIndex, FlowchartDiagramBuilder) with the model it builds (FlowchartDiagram, FlowchartNode, FlowchartEdge, MermaidDiagram); what carries over to the other 32 readers.

## Where the time goes now

All numbers come from the baseline benchmark built from main de81532 on an Apple M5 Max. The machine was loaded (load average 4 to 25). Each figure is a median of alternated runs unless marked.

READING ALONE ("--profile <case> parsing") AGAINST READ+LAYOUT ("reading"):
- Pele's 114 flowchart examples (the same file as flowchart-docs): reading 3.51 to 3.57 µs over five alternated 1 s runs at load 5, and up to 4.5 µs under heavier load. Read+layout is 10.7, so reading is about 33 %.
- tree 50: reading 48 to 56 of about 108 µs (44 %). tree 500: 470 to 525 of 1,001 (47 %).
- mesh 50: 45 to 52 of 269 (17 %). mesh 500: 430 to 480 of 3,478 (13 %).
- Present reading cost per line: about 1 µs a line on the trees (49 lines of about 32 B for tree 50), against about 40 ns a byte for the examples.

OTHER TYPES (reading / read+layout in µs; 0.7 to 1 s runs at load about 11, single runs, noisy):
agentflow 17.9/43.6, architecture 4.9/14.5, block 3.25/8.7, c4 15.5/54.8, class 2.7/14.4, cynefin 4.5/14.3, er 4.2/18.6, eventmodeling 6.0/11.2, gantt 3.6/17.6, git 6.6/12.9, info 0.19/0.36, ishikawa 3.7/11.8, journey 3.3/8.6, kanban 4.3/10.4, mindmap 1.6/3.7, packet 2.0/6.5, pie 2.7/5.0, quadrant 6.4/10.6, radar 6.6/8.9, railroad 5.7/17.2, requirement 6.0/25.6, sankey 6.1/26.8, sequence 4.1/11.0, state 2.6/21.7, swimlane 11.7/38.6, timeline 4.7/9.0, treemap 4.0/10.8, treeview 5.5/8.5, usecase 8.2/40.2, venn 3.4/19.9, wardley 5.3/10.1, xychart 6.2/12.9.
Reading is 20 to 75 % of read+layout across types.

SAMPLE OF THE 114 EXAMPLES' READING (sample(1), 2,521 samples under MermaidDiagramReader.read; percentages inclusive):
- FlowchartParser.parse 95 %, of which readNode 47 %.
- FlowchartNodeSyntax.readAttributes 24 %. This is the @{ … } read through Strings and the YAML reader: StringProtocol.contains/range 10 %, SequenceAttributes YAML 5 %.
- FlowchartLookAheadIndex.init 11 % (four lists built over every byte).
- FlowchartDiagramBuilder.nodeIndex 11 % (String dictionary and hashing).
- readKeywordStatement 10 % and DiagramLabelDecoder 7 %.
- styleNodes and styleEdges 6 %, run even when nothing styles the diagram.
- Preprocessing 2 %; the shared front end is about 4 % for flowcharts.
- By symbol: swift_retain/release/RefCounts about 20 %, array growth (_consumeAndCreateNew) 12 %, malloc/free about 15 %.

TREE 500 SAMPLE: readNode 58 %, nodeIndex 17 %, readShape 17 %, look-ahead index build 8 % plus its binary searches 6 %, define/defineAsset 9 % (FlowchartNode copied out and back with its DiagramElementStyle), styleNodes 5 %.

FRONT END ALONE (preprocessing, front matter, keyword; a new "frontend" mode):
- 0.10 to 0.12 µs an input on corpora without front matter.
- 0.4 to 0.93 µs on corpora with front matter: git 0.93 (23 of 35 inputs have it), radar 0.85, pie 0.73, gantt 0.63.
- Work inside the type readers derived from front matter. In the radar sample: MermaidDiagramReader.preprocessed 14 %, MermaidThemeSeriesPalette.seriesColors 18 % (DiagramSeriesInk luminance for all 12 slots, DiagramThemeColor.isSafe), MermaidConfigurationOptions.init 6 % (walks the YAML again into String dictionaries and scans the text for directives again). XY chart: 11, 13 and 6 %. Quadrant: 10 % preprocessing.
- So the shared front end plus configuration and colours costs about 1.5 to 2.5 µs per radar, XY, pie or Git input. The remainder of each type's reading is its own lexer and builder.

SHARED PATTERNS IN THE OTHER READERS:
- FirstMatchTokenizer (event model, railroad, Langium types) tries closures in order per token, with a search memo keyed by [UInt8].
- The agent flow, C4 and use case lexers convert the whole text to [UInt16] for Jison's columns.
- Every reader receives a MermaidTextCursor over a copied [UInt8].

Known size of the remaining flowchart gap: the unmerged origin/speed-flowchart-reading (7e01128) claims 1.5 to 2.7x on reading with the same model.

## Design

GOAL: a reader that touches each source byte a small constant number of times. It allocates only the lists its result keeps (nodes, edges, and one extras box only when used). It makes no String for a name or a one-line label, keys nothing by String, uses no closure or existential in hot paths, and gives a model the layout can read directly.

1. SOURCE TEXT (shared). The text the models index, owned once.
   struct MermaidTextRange: Equatable, Sendable { var start: Int32; var end: Int32; var length: Int }  // start < 0: side bytes at ~start
   public struct MermaidSourceText: Sendable {
       enum Storage { case string(String), bytes([UInt8]) }   // the caller's String when no pass changed a byte
       func withBytes<Result>(_ body: (UnsafeBufferPointer<UInt8>) throws -> Result) rethrows -> Result
       func string(_ range: MermaidTextRange) -> String
       func line(at offset: Int) -> Int          // newlines before offset + 1; same as MermaidTextCursor.line
       var legacyBytes: [UInt8] { get }           // copy made on demand for readers not yet moved
   }

2. FRONT END. Cost: one SIMD16 scan, with no copy when no pass changes a byte.
   struct MermaidFrontEndResult {
       var text: MermaidSourceText
       var keyword: MermaidTextRange
       var bodyStart: Int
       var frontMatter: MermaidYAMLTree?
       var frontMatterTitle: String?
       var directiveRanges: [Range<Int32>]
   }
   enum MermaidFrontEnd { static func read(_ source: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> MermaidFrontEndResult }
   - Scanned once: CR, <, >, %, #, NUL, @, and the line count.
   - Each pass gets an exact detector on the borrowed bytes. Prototyped: tag attributes need `="`; directives need `%%{`; MermaidPreprocessing.droppingColorSemicolons ported as a predicate, so a style without a dropped `;` is not copied.
   - A pass runs, and copies, only when its detector fires.
   - The type keyword dispatches on its bytes (length, then compare), never through String switches.

3. FRONT MATTER AND CONFIGURATION.
   - YAML is read once into a flat tree:
     struct MermaidYAMLNode { var kind: UInt8; var key: MermaidTextRange; var scalar: MermaidTextRange; var number: Double; var firstChild: Int32; var nextSibling: Int32 }
     struct MermaidYAMLTree { var nodes: [MermaidYAMLNode]; func child(_ node: Int32, key: StaticString) -> Int32? }
   - Scalars stay ranges, with Pele's scalar rules applied lazily. Anything outside the fast block-mapping or flow-mapping subset falls back to SequenceAttributesBlockSyntax, which stays the reference reader.
   - Configuration becomes path lookups merged over front matter `config:` and directive ranges in order:
     struct MermaidConfiguration { func value(section: StaticString, key: StaticString) -> MermaidConfigurationOptions.Value? }
     This replaces building String dictionaries per section and scanning for directives again.
   - Theme series colours keep their texts and resolve and ink a slot when it is first read. Pie, radar and Git use 3 to 8 of the 12 slots.

4. FLOWCHART MODEL (prototyped). Every record is a trivial struct.
   struct FlowchartLabelReference {
       enum Kind: UInt8 { case none, line, writtenPlain, writtenMarkdown, decoded }
       var kind: Kind; var range: MermaidTextRange
   }
   // line: the range is the single drawn line, trimmed and unmarked (DiagramLabelDecoder's own shortcut).
   // written*: decoded on demand by DiagramLabelDecoder.label(from:form:) from exactly the text the present reader would pass it.
   // decoded: an index into extras.decodedLabels, for a string joined with plain text or ends that Foundation trims beyond ASCII.
   struct FlowchartNodeRecord { var identifier: MermaidTextRange; var label: FlowchartLabelReference; var shape: FlowchartNodeShape; var assetIndex: Int32 }  // 24 B
   struct FlowchartEdgeRecord { var sourceIndex: Int32; var targetIndex: Int32; var minimumRankSpan: Int32; var stroke: FlowchartEdgeStroke; var sourceArrowhead: FlowchartArrowhead; var targetArrowhead: FlowchartArrowhead; var label: FlowchartLabelReference }  // 28 B
   struct FlowchartGroupRecord { var writtenIdentifier: MermaidTextRange; var generatedNumber: Int32; var title: FlowchartLabelReference; var direction: FlowchartDirection?; var representingNodeIndex: Int32; var isCollapsed: Bool; var nodeIndices: Range<Int32>; var childGroupIndices: Range<Int32> }
   final class FlowchartModelExtras: Sendable {
       let groups: [FlowchartGroupRecord]; let groupMembers: [Int32]
       let decodedLabels: [DiagramLabel]; let assetAttributes: [FlowchartNodeAssetAttributes]
       let nodeStyles: [DiagramElementStyle?]; let edgeStyles: [DiagramElementStyle?]
       let title: String?; let accessibilityTitle: String?; let accessibilityDescription: String?
   }
   // Built by the reading and never changed after it.
   struct FlowchartModel: Sendable {
       var text: MermaidSourceText; var direction: FlowchartDirection
       var nodes: [FlowchartNodeRecord]; var edges: [FlowchartEdgeRecord]
       var unappliedStatementCount: Int; var extras: FlowchartModelExtras?
       func label(_ reference: FlowchartLabelReference) -> DiagramLabel?
       func identifier(ofNode index: Int) -> String
       func materialized() -> (nodes: [FlowchartNode], edges: [FlowchartEdge], groups: [FlowchartSubgraph])
   }
   A usual diagram is 2 allocations: nodes, and edges reserved at the first edge.

5. NAMES.
   struct FlowchartNameTable { mutating func intern(_ range: MermaidTextRange, in bytes: FlowchartBytes, side: inout [UInt8]) -> Int }
   - Open addressing, FNV-1a 32 over the bytes, verified with memcmp.
   - Each name carries parallel metadata: nodeIndex, endedGroupIndex, isTaken, isCollapsed, isEdgeIdentifier, listedByGroupSerial, slot.
   - Group identifiers Mermaid makes (`subGraph<n>`) are written as digits into side bytes, with no interpolation.

6. SCRATCH.
   - The working lists live in struct FlowchartReadingLists, kept in a per-thread final class through a pthread key: no API change.
   - They are swapped into the reader struct once per reading, so the hot loops see no class-property exclusivity checks.
   - Resetting clears only the slots used.

7. LEXER.
   - struct FlowchartBytes { base: UnsafePointer<UInt8>; count: Int }, where subscript returns 0 outside the text. Prototype: a text holding NUL falls back to the present reader; the production design checks count instead of relying on the 0.
   - func token(at:) -> (FlowchartPieceToken, Int)? is Pele's tests ported one for one: startsKeywordOrAccessibility, startsLink, endOfNodeString with two 64-bit masks, `v`, unicode letters, the space token, and FlowchartStyleGrammar on the same tokens.
   - The far look-aheads (a direction statement later on the line, a link identifier's `@`) use lists built only when a SIMD prefilter finds `d`,`i`,…,`n` or an `@` not followed by `{` or `"`.
   - Production must use binary search plus a word-break and line-end index, as FlowchartLookAheadIndex does, for hostile safety. The prototype scans linearly there.

8. STATEMENTS.
   - FlowchartParser's logic is ported one for one on byte offsets.
   - Text in brackets is scanned with a stop-byte mask: bracket bytes, the state's bytes and the closings' first bytes.
   - Links follow readLink, readOperator, readRun, readDotted, readTextInside and closingRun exactly.
   - Attributes: a single-line flow mapping of letter keys to double-quoted or YAML-safe plain scalars (digits for w/h) is read on bytes, and shapes are found in a byte-keyed table. A multi-line body, an escape or a YAML word (`true`, `null` and so on) goes to the YAML reader.
   - Groups: members are listed on one stack buffer (an inner group's members are always the suffix). Nesting uses one withUnsafeTemporaryAllocation buffer holding parents, CSR children, marks, preorder and places.
   - Styles: recorded by name index and applied only when a statement or `:::` exists.
   - Errors: positions are kept, and line(at:) gives the same line the cursor gave.

9. PUBLIC FLOWCHARTDIAGRAM AS A FAÇADE.
   - public struct FlowchartDiagram { var model: FlowchartModel; ... }
   - The existing public properties stay: nodes, edges and subgraphs become computed views materialized on read.
   - New accessors for the layout: nodeCount, edgeCount, nodeLabel(at:), edgeLabel(at:), nodeShape(at:), edgeEnds(at:), nodeStyle(at:), groups.
   - == compares semantically: decoded labels against decoded labels.

10. OTHER TYPES CARRY OVER (designed, not prototyped):
    - MermaidSourceText plus the front-end result replace the copied cursor.
    - FlowchartNameTable generalizes to MermaidNameTable.
    - FirstMatchTokenizer rules compile into a first-byte dispatch table with matcher enums instead of closures and no String names.
    - The UTF-16 lexers (agent flow, C4, use case) run on UTF-8 bytes and compute UTF-16 columns from the line's prefix only when an error is reported.

HOW OUTPUT STAYS BYTE-IDENTICAL:
- The new reader changes only the representation. Every label still goes through DiagramLabelDecoder with the same input string and form, and the unmarked shortcut is decided on the same raw bytes. This matters: DiagramLabel.isReadWithoutMarkup differs between paths and changes wrapping.
- Before merge: a reference reader (the 0.7.0 FlowchartParser family, kept in tests) checks model equality on all corpora plus mutation fuzzing; --output-digest must be identical (826 lines, ff8a133226b37b4b); errors and lines must be identical.
- The prototype already proves model equality on:
  - all 113 of 114 examples it reads (1 falls back to the present reader);
  - tree and mesh 50 and 500;
  - the 60 random flat flowcharts;
  - 923 of 956 Mermaid spec texts. The other 33: 22 are refusals, read by the present reader, whose error matches; 10 are other bail-outs; 1 is not a flowchart.
- No corpus input differs.

ONE NAMED BUG FIX TO DECIDE:
- Identifiers compare by UTF-8 bytes, as JavaScript compares code units.
- Swift String == today merges canonically equivalent spellings: the Kelvin sign and K, a Hangul syllable and its jamo. Pele keeps them as distinct nodes.
- No corpus input depends on it. The alternative, a String-keyed fallback once a name beyond ASCII appears (as speed-flowchart-reading does), keeps 0.7.0 exactly at a small cost.

## Prototype measurements

- All prototype numbers are measured on the M5 Max, Release, under load 4 to 25 from other agents. 'In process' means alternating rounds of the present reader and the prototype in the same binary (--flat-pairs: 0.4 to 0.6 s per round, 5 to 7 pairs, medians). 'Against baseline' means alternating 1 s --profile runs of the untouched baseline binary (parsing) and the prototype (flat).
- Model equality (--flat-check, materialized FlowchartDiagram == present reader's): examples 113/113 read flat equal, 1 fell back; trees and meshes 50 and 500 equal; 60 random flat equal; spec texts 923/923 equal; 32 bail-outs (22 of them refusals, whose errors match the present reader's), 1 other type; 0 different, 0 errors disagreeing.
- Reading alone on the 114 examples, against baseline, 5 pairs: 3.512 to 3.566 µs baseline against 0.706 to 0.725 µs prototype, 4.9x. In process: 3.65 against 0.72 µs, 5.1x.
- Reading alone per input (--flat-each, median of 7, warm), 114 examples: mean 3.24 µs present against 0.643 µs prototype; median input 0.38 µs; smallest input (one node) 0.28 µs.
- By feature, prototype mean (present mean): plain 44 inputs 0.385 (2.15); @{} attributes 49 inputs 0.410 (3.01); groups 7 inputs 1.22 (8.21); front matter 5 inputs, still through the present preprocessing and YAML, 1.49 (6.75); styles 5 inputs, still parsed by FlowchartStyleSyntax and DiagramElementStyle.reading on Strings, 3.17 (4.93); link identifiers 4 inputs, one of which falls back, 1.11 (2.76).
- Trees and meshes, in process: tree 50: 48.1 against 6.32 µs (7.7x). mesh 50: 44.7 against 6.43 µs (7.0x). tree 500: 471.7 against 62.8 µs (7.5x). mesh 500: 433.6 against 63.8 µs (6.8x).
- Making the flat model into the present FlowchartDiagram (the compatibility shim) costs, measured: about 0.57 µs on the examples (1.29 against 0.72 µs), 6.8 µs on tree 50, 63 µs on tree 500.
- Read and layout with the prototype reader plus the shim, then the present layout (flatlayout), against the baseline's reading mode, 3 pairs under load about 25: examples 13.3 to 16.5 against 9.9 to 12.3 µs (1.32x within each pair); tree 50 about 114 against about 78 µs (1.47x); mesh 50 1.1 to 1.2x.
- Front end alone (frontend against flatfrontend): corpora without front matter 0.10 to 0.12 µs against 0.02 to 0.05 µs. Corpora with front matter are unchanged or worse in the prototype, since they still go through the present preprocessing (git 0.93 against 1.01, radar 0.85 against 0.96).
- Hostile inputs: a 20 kB line `a:a:…` gives 428 µs present against 120 µs prototype. 2,000 links give 789 against 137 µs. 300 nested groups give 208 against 23 µs. The `@` hostile line falls back at once. The prototype's linear look-up of later direction statements and of link `@`s, and its member scan after an inner group ends, are not yet bounded by an index for adversarial texts.

## Expected after

- Flowchart reading alone on Pele's 114 examples: measured 0.64 to 0.72 µs with the prototype (4.9 to 5.1x). Estimated 0.42 to 0.50 µs (7 to 8.5x the present 3.5) once styles and front matter are read on bytes and the remaining copies and retains are trimmed. That arithmetic: styles 3.2 to about 1.0 µs over 5 inputs (−0.10 on the mean), front matter 1.5 to about 0.6 over 5 inputs (−0.04), the link identifier fallback removed (−0.02), plain path 0.39 to about 0.30 (−0.07).
- The 0.5 µs reading target is reachable on that estimate but not yet shown; the 50x stretch (about 0.07 µs) is not reachable. A one-node flowchart measured 0.28 µs: borrowing the String's bytes, two SIMD scans, the scratch swap, one node list allocated and freed, the model handed back and dropped.
- Trees and meshes reading alone (measured): tree 50 6.3 µs, tree 500 63 µs, mesh 50 6.4 µs, mesh 500 64 µs. Estimated 5 and 50 µs once the bracket text read again for an existing node is skipped by bytes.
- Read and layout: reading cannot give 10x on its own. With reading at 0, the examples' read and layout would still be about 7.1 µs against the 2.2 µs target. Measured with the shim: about 1.3x on the examples and 1.5x on tree 50. Estimated once the layout reads the flat model directly (no shim): examples about 7.6 µs (10.6 − 3.5 + 0.5) before any layout work, tree 50 about 66 µs (108 − 48 + 6).
- Other types, estimated, not measured: a zero-copy front end saves about 0.07 µs an input without front matter. Flat YAML front matter saves about 0.3 to 0.6 µs an input with it. Lazy theme colours plus configuration path lookups save about 1 to 1.5 µs per radar, XY, pie, Git or timeline input (18 % + 6 % of radar's 6.6 µs sampled). Type lexers redesigned the same way (compiled FirstMatchTokenizer, byte lexers with lazy UTF-16 columns, interned names, flat records): estimated 2 to 4x on each type's own reading, to be measured per package.

## Packages

### R0 Reading equivalence harness (land first)

Depends on: nothing

Owns: Tests/MermaidDiagramsTests/Reference/ReferenceFlowchartParser.swift (copies of 0.7.0's FlowchartParser, FlowchartDiagramBuilder, Flowchart*Syntax, FlowchartLexerText, FlowchartLookAheadIndex, FlowchartSubgraphNesting, renamed Reference*), Tests/MermaidDiagramsTests/FlowchartModelEquivalenceTests.swift, Sources/MermaidDiagramsBenchmark/ReadingEquivalenceCheck.swift (the --flat-check, --flat-pairs and --flat-each modes ported from the prototype, plus a file: corpus option)

Freezes 0.7.0's reader as the reference in the test target. Compares every model (and error with its line) on the 956 flowchart spec texts, every compat input, the 114 examples, the trees and meshes, the random flat flowcharts, the hostile cases, and 10,000 mutations of the examples (cut lines, spliced tokens, inserted `@`, `direction`, `%%`, `\r`, non-ASCII).

Expected gain: None by itself. It is the gate that lets R5 change the reader without changing a byte of output.

### R1 Source text and zero-copy front end

Depends on: nothing

Owns: Sources/MermaidDiagrams/Reading/MermaidSourceText.swift (new), Sources/MermaidDiagrams/Reading/MermaidFrontEnd.swift (new), Sources/MermaidDiagrams/Reading/MermaidTypeKeyword.swift (new), Sources/MermaidDiagrams/Reading/MermaidDiagramReader.swift, Sources/MermaidDiagrams/Reading/MermaidPreprocessing.swift, Sources/MermaidDiagrams/Reading/MermaidTextCursor.swift

Adds MermaidSourceText (the caller's String or preprocessed bytes, ranges into it, line(at:)). One SIMD scan for CR, <, >, %, #, NUL, @ and newlines. Exact per-pass detectors (tag attributes, directives, colour semicolons as a predicate), so a pass copies only when it changes a byte. The type keyword dispatches on bytes. MermaidTextCursor gains init(text:from:) that shares storage, with a legacy [UInt8] made on demand, so the 32 other readers keep working unchanged.

Expected gain: Measured in the prototype: front end 0.10 to 0.12 to 0.02 to 0.05 µs an input on corpora without front matter. Enables zero-copy flowchart reading (part of R5's 4.9x).

### R2 Flat YAML front matter and configuration lookups

Depends on: R1

Owns: Sources/MermaidDiagrams/Reading/MermaidYAMLTree.swift (new), Sources/MermaidDiagrams/Reading/MermaidYAMLTreeReader.swift (new), Sources/MermaidDiagrams/Reading/MermaidFrontMatter.swift, Sources/MermaidDiagrams/Reading/MermaidYAMLDocument.swift, Sources/MermaidDiagrams/Reading/MermaidConfigurationOptions.swift, Sources/MermaidDiagrams/Reading/MermaidConfigurationNumbers.swift, Sources/MermaidDiagrams/Reading/MermaidDirectiveConfiguration.swift

Front matter is found on bytes without copying its body. It is read once into a flat MermaidYAMLTree (scalar ranges) for block and flow mappings of plain or quoted scalars, falling back to the existing SequenceAttributesBlockSyntax reader (left untouched as the reference) for anything else. MermaidConfigurationOptions answers value(section:key:) from the tree and the directive ranges R1 found, instead of building String dictionaries and scanning for directives again. The title is a lookup. PeleYAMLDifferentialTests and PelePreprocessingDifferentialTests must pass unchanged.

Expected gain: Estimated: front matter inputs 1.2 to 2.4 µs to 0.4 to 0.6 µs (5 of the flowchart examples, 23 of 35 Git, 7 of 14 timeline, 4 of 8 XY and Sankey). Configuration lookups 5 to 6 % of radar and XY reading.

### R3 Theme series colours resolved per slot when read

Depends on: R2

Owns: Sources/MermaidDiagrams/Reading/MermaidThemeSeriesColors.swift, Sources/MermaidDiagrams/Scene/DiagramSeriesColors.swift

Reading keeps the palette's texts. A slot's DiagramThemeColor and its ink (DiagramSeriesInk) are made when the slot is first read and memoized, with Sendable-safe storage (a lock or once per slot). DiagramScene.seriesColors keeps its public type and values.

Expected gain: Estimated: about 18 % of radar's and 13 % of XY's reading (about 1.2 and 0.8 µs). Charts read 3 to 8 of the 12 slots. Coordinate with the scene/SVG area, which also owns Scene/.

### R4 Flowchart byte lexer, hostile-safe

Depends on: R0

Owns: Sources/MermaidDiagrams/Reading/FlowchartLexerText.swift (becomes FlowchartBytes), Sources/MermaidDiagrams/Reading/FlowchartLookAheadIndex.swift, Sources/MermaidDiagrams/Reading/FlowchartIdentifierSyntax.swift, Sources/MermaidDiagrams/Reading/FlowchartStyleGrammar.swift

Ports the prototype's FlatBytes/token(at:) onto a pointer: Pele's token tests one for one, node-string masks, the style grammar on the same tokens. The look-ahead lists are built only when a SIMD prefilter finds `direction` or a link `@`, then answered by binary search with a word-break and line-end index (as today), so `a:a:a…` and many-`@` texts stay linear.

Expected gain: Part of R5's measured 4.9x. The index build was 8 to 11 % of today's reading and now runs only for the 2 % of texts that need it.

### R5 Flowchart flat reader and model

Depends on: R0, R4, R1 (optional: without it the model indexes the cursor's copied bytes)

Owns: Sources/MermaidDiagrams/Reading/FlowchartParser.swift, Sources/MermaidDiagrams/Reading/FlowchartDiagramBuilder.swift, Sources/MermaidDiagrams/Reading/FlowchartNodeSyntax.swift, Sources/MermaidDiagrams/Reading/FlowchartAttributeSyntax.swift, Sources/MermaidDiagrams/Reading/FlowchartLinkSyntax.swift, Sources/MermaidDiagrams/Reading/FlowchartTextSyntax.swift, Sources/MermaidDiagrams/Reading/FlowchartSubgraphNesting.swift, Sources/MermaidDiagrams/Flowchart/FlowchartNodeShapeNames.swift, Sources/MermaidDiagrams/Reading/FlowchartModel.swift (new), Sources/MermaidDiagrams/Reading/FlowchartNameTable.swift (new), Sources/MermaidDiagrams/Reading/FlowchartReadingScratch.swift (new), Sources/MermaidDiagrams/Reading/FlowchartGroupReading.swift (new)

The prototype's reader made production-grade:
- FlowchartModel with its records and FlowchartModelExtras.
- Interned names with a per-thread scratch swapped in once.
- Labels as references, decoded by DiagramLabelDecoder on demand.
- Single-line @{ } read on bytes, YAML otherwise.
- Shape names looked up in a byte table.
- Groups on one member stack, nested in one stack buffer. Bounding the member check after an inner group ends needs a per-group mark restored on close (the prototype's scan can be quadratic).
- Styles recorded by name index and applied only when written.
- Errors from positions.
Until R6 lands, FlowchartParser.parse returns FlowchartDiagram(materialized: model).

Expected gain: Measured with the prototype: 114 examples reading 3.54 to 0.72 µs (4.9x), trees and meshes 7.0 to 7.7x. With the shim, read and layout about 1.3x on the examples and 1.5x on tree 50 (measured under load).

### R6 FlowchartDiagram as a façade over the flat model

Depends on: R5

Owns: Sources/MermaidDiagrams/Flowchart/FlowchartDiagram.swift, Sources/MermaidDiagrams/Flowchart/FlowchartNode.swift, Sources/MermaidDiagrams/Flowchart/FlowchartEdge.swift, Sources/MermaidDiagrams/Reading/TitledMermaidDiagram.swift, Sources/MermaidDiagrams/Reading/MermaidDiagramContent.swift

FlowchartDiagram stores a FlowchartModel. The public nodes, edges and subgraphs become computed views materialized on access. Adds internal accessors for the layout: nodeCount, edgeCount, nodeLabel(at:), edgeLabel(at:), nodeShape(at:), nodeAsset(at:), nodeStyle(at:), edgeEnds(at:), edgeLink(at:), groups. == is semantic. hasNothingToDraw uses nodeCount. The title setter writes the extras.

Expected gain: Removes the shim for consumers that move to the accessors: measured 0.57 µs on the examples, 6.8 µs on tree 50, 63 µs on tree 500.

### R7 Layout and accessibility read the flat model (layout area)

Depends on: R6

Owns: Sources/MermaidDiagrams/Flowchart/FlowchartMeasurement.swift, Sources/MermaidDiagrams/Flowchart/FlowchartClusterGraph.swift, Sources/MermaidDiagrams/Flowchart/FlowchartCollapsedGroups.swift, Sources/MermaidDiagrams/Flowchart/FlowchartPageAssembly.swift, Sources/MermaidDiagrams/Swimlane/SwimlaneGraph.swift, Sources/MermaidDiagrams/Swimlane/SwimlaneLayoutEngine.swift, Sources/MermaidDiagrams/Swimlane/SwimlanePageAssembly.swift, Sources/MermaidDiagrams/Preparation/MermaidDiagramGraphAccessibility.swift, Sources/MermaidDiagrams/Preparation/MermaidDiagramGraphPreparation.swift, Sources/MermaidDiagrams/Layout/DiagramNarrowColumn.swift, Sources/MermaidDiagrams/AgentFlow/Layout/AgentFlowClusterGraph.swift

These files switch from diagram.nodes[i].label and similar to R6's accessors. Each label is decoded once, into its DiagramTextBlock. The accessibility text uses the line ranges' strings and decodes only labels with markup. Owned by whoever owns the layered or flowchart layout, so the reading agents never touch layout files.

Expected gain: Measured shim cost: 0.57 µs on the examples, 6.8 µs on tree 50.

### R8 Style statements and declarations on bytes

Depends on: R5 (interface only; both can be built in parallel against the agreed signature)

Owns: Sources/MermaidDiagrams/Reading/FlowchartStyleSyntax.swift, Sources/MermaidDiagrams/Style/DiagramElementStyle.swift, Sources/MermaidDiagrams/Style/DiagramColor.swift

classDef, class, style and linkStyle are split on bytes (head, comma lists, indexes). DiagramElementStyle.reading and DiagramColor read their declarations from a byte range, and classes are interned in the name table. Exposes FlowchartStyleSyntax.statement(keyword:in:range:) for R5. The state and class diagrams' classDef and style use the same entry.

Expected gain: Measured today in the prototype: styled flowcharts 3.17 µs each, about 61 % of it in String style parsing (sampled). Estimated 1.0 µs, or −0.10 µs on the 114 examples' mean.

### R9 Compiled FirstMatchTokenizer

Depends on: R0 pattern: a frozen reference of these lexers in tests

Owns: Sources/MermaidDiagrams/Reading/FirstMatchTokenizer.swift, Sources/MermaidDiagrams/Reading/FirstMatchTokenPatterns.swift, Sources/MermaidDiagrams/Reading/FirstMatchTokenReader.swift, Sources/MermaidDiagrams/EventModeling/EventModelLexer.swift, Sources/MermaidDiagrams/Railroad/Reading/RailroadLexers.swift

Rules compile once into a first-byte dispatch table of rule indexes. Matchers become an enum interpreted in a switch (literal, keyword with boundary, class run, small patterns) instead of @Sendable closures. Rule names are used only in diagnostics. The search memo becomes a small fixed table instead of [[UInt8]: …].

Expected gain: Not measured. Estimated 2 to 3x on event model and railroad reading (6.0 and 5.7 µs).

### R10 Byte lexers with lazy UTF-16 columns (one package per type: agent flow, C4, use case)

Depends on: R1

Owns: Sources/MermaidDiagrams/AgentFlow/Reading/* (agent flow package), Sources/MermaidDiagrams/C4/Reading/* (C4 package), Sources/MermaidDiagrams/UseCase/Reading/* (use case package)

Each lexer runs on UTF-8 bytes. A Jison column is computed from the line's prefix in UTF-16 code units only when an error is reported, instead of converting the whole text to [UInt16]. Names are interned and records are flat, as in R5.

Expected gain: Not measured. Estimated 2 to 4x on 17.9 (agent flow), 15.5 (C4) and 8.2 µs (use case) of reading.

## Public API changes

- For Graphite, nothing changes: MermaidDiagramPreparation.prepare(source:…), prepare(_ diagram: MermaidDiagram, …), PreparedMermaidDiagram.scene and narrowScene, DiagramSceneRenderer, DiagramSVGWriter and DiagramScene.seriesColors keep their signatures and outputs. MermaidDiagramReader.read(_:limits:) and MermaidDiagramReadError are unchanged, with the same cases and lines.
- FlowchartDiagram (0.8.0): nodes, edges and subgraphs stay public with their types. They become computed views that build the arrays on each access, so their cost becomes O(n) per access. New public read-only accessors: nodeCount, edgeCount, node(at:) -> FlowchartNode, edge(at:) -> FlowchartEdge. Equatable stays semantic.
- FlowchartNode, FlowchartEdge and FlowchartSubgraph are unchanged as public value types; they are made on demand.
- DiagramScene.seriesColors keeps its public type and values. If R3 lands, the slots are resolved lazily.
- Named behaviour change to decide: flowchart identifiers, class names and group identifiers compare by UTF-8 bytes, as Pele's JavaScript compares code units. Swift's canonical equivalence today merges spellings such as the Kelvin sign and K. No corpus input changes. Keeping 0.7.0 exactly is possible with a String-keyed fallback once a name beyond ASCII appears.
- Note: the Graphite checkout at ~/Desktop/Graphite (branch main) still builds an in-tree Packages/MermaidDiagrams. Its Sources/GraphiteUI/ReadingDiagram.swift calls MermaidDiagramReader.read and reads FlowchartDiagram.unappliedStatementCount. That property stays as it is.

## Risks

- Exactness of a reimplemented Pele lexer: the token tests, text states, trimming rules and the unmarked shortcut must match byte for byte. isUnmarked must be decided on the raw text the decoder receives: DiagramLabel.isReadWithoutMarkup differs between the shortcut and full decoding and changes wrapping. Mitigations: R0's frozen reference, model equality on all corpora, mutation fuzzing, and --output-digest. The prototype shows zero differences on 1,100+ inputs but reads only 923 of 956 spec texts flat.
- Two front-end paths (borrowed bytes against preprocessed copies) rely on each pass's detector firing exactly when the pass would change a byte. The prototype's tag-attribute detector is conservative (`="` anywhere). The colour-semicolon detector is a port and needs its own differential test against MermaidPreprocessing.
- Hostile inputs: the prototype's look-up of later direction statements and of link `@`s is linear per token, and so is its member check after an inner group ends. Production must restore the binary-searched indexes (word breaks, line ends) and a per-group mark so that MermaidDiagramLimits' 50 kB stays linear. LayeredLayoutWorstCaseTests-style reading tests are needed.
- Unsafe pointers: every read is bounds-checked through a subscript that returns 0 outside the text. A text holding NUL currently falls back to the present reader; production must handle it by length checks instead.
- Lazy labels move decoding cost into layout and accessibility. A consumer that decodes the same label twice pays twice. R7 must decode once per label per layout.
- Thread-local scratch through pthread keys keeps memory per reading thread. Cap retained capacity (for example shrink above 64 kB), and keep the scratch per thread, never shared, for Sendable correctness.
- The façade's public nodes, edges and subgraphs become O(n) per access. External callers that index diagram.nodes[i] in a loop would go quadratic; document the change and offer node(at:).
- Gains are measured under heavy, varying load (4 to 25). Ratios come from alternated pairs, but absolute µs may move ±15 %. The 0.5 µs reading target is an estimate (0.42 to 0.50) built on unbuilt packages R2 and R8; the measured prototype is at 0.64 to 0.72 µs.
- Reading alone cannot deliver the 10x read and layout target for flowcharts: even free reading leaves about 7.1 µs of layout on the examples against a 2.2 µs target. The layout and SVG areas must supply most of it.
- The prototype's style path still parses with String-based FlowchartStyleSyntax and DiagramElementStyle. Its front-matter path still uses the present preprocessing and YAML, so those categories' figures are the present code's cost, not the design's.

Prototype: branch `redesign-prototype-reading` (the copy of main the design measured, with its prototype code and benchmark modes).
