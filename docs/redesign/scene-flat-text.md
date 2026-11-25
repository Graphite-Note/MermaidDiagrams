# Redesign: scene-flat-text

How a diagram type hands its scene texts measured from source ranges (wave 3, package scene-flat-text).

## The API

All internal to the library.

- `DiagramFlatTextMeasuring.measure(bytes, range, form:measurer:maximumWidth:into:)` and `measureBreakingCharacters` were already there (wave 2). They give a `DiagramMeasuredText`: a few numbers, no reference counting. Its lines go into a `DiagramMeasuredLines` the layout keeps.
- New: `DiagramFlatTextMeasuring.measure(written: String, form:measurer:maximumWidth:into:)` measures a String a model still keeps. Its fast-path lines are copied into the lines' derived bytes (`DiagramMeasuredLines.deriveLines(of:source:)`), so nothing points at the String afterwards.
- New: `DiagramFlatTextMeasuring.measure(_ label: DiagramLabel, measurer:maximumWidth:into:)` measures a label that is already decoded, as its block would be. A layout can then keep every text it measures in one list.
- New: `DiagramMeasuredText.translated(by:)` and `centered(at:)`, which work like `DiagramTextBlock.translated(by:)` and setting a block's center.
- New: `DiagramTextBlock(_ measured:, of lines:, source:)` (Text/DiagramMeasuredTextBlocks.swift) is the bridge. It copies the text's line bytes, plus its run bytes when it has emphasis, once into the thread's text storage, with their widths. It keeps the same record shapes as measuring the decoded label gives: one line without emphasis in the record itself, otherwise line records and run records. So scene text, SVG, painting and accessibility are the same to the byte. Line and run indexes are checked against `lines`, and every byte range against `source` or the derived bytes.
- New: `DiagramSceneBuilder.text(_ text:, of lines:, source:, paint, isBold:isItalic:isMonospaced:rotation:outline:part:)`, `texts(_:of:source:...)` and `title(_:of:source:)` (Scene/DiagramSceneBuilderMeasuredText.swift). `source` defaults to `DiagramMeasuredLines.noSource` for texts whose lines are all derived. Once the scene is made it needs neither `lines` nor `source`.
- New: span overloads. `DiagramTurningRouteDrawing.path(through:segmentsRunVertically:...)` is now generic over any `RandomAccessCollection` indexed from 0, for both the route and its axes. `DiagramRouteDrawing.path(through:flowIsVertical:...)` and `path(through:segmentsRunVertically:...)` have the same kind of overload. `DiagramFillPlacement.placement(of:tips:among:)` takes any collections. A `ScratchSpan<CGPoint>` or `ScratchSpan<Bool>` can be passed directly: the route is copied once, into the list the helper already built.

## How a type moves to it

1. Keep one `DiagramMeasuredLines` per layout, a stored value, and one `DiagramFlatMeasurer` per font.
2. For each text the model keeps as a source range, call `measure(sourceBytes, range, form:...)`. For a text the model keeps as a String, call `measure(written:)`. For one it keeps as a `DiagramLabel`, call `measure(label)`. Keep the `DiagramMeasuredText` in the layout's flat records and place it with `centered(at:)` or `translated(by:)`. Use `.size` and `.frame` where the layout read a block's.
3. In the scene, inside `model.text.withBytes { source in ... }`, call `builder.text(measured, of: layout.lines, source: source, paint, ..., part:)` where the type called `builder.text(block, ...)`.
4. If a public layout type must keep a `DiagramTextBlock` field (Graphite reads `FlowchartLayout` and some drawing parts), make the block at the end with `DiagramTextBlock(measured, of: lines, source:)`.
5. Literal, fitted and `lines:lineWidths:` blocks (packet, treemap, tree view) have no flat measuring yet. They stay blocks and go to `builder.text(block)`. Both kinds of text can be mixed in one scene.

## Proof

- `DiagramSceneMeasuredTextCorpusTests` prepares every input of every corpus twice, regular and narrow. The second time, a debug-only hook (`DiagramSceneTextSubstitution`) swaps each block the builder is given for the same text measured again: from the bytes it was written in when its label was decoded, or from its label when the label was made without decoding. The result has no difference: every digest line (SVG, palette SVG, spoken texts, narrow SVGs) and every scene text's lines are the same across all 825 inputs. In total 33,592 texts were drawn from their written bytes, 9,828 from their labels, and 2,223 were left as blocks (literal or fitted, mostly packet, treemap and tree view). The graph types:

  | Type | From written bytes | From labels | Kept |
  |---|---|---|---|
  | state | 146 | 387 | 0 |
  | class | 225 | 1,474 | 0 |
  | ER | 707 | 963 | 0 |
  | requirement | 658 | 462 | 0 |

  Their names and members are written into labels without decoding, which is why so many come from labels.
- `DiagramSceneMeasuredTextTests` covers, in three faces (16 and 12 pt, which sum exactly, and 12.8 pt, which does not) at three widths:
  - every text the corpora decode, drawn from its bytes and from its block, with every builder option (bold, italic, monospaced, turned, outlined, title, part);
  - 2,000 random texts of markup, breaks, entities and non-ASCII;
  - texts measured from Strings and from labels;
  - eight threads at once;
  - a 40,000-byte line, 2,000 breaks, 900 runs of emphasis, and 3,000 texts across several storages.

  Each case compares the blocks, their record shape, scene lines, styled runs, look and the whole SVG.
- Two mutations were each caught by every test above: a one-line width off by 0.5 above 30 bytes, and runs written without their style.
- `DiagramRouteDrawingSpanTests` checks 3,000 random routes and 2,000 fill placements from spans against arrays, to the bit.

## What it costs and saves

`--measured-scene-text` measures the C4 documentation texts (238 texts at 14 pt), in alternating rounds within one process. It compares taking each text to a scene as today (decode a String label, measure a block, `builder.text(block)`, make the scene) with measuring from the range and calling `builder.text(measured, of:source:)`.

| Room | Blocks | Measured texts | Speedup |
|---|---|---|---|
| unbounded | 80–84 ns a text | 54–58 ns a text | 1.46x |
| 166 pt | 120 ns a text | 70 ns a text | 1.72x |

Measuring alone (`--flat-text`) costs 25 ns (unbounded) or 38 ns (166 pt) flat, against 54 or 100 ns as blocks. So the bridge plus the builder add about 30 ns a text, about 5 ns more than handing over a ready block. That extra is the one copy of the line bytes, which the block path made earlier, when the label was decoded.

So most of the saving comes from measuring on bytes: no String, no label, and no reference to a storage in the layout. The scene step itself costs about the same.

Narrow scenes lay out again and so copy again, as blocks do today.

## The flowchart

The flowchart's usual labels were already flat end to end. A `line` reference, which nearly every label is, gets its bytes written once into the thread's text storage, is measured there, and the scene keeps that block. Neither the renderer nor the SVG writer makes a String of it.

Measuring those labels with `DiagramFlatTextMeasuring` and the bridge was slower:
- `FlowchartMeasurement` went from 297 to 472 of about 1,720 samples on the documentation examples.
- Read and layout was 0.95x, in five alternating pairs.

It scans bytes the reader has already classified, fills a list of lines, and copies them again. Text with markup goes back and forth through the derived bytes. That path was dropped.

What the flowchart keeps (Flowchart/FlowchartTextMeasuring.swift): a `plain` or `markdown` label in the text read is decoded from its bytes (`label(fromUTF8:)`), with no String. The effect is neutral within noise: 0.997x read and layout, 1.00x prepared with SVG, six alternating pairs at load 8 to 13. The sampled measurement went from 297 of 1,722 samples to 288 of 1,697.

## Not done

- No type layout outside the flowchart uses measured texts yet. That is the type packages' work, on this API.
- No flat literal, fitting or `lines:lineWidths:` measuring.
- The builder's middle copy of each run's elements (drawing lane, run lane, record buffers, storage) and scene destruction (about 8% of a flowchart scene) are not started.
