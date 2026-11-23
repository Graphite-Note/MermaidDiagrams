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
drawings.

## Reasons

| Reason | What differs, and where |
|---|---|
| info-version | The info diagram prints the package's name and version (`MermaidDiagrams v0.3.0`) where Pele prints its own (`Pele v1.13.0`, info/render.ts): intended. |
| nothing-to-draw | The package refuses a diagram that declares nothing drawn (`MermaidDiagramPreparationFailure.nothingToDraw`), where Pele draws an empty page: intended. |
| repeated-commit | A Git graph naming a commit id twice is refused (`duplicateCommitIdentifier`), where Pele, as Mermaid, warns and keeps the later commit in the earlier one's place (git/db.ts `add`), so that the graph loses a commit: intended (`GitGraphDiagramBuilder.refuseTakenIdentifier`). |
| drawing-limit | Pele draws the 500-node mesh 22,433 points wide; the package refuses a drawing longer than `MermaidDiagramLimits.maximumDrawingSideLength` (20,000 points): intended. |
| blank-text | A label with nothing to show (a block arrow's `[" "]`, or a flowchart node's `(fa:fa-spinner)` whose icon Pele leaves out, having none to draw) is written by Pele as a `<text>` element; the scene writes no blank text. Nothing visible differs. |
| text-per-line | Pele writes an event model's data as one `<text>` of left-aligned `<tspan>` lines; a scene text is one centred block, so each line is a text of its own. Nothing visible differs. |
| outlined-text | Pele draws an outlined text (a Sankey diagram's `labelStyle: outlined`, a flowchart group's title over an edge) as two `<text>` elements, the halo and the text; the scene draws one text with its outline (`DiagramSceneText.outline`). Nothing visible differs. |
| journey-parts | A user journey's dashed stems and score line are painted in the scene's `edge` part (`UserJourneyScene`); Pele classes them `pele-stems` and draws one `pele-edge` path. Nothing visible differs. |
| beyond-ascii | Text outside ASCII (emoji, accented letters, ❤) is measured by Pele's table as 580 thousandths of the size (1,000 for wide scripts, text/measurer.ts `metricsMeasurer`) and by the package with Core Text and its fallback fonts. |
| bold-text | Text a class sets bold (`classDef … font-weight:bold`) is measured by Pele with its table's bold advances (text/measurer.ts); the package measures a state's or a requirement's text a class sets bold in the regular face, so the box is narrower (requirement-docs#8, 27 points), or its name does not wrap at 200 points where Pele's does (state-docs#21: two lines, 18 points taller). |
| monospaced-font | Pele's table measures every monospaced character as 600 thousandths of the size (text/measurer.ts `metricsMeasurer`, `Style.Mono`); the package measures in the system's monospaced font (SF Mono, 602 thousandths). A railroad terminal is its text and 24 points rounded up to an even width (railroad/render.ts `even`), so `Hello` at 14 points is 66 points in Pele and 68 in the package: the code is the same, the font is not. |
| muted-spans | Pele writes a PEG predicate's marks (`? ` and ` ?` around `!Keyword`) as muted `<tspan>` pieces of the predicate's one `<text>`; a scene text has one paint, so the package writes three texts. Nothing visible differs. |

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
| flowchart-docs#98 | texts | outlined-text | +0 +0 |
| flowchart-docs#111 | texts | blank-text | +0 +0 |
| gantt-docs#6 | refused | nothing-to-draw |  |
| git-docs#14 | refused | repeated-commit |  |
| info-docs#0 | width | info-version | +90 +0 |
| info-docs#1 | width | info-version | +90 +0 |
| journey-docs#0 | edges | journey-parts | +0 +0 |
| railroad-docs#2 | width | monospaced-font | +4 +0 |
| railroad-docs#12 | texts | muted-spans | +0 +0 |
| requirement-docs#8 | width | bold-text | -27 +0 |
| sankey-docs#5 | texts | outlined-text | +0 +0 |
| state-docs#21 | height | bold-text | -2 -18 |
| treeview-docs#11 | width | beyond-ascii | +5 +0 |
| bench-generated#2 | refused | drawing-limit |  |
| bench-generated#3 | refused | drawing-limit |  |

## Mermaid's flowchart specs

`FlowchartSpecDifferentialTests` reads every text Mermaid's flowchart specs parse (`pele-flowchart-compat.json`,
recorded from Pele's ports in `tests/compat/flowchart`) and compares the flowchart with Pele's database, each of Pele's
texts as its label layout draws it (`PeleDrawnText`: broken at `<br>`, `\n` and line breaks, trimmed, a Markdown string
without its emphasis markers). Each text that differs is listed by its index in that file, what differs
(`FlowchartSpecComparison`) and why, in a table of reasons and a table of texts (`| Text | Differs in | Reason |`).
Every text is read as Pele reads it today: none is listed.

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
