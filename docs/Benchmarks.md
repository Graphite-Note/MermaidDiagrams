# Benchmarks

`swift run -c release MermaidDiagramsBenchmark` times reading, layout, the drawing parts and painting, with the median and 99th percentile per diagram, and the heap a layout holds, on the inputs of Pele's benchmark (`FlowchartCorpus`; the documentation examples are its resources), then mindmaps (`MindmapBenchmark` on `MindmapCorpus`), timelines (`TimelineBenchmark` on `TimelineCorpus`), Git graphs (`GitGraphBenchmark` on `GitGraphCorpus`), user journeys (`UserJourneyBenchmark` on `UserJourneyCorpus`), quadrant charts (`QuadrantChartBenchmark` on `QuadrantChartCorpus`), XY charts (`XYChartBenchmark` on `XYChartCorpus`), Sankey diagrams (`SankeyBenchmark` on `SankeyCorpus`), Venn diagrams (`VennBenchmark` on `VennCorpus`), Cynefin frameworks (`CynefinBenchmark` on `CynefinCorpus`), Wardley maps (`WardleyMapBenchmark` on `WardleyMapCorpus`), event models (`EventModelBenchmark` on `EventModelCorpus`), railroad diagrams (`RailroadBenchmark` on `RailroadCorpus`), C4 diagrams (`C4Benchmark` on `C4Corpus`), requirement and swimlane diagrams (`LayeredDiagramBenchmarks` on `RequirementCorpus` and `SwimlaneCorpus`), use case diagrams (`UseCaseBenchmark` on `UseCaseCorpus`), kanban boards, tree views and Ishikawa diagrams (`OutlineDiagramBenchmarks` on `KanbanCorpus`, `TreeViewCorpus` and `IshikawaCorpus`), info diagrams, packet diagrams, radar charts and treemaps (`InfoDiagramBenchmark`, `PacketDiagramBenchmark`, `RadarChartBenchmark` and `TreemapBenchmark` on their corpora), among the other types, and last, per type, what its scene adds to reading and laying out, the whole preparation, the scene's painting and its SVG (`DiagramSceneBenchmark`), then what a narrow column adds to the layouts of the types that narrow, and what a start date in JavaScript's legacy forms costs a Gantt chart (`NarrowColumnBenchmark`). Graphite records the results in its `Docs/Coverage.md`.
`BlockBenchmark` times block diagrams on `BlockCorpus` (Mermaid's examples and generated grids). `ArchitectureBenchmark` times architecture diagrams on `ArchitectureCorpus`. `AgentFlowBenchmark` times agent flows on `AgentFlowCorpus` (Mermaid's examples and generated flows).

## Beside Pele

`PeleComparisonBenchmark`, last in the run (alone with `--pele-comparison`), times the package on the inputs of Pele's own benchmark (`scripts/bench.mjs`: Mermaid's 114 flowchart examples, trees and meshes of 50 and 500 nodes from the same generators and seed) and on each type's documentation examples, counted as Pele's benchmark counts them: every input of a case per run, refused ones included, one run not counted, then runs until 300 ms are spent (at least 5, at most 2,000), the median and the 99th percentile divided by the inputs. Beside each it prints Pele's time on the same inputs, measured by `scripts/pele/run.sh --bench` on the same Mac and kept in `pele-bench.json`: Pele's `render`, which reads, lays out and writes the SVG, in Deno 2.9.8 (V8), measuring text with its table of Arial's advances. The package's two times are reading and layout (the plan's "parse + layout"), and the whole preparation with its SVG (read, lay out, make the scene and what a screen reader says, write the SVG), which is what Pele's `render` does.

On an iPad or an iPhone the same comparison runs as an XCTest beside Pele itself on the device
(`PeleJavaScriptCoreComparison`, in `MermaidDiagramsDeviceBenchmarkTests`, skipped unless
`MERMAID_DIAGRAMS_DEVICE_BENCHMARK` is set, which the shared scheme `MermaidDiagramsDeviceBenchmark` sets; that scheme
tests that target alone, in Release, without code coverage):

```sh
xcodebuild test -scheme MermaidDiagramsDeviceBenchmark -configuration Release -enableCodeCoverage NO \
  -destination id=<device> -allowProvisioningUpdates DEVELOPMENT_TEAM=<team>
```

The device must be unlocked. Pele runs from `pele-bundle.js`, its modules joined into one plain script by
`scripts/pele/bundle.sh` (see `scripts/pele/README.md`), twice: in a JSContext (JavaScriptCore in the test's own process,
which iOS lets run only its interpreters, so Pele interpreted) and in a WebKit page (a WKWebView in a window of the test's
app, whose JavaScriptCore compiles to machine code: Pele as Obsidian runs it there). In both it measures text with its
table of Arial's advances, as in Deno (the page's canvases give it no context); the JSContext gets a URL class for Pele's
links (`javascriptcore-url.js`), which a page has. Before timing, each draws every documentation example and the test
fails for one drawn otherwise than Pele drew it in Deno (`pele-bundle-drawings.json`: type, page and a hash of the SVG),
but for the Gantt charts in the page when the device's time zone is not UTC (Pele writes their dates in the page's time
zone, which an app cannot set). Each case is then timed as above, Pele in the JSContext with the same loop, and in the page
with samples that each repeat the case for at least 50 ms (the page's clock moves by whole milliseconds) over 3 s, so its
99th percentile is of those means and smoother than one run's; the
speed-up and the targets are against Pele in the page. With `TEST_RUNNER_MERMAID_DIAGRAMS_CHECK_TARGETS=1` before
`xcodebuild`, each missed target fails the test, as `--check-targets` fails the Mac's run. On the Mac,
`--pele-javascriptcore` runs the same comparison beside Pele in a JSContext of the benchmark's own process (no page: the
benchmark is a tool with no app); macOS gives that process JavaScriptCore's compilers only when it is signed with the
`com.apple.security.cs.allow-jit` entitlement (`codesign -f -s - --entitlements <plist> <binary>`), and interprets Pele
otherwise.

`--readme-pictures <folder>` paints the Gallery's pictures and prints the text of [the gallery](Gallery.md), and with `--diagram <text file> <name>` after the folder paints that one diagram as `<name>-light.png` and `<name>-dark.png` and prints its `<picture>` element (the README's speed chart is `docs/pictures/speed.mmd`, drawn with `--readme-pictures docs/pictures --diagram docs/pictures/speed.mmd speed`). `--profile <case> [reading|preparation|narrow|painting] [seconds]` repeats one case (a name of Pele's benchmark, `tree: 500 nodes`, or a corpus, `treemap-docs`) for a sampler such as `sample(1)` or Instruments' Time Profiler (`ProfilingLoop`): `preparation` prepares with the SVG and no narrow scene, as the comparison times it, `narrow` with the narrow scene for Graphite's narrowest column, read so that it is laid out, and no SVG, as Graphite prepares a diagram it shows in a narrow column. `--output-digest [folder]` prepares every input Pele's runner drew (its 765 corpus inputs and the 60 random flat flowcharts) as Graphite prepares it and prints one line per input with a digest (64-bit FNV-1a) of its regular SVG with Pele's variables and with a fixed palette, what a screen reader says, and its narrow scene's SVG at 280, 390 and 600 points, or of why it is refused, then a digest of every line (`OutputDigest`); with a folder it writes the SVGs there too. A change meant to leave the output as it is (a speed change) is checked by running it on both builds and comparing the output with `diff`. `--layout-memory` prints, per case of the comparison with Pele, the heap one layout holds and the heap one preparation holds without its narrow scene, with it not read yet and with it read, median and largest per diagram (`LayoutMemoryBenchmark`; Graphite's target is 64 kB of layout data for a typical diagram); `--scenes` runs only `DiagramSceneBenchmark`. `--check-targets` exits with status 1 after a line `missed target: …` for each median that misses a target of Graphite's plan (`Docs/Native-diagrams-todo.md`, Performance targets) on documentation examples: reading and layout at most 30 µs a diagram, and ten times faster than Pele on the same inputs. The default run only reports.

Measured 2026-11-27 for 0.8.0 on an Apple M5 Max (128 GB, macOS 27.2.1), release builds (`swift build -c release`), with other builds running on the machine (load average 3.5 to 4.3). Three rounds each ran 0.7.0's comparison, 0.8.0's and Pele 1.13.0's own benchmark (`scripts/pele/run.sh --bench`) one after the other on the same inputs, and each figure is the median of the three rounds. Per diagram, median / 99th percentile in µs, and each speed-up is Pele's or 0.7.0's median divided by 0.8.0's:

| Inputs | Diagrams | Pele 1.13.0, render | Package, read and layout | Against Pele | Against 0.7.0 | Package, prepared with SVG | Against Pele | Against 0.7.0 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| docs: all examples | 114 | 21.23 / 53.34 | 2.23 / 2.66 | 9.5× | 4.53× | 3.82 / 4.19 | 5.6× | 4.07× |
| tree: 50 nodes | 1 | 150.62 / 242.54 | 22.46 / 25.38 | 6.7× | 4.61× | 38.33 / 41.38 | 3.9× | 4.47× |
| mesh: 50 nodes, 20 extra labelled edges | 1 | 399.50 / 904.83 | 118.29 / 139.71 | 3.4× | 2.19× | 137.17 / 161.08 | 2.9× | 2.51× |
| tree: 500 nodes | 1 | 1488.79 / 2335.33 | 241.29 / 277.04 | 6.2× | 4.06× | 338.88 / 368.25 | 4.4× | 4.13× |
| mesh: 500 nodes, 200 extra labelled edges | 1 | 5562.83 / 7897.54 | 1998.58 / 2188.29 | 2.8× | 1.69× | 2145.58 / 2399.83 | 2.6× | 1.84× |
| agentflow-docs | 12 | 44.35 / 105.02 | 10.24 / 12.53 | 4.3× | 3.45× | 13.97 / 16.45 | 3.2× | 3.20× |
| architecture-docs | 6 | 26.37 / 45.49 | 10.90 / 12.76 | 2.4× | 1.14× | 15.42 / 17.87 | 1.7× | 1.90× |
| block-docs | 30 | 5.75 / 10.74 | 3.14 / 3.87 | 1.8× | 2.30× | 4.86 / 5.75 | 1.2× | 2.53× |
| c4-docs | 6 | 73.40 / 125.83 | 16.18 / 18.90 | 4.5× | 2.88× | 26.83 / 30.85 | 2.7× | 2.90× |
| class-docs | 38 | 22.61 / 43.47 | 3.75 / 4.59 | 6.0× | 3.11× | 6.59 / 7.42 | 3.4× | 3.19× |
| cynefin-docs | 3 | 22.86 / 42.83 | 6.86 / 7.90 | 3.3× | 1.82× | 11.49 / 12.68 | 2.0× | 2.28× |
| er-docs | 25 | 23.87 / 42.31 | 3.27 / 3.96 | 7.3× | 5.35× | 7.14 / 8.15 | 3.3× | 4.25× |
| eventmodeling-docs | 12 | 13.15 / 20.68 | 4.67 / 5.43 | 2.8× | 2.08× | 8.44 / 9.67 | 1.6× | 2.53× |
| flowchart-docs | 114 | 17.21 / 24.33 | 2.21 / 2.66 | 7.8× | 4.65× | 3.77 / 4.13 | 4.6× | 4.02× |
| gantt-docs | 11 | 23.40 / 37.68 | 10.79 / 13.33 | 2.2× | 1.46× | 15.05 / 17.50 | 1.6× | 1.79× |
| git-docs | 35 | 24.27 / 36.65 | 8.01 / 9.02 | 3.0× | 1.40× | 15.07 / 16.35 | 1.6× | 2.08× |
| info-docs | 2 | 1.10 / 1.81 | 0.21 / 0.25 | 5.3× | 1.57× | 0.54 / 0.69 | 2.0× | 1.96× |
| ishikawa-docs | 1 | 11.50 / 32.83 | 2.67 / 2.96 | 4.3× | 3.84× | 6.62 / 7.42 | 1.7× | 3.49× |
| journey-docs | 1 | 9.38 / 22.42 | 2.08 / 2.38 | 4.5× | 3.14× | 7.42 / 8.17 | 1.3× | 3.57× |
| kanban-docs | 3 | 16.85 / 29.11 | 4.24 / 4.93 | 4.0× | 1.97× | 7.47 / 8.29 | 2.3× | 2.18× |
| mindmap-docs | 13 | 6.17 / 11.90 | 1.97 / 2.29 | 3.1× | 1.60× | 3.59 / 4.04 | 1.7× | 2.26× |
| packet-docs | 4 | 9.27 / 14.81 | 2.94 / 3.41 | 3.2× | 1.97× | 5.72 / 6.41 | 1.6× | 2.53× |
| pie-docs | 2 | 9.10 / 17.52 | 2.62 / 2.92 | 3.5× | 1.60× | 4.85 / 5.44 | 1.9× | 2.46× |
| quadrant-docs | 3 | 13.00 / 36.20 | 5.10 / 5.96 | 2.5× | 1.98× | 7.35 / 8.58 | 1.8× | 2.57× |
| radar-docs | 3 | 17.40 / 31.65 | 3.47 / 4.04 | 5.0× | 2.23× | 6.47 / 7.15 | 2.7× | 2.54× |
| railroad-docs | 14 | 15.47 / 21.89 | 7.51 / 9.00 | 2.1× | 1.90× | 12.67 / 14.74 | 1.2× | 2.59× |
| requirement-docs | 9 | 27.98 / 50.55 | 4.01 / 4.87 | 7.0× | 5.19× | 8.11 / 9.21 | 3.4× | 4.28× |
| sankey-docs | 8 | 36.01 / 74.47 | 13.05 / 16.06 | 2.8× | 1.62× | 18.57 / 21.53 | 1.9× | 2.01× |
| sequence-docs | 38 | 10.13 / 18.45 | 4.37 / 5.16 | 2.3× | 1.93× | 7.75 / 8.69 | 1.3× | 2.43× |
| state-docs | 22 | 39.38 / 88.16 | 4.57 / 5.68 | 8.6× | 3.91× | 7.86 / 8.95 | 5.0× | 3.57× |
| swimlane-docs | 13 | 34.43 / 74.13 | 6.80 / 8.46 | 5.1× | 4.85× | 10.44 / 12.09 | 3.3× | 4.39× |
| timeline-docs | 14 | 13.73 / 21.25 | 2.35 / 2.54 | 5.8× | 3.35× | 8.76 / 10.14 | 1.6× | 2.98× |
| treemap-docs | 8 | 16.19 / 25.32 | 6.02 / 6.77 | 2.7× | 1.57× | 9.71 / 10.65 | 1.7× | 2.07× |
| treeview-docs | 13 | 9.18 / 15.24 | 3.19 / 3.52 | 2.9× | 2.24× | 4.42 / 4.87 | 2.1× | 2.81× |
| usecase-docs | 24 | 46.69 / 95.61 | 12.51 / 15.47 | 3.7× | 2.41× | 15.94 / 17.71 | 2.9× | 2.56× |
| venn-docs | 8 | 90.27 / 116.77 | 14.94 / 17.77 | 6.0× | 1.11× | 15.96 / 19.06 | 5.7× | 1.30× |
| wardley-docs | 19 | 11.65 / 18.98 | 4.72 / 5.70 | 2.5× | 1.93× | 7.66 / 8.88 | 1.5× | 2.09× |
| xychart-docs | 8 | 12.16 / 25.43 | 5.43 / 6.26 | 2.2× | 2.07× | 8.51 / 9.55 | 1.4× | 2.49× |

Against Pele, reading and layout are 1.8 (block diagrams) to 9.5 (Pele's 114 examples) times as fast, and the whole preparation with its SVG 1.2 (block diagrams) to 5.7 (Venn diagrams) times. Every case now prepares with its SVG faster than Pele's `render`, where 27 of the 38 were slower in 0.7.0. Against 0.7.0, reading and layout are 1.1 (Venn) to 5.4 (entity relationship) times as fast, and the preparation with its SVG 1.3 (Venn) to 4.5 (the 50-node tree) times.

What 0.8.0 changed (the plan is `docs/redesign/`): texts are byte ranges and small records of a per-thread text storage instead of Strings, measured and wrapped on their UTF-8 bytes. Every type is read on its text's own bytes into flat records, with names interned as numbers, and the public diagram types are façades over those records. The layered and compound layouts, and each type's layout, run on one reusable scratch arena per thread instead of arrays made per layout. Scenes record their paths into the thread's path lanes instead of making Core Graphics paths, and the SVG writer writes every document into one block of bytes each thread keeps. Each step was checked with `--output-digest` against the build before it, and 0.8.0 gives the same 826 lines as 0.7.0 but the info diagram's version, so every SVG, narrow scene and spoken text is the one 0.7.0 drew.

Graphite's targets (`Docs/Native-diagrams-todo.md`, Performance targets), on this Mac:

- Reading and layout ten times as fast as Pele: missed, though close on the flowchart family. Pele's 114 examples are 9.5 times as fast, state diagrams 8.6, the flowchart corpus 7.8, entity relationship 7.3 and requirement diagrams 7.0. The furthest are block diagrams (1.8), railroad diagrams (2.1), Gantt and XY charts (2.2).
- Reading and layout in at most 30 µs a diagram: met on all 33 documentation corpora. The slowest is C4 at 16.2 µs.
- The whole preparation with its SVG ten times as fast as Pele's `render`: missed. It is 1.2 (block diagrams) to 5.7 (Venn diagrams) times Pele's speed, 5.6 times on Pele's 114 examples. Making the scene, what a screen reader says and the SVG still costs more than reading and laying out for most types.
- At most 64 kB of layout data for a typical diagram (`--layout-memory`): met. Every documentation corpus holds at most 12.7 kB a layout (median, C4) and 22.3 kB (largest, railroad), and Pele's generated 50-node mesh 48.5 kB (65.4 kB in 0.7.0). Only the 500-node tree (180.0 kB) and mesh (611.7 kB) hold more.
- A width change laid out again without reading again, within one frame: met for the one narrow column the package lays out (`narrowestColumnWidth`), which is laid out from the read diagram when it is first read. Reading it added 0.5 µs (state) to 128 µs (Sankey) a diagram on the documentation examples when last measured (main at 3015de9, 2026-11-23), far under a frame's 16 ms. Any other width is drawn by scaling a scene, and the package has no layout for an arbitrary width.

What still costs most, from the redesign's notes: the shared layered and compound layouts (about half of a state diagram's layout), the scene builder, the readers of sequence, railroad, Gantt, kanban, event model, block, XY chart, mindmap, Wardley, Cynefin, architecture, packet, treemap, quadrant, Venn and Git diagrams, which are not yet on flat records of bytes from reading to scene, and the class layout's lists, not yet on the arena.

The tables of 0.7.0 (2026-11-24) and 0.6.1 (2026-11-23) are in this file's history.

Painting is not faster (measured for 0.7.0, 2026-11-24): Core Graphics paints a merged path over the whole of its bounds, so a 500-node tree's scene (49,082 points wide) takes about 0.2 s to paint at two pixels a point and the 500-node mesh about 1 s, nearly all of it in two paths (the edges and the nodes); painting them cut into pieces that share no pixel was tried and changes the edges' smoothing in a few hundred pixels, so it was left out.

Pele in JavaScriptCore on the same Mac (`--pele-javascriptcore`, 2026-11-23, against 0.6.1, load about 3), per diagram, median in µs: compiled (the benchmark signed with `com.apple.security.cs.allow-jit`), JavaScriptCore runs Pele faster than Deno's V8 does; interpreted (the benchmark as `swift build` signs it), it is about ten times slower. Pele's flowchart examples: 15.83 compiled, 158.46 interpreted, against 22.13 in Deno (0.6.1's package 15.63, 0.7.0's 10.68 above); agent flows 31.78 / 334.49 (0.6.1 52.54, 0.7.0 37.13); block diagrams 5.71 / 71.99 (8.41, 7.42); C4 56.72 / 671.99 (71.54, 48.04); requirement diagrams 20.79 / 261.69 (29.66, 21.17); use case diagrams 26.12 / 346.38 (45.75, 31.91); Venn diagrams 44.98 / 648.06 (21.17, 17.17); the 500-node mesh 5,145.58 / 87,741.33 (5,304.42, 3,478.04). Every documentation example was drawn as in Deno.

### In the iOS simulators

Not a device's speed: a simulator runs the iOS app on the Mac's own processor (here the M5 Max), so these numbers say how the package and Pele compare under iOS's frameworks and WebKit, not how fast an iPad or an iPhone is. Measured 2026-11-27 for 0.8.1 (the same code as 0.8.0 for timing) with Xcode 27.2 (27B52), `xcodebuild test -scheme MermaidDiagramsDeviceBenchmark -configuration Release -enableCodeCoverage NO -destination id=<simulator>` (the command above), in a simulator of each made for the run on the iOS 27.2 runtime (24B8117), one after the other. The machine was not quiet: two other Xcode builds ran beside both runs, and the load average was 66 falling to 10 during the iPad's run and 28 to 17 during the iPhone's. Pele and the package are timed case by case in the same process, so each speed-up compares them under the same load, but single cases can be off, as the iPhone's Git graphs prepared with their SVG show (35.85 µs, 99th percentile 246, against 17.65 on the iPad). Every documentation example was drawn by Pele in the JSContext and in the page as in Deno, but the page's Gantt charts, which it writes in the Mac's time zone (UTC+1) and were not compared. Per diagram, median / 99th percentile in µs, and the speed-up is against Pele in the page.

iPad Pro 13-inch (M5) simulator:

| Inputs | Diagrams | Pele in WebKit, render | Pele in a JSContext, render | Package, read and layout | Speed-up | Package, prepared with SVG |
|---|---:|---:|---:|---:|---:|---:|
| docs: all examples | 114 | 12.61 / 18.64 | 17.00 / 56.05 | 2.13 / 2.67 | 5.9× | 3.81 / 4.31 |
| tree: 50 nodes | 1 | 140.62 / 236.33 | 147.79 / 870.83 | 23.79 / 30.62 | 5.9× | 43.21 / 58.12 |
| mesh: 50 nodes, 20 extra labelled edges | 1 | 398.44 / 523.44 | 400.54 / 1503.08 | 115.46 / 140.04 | 3.5× | 147.96 / 176.50 |
| tree: 500 nodes | 1 | 1468.75 / 1578.12 | 1505.96 / 4547.21 | 270.88 / 343.88 | 5.4× | 391.83 / 551.46 |
| mesh: 500 nodes, 200 extra labelled edges | 1 | 6500.00 / 11500.00 | 6283.75 / 12561.62 | 3111.38 / 4566.58 | 2.1× | 3490.75 / 6030.71 |
| agentflow-docs | 12 | 44.92 / 85.29 | 54.93 / 470.92 | 13.48 / 52.40 | 3.3× | 18.99 / 49.09 |
| architecture-docs | 6 | 31.58 / 36.78 | 25.81 / 142.00 | 14.01 / 43.06 | 2.3× | 21.09 / 61.44 |
| block-docs | 30 | 7.16 / 8.85 | 10.10 / 54.39 | 3.86 / 7.32 | 1.9× | 5.90 / 10.71 |
| c4-docs | 6 | 76.82 / 118.49 | 107.78 / 424.55 | 19.25 / 37.85 | 4.0× | 39.40 / 79.91 |
| class-docs | 38 | 20.56 / 24.67 | 25.95 / 153.25 | 4.20 / 10.10 | 4.9× | 8.13 / 20.95 |
| cynefin-docs | 3 | 26.04 / 32.88 | 24.06 / 221.00 | 7.68 / 19.46 | 3.4× | 15.19 / 23.71 |
| er-docs | 25 | 21.25 / 25.31 | 29.59 / 94.85 | 4.18 / 10.11 | 5.1× | 10.69 / 23.09 |
| eventmodeling-docs | 12 | 14.97 / 18.55 | 16.28 / 79.42 | 5.83 / 13.94 | 2.6× | 10.21 / 22.39 |
| flowchart-docs | 114 | 14.80 / 28.23 | 15.57 / 37.16 | 2.69 / 7.87 | 5.5× | 4.52 / 10.23 |
| gantt-docs | 11 | 26.28 / 42.97 | 33.95 / 130.77 | 13.92 / 46.91 | 1.9× | 18.13 / 58.23 |
| git-docs | 35 | 24.11 / 29.91 | 26.76 / 113.68 | 9.03 / 16.03 | 2.7× | 17.65 / 25.70 |
| info-docs | 2 | 0.89 / 1.02 | 1.12 / 3.02 | 0.23 / 0.29 | 3.9× | 0.54 / 0.62 |
| ishikawa-docs | 1 | 9.40 / 11.35 | 11.29 / 30.42 | 2.71 / 3.54 | 3.5× | 8.00 / 9.75 |
| journey-docs | 1 | 9.52 / 11.60 | 12.92 / 31.54 | 2.04 / 2.75 | 4.7× | 8.67 / 10.42 |
| kanban-docs | 3 | 13.02 / 13.67 | 13.96 / 26.72 | 4.26 / 5.18 | 3.1× | 8.46 / 10.11 |
| mindmap-docs | 13 | 4.06 / 4.96 | 4.29 / 10.74 | 1.94 / 2.26 | 2.1× | 3.55 / 3.91 |
| packet-docs | 4 | 8.42 / 8.79 | 8.86 / 17.56 | 2.90 / 3.57 | 2.9× | 6.50 / 7.74 |
| pie-docs | 2 | 7.93 / 8.54 | 9.00 / 17.52 | 2.54 / 3.42 | 3.1× | 4.81 / 5.88 |
| quadrant-docs | 3 | 11.07 / 12.21 | 13.46 / 31.40 | 5.72 / 6.90 | 1.9× | 7.92 / 9.04 |
| radar-docs | 3 | 15.30 / 16.28 | 16.19 / 34.01 | 3.56 / 4.43 | 4.3× | 6.38 / 7.39 |
| railroad-docs | 14 | 14.51 / 15.90 | 14.34 / 55.32 | 7.56 / 9.11 | 1.9× | 15.12 / 17.79 |
| requirement-docs | 9 | 21.27 / 27.34 | 20.74 / 87.43 | 4.01 / 4.96 | 5.3× | 9.30 / 11.21 |
| sankey-docs | 8 | 29.30 / 32.23 | 30.23 / 102.15 | 13.39 / 16.17 | 2.2× | 20.11 / 24.01 |
| sequence-docs | 38 | 9.87 / 12.95 | 10.28 / 39.11 | 4.28 / 4.91 | 2.3× | 8.29 / 9.45 |
| state-docs | 22 | 23.79 / 27.34 | 25.28 / 76.95 | 5.32 / 6.68 | 4.5× | 8.80 / 9.94 |
| swimlane-docs | 13 | 28.85 / 37.86 | 28.90 / 132.86 | 6.84 / 8.38 | 4.2× | 11.02 / 12.62 |
| timeline-docs | 14 | 12.56 / 14.79 | 12.12 / 45.37 | 2.30 / 2.74 | 5.5× | 10.10 / 11.75 |
| treemap-docs | 8 | 14.16 / 15.14 | 14.34 / 27.30 | 5.98 / 6.87 | 2.4× | 10.52 / 12.57 |
| treeview-docs | 13 | 7.96 / 9.62 | 8.53 / 19.57 | 3.14 / 3.48 | 2.5× | 4.44 / 4.99 |
| usecase-docs | 24 | 25.39 / 30.60 | 27.89 / 113.83 | 12.75 / 16.40 | 2.0× | 16.57 / 17.90 |
| venn-docs | 8 | 43.95 / 45.41 | 45.28 / 70.58 | 14.94 / 17.06 | 2.9× | 16.21 / 18.90 |
| wardley-docs | 19 | 10.28 / 12.75 | 10.88 / 41.73 | 4.82 / 6.07 | 2.1× | 7.99 / 9.40 |
| xychart-docs | 8 | 10.99 / 13.43 | 12.32 / 34.21 | 5.38 / 6.22 | 2.0× | 10.30 / 13.40 |

iPhone 17 Pro simulator:

| Inputs | Diagrams | Pele in WebKit, render | Pele in a JSContext, render | Package, read and layout | Speed-up | Package, prepared with SVG |
|---|---:|---:|---:|---:|---:|---:|
| docs: all examples | 114 | 12.88 / 19.19 | 16.51 / 52.09 | 2.28 / 2.90 | 5.7× | 3.98 / 5.28 |
| tree: 50 nodes | 1 | 146.48 / 226.56 | 147.83 / 894.29 | 25.17 / 36.17 | 5.8× | 46.25 / 62.17 |
| mesh: 50 nodes, 20 extra labelled edges | 1 | 382.81 / 531.25 | 404.21 / 1425.33 | 121.75 / 165.00 | 3.1× | 150.21 / 179.62 |
| tree: 500 nodes | 1 | 1562.50 / 1687.50 | 1550.17 / 4890.25 | 267.71 / 298.33 | 5.8× | 385.83 / 428.54 |
| mesh: 500 nodes, 200 extra labelled edges | 1 | 5750.00 / 6187.50 | 5955.62 / 7255.58 | 2167.83 / 2406.25 | 2.7× | 2427.88 / 2895.62 |
| agentflow-docs | 12 | 26.69 / 36.13 | 28.24 / 159.43 | 10.54 / 12.75 | 2.5× | 14.73 / 17.51 |
| architecture-docs | 6 | 21.16 / 22.79 | 21.64 / 102.12 | 11.23 / 13.44 | 1.9× | 16.31 / 20.06 |
| block-docs | 30 | 6.25 / 7.16 | 6.05 / 28.15 | 3.29 / 4.03 | 1.9× | 5.05 / 6.62 |
| c4-docs | 6 | 55.99 / 69.01 | 62.42 / 210.64 | 15.49 / 18.54 | 3.6× | 30.78 / 35.61 |
| class-docs | 38 | 14.80 / 17.06 | 15.65 / 50.75 | 3.72 / 4.28 | 4.0× | 7.17 / 9.99 |
| cynefin-docs | 3 | 21.81 / 34.18 | 20.76 / 155.07 | 6.83 / 8.15 | 3.2× | 13.74 / 15.88 |
| er-docs | 25 | 18.12 / 20.00 | 16.75 / 53.14 | 3.34 / 4.02 | 5.4× | 8.50 / 10.48 |
| eventmodeling-docs | 12 | 12.37 / 14.32 | 12.74 / 58.22 | 4.74 / 5.72 | 2.6× | 9.10 / 12.59 |
| flowchart-docs | 114 | 13.16 / 23.85 | 13.01 / 72.46 | 3.05 / 7.04 | 4.3× | 5.37 / 12.08 |
| gantt-docs | 11 | 29.83 / 36.93 | 34.09 / 125.77 | 14.10 / 34.31 | 2.1× | 20.41 / 45.29 |
| git-docs | 35 | 29.46 / 36.16 | 31.72 / 103.50 | 13.16 / 38.19 | 2.2× | 35.85 / 246.06 |
| info-docs | 2 | 1.22 / 2.14 | 1.94 / 38.75 | 0.27 / 0.69 | 4.5× | 0.69 / 2.12 |
| ishikawa-docs | 1 | 11.96 / 24.90 | 16.50 / 1308.21 | 3.29 / 13.25 | 3.6× | 9.29 / 47.00 |
| journey-docs | 1 | 12.21 / 14.16 | 15.12 / 99.38 | 2.50 / 18.75 | 4.9× | 10.25 / 76.42 |
| kanban-docs | 3 | 15.95 / 19.21 | 19.44 / 97.32 | 4.96 / 36.46 | 3.2× | 9.85 / 55.08 |
| mindmap-docs | 13 | 5.03 / 5.78 | 5.31 / 29.94 | 2.55 / 11.25 | 2.0× | 4.60 / 19.73 |
| packet-docs | 4 | 10.50 / 14.89 | 13.10 / 140.32 | 3.75 / 10.81 | 2.8× | 8.93 / 29.16 |
| pie-docs | 2 | 10.13 / 10.74 | 13.04 / 52.08 | 3.10 / 12.19 | 3.3× | 5.85 / 23.65 |
| quadrant-docs | 3 | 14.32 / 18.88 | 17.75 / 76.15 | 7.15 / 20.40 | 2.0× | 10.57 / 48.29 |
| radar-docs | 3 | 19.86 / 21.16 | 22.19 / 84.00 | 4.06 / 5.53 | 4.9× | 7.85 / 11.26 |
| railroad-docs | 14 | 18.14 / 21.48 | 21.37 / 95.41 | 8.66 / 19.29 | 2.1× | 19.07 / 41.27 |
| requirement-docs | 9 | 26.04 / 31.68 | 30.19 / 135.20 | 4.74 / 12.48 | 5.5× | 10.86 / 23.36 |
| sankey-docs | 8 | 35.64 / 39.06 | 39.69 / 194.41 | 16.59 / 40.52 | 2.1× | 22.97 / 50.06 |
| sequence-docs | 38 | 11.72 / 16.24 | 18.42 / 64.18 | 5.53 / 13.26 | 2.1× | 11.42 / 26.98 |
| state-docs | 22 | 28.76 / 33.38 | 37.00 / 115.16 | 5.95 / 15.76 | 4.8× | 10.03 / 25.71 |
| swimlane-docs | 13 | 33.65 / 46.88 | 35.52 / 198.53 | 7.54 / 9.35 | 4.5× | 12.55 / 33.43 |
| timeline-docs | 14 | 13.95 / 16.46 | 13.09 / 54.88 | 2.40 / 2.67 | 5.8× | 11.28 / 91.42 |
| treemap-docs | 8 | 14.16 / 17.33 | 15.31 / 41.67 | 6.11 / 6.99 | 2.3× | 10.61 / 12.34 |
| treeview-docs | 13 | 7.96 / 9.62 | 8.57 / 14.16 | 3.14 / 3.52 | 2.5× | 4.46 / 4.83 |
| usecase-docs | 24 | 26.04 / 31.90 | 27.13 / 76.39 | 13.19 / 16.57 | 2.0× | 17.32 / 21.39 |
| venn-docs | 8 | 44.43 / 45.41 | 45.42 / 71.49 | 14.75 / 17.49 | 3.0× | 16.65 / 19.67 |
| wardley-docs | 19 | 10.49 / 12.75 | 11.09 / 43.15 | 5.06 / 6.09 | 2.1× | 8.12 / 9.10 |
| xychart-docs | 8 | 11.23 / 13.18 | 12.60 / 34.59 | 5.47 / 6.12 | 2.1× | 10.37 / 12.35 |

In both simulators reading and layout are 1.9 (block diagrams, Gantt charts, railroad and architecture diagrams) to 5.9 (Pele's 114 examples) times as fast as Pele in the page, where 0.7.0 was 0.7 to 2.7 times, and every documentation corpus reads and lays out in at most 19.3 µs a diagram (C4 on the iPad). With its SVG the package is 1.0 (railroad diagrams) to 4.0 (the 500-node tree) times Pele's speed, 3.2 to 3.3 times on Pele's 114 examples, and only the iPhone's Git graphs (0.8, the case named above) come out slower than Pele. WebKit's compiled JavaScriptCore runs Pele faster than Deno does on the Mac for several types (Venn diagrams 44 against 90 µs), so the speed-ups here are lower than the Mac's. The ten-times targets are missed on every case in both.

Not measured on the devices yet: on 2026-11-23, from about 17:00 to 19:15, neither the iPad Pro 11-inch (3rd generation, iPad13,6) nor the iPhone 13 Pro (iPhone14,2), both paired with the Mac over the network, opened a connection to Xcode (`devicectl`: "The tunnel connection failed while the system tried to connect to the device"; `xcodebuild`: timed out waiting for the destination) in 40 attempts, so the test never started on either. The command above, run with a device unlocked and reachable, gives the device's table.
