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

The tables below are of 0.7.0, measured 2026-11-24, and give way to 0.8.0's once measured.

Not a device's speed: a simulator runs the iOS app on the Mac's own processor (here the M5 Max), so these numbers say how the package and Pele compare under iOS's frameworks and WebKit, not how fast an iPad or an iPhone is. Measured 2026-11-24 for 0.7.0 with Xcode 27.2 (27B52), `xcodebuild test -scheme MermaidDiagramsDeviceBenchmark -configuration Release -enableCodeCoverage NO -destination id=<simulator>` (the command above), in a simulator of each made for the run on the iOS 27.2 runtime (24B8117), one after the other, the Mac otherwise quiet (load average 4 to 5, under the 5 waited for; a first run of each, right after the build, with the load at 8 to 16, is not given). Every documentation example was drawn by Pele in the JSContext and in the page as in Deno, but the page's Gantt charts, which it writes in the Mac's time zone (UTC+1) and were not compared. In a simulator Pele in the JSContext runs about as fast as in the page (0.95 to 1.6 times its time), so it appears to be compiled there, as it is not on a device. The page's clock moves by whole milliseconds, which shows in Pele's 99th percentiles. The first case, Pele's 114 examples, has a high 99th percentile for the package in both: it runs first, while the app is still starting. Per diagram, median / 99th percentile in µs; the speed-up is against Pele in the page.

iPad Pro 13-inch (M5) simulator:

| Inputs | Diagrams | Pele in WebKit, render | Pele in a JSContext, render | Package, read and layout | Speed-up | Package, prepared with SVG |
|---|---:|---:|---:|---:|---:|---:|
| docs: all examples | 114 | 30.15 / 49.89 | 65.09 / 2953.99 | 19.70 / 283.35 | 1.5× | 29.05 / 199.40 |
| tree: 50 nodes | 1 | 195.31 / 425.78 | 432.88 / 27992.54 | 157.75 / 348.33 | 1.2× | 240.08 / 482.46 |
| mesh: 50 nodes, 20 extra labelled edges | 1 | 500.00 / 695.31 | 880.42 / 3455.54 | 363.25 / 616.75 | 1.4× | 520.42 / 883.96 |
| tree: 500 nodes | 1 | 2093.75 / 3937.50 | 2700.71 / 15997.38 | 1440.83 / 1977.75 | 1.5× | 2309.29 / 4605.33 |
| mesh: 500 nodes, 200 extra labelled edges | 1 | 7000.00 / 7875.00 | 10433.67 / 14457.62 | 5254.17 / 11020.25 | 1.3× | 6030.29 / 11004.33 |
| agentflow-docs | 12 | 35.16 / 61.85 | 43.11 / 202.15 | 46.05 / 110.14 | 0.8× | 57.39 / 122.36 |
| architecture-docs | 6 | 25.07 / 26.69 | 25.61 / 157.64 | 14.49 / 37.09 | 1.7× | 35.90 / 91.95 |
| block-docs | 30 | 7.03 / 8.20 | 7.50 / 45.50 | 8.29 / 17.97 | 0.8× | 15.61 / 36.13 |
| c4-docs | 6 | 66.41 / 91.15 | 95.58 / 413.31 | 57.45 / 123.72 | 1.2× | 116.81 / 331.41 |
| class-docs | 38 | 18.91 / 22.62 | 23.43 / 86.48 | 12.33 / 21.41 | 1.5× | 30.88 / 56.20 |
| cynefin-docs | 3 | 23.44 / 31.90 | 23.74 / 228.03 | 12.74 / 16.19 | 1.8× | 31.01 / 47.01 |
| er-docs | 25 | 17.50 / 19.69 | 18.75 / 99.97 | 17.14 / 20.96 | 1.0× | 32.03 / 38.16 |
| eventmodeling-docs | 12 | 12.70 / 14.00 | 12.65 / 57.17 | 10.03 / 12.23 | 1.3× | 23.13 / 28.13 |
| flowchart-docs | 114 | 12.34 / 14.53 | 13.85 / 59.42 | 10.55 / 12.60 | 1.2× | 16.17 / 18.73 |
| gantt-docs | 11 | 23.44 / 37.64 | 24.23 / 83.42 | 15.69 / 19.00 | 1.5× | 29.32 / 34.90 |
| git-docs | 35 | 20.98 / 28.12 | 21.66 / 53.98 | 11.47 / 18.11 | 1.8× | 36.20 / 51.46 |
| info-docs | 2 | 0.85 / 0.92 | 1.15 / 3.88 | 0.33 / 0.50 | 2.6× | 1.00 / 1.25 |
| ishikawa-docs | 1 | 10.01 / 10.38 | 11.71 / 33.83 | 10.12 / 13.42 | 1.0× | 25.33 / 34.17 |
| journey-docs | 1 | 10.25 / 12.45 | 13.12 / 42.50 | 6.79 / 9.88 | 1.5× | 27.33 / 37.75 |
| kanban-docs | 3 | 13.83 / 14.16 | 15.60 / 30.12 | 8.50 / 10.40 | 1.6× | 18.12 / 25.19 |
| mindmap-docs | 13 | 4.21 / 5.11 | 4.51 / 15.31 | 3.10 / 4.02 | 1.4× | 8.45 / 11.13 |
| packet-docs | 4 | 8.79 / 9.03 | 9.60 / 17.98 | 5.71 / 7.78 | 1.5× | 16.33 / 26.97 |
| pie-docs | 2 | 8.30 / 8.79 | 9.79 / 23.25 | 4.12 / 4.79 | 2.0× | 12.71 / 19.25 |
| quadrant-docs | 3 | 11.72 / 13.51 | 14.43 / 57.18 | 10.71 / 14.89 | 1.1× | 20.53 / 26.18 |
| radar-docs | 3 | 15.95 / 16.60 | 16.69 / 36.72 | 7.39 / 8.61 | 2.2× | 19.06 / 22.11 |
| railroad-docs | 14 | 15.07 / 17.30 | 14.92 / 63.51 | 13.89 / 16.24 | 1.1× | 34.96 / 39.82 |
| requirement-docs | 9 | 21.70 / 29.95 | 21.56 / 98.81 | 21.40 / 25.76 | 1.0× | 37.25 / 43.56 |
| sankey-docs | 8 | 30.76 / 33.20 | 32.41 / 140.40 | 21.51 / 28.69 | 1.4× | 40.21 / 53.89 |
| sequence-docs | 38 | 10.49 / 13.36 | 10.96 / 42.14 | 8.47 / 10.01 | 1.2× | 20.16 / 24.53 |
| state-docs | 22 | 25.21 / 30.18 | 25.35 / 84.64 | 17.76 / 21.02 | 1.4× | 28.75 / 33.91 |
| swimlane-docs | 13 | 30.05 / 39.66 | 29.62 / 129.92 | 32.50 / 37.94 | 0.9× | 47.21 / 53.16 |
| timeline-docs | 14 | 13.11 / 14.51 | 13.16 / 59.29 | 7.84 / 9.66 | 1.7× | 29.53 / 39.22 |
| treemap-docs | 8 | 14.65 / 15.62 | 15.30 / 34.36 | 9.49 / 11.98 | 1.5× | 22.78 / 29.94 |
| treeview-docs | 13 | 8.26 / 9.77 | 9.17 / 20.41 | 7.36 / 9.48 | 1.1× | 13.44 / 17.07 |
| usecase-docs | 24 | 27.34 / 31.90 | 28.60 / 87.26 | 31.41 / 39.42 | 0.9× | 46.44 / 87.72 |
| venn-docs | 8 | 44.92 / 45.90 | 46.55 / 98.72 | 17.03 / 22.65 | 2.6× | 22.73 / 40.26 |
| wardley-docs | 19 | 10.90 / 13.57 | 12.07 / 49.85 | 9.11 / 11.19 | 1.2× | 18.11 / 21.58 |
| xychart-docs | 8 | 11.47 / 14.89 | 12.82 / 44.74 | 11.20 / 13.82 | 1.0× | 24.16 / 29.06 |

iPhone 17 Pro simulator:

| Inputs | Diagrams | Pele in WebKit, render | Pele in a JSContext, render | Package, read and layout | Speed-up | Package, prepared with SVG |
|---|---:|---:|---:|---:|---:|---:|
| docs: all examples | 114 | 30.15 / 59.76 | 209.82 / 1341.85 | 18.39 / 1849.57 | 1.6× | 38.03 / 1085.00 |
| tree: 50 nodes | 1 | 226.56 / 429.69 | 607.67 / 107925.38 | 156.46 / 423.58 | 1.4× | 261.71 / 587.79 |
| mesh: 50 nodes, 20 extra labelled edges | 1 | 593.75 / 710.94 | 1888.33 / 42280.54 | 459.75 / 788.46 | 1.3× | 491.21 / 879.71 |
| tree: 500 nodes | 1 | 2343.75 / 4687.50 | 2840.71 / 8774.12 | 1546.71 / 2594.08 | 1.5× | 2337.58 / 3031.00 |
| mesh: 500 nodes, 200 extra labelled edges | 1 | 8125.00 / 8750.00 | 11464.71 / 23700.58 | 5750.46 / 6929.12 | 1.4× | 7249.00 / 8622.12 |
| agentflow-docs | 12 | 41.02 / 59.24 | 64.41 / 276.25 | 56.43 / 149.73 | 0.7× | 60.98 / 103.24 |
| architecture-docs | 6 | 26.37 / 30.92 | 27.53 / 160.94 | 13.10 / 32.15 | 2.0× | 34.44 / 43.91 |
| block-docs | 30 | 6.25 / 7.29 | 6.82 / 37.22 | 7.46 / 9.03 | 0.8× | 13.29 / 15.48 |
| c4-docs | 6 | 61.20 / 84.64 | 63.56 / 241.39 | 50.15 / 64.27 | 1.2× | 88.43 / 106.52 |
| class-docs | 38 | 16.24 / 17.89 | 18.79 / 63.68 | 12.03 / 14.96 | 1.4× | 22.12 / 28.51 |
| cynefin-docs | 3 | 21.81 / 27.67 | 21.65 / 159.32 | 12.86 / 16.21 | 1.7× | 30.43 / 37.85 |
| er-docs | 25 | 17.50 / 20.62 | 18.85 / 63.03 | 17.39 / 20.82 | 1.0× | 32.07 / 36.54 |
| eventmodeling-docs | 12 | 12.86 / 14.16 | 13.01 / 60.10 | 9.83 / 11.63 | 1.3× | 22.98 / 26.75 |
| flowchart-docs | 114 | 12.47 / 15.08 | 14.19 / 29.79 | 10.53 / 13.17 | 1.2× | 16.13 / 17.79 |
| gantt-docs | 11 | 23.44 / 36.22 | 24.66 / 85.84 | 15.75 / 18.66 | 1.5× | 29.46 / 42.02 |
| git-docs | 35 | 20.98 / 27.23 | 22.05 / 57.75 | 11.61 / 13.32 | 1.8× | 34.83 / 39.53 |
| info-docs | 2 | 0.85 / 0.92 | 1.17 / 4.92 | 0.35 / 0.52 | 2.4× | 1.00 / 1.12 |
| ishikawa-docs | 1 | 10.01 / 10.25 | 11.67 / 32.79 | 10.17 / 13.21 | 1.0× | 25.33 / 35.88 |
| journey-docs | 1 | 10.13 / 12.57 | 13.29 / 42.08 | 6.75 / 8.46 | 1.5× | 26.29 / 35.38 |
| kanban-docs | 3 | 13.83 / 14.32 | 16.08 / 38.50 | 8.74 / 10.99 | 1.6× | 18.54 / 23.64 |
| mindmap-docs | 13 | 4.28 / 4.96 | 4.54 / 10.14 | 3.07 / 4.05 | 1.4× | 8.44 / 11.39 |
| packet-docs | 4 | 8.79 / 9.03 | 9.96 / 18.45 | 5.57 / 7.42 | 1.6× | 16.34 / 21.57 |
| pie-docs | 2 | 8.30 / 9.40 | 10.40 / 24.56 | 4.15 / 5.21 | 2.0× | 12.56 / 16.96 |
| quadrant-docs | 3 | 11.56 / 13.35 | 14.49 / 44.07 | 10.72 / 14.51 | 1.1× | 20.46 / 26.11 |
| radar-docs | 3 | 15.95 / 16.60 | 17.56 / 38.53 | 7.38 / 9.26 | 2.2× | 18.03 / 22.46 |
| railroad-docs | 14 | 15.07 / 17.02 | 16.04 / 68.75 | 14.34 / 19.58 | 1.1× | 35.51 / 40.39 |
| requirement-docs | 9 | 21.70 / 30.82 | 22.26 / 101.81 | 21.96 / 26.33 | 1.0× | 38.13 / 48.68 |
| sankey-docs | 8 | 31.25 / 32.71 | 32.68 / 120.22 | 22.56 / 28.96 | 1.4× | 40.57 / 47.33 |
| sequence-docs | 38 | 10.49 / 13.57 | 11.12 / 49.55 | 9.47 / 11.37 | 1.1× | 21.63 / 26.19 |
| state-docs | 22 | 25.21 / 27.34 | 26.53 / 80.54 | 19.59 / 24.06 | 1.3× | 30.98 / 42.14 |
| swimlane-docs | 13 | 30.05 / 39.66 | 31.14 / 291.73 | 34.26 / 45.61 | 0.9× | 48.49 / 58.71 |
| timeline-docs | 14 | 13.11 / 15.62 | 12.93 / 54.78 | 8.26 / 10.01 | 1.6× | 30.14 / 36.54 |
| treemap-docs | 8 | 14.89 / 16.85 | 15.07 / 29.13 | 10.30 / 12.91 | 1.4× | 23.78 / 41.69 |
| treeview-docs | 13 | 8.11 / 9.31 | 9.06 / 22.20 | 7.93 / 9.82 | 1.0× | 13.96 / 16.99 |
| usecase-docs | 24 | 26.69 / 31.90 | 29.56 / 120.24 | 31.76 / 39.12 | 0.8× | 44.74 / 53.95 |
| venn-docs | 8 | 45.41 / 46.39 | 43.05 / 89.38 | 16.95 / 20.02 | 2.7× | 22.19 / 28.00 |
| wardley-docs | 19 | 10.69 / 13.16 | 11.56 / 49.86 | 9.05 / 10.97 | 1.2× | 18.07 / 22.15 |
| xychart-docs | 8 | 11.47 / 16.11 | 12.78 / 49.45 | 11.33 / 15.47 | 1.0× | 24.36 / 35.13 |

In both simulators reading and layout are 0.7 (agent flows) to 2.7 (Venn diagrams) times as fast as Pele in the page and the whole preparation with its SVG 0.4 (journey) to 2.0 (Venn) times; agent flows, block diagrams, use case diagrams and swimlanes read and lay out more slowly than Pele there, and only Venn diagrams and Pele's 500-node mesh prepare with their SVG faster than Pele in both (on the iPad also Pele's 114 examples, 1.04 times; on the iPhone also the 50-node mesh and, level, the 500-node tree). WebKit's compiled JavaScriptCore runs Pele faster than Deno does on the Mac for several types (Venn diagrams 45 against 92 µs, use case diagrams 27 against 50), so the speed-ups here are lower than the Mac's. The ten-times targets are missed on every case in both, and the 30 µs target on agent flows, C4 diagrams, swimlanes and use case diagrams.

Not measured on the devices yet: on 2026-11-23, from about 17:00 to 19:15, neither the iPad Pro 11-inch (3rd generation, iPad13,6) nor the iPhone 13 Pro (iPhone14,2), both paired with the Mac over the network, opened a connection to Xcode (`devicectl`: "The tunnel connection failed while the system tried to connect to the device"; `xcodebuild`: timed out waiting for the destination) in 40 attempts, so the test never started on either. The command above, run with a device unlocked and reachable, gives the device's table.
