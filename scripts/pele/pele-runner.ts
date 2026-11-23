/**
 * File: pele-runner.ts
 * --------------------
 * Layer: Tooling
 * Description: Renders Mermaid's documentation examples and Pele's generated benchmark graphs with Pele itself, in
 *              Deno's sandbox, and writes what each SVG holds and how long Pele took, for the package's differential
 *              tests and its benchmark against Pele.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 *
 * MIT licensed, as the package is. It reads Pele's sources and corpora as data and runs none of Pele's scripts: see
 * README.md beside it for the exact command.
 */

type Counts = Record<string, number>;

interface Rendered {
  svg: string;
  width: number;
  height: number;
  type: string;
}

interface Core {
  register(...diagrams: unknown[]): void;
  render(source: string, options?: Record<string, unknown>): Rendered;
}

interface InputRecord {
  corpus: string;
  index: number;
  sourceHash: string;
  type?: string;
  error?: string;
  width?: number;
  height?: number;
  texts?: Counts;
  groups?: Counts;
  subpaths?: Counts;
  medianMicroseconds?: number;
  percentile99Microseconds?: number;
  runs?: number;
}

interface TimedCase {
  name: string;
  diagramCount: number;
  renderedCount: number;
  medianMillisecondsPerCase: number;
  medianMicrosecondsPerDiagram: number;
  percentile99MicrosecondsPerDiagram: number;
  runs: number;
}

const [peleRoot, outputFolder, ...flags] = Deno.args;
if (peleRoot === undefined || outputFolder === undefined) {
  console.error('usage: pele-runner.ts <pele root> <output folder> [--corpus] [--compat] [--bench] [--svg]');
  Deno.exit(2);
}
const runsCorpus = flags.length === 0 || flags.includes('--corpus');
const runsCompat = flags.length === 0 || flags.includes('--compat');
const runsBench = flags.length === 0 || flags.includes('--bench');
// `--svg` (with `--corpus`) also writes each input's SVG as svg/<corpus>-<index>.svg, to look at beside the package's drawing.
const writesDrawings = flags.includes('--svg');

// Mermaid's Gantt charts are placed against "now": the package's tests and benchmark use the same instant
// (GanttChartCorpus.now, 2014-01-15 12:00 UTC); the command runs with TZ=UTC.
const ganttNow = 1_389_787_200_000;

const core: Core = await import(`${peleRoot}/src/core.ts`);
const measurerModule = await import(`${peleRoot}/src/text/measurer.ts`);
for await (const entry of Deno.readDir(`${peleRoot}/src/entries`)) {
  if (entry.isFile && entry.name.endsWith('.ts')) core.register((await import(`${peleRoot}/src/entries/${entry.name}`)).default);
}
// Pele measures text with a canvas where there is one and with its table of Arial's advances elsewhere
// (text/measurer.ts defaultMeasurer). Deno has OffscreenCanvas but no 2D context, so it falls back to the table.
const measurerName =
  measurerModule.canvasMeasurer('sans-serif') === null ? 'metricsMeasurer (Arial advance table, text/metrics.ts)' : 'canvasMeasurer';

/** FNV-1a over the UTF-8 bytes, 32 bits, as hexadecimal: the package's tests check they compare the same text. */
function sourceHash(source: string): string {
  let hash = 0x811c9dc5;
  for (const byte of new TextEncoder().encode(source)) hash = Math.imul(hash ^ byte, 0x01000193) >>> 0;
  return hash.toString(16).padStart(8, '0');
}

const shapeElements = new Set(['rect', 'path', 'polygon', 'polyline', 'circle', 'ellipse', 'line']);

/** The SVG's elements counted by the nearest `pele-…` class on them or around them: the groups (`<g>`) by their own
 *  class, the texts (and spans of a class of their own) by theirs or their group's, and the subpaths of shapes (each `M` of a path, one per other shape) by
 *  theirs or their group's. */
function countParts(svg: string): { texts: Counts; groups: Counts; subpaths: Counts } {
  const texts: Counts = {};
  const groups: Counts = {};
  const subpaths: Counts = {};
  const classStack: string[] = [];
  const tagPattern = /<(\/?)([a-zA-Z]+)((?:[^>"]|"[^"]*")*?)(\/?)>/g;
  const add = (counts: Counts, key: string, amount: number) => (counts[key] = (counts[key] ?? 0) + amount);
  for (const match of svg.matchAll(tagPattern)) {
    const [, closing, tag, attributes, selfClosing] = match;
    if (closing) {
      classStack.pop();
      continue;
    }
    const own = /\sclass="([^"]*)"/.exec(attributes)?.[1]?.split(/\s+/).find((name) => name.startsWith('pele-'));
    const part = own?.slice('pele-'.length) ?? classStack[classStack.length - 1] ?? '';
    if (own !== undefined && tag === 'g') add(groups, part, 1);
    // A span of its own class (a Sankey node's value) is a text of its own, as the package writes it.
    if (tag === 'text' || (tag === 'tspan' && own !== undefined)) add(texts, part, 1);
    if (shapeElements.has(tag)) {
      const data = tag === 'path' ? /\sd="([^"]*)"/.exec(attributes)?.[1] ?? '' : 'M';
      add(subpaths, part, (data.match(/[Mm]/g) ?? []).length);
    }
    if (!selfClosing) classStack.push(part);
  }
  return { texts, groups, subpaths };
}

/** Pele's benchmark loop (scripts/bench.mjs `time`): one warm run, then runs until `budgetMilliseconds` are spent, at
 *  least 5 and at most 2,000; the sorted samples in milliseconds. */
function samples(run: () => void, budgetMilliseconds: number): number[] {
  run();
  let budget = budgetMilliseconds;
  const taken: number[] = [];
  while (budget > 0 || taken.length < 5) {
    const start = performance.now();
    run();
    const elapsed = performance.now() - start;
    taken.push(elapsed);
    budget -= elapsed;
    if (taken.length >= 2000) break;
  }
  return taken.sort((first, second) => first - second);
}

const median = (sorted: number[]) => sorted[sorted.length >> 1];
const percentile99 = (sorted: number[]) => sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * 0.99) - 1)];
const rounded = (value: number) => Math.round(value * 1000) / 1000;

async function corpora(): Promise<[string, string[]][]> {
  const found: [string, string[]][] = [];
  for await (const entry of Deno.readDir(`${peleRoot}/tests/corpus`)) {
    if (!entry.name.endsWith('.json')) continue;
    const content: unknown[] = JSON.parse(await Deno.readTextFile(`${peleRoot}/tests/corpus/${entry.name}`));
    const sources = content.map((item) => (typeof item === 'string' ? item : (item as { src: string }).src));
    found.push([entry.name.replace(/\.json$/, ''), sources]);
  }
  return found.sort(([first], [second]) => (first < second ? -1 : 1));
}

// The generated graphs of scripts/bench.mjs, written as it writes them.
function chain(nodeCount: number, fan: number): string {
  let source = 'flowchart TD\n';
  for (let node = 1; node < nodeCount; node++) {
    const parent = Math.floor((node - 1) / fan);
    source += `  n${parent}[Node ${parent}] --> n${node}[Node ${node}]\n`;
  }
  return source;
}

function mesh(nodeCount: number, extraEdgeCount: number): string {
  let source = 'flowchart TD\n';
  let seed = 7;
  const random = () => (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 4294967296;
  for (let node = 1; node < nodeCount; node++) source += `  n${Math.floor(random() * node)} --> n${node}\n`;
  for (let edge = 0; edge < extraEdgeCount; edge++) {
    source += `  n${Math.floor(random() * nodeCount)} -->|label ${edge}| n${Math.floor(random() * nodeCount)}\n`;
  }
  return source;
}

const generated: [string, string][] = [
  ['tree: 50 nodes', chain(50, 3)],
  ['mesh: 50 nodes, 20 extra labelled edges', mesh(50, 20)],
  ['tree: 500 nodes', chain(500, 3)],
  ['mesh: 500 nodes, 200 extra labelled edges', mesh(500, 200)],
];

function record(corpus: string, index: number, source: string): InputRecord {
  const base: InputRecord = { corpus, index, sourceHash: sourceHash(source) };
  const options = { now: ganttNow };
  let rendered: Rendered;
  try {
    rendered = core.render(source, options);
  } catch (error) {
    const code = (error as { code?: string }).code ?? 'exception';
    return { ...base, error: `${code}: ${String((error as Error).message ?? error).slice(0, 160)}` };
  }
  if (writesDrawings) Deno.writeTextFileSync(`${outputFolder}/svg/${corpus}-${index}.svg`, rendered.svg);
  const timings = samples(() => core.render(source, options), 40);
  return {
    ...base,
    type: rendered.type,
    width: rendered.width,
    height: rendered.height,
    ...countParts(rendered.svg),
    medianMicroseconds: rounded(median(timings) * 1000),
    percentile99Microseconds: rounded(percentile99(timings) * 1000),
    runs: timings.length,
  };
}

function timedCase(name: string, sources: string[]): TimedCase {
  let renderedCount = 0;
  const runAll = () => {
    renderedCount = 0;
    for (const source of sources) {
      try {
        core.render(source);
        renderedCount++;
      } catch {
        continue;
      }
    }
  };
  const timings = samples(runAll, 300);
  return {
    name,
    diagramCount: sources.length,
    renderedCount,
    medianMillisecondsPerCase: rounded(median(timings)),
    medianMicrosecondsPerDiagram: rounded((median(timings) * 1000) / sources.length),
    percentile99MicrosecondsPerDiagram: rounded((percentile99(timings) * 1000) / sources.length),
    runs: timings.length,
  };
}

const allCorpora = await corpora();
const machine = { deno: Deno.version.deno, v8: Deno.version.v8, os: Deno.build.os, arch: Deno.build.arch };
const peleVersion = JSON.parse(await Deno.readTextFile(`${peleRoot}/package.json`)).version;
await Deno.mkdir(outputFolder, { recursive: true });
if (writesDrawings) await Deno.mkdir(`${outputFolder}/svg`, { recursive: true });

if (runsCorpus) {
  const records: InputRecord[] = [];
  for (const [corpus, sources] of allCorpora) sources.forEach((source, index) => records.push(record(corpus, index, source)));
  generated.forEach(([, source], index) => records.push(record('bench-generated', index, source)));
  const lines = records.map((item) => JSON.stringify(item));
  const header = JSON.stringify({ pele: peleVersion, measurer: measurerName, fontSize: 16, ganttNow, ...machine });
  await Deno.writeTextFile(`${outputFolder}/pele-corpus.json`, `{"run": ${header},\n"inputs": [\n${lines.join(',\n')}\n]}\n`);
  console.log(`corpus: ${records.length} inputs, ${records.filter((item) => item.error).length} refused, measured with ${measurerName}`);
}

if (runsCompat) {
  const { recordFlowchartSpecs, copyCompatInputs } = await import('./compat-recorder.ts');
  const inputs = await copyCompatInputs(peleRoot);
  await Deno.writeTextFile(`${outputFolder}/pele-compat-inputs.json`, JSON.stringify(inputs, null, 0) + '\n');
  const inputCount = Object.values(inputs).reduce((sum, list) => sum + list.length, 0);
  console.log(`compat: ${inputCount} diagram texts written in ${Object.keys(inputs).length} spec and test files`);
  const parsed = await recordFlowchartSpecs(peleRoot);
  const lines = parsed.map((item) => JSON.stringify(item));
  await Deno.writeTextFile(`${outputFolder}/pele-flowchart-compat.json`, `[\n${lines.join(',\n')}\n]\n`);
  console.log(`compat: ${parsed.length} texts parsed by the flowchart specs, ${parsed.filter((item) => item.error).length} refused`);
}

if (runsBench) {
  const flowchartDocs = allCorpora.find(([name]) => name === 'flowchart-docs')?.[1] ?? [];
  const cases: TimedCase[] = [timedCase('docs: all examples', flowchartDocs), ...generated.map(([name, source]) => timedCase(name, [source]))];
  const perType = allCorpora.filter(([name]) => name.endsWith('-docs')).map(([name, sources]) => timedCase(name, sources));
  const result = { run: { pele: peleVersion, measurer: measurerName, date: new Date().toISOString(), ...machine }, cases, perType };
  await Deno.writeTextFile(`${outputFolder}/pele-bench.json`, JSON.stringify(result, null, 1) + '\n');
  console.table(cases.map((item) => ({ case: item.name, diagrams: item.diagramCount, pele: `${item.medianMillisecondsPerCase} ms` })));
  console.table(perType.map((item) => ({ corpus: item.name, median: item.medianMicrosecondsPerDiagram, p99: item.percentile99MicrosecondsPerDiagram })));
}
