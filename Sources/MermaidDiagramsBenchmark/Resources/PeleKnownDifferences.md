# Known differences from Pele

`PeleDifferentialTests` prepares every input Pele's runner drew (`pele-corpus.json`: Mermaid's documentation examples of
every type, Pele's 239 agent flow reference inputs and the generated graphs of Pele's benchmark) with text measured in
Arial, as Pele measures it outside a browser, and compares the scene with what Pele drew. An input differs when one side
refuses it and the other draws it (`refused`), when its page differs in `width` or `height` by more than 2 points or 1 %
(see `PeleComparison.isWithinTolerance`), when it holds another number of texts (`texts`: Pele's `<text>` elements and
spans of a class of their own, the scene's texts), or, where Pele draws `pele-edge` parts, when the edges' subpaths
differ in number (`edges`). Every input that differs is listed here with why; the tests fail when an input differs and is
not listed, or is listed and does not differ as listed. The reasons were found by reading both codes and comparing the
drawings.

## Reasons

| Reason | What differs, and where |
|---|---|
| info-version | The info diagram prints the package's name and version (`MermaidDiagrams v0.3.0`) where Pele prints its own (`Pele v1.13.0`, info/render.ts): intended. |
| nothing-to-draw | The package refuses a diagram that declares nothing drawn (`MermaidDiagramPreparationFailure.nothingToDraw`), where Pele draws an empty page: intended. |
| repeated-commit | A Git graph naming a commit id twice is refused (`duplicateCommitIdentifier`), where Pele, as Mermaid, warns and keeps the later commit in the earlier one's place (git/db.ts `add`), so that the graph loses a commit: intended (`GitGraphDiagramBuilder.refuseTakenIdentifier`). |
| drawing-limit | Pele draws the 500-node mesh 22,433 points wide; the package refuses a drawing longer than `MermaidDiagramLimits.maximumDrawingSideLength` (20,000 points): intended. |
| blank-text | A label of a space only (a block arrow's `[" "]`) is written by Pele as a `<text>` element; the scene writes no blank text. Nothing visible differs. |
| text-per-line | Pele writes an event model's data as one `<text>` of left-aligned `<tspan>` lines; a scene text is one centred block, so each line is a text of its own. Nothing visible differs. |
| outlined-text | Pele draws an outlined text (a Sankey diagram's `labelStyle: outlined`, a flowchart group's title over an edge) as two `<text>` elements, the halo and the text; the scene draws one text with its outline (`DiagramSceneText.outline`). Nothing visible differs. |
| journey-parts | A user journey's dashed stems and score line are painted in the scene's `edge` part (`UserJourneyScene`); Pele classes them `pele-stems` and draws one `pele-edge` path. Nothing visible differs. |
| beyond-ascii | Text outside ASCII (emoji, accented letters, ❤) is measured by Pele's table as 580 thousandths of the size (1,000 for wide scripts, text/measurer.ts `metricsMeasurer`) and by the package with Core Text and its fallback fonts. |
| line-height | A label of more than one line (a `<br>`, or wrapped at its width) has its lines 1.5 sizes apart in the package's `DiagramTextBlock`, 1.3 sizes apart in Pele (text/label.ts `WRAPPED_LINE_HEIGHT`, used by `layoutLabel` for every label of more than one line). The plane maps, agent flows, C4 and use case diagrams already set such lines 1.3 apart (`PlaneMapLabel`, `C4TextLabel`, `UseCaseTextLabel`); the other types do not, which makes each extra line 3 to 6 points taller than Pele's. Left as it is here: changing `DiagramTextBlock` changes every multi-line layout of those types. |
| icon-nodes | A flowchart node written `@{ icon: …, form: …, pos: …, h: … }` is drawn by Pele as an icon shape of that height with its label above or below; the package reads those keys and leaves them (`FlowchartNodeSyntax.readAttributes`), drawing a rectangle. |
| icons-in-text | Pele draws `fa:fa-…` in a label as an icon one size wide (text/icons.ts); the package writes the words as text, so the labels are wider. |
| layered-layout | The layered layout places nodes differently: the package's ranking, ordering and positioning (`LayeredRanking`, `LayeredOrdering`, `LayeredPositioning`, `LayeredClusterLayout`) follow Pele's method but are not step-for-step ports of layout/layered.ts and layout/compound.ts (which, for example, balance ranks in eight passes, order with its own sweeps and straighten long edges past labels), so an edge of several ranks, a crossing or a group can end up elsewhere: in `flowchart-docs#92` the target of `---->` sits one rank lower than Pele puts it, in `requirement-docs#4` the two requirements under `test_req` are swapped and the relations cross. |
| self-loop | An agent flow's node with an edge to itself is 18 points narrower than Pele draws it: the loop's reach beside the node differs (not followed further). |
| monospaced-font | Pele's table measures every monospaced character as 600 thousandths of the size (text/measurer.ts `metricsMeasurer`, `Style.Mono`); the package measures in the system's monospaced font (SF Mono, 602 thousandths). A railroad terminal is its text and 24 points rounded up to an even width (railroad/render.ts `even`), so `Hello` at 14 points is 66 points in Pele and 68 in the package: the code is the same, the font is not. |
| muted-spans | Pele writes a PEG predicate's marks (`? ` and ` ?` around `!Keyword`) as muted `<tspan>` pieces of the predicate's one `<text>`; a scene text has one paint, so the package writes three texts. Nothing visible differs. |

## Inputs

| Input | Differs in | Reason | Package minus Pele (width, height) |
|---|---|---|---|
| agentflow-reference#57 | width | layered-layout | +3 +0 |
| agentflow-reference#131 | refused | nothing-to-draw |  |
| agentflow-reference#134 | width, height | self-loop | -18 +4 |
| agentflow-reference#135 | width | self-loop | -18 +2 |
| agentflow-reference#230 | width, height | self-loop | -18 +4 |
| block-docs#25 | texts | blank-text | +0 +0 |
| block-docs#26 | texts | blank-text | +0 +0 |
| class-docs#0 | width | layered-layout | +24 +0 |
| class-docs#21 | height | layered-layout | +0 -5 |
| er-docs#4 | width | beyond-ascii | +5 +0 |
| er-docs#18 | width | layered-layout | -9 -4 |
| eventmodeling-docs#3 | texts | text-per-line | +2 +0 |
| eventmodeling-docs#4 | texts | text-per-line | +2 +0 |
| flowchart-docs#2 | width | beyond-ascii | +5 +0 |
| flowchart-docs#3 | height | line-height | -1 +9 |
| flowchart-docs#6 | height | layered-layout | +0 -5 |
| flowchart-docs#7 | height | layered-layout | +0 -5 |
| flowchart-docs#68 | width, height | icon-nodes | +28 -42 |
| flowchart-docs#69 | width, height | icon-nodes | +28 -42 |
| flowchart-docs#92 | width, height | layered-layout | -29 +25 |
| flowchart-docs#93 | width, height | layered-layout | -29 +25 |
| flowchart-docs#96 | width | layered-layout | +6 +0 |
| flowchart-docs#97 | width | layered-layout | -12 +0 |
| flowchart-docs#98 | width, texts | layered-layout, outlined-text | -20 +0 |
| flowchart-docs#100 | width, height | layered-layout | -126 +84 |
| flowchart-docs#102 | height | line-height | -4 +12 |
| flowchart-docs#111 | width, height | icons-in-text | +206 +24 |
| flowchart-docs#112 | width, height | icons-in-text | +86 +24 |
| gantt-docs#6 | refused | nothing-to-draw |  |
| git-docs#14 | refused | repeated-commit |  |
| info-docs#0 | width | info-version | +90 +0 |
| info-docs#1 | width | info-version | +90 +0 |
| journey-docs#0 | edges | journey-parts | +0 +0 |
| kanban-docs#1 | height | line-height | +0 +6 |
| kanban-docs#2 | height | line-height | +0 +12 |
| mindmap-docs#0 | height | line-height | +0 +6 |
| mindmap-docs#12 | height | beyond-ascii | +3 +9 |
| railroad-docs#2 | width | monospaced-font | +4 +0 |
| railroad-docs#12 | texts | muted-spans | +0 +0 |
| requirement-docs#3 | width | layered-layout | -5 +0 |
| requirement-docs#4 | width | layered-layout | +270 +0 |
| requirement-docs#8 | width | layered-layout | -27 +0 |
| sankey-docs#5 | texts | outlined-text | +0 +0 |
| sequence-docs#23 | height | line-height | +0 +12 |
| sequence-docs#24 | height | line-height | +0 +24 |
| state-docs#0 | width | layered-layout | -3 +0 |
| state-docs#2 | width, height | layered-layout | -12 -8 |
| state-docs#3 | width, height | layered-layout | -12 -8 |
| state-docs#10 | width, height | layered-layout | +16 -8 |
| state-docs#11 | width, height | layered-layout | +24 -24 |
| state-docs#12 | width, height | layered-layout | +16 -16 |
| state-docs#15 | height | line-height | +0 +6 |
| state-docs#16 | width, height | layered-layout | +20 -4 |
| state-docs#17 | width | layered-layout | +8 +0 |
| state-docs#21 | height | layered-layout | -2 -18 |
| timeline-docs#2 | height | line-height | +0 +9 |
| timeline-docs#3 | height | line-height | +0 +30 |
| timeline-docs#4 | height | line-height | +0 +12 |
| timeline-docs#5 | height | line-height | +0 +18 |
| treeview-docs#11 | width | beyond-ascii | +5 +0 |
| usecase-docs#1 | height | layered-layout | +0 +4 |
| usecase-docs#2 | height | layered-layout | +0 +4 |
| usecase-docs#11 | height | layered-layout | +0 -8 |
| usecase-docs#15 | width | layered-layout | -8 +0 |
| usecase-docs#22 | height | layered-layout | -3 +18 |
| bench-generated#0 | width | layered-layout | -368 +0 |
| bench-generated#1 | width, height | layered-layout | -754 -115 |
| bench-generated#2 | refused | drawing-limit |  |
| bench-generated#3 | width, height | layered-layout | -18156 -2556 |

## Mermaid's flowchart specs

`FlowchartSpecDifferentialTests` reads every text Mermaid's flowchart specs parse (`pele-flowchart-compat.json`,
recorded from Pele's ports in `tests/compat/flowchart`) and compares the flowchart with Pele's database, each of Pele's
texts as its label layout draws it (`PeleDrawnText`: broken at `<br>`, `\n` and line breaks, trimmed, a Markdown string
without its emphasis markers). Each text that differs is listed by its index in that file, what differs
(`FlowchartSpecComparison`) and why.

| Reason | What differs |
|---|---|
| yaml-block-scalar | A node's `@{ … }` with a YAML block scalar (`label:`, a vertical bar and indented lines) is read by Pele's YAML reader; the package's attribute reader takes one line per value and refuses it. |
| edge-identifier-and-quotes | `A id1@-->B` (an edge id after a space) and a single-quoted `shape: 'rect'` are read by Pele; the package refuses the line. |

| Text | Differs in | Reason |
|---|---|---|
| 66 | refused | edge-identifier-and-quotes |
| 366 | refused | yaml-block-scalar |

## Compat files without copied texts

`PeleCompatCoverageTests` walks the copy of tests/compat's inputs (`pele-compat-inputs.json`: each spec and test file's
strings that are diagram texts) and looks for each, spaces aside and without its first line, in the package's tests and
resources. A file of which none is found must be listed here with what ports it or why nothing does.

| Compat file | What covers it |
|---|---|
| block/blockDB.spec.ts | Its two "texts" are test names that start with the word `block`; the database's cases are ported in `BlockParserTests` with texts of its own. |
| c4/c4PersonExt.spec.ts | `C4ParserTests` ports `Person_Ext` with texts of its own. |
| mindmap/mindmapDb.getData.test.ts | `MindmapParserTests` ports `getData` with texts of its own. |
| sequence/keywordActors.spec.ts | `SequenceStatementsMermaidSpecTests` ports it with texts of its own. |
| state/stateDiagram-colorIndex.spec.ts | Not ported: it checks the colour slot Mermaid's database gives each composite state, which the package's state diagram model does not hold. |
| treemap/utils.test.ts | `TreemapParserTests` and `TreemapLayoutTests` port its value formatting with texts of their own. |
| usecase-parser/usecase.lexer.spec.ts | `UseCaseLexerTests` ports the lexer's tokens with texts of its own. |
