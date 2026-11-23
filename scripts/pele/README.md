# Pele's runner

Runs [Pele](https://github.com/obsidianmd/pele) itself (MIT licensed, `PELE-LICENSE`) on the inputs the package is tested
and timed on, and records what Pele drew and how long it took, so that the package's tests compare with Pele's own output
and its benchmark prints Pele's times beside its own. MIT licensed, as the package is.

Pele's TypeScript does not run in Node (its imports name `.js` files that are `.ts`, and it declares enums and
parameter properties). It runs in [Deno](https://deno.com) 2.9.8 with `--unstable-sloppy-imports`, which reads the `.js`
imports as `.ts` and transpiles the rest. Nothing of Pele's tooling runs: no npm, no package script, no bundler. The runner
imports `src/core.ts` and registers each type from `src/entries/*.ts`; it never imports `src/index.ts` or the registry.
The info diagram imports Pele's `package.json` without an import attribute, which Deno refuses: an import map given on the
command line answers that one import with a module holding the version read from `package.json`. Two of Mermaid's
flowchart specs import vitest's `vi`, answered by `vitest-stand-in.ts`.

Text: Pele measures text with a canvas in a browser and with its table of Arial's advances elsewhere (`src/text/measurer.ts`
`defaultMeasurer`). Deno has `OffscreenCanvas` but no 2D context, so Pele uses the table (`metricsMeasurer`), which the
runner checks and records; the package's tests measure in Arial (`ArialMT`) at Pele's 16 points to match.

## Command

```sh
scripts/pele/run.sh <pele checkout> <output folder> [--corpus] [--compat] [--random-flat] [--bench] [--preprocessing] [--svg] [--svg-of=<corpus>#<index>,…] [--svg-at=<width>] [--max-width=<width>,…]
```

which runs, in Deno's sandbox (read access to the Pele checkout and this folder only, write access to the output folder
only, no network, no subprocess, no environment variable):

```sh
TZ=UTC deno run --unstable-sloppy-imports --no-prompt --import-map="data:application/json,{…}" \
  --allow-read="<pele>,<this folder>" --allow-write="<output>" scripts/pele/pele-runner.ts <pele> <output> [flags]
```

With no flag it does the corpus, compat, random flat, bench and preprocessing runs:

- `--corpus` renders every input of Pele's `tests/corpus` (Mermaid's documentation examples of every type, the same files
  as the package's benchmark resources, and the agent flow reference's 239 inputs) and the generated graphs of Pele's
  benchmark, with `now` at 2014-01-15 12:00 UTC for Gantt charts, and writes `pele-corpus.json`: per input its corpus and
  index, an FNV-1a hash of its text, its type, its SVG's width and height (or the error Pele threw), its `<text>` elements,
  `<g>` groups and the subpaths of its shapes counted by Pele's classes, and the median and 99th percentile of its render
  time over repeated runs (40 ms of runs after one not counted, at least 5).
- `--compat` writes `pele-compat-inputs.json`, every string of `tests/compat`'s spec and test files that is a diagram text,
  and `pele-flowchart-compat.json`, every text Pele's ports of Mermaid's flowchart specs parse with what Pele's flowchart
  database made of it (the specs run with stand-ins for `describe`, `it` and `expect` that check nothing).
- `--random-flat` generates 60 random flat flowcharts (a seeded generator, as the benchmark's mesh: 4 to 33 nodes in the
  four directions, with long, labelled, dotted and backward edges) for the layered layout, and writes their sources
  (`random-flat.json`) and what Pele drew of them, recorded as the corpus is (`pele-random-flat.json`).
- `--svg-of=<corpus>#<index>,…` writes the SVGs Pele draws of those inputs only (a random flat flowchart or a generated
  graph included) to `<output>/svg`; it records nothing.
- `--svg-at=<width>` draws the `--svg-of` inputs as Pele's mount shows them in a container that wide (below), to
  `svg/<corpus>-<index>-at-<width>.svg`.
- `--max-width=<width>,…` writes `pele-narrow.json`: every documentation example (the `-docs` corpora) as Pele's mount
  shows it in a container of each width (`src/mount.ts` `fit`: the drawing without a width when it fits or when drawing
  it for no room at all changes nothing, else the drawing for that width, `maxWidth`), recorded as the corpus is with
  `narrowed` saying which drawing it is, untimed. It runs only when asked for; the package keeps the run at 280, 390 and
  600 points for `PeleNarrowDifferentialTests`.
- `--bench` reproduces Pele's `scripts/bench.mjs` (its five cases: the 114 flowchart examples, a tree and a mesh of 50 and
  of 500 nodes, generated with the same seed; each case timed whole, one run not counted, then runs until 300 ms are
  spent, at least 5 and at most 2,000) and times each type's documentation examples the same way, and writes
  `pele-bench.json` with the median per case and the median and 99th percentile per diagram.
- `--preprocessing` writes `pele-preprocessing.json` (`preprocessing-recorder.ts`): what Pele's own YAML reader
  (`src/util/yaml.ts`) makes of 52 texts (its own tests' texts, then front matter and node data written in the ways those
  leave out), what its preprocessing (`src/preprocess.ts`, then `encodeEntities`) makes of 33 diagram texts
  (directives, tags' attributes, line breaks, front matter, colour semicolons): the text left, the title and the configuration, or the error; and the
  moment JavaScript's `new Date(text)` reads for 48 texts a Gantt chart's start may fall back to.
- `--svg` writes the SVG Pele draws for each documentation example to `svg/<corpus>-<index>.svg` in the output folder
  (refused inputs have none), untimed, to compare a drawing with the package's by eye; it runs only when asked for.

The package keeps `pele-corpus.json`, `pele-narrow.json`, `pele-bench.json`, `pele-compat-inputs.json`, `pele-flowchart-compat.json`,
`random-flat.json`, `pele-random-flat.json` and `pele-preprocessing.json` in
`Sources/MermaidDiagramsBenchmark/Resources`; run the benchmark part on a quiet machine, then
`swift run -c release MermaidDiagramsBenchmark --pele-comparison` on the same machine.
