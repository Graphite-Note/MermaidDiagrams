# Known differences from Pele

`PeleDifferentialTests` prepares every input Pele's runner drew (`pele-corpus.json`: Mermaid's documentation examples of
every type, Pele's 239 agent flow reference inputs and the generated graphs of Pele's benchmark; `pele-random-flat.json`:
the runner's 60 random flat flowcharts, `random-flat`) with text measured in
Arial, as Pele measures it outside a browser, and compares the scene with what Pele drew. An input differs when one side
refuses it and the other draws it (`refused`), when its page differs in `width` or `height` by more than 2 points or 1 %
(see `PeleComparison.isWithinTolerance`), when it holds another number of texts (`texts`: Pele's `<text>` elements and
spans of a class of their own, the scene's texts), or, where Pele draws `pele-edge` parts, when the edges' subpaths
differ in number (`edges`). Every input that differs is listed here with why; the tests fail when an input differs and is
not listed, or is listed and does not differ as listed. The reasons were found by reading both codes and comparing the
drawings; those marked `not-traced` were not followed to their cause.

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
| bold-text | Text set bold by a class (`classDef … font-weight:bold`) or by Markdown's `**…**` is measured by Pele with its table's bold advances (text/measurer.ts), wider than the regular ones; the package measures these texts in the regular face (a state's or a requirement's class, a requirement's field or a note in Markdown), so the box is a few points narrower, or its text does not wrap at 200 points where Pele's does (state-docs#21: two lines, 18 points taller). |
| icon-nodes | A flowchart node written `@{ icon: …, form: …, pos: …, h: … }` is drawn by Pele as an icon shape of that height with its label above or below; the package reads those keys and leaves them (`FlowchartNodeSyntax.readAttributes`), drawing a rectangle. |
| icons-in-text | Pele draws `fa:fa-…` in a label as an icon one size wide (text/icons.ts); the package writes the words as text, so the labels are wider. |
| not-traced | Not followed to its cause in this pass. |

## Inputs

| Input | Differs in | Reason | Package minus Pele (width, height) |
|---|---|---|---|
| agentflow-reference#131 | refused | nothing-to-draw |  |
| block-docs#25 | texts | blank-text | +0 +0 |
| block-docs#26 | texts | blank-text | +0 +0 |
| er-docs#4 | width | beyond-ascii | +5 +0 |
| eventmodeling-docs#3 | texts | text-per-line | +2 +0 |
| eventmodeling-docs#4 | texts | text-per-line | +2 +0 |
| flowchart-docs#2 | width | beyond-ascii | +5 +0 |
| flowchart-docs#3 | height | not-traced | -1 +9 |
| flowchart-docs#68 | width, height | icon-nodes | +28 -42 |
| flowchart-docs#69 | width, height | icon-nodes | +28 -42 |
| flowchart-docs#98 | texts | outlined-text | +0 +0 |
| flowchart-docs#102 | height | not-traced | -4 +12 |
| flowchart-docs#111 | width, height | icons-in-text | +206 +24 |
| flowchart-docs#112 | width, height | icons-in-text | +86 +24 |
| gantt-docs#6 | refused | nothing-to-draw |  |
| git-docs#12 | width, height | not-traced | +56 -12 |
| git-docs#14 | refused | repeated-commit |  |
| info-docs#0 | width | info-version | +90 +0 |
| info-docs#1 | width | info-version | +90 +0 |
| journey-docs#0 | edges | journey-parts | +0 +0 |
| kanban-docs#1 | height | line-height | +0 +6 |
| kanban-docs#2 | height | line-height | +0 +12 |
| mindmap-docs#0 | height | line-height | +0 +6 |
| mindmap-docs#12 | height | beyond-ascii | +3 +9 |
| railroad-docs#2 | width | not-traced | +4 +0 |
| railroad-docs#12 | texts | not-traced | +0 +0 |
| requirement-docs#3 | width | bold-text | -5 +0 |
| requirement-docs#8 | width | bold-text | -27 +0 |
| sankey-docs#5 | texts | outlined-text | +0 +0 |
| sequence-docs#23 | height | line-height | +0 +12 |
| sequence-docs#24 | height | line-height | +0 +24 |
| sequence-docs#29 | width | not-traced | -5 +0 |
| sequence-docs#30 | width | not-traced | -5 +0 |
| state-docs#15 | height | line-height | +0 +6 |
| state-docs#21 | height | bold-text | -2 -18 |
| timeline-docs#2 | height | line-height | +0 +9 |
| timeline-docs#3 | height | line-height | +0 +30 |
| timeline-docs#4 | height | line-height | +0 +12 |
| timeline-docs#5 | height | line-height | +0 +18 |
| treeview-docs#11 | width | beyond-ascii | +5 +0 |
| usecase-docs#15 | width | bold-text | -8 +0 |
| bench-generated#2 | refused | drawing-limit |  |
| bench-generated#3 | refused | drawing-limit |  |

## Mermaid's flowchart specs

`FlowchartSpecDifferentialTests` reads every text Mermaid's flowchart specs parse (`pele-flowchart-compat.json`,
recorded from Pele's ports in `tests/compat/flowchart`) and compares the flowchart with Pele's database. Each text that
differs is listed by its index in that file, what differs (`FlowchartSpecComparison`) and why.

| Reason | What differs |
|---|---|
| identifier-characters | Pele's identifiers run over every token its grammar's `idString` takes (letters, digits, `!"#$%&'*+.` `` ` `` `?\_/`, `-` not before `>`, `-` or `.`, `,`, `:`, `&`, `*`, flowchart/parser.ts `ID` and lexer.ts `NODE_CHAR`), so `a.graph.node`, `node-graph`, `#node` and `odd-` are identifiers; the package reads letters, digits, `_`, characters beyond ASCII and a `-` before one of them (`MermaidTextCursor.readIdentifier`) and refuses the rest. |
| text-brackets | Pele refuses `(`, `)` and `"` inside a square or round node's text (`A[This is a () in text]`), as Mermaid's specs expect; the package reads them as text. |
| yaml-block-scalar | A node's `@{ … }` with a YAML block scalar (`label:`, a vertical bar and indented lines) is read by Pele's YAML reader; the package's attribute reader takes one line per value and refuses it. |
| edge-identifier-and-quotes | `A id1@-->B` (an edge id after a space) and a single-quoted `shape: 'rect'` are read by Pele; the package refuses the line. |
| markdown-text | A Markdown string's label: the package keeps its text as styled spans and the comparison strips Pele's marks, so a string with a line break or `*` inside words differs in what is compared, not in what is drawn (not traced further). |
| spaces-in-text | `Chimpansen hoppar åäö  <br> -  ÅÄÖ`: the node's text differs in its spaces around the line break (not traced further). |
| trailing-spaces-group | `subgraph myTitle   ` (spaces before the line's end) is a title without an identifier for Pele (`subGraph0` titled `myTitle`); the package takes `myTitle` as the identifier. |

| Text | Differs in | Reason |
|---|---|---|
| 66 | refused | edge-identifier-and-quotes |
| 345 | node texts, edge texts | markdown-text |
| 346 | node texts, edge texts | markdown-text |
| 366 | refused | yaml-block-scalar |
| 417 | refused | identifier-characters |
| 418 | refused | identifier-characters |
| 419 | refused | identifier-characters |
| 420 | refused | identifier-characters |
| 421 | refused | identifier-characters |
| 422 | refused | identifier-characters |
| 423 | refused | identifier-characters |
| 424 | refused | identifier-characters |
| 425 | refused | identifier-characters |
| 426 | refused | identifier-characters |
| 427 | refused | identifier-characters |
| 428 | refused | identifier-characters |
| 429 | refused | identifier-characters |
| 430 | refused | identifier-characters |
| 431 | refused | identifier-characters |
| 432 | refused | identifier-characters |
| 433 | refused | identifier-characters |
| 434 | refused | identifier-characters |
| 453 | refused | identifier-characters |
| 454 | refused | identifier-characters |
| 455 | refused | identifier-characters |
| 456 | refused | identifier-characters |
| 457 | refused | identifier-characters |
| 458 | refused | identifier-characters |
| 459 | refused | identifier-characters |
| 460 | refused | identifier-characters |
| 461 | refused | identifier-characters |
| 462 | refused | identifier-characters |
| 463 | refused | identifier-characters |
| 464 | refused | identifier-characters |
| 465 | refused | identifier-characters |
| 466 | refused | identifier-characters |
| 467 | refused | identifier-characters |
| 468 | refused | identifier-characters |
| 469 | refused | identifier-characters |
| 470 | refused | identifier-characters |
| 485 | refused | identifier-characters |
| 486 | refused | identifier-characters |
| 487 | refused | identifier-characters |
| 488 | refused | identifier-characters |
| 489 | refused | identifier-characters |
| 490 | refused | identifier-characters |
| 492 | refused | identifier-characters |
| 493 | refused | identifier-characters |
| 494 | refused | identifier-characters |
| 495 | refused | identifier-characters |
| 496 | refused | identifier-characters |
| 498 | refused | identifier-characters |
| 499 | refused | identifier-characters |
| 501 | refused | identifier-characters |
| 502 | refused | identifier-characters |
| 504 | refused | identifier-characters |
| 505 | refused | identifier-characters |
| 506 | refused | identifier-characters |
| 507 | refused | identifier-characters |
| 508 | refused | identifier-characters |
| 510 | refused | identifier-characters |
| 511 | refused | identifier-characters |
| 513 | refused | identifier-characters |
| 514 | refused | identifier-characters |
| 516 | refused | identifier-characters |
| 517 | refused | identifier-characters |
| 518 | refused | identifier-characters |
| 519 | refused | identifier-characters |
| 520 | refused | identifier-characters |
| 522 | refused | identifier-characters |
| 523 | refused | identifier-characters |
| 865 | refused | identifier-characters |
| 869 | node texts | spaces-in-text |
| 886 | refused | text-brackets |
| 887 | refused | text-brackets |
| 888 | refused | text-brackets |
| 890 | refused | text-brackets |
| 946 | groups | trailing-spaces-group |

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
