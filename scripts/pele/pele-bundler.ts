/**
 * File: pele-bundler.ts
 * ---------------------
 * Layer: Tooling
 * Description: Joins Pele's modules, as Deno transpiled them, into one plain script that defines `Pele` (its render
 *              with every type registered), for JavaScriptCore's JSContext, which runs scripts and loads no modules;
 *              checks that the script draws every corpus input as Pele's modules do and records each drawing's hash.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 *
 * MIT licensed, as the package is. Run by bundle.sh beside it, in Deno's sandbox: see README.md there.
 *
 * Deno writes the JavaScript it makes of each TypeScript module to its cache (`<DENO_DIR>/gen/file/<path>.js`) when the
 * module is loaded. This script loads Pele's core and every entry, as pele-runner.ts does, then reads those files. Pele's
 * modules form no import cycle and export no binding they change later, so each module becomes a function run once, in
 * an order where what it imports has run before it, its imports constants taken from those modules' exports: what an
 * ES module's live bindings would give it. Every import and export statement the transpiled modules use is read; one of
 * another form stops the script rather than being guessed at.
 */

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

/** One transpiled module: its body with its import and export statements taken out, what it imports from which
 *  module, and its exports by name, each a local name or a name of another module. */
interface LinkedModule {
  path: string;
  body: string;
  imports: { from: string; imported: string; local: string }[];
  dependencies: string[];
  localExports: Map<string, string>;
  reExports: Map<string, { from: string; imported: string }>;
}

const [peleRoot, cacheFolder, outputFolder] = Deno.args;
if (peleRoot === undefined || cacheFolder === undefined || outputFolder === undefined) {
  console.error('usage: pele-bundler.ts <pele root> <Deno cache folder> <output folder>');
  Deno.exit(2);
}

// The instant the package's tests and benchmark place Gantt charts against (GanttChartCorpus.now), as pele-runner.ts.
const ganttNow = 1_389_787_200_000;

const entryFiles: string[] = [];
for await (const entry of Deno.readDir(`${peleRoot}/src/entries`)) {
  if (entry.isFile && entry.name.endsWith('.ts')) entryFiles.push(`${peleRoot}/src/entries/${entry.name}`);
}
entryFiles.sort();
const corePath = `${peleRoot}/src/core.ts`;
const measurerPath = `${peleRoot}/src/text/measurer.ts`;

// Loading the modules makes Deno transpile them into its cache; they are also the reference the script is checked with.
const core: Core = await import(corePath);
const entries = await Promise.all(entryFiles.map(async (path) => (await import(path)).default));
core.register(...entries);

const identifier = /^[A-Za-z_$][\w$]*$/;
const moduleNamePrefix = '__peleModule';

function directoryOf(path: string): string {
  return path.slice(0, path.lastIndexOf('/'));
}

/** The file an import names, read as Deno's sloppy imports read it: `x.js` is `x.ts` when only that exists. */
function resolve(specifier: string, importer: string): string {
  if (!specifier.startsWith('.')) throw new Error(`${importer}: import of ${specifier}, not a relative path`);
  const parts = `${directoryOf(importer)}/${specifier}`.split('/');
  const kept: string[] = [];
  for (const part of parts) {
    if (part === '..') kept.pop();
    else if (part !== '.') kept.push(part);
  }
  const path = kept.join('/');
  if (path.endsWith('.json')) return path;
  if (path.endsWith('.js')) {
    const typeScript = `${path.slice(0, -3)}.ts`;
    try {
      Deno.statSync(typeScript);
      return typeScript;
    } catch {
      return path;
    }
  }
  throw new Error(`${importer}: import of ${specifier} names no .js, .ts or .json file`);
}

/** `a`, `a as b` for each item of an import or export list. */
function listItems(list: string, statement: string): { name: string; alias: string }[] {
  return list.split(',').map((item) => item.trim()).filter((item) => item.length > 0).map((item) => {
    const [name, as, alias, ...rest] = item.split(/\s+/);
    if (!identifier.test(name) || rest.length > 0 || (as !== undefined && (as !== 'as' || !identifier.test(alias ?? '')))) {
      throw new Error(`unread list item ${item} in ${statement}`);
    }
    return { name, alias: alias ?? name };
  });
}

async function transpiled(path: string): Promise<string> {
  const text = await Deno.readTextFile(`${cacheFolder}/gen/file${path}.js`);
  // Deno ends each file with its source map and its cache's metadata, neither of which the script needs.
  return text.split('\n').filter((line) => !line.startsWith('//# sourceMappingURL=') && !line.startsWith('// denoCacheMetadata=')).join('\n');
}

async function link(path: string): Promise<LinkedModule> {
  const linked: LinkedModule = { path, body: '', imports: [], dependencies: [], localExports: new Map(), reExports: new Map() };
  if (path.endsWith('.json')) {
    // Only the info diagram imports JSON (Pele's package.json, for its version); its keys are the module's exports.
    const value = JSON.parse(await Deno.readTextFile(path));
    linked.body = `const json = ${JSON.stringify(value)};`;
    for (const key of Object.keys(value)) if (identifier.test(key)) linked.localExports.set(key, `json.${key}`);
    return linked;
  }
  const text = await transpiled(path);
  if (text.includes(moduleNamePrefix)) throw new Error(`${path} names ${moduleNamePrefix}, which the script's modules are named`);
  const kept: string[] = [];
  for (const line of text.split('\n')) {
    if (!/^(import|export)\b/.test(line)) {
      if (/^\s+(import|export)\s/.test(line) || /\bimport\s*\(|\bimport\.meta\b/.test(line)) throw new Error(`${path}: unread ${line.trim()}`);
      kept.push(line);
      continue;
    }
    let match: RegExpMatchArray | null;
    if ((match = line.match(/^import \{([^}]*)\} from '([^']+)';$/))) {
      const from = resolve(match[2], path);
      linked.dependencies.push(from);
      for (const { name, alias } of listItems(match[1], line)) linked.imports.push({ from, imported: name, local: alias });
      kept.push('');
    } else if ((match = line.match(/^import '([^']+)';$/))) {
      linked.dependencies.push(resolve(match[1], path));
      kept.push('');
    } else if ((match = line.match(/^export \{([^}]*)\} from '([^']+)';$/))) {
      const from = resolve(match[2], path);
      linked.dependencies.push(from);
      for (const { name, alias } of listItems(match[1], line)) linked.reExports.set(alias, { from, imported: name });
      kept.push('');
    } else if ((match = line.match(/^export \{([^}]*)\};$/))) {
      for (const { name, alias } of listItems(match[1], line)) linked.localExports.set(alias, name);
      kept.push('');
    } else if ((match = line.match(/^export ((?:async )?function\*?|class|const|let|var) ([A-Za-z_$][\w$]*)\b/))) {
      // A declaration list (`export const a = 1, b = 2`) would export its first name only; an import of another stops
      // the script below, as the name is not among the module's exports.
      linked.localExports.set(match[2], match[2]);
      kept.push(line.slice('export '.length));
    } else {
      throw new Error(`${path}: unread ${line}`);
    }
  }
  linked.body = kept.join('\n');
  return linked;
}

// Every module reached from the core, the measurer and the entries, ordered so that each follows what it imports.
const modules = new Map<string, LinkedModule>();
const ordered: LinkedModule[] = [];
const visiting = new Set<string>();
async function visit(path: string): Promise<void> {
  if (modules.has(path)) return;
  if (visiting.has(path)) throw new Error(`import cycle through ${path}: the script's modules need none`);
  visiting.add(path);
  const linked = await link(path);
  for (const dependency of linked.dependencies) await visit(dependency);
  visiting.delete(path);
  modules.set(path, linked);
  ordered.push(linked);
}
for (const root of [corePath, measurerPath, ...entryFiles]) await visit(root);

const moduleNames = new Map(ordered.map((linked, index) => [linked.path, `${moduleNamePrefix}${index}`]));
function exportsOf(path: string): Set<string> {
  const linked = modules.get(path)!;
  return new Set([...linked.localExports.keys(), ...linked.reExports.keys()]);
}

const relative = (path: string) => path.slice(peleRoot.length + 1);
const peleVersion = JSON.parse(await Deno.readTextFile(`${peleRoot}/package.json`)).version as string;
const license = (await Deno.readTextFile(`${peleRoot}/LICENSE`)).trim().split('\n').map((line) => ` * ${line}`.trimEnd()).join('\n');
const pieces: string[] = [
  `/*\n * Pele ${peleVersion} (https://github.com/obsidianmd/pele), its ${ordered.length} modules from src/ as Deno ${Deno.version.deno} ` +
    `transpiled them,\n * joined into one script by MermaidDiagrams' scripts/pele/pele-bundler.ts. Pele's license:\n *\n${license}\n */`,
  'var Pele = (function () {',
  "'use strict';",
];
for (const linked of ordered) {
  const imports = new Map<string, string[]>();
  for (const { from, imported, local } of linked.imports) {
    if (!exportsOf(from).has(imported)) throw new Error(`${relative(linked.path)} imports ${imported}, which ${relative(from)} does not export`);
    imports.set(from, [...(imports.get(from) ?? []), imported === local ? local : `${imported}: ${local}`]);
  }
  const exported: string[] = [];
  for (const [name, local] of linked.localExports) exported.push(`${name}: ${local}`);
  for (const [name, { from, imported }] of linked.reExports) {
    if (!exportsOf(from).has(imported)) throw new Error(`${relative(linked.path)} exports ${imported} from ${relative(from)}, which has none`);
    exported.push(`${name}: ${moduleNames.get(from)}.${imported}`);
  }
  pieces.push(
    `// ${relative(linked.path)}`,
    `const ${moduleNames.get(linked.path)} = (function () {`,
    ...[...imports].map(([from, names]) => `const { ${names.join(', ')} } = ${moduleNames.get(from)};`),
    linked.body.trim(),
    `return { ${exported.join(', ')} };`,
    '})();',
  );
}
const coreName = moduleNames.get(corePath)!;
const measurerName = moduleNames.get(measurerPath)!;
pieces.push(
  `${coreName}.register(${entryFiles.map((path) => `${moduleNames.get(path)}.default`).join(', ')});`,
  `return { version: '${peleVersion}', render: ${coreName}.render, textMeasuredWithTable: ${measurerName}.canvasMeasurer('sans-serif') === null };`,
  '})();',
  '',
);
const script = pieces.join('\n');
await Deno.mkdir(outputFolder, { recursive: true });
await Deno.writeTextFile(`${outputFolder}/pele-bundle.js`, script);

// The script, run as a plain script, must draw every input of Pele's corpora as Pele's modules do.
(0, eval)(script);
const bundled = (globalThis as unknown as { Pele: Core & { textMeasuredWithTable: boolean } }).Pele;

/** FNV-1a over the UTF-8 bytes, 32 bits, as hexadecimal, as pele-runner.ts and PeleResults.sourceHash write it. */
function hash(text: string): string {
  let value = 0x811c9dc5;
  for (const byte of new TextEncoder().encode(text)) value = Math.imul(value ^ byte, 0x01000193) >>> 0;
  return value.toString(16).padStart(8, '0');
}

function drawn(render: Core['render'], source: string): string {
  try {
    const rendered = render(source, { now: ganttNow });
    return `${rendered.type} ${rendered.width}x${rendered.height} ${hash(rendered.svg)}`;
  } catch (error) {
    return `error ${(error as { code?: string }).code ?? 'exception'}: ${String((error as Error).message ?? error).slice(0, 160)}`;
  }
}

const records: { corpus: string; index: number; sourceHash: string; drawing: string }[] = [];
const corpusNames: string[] = [];
for await (const entry of Deno.readDir(`${peleRoot}/tests/corpus`)) if (entry.name.endsWith('-docs.json')) corpusNames.push(entry.name);
let differing = 0;
for (const name of corpusNames.sort()) {
  const content: unknown[] = JSON.parse(await Deno.readTextFile(`${peleRoot}/tests/corpus/${name}`));
  content.forEach((item, index) => {
    const source = typeof item === 'string' ? item : (item as { src: string }).src;
    const fromModules = drawn(core.render, source);
    const fromScript = drawn(bundled.render, source);
    if (fromModules !== fromScript) {
      differing++;
      console.error(`${name}#${index}: modules ${fromModules}, script ${fromScript}`);
    }
    records.push({ corpus: name.replace(/\.json$/, ''), index, sourceHash: hash(source), drawing: fromModules });
  });
}
if (differing > 0) {
  console.error(`${differing} inputs drawn differently by the script`);
  Deno.exit(1);
}
const header = JSON.stringify({ pele: peleVersion, deno: Deno.version.deno, ganttNow, textMeasuredWithTable: bundled.textMeasuredWithTable });
await Deno.writeTextFile(`${outputFolder}/pele-bundle-drawings.json`,
  `{"run": ${header},\n"inputs": [\n${records.map((item) => JSON.stringify(item)).join(',\n')}\n]}\n`);
console.log(`bundle: ${ordered.length} modules, ${script.length} characters; ${records.length} documentation examples drawn alike`);
