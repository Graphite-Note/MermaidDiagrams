/**
 * File: compat-recorder.ts
 * ------------------------
 * Layer: Tooling
 * Description: Runs the flowchart specs Pele ports from Mermaid 12.1.0 (tests/compat/flowchart) with Pele's parser and
 *              records every text they parse and what Pele's flowchart database made of it, for the package's
 *              differential parser tests. The specs' own assertions are not checked: Pele passes them in its suite.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 *
 * MIT licensed, as the package is. pele-runner.ts loads it for `--compat`.
 */

type Body = () => unknown;

interface ParsedText {
  spec: string;
  test: string;
  source: string;
  error?: string;
  direction?: string;
  nodes?: { id: string; text: string; type: string }[];
  edges?: { start: string; end: string; type: string; stroke: string; length: number; text: string }[];
  subgraphs?: { id: string; title: string; nodes: string[] }[];
}

interface FlowDatabase {
  direction?: string;
  nodes: Map<string, { id: string; text?: string; type?: string }>;
  edges: { start: string; end: string; type?: string; stroke?: string; length?: number; text: string }[];
  subgraphs: { id: string; title: string; nodes: string[] }[];
}

interface Parser {
  yy: FlowDatabase;
  parse(source: string): void;
}

/** Stands in for vitest's `expect`: any chain of matchers is accepted, and a matcher given a function runs it, so that
 *  the texts a spec expects to be refused are parsed (and recorded) too. */
function acceptingExpectation(value: unknown): unknown {
  const matcher = (): unknown =>
    new Proxy(() => {}, {
      get: (_target, name) => (name === 'then' ? undefined : matcher()),
      apply: () => {
        if (typeof value === 'function') {
          try {
            (value as () => unknown)();
          } catch {
            // The spec expected it to throw; what Pele made of it is recorded by the parser's wrapper.
          }
        }
        return matcher();
      },
    });
  return matcher();
}

export async function recordFlowchartSpecs(peleRoot: string): Promise<ParsedText[]> {
  const folder = `${peleRoot}/tests/compat/flowchart`;
  const adapter = await import(`${folder}/adapter.ts`);
  const parser: Parser = adapter.default;
  const recorded: ParsedText[] = [];
  let current = { spec: '', test: '' };
  const parse = parser.parse.bind(parser);
  parser.parse = (source: string) => {
    const entry: ParsedText = { ...current, source };
    recorded.push(entry);
    try {
      parse(source);
    } catch (error) {
      entry.error = String((error as Error).message ?? error).split('\n')[0].slice(0, 120);
      throw error;
    }
    const database = parser.yy;
    entry.direction = database.direction?.trim();
    entry.nodes = [...database.nodes.values()].map((node) => ({ id: node.id, text: node.text ?? '', type: node.type ?? '' }));
    entry.edges = database.edges.map((edge) => ({
      start: edge.start,
      end: edge.end,
      type: edge.type ?? '',
      stroke: edge.stroke ?? '',
      length: edge.length ?? 1,
      text: edge.text,
    }));
    entry.subgraphs = database.subgraphs.map((group) => ({ id: group.id, title: group.title, nodes: [...group.nodes] }));
  };

  const globals = globalThis as Record<string, unknown>;
  let tests: { name: string; body: Body; setUp: Body[] }[] = [];
  let setUp: Body[] = [];
  globals.describe = (_name: string, body: Body) => {
    const outer = setUp;
    setUp = [...setUp];
    body();
    setUp = outer;
  };
  const register = (name: string, body: Body) => tests.push({ name, body, setUp });
  // `it.each(rows)(name, body)`: one test per row, its body given the row (spread when it is a list).
  const each = (rows: unknown[]) => (name: string, body: (...values: unknown[]) => unknown) =>
    rows.forEach((row) => register(`${name} ${JSON.stringify(row)}`, () => (Array.isArray(row) ? body(...row) : body(row))));
  // A test the spec skips is skipped here too.
  globals.it = globals.test = Object.assign(register, { each, skip: () => {} });
  globals.beforeEach = (body: Body) => setUp.push(body);
  globals.afterEach = globals.beforeAll = globals.afterAll = () => {};
  globals.expect = acceptingExpectation;

  const specs: string[] = [];
  for await (const entry of Deno.readDir(folder)) if (/\.spec\.[jt]s$/.test(entry.name)) specs.push(entry.name);
  for (const spec of specs.sort()) {
    tests = [];
    setUp = [];
    await import(`${folder}/${spec}`);
    for (const test of tests) {
      current = { spec, test: test.name };
      try {
        for (const step of test.setUp) await step();
        await test.body();
      } catch {
        // A refused text is recorded with its error; a spec that drives the database directly records nothing.
      }
    }
  }
  return recorded;
}

// The words a diagram's text starts with, as Pele's detect.ts knows them.
const diagramKeyword =
  /^(?:graph|flowchart(?:-elk)?|sequenceDiagram|classDiagram(?:-v2)?|stateDiagram(?:-v2)?|erDiagram|gantt|pie|gitGraph|mindmap|timeline|journey|quadrantChart|xychart(?:-beta)?|requirementDiagram|C4(?:Context|Container|Component|Dynamic|Deployment)|sankey(?:-beta)?|block(?:-beta)?|packet(?:-beta)?|kanban|architecture(?:-beta)?|radar(?:-beta)?|treemap(?:-beta)?|info|showInfo|agentflow-beta|usecase(?:-beta)?|railroad(?:-ebnf|-abnf|-peg)?-beta|treeView-beta|venn-beta|cynefin-beta|wardley-beta|swimlane-beta|ishikawa(?:-beta)?|eventmodeling)\b/;

/** Every string a compat spec or test file writes that is a diagram's text (it starts, after any front matter, with a
 *  type's keyword), as written in the file once its escapes are read: the package's copy of tests/compat's inputs. */
export async function copyCompatInputs(peleRoot: string): Promise<Record<string, string[]>> {
  const root = `${peleRoot}/tests/compat`;
  const copied: Record<string, string[]> = {};
  const literal = /`((?:[^`\\$]|\\[\s\S]|\$(?!\{))*)`|'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)"/g;
  for await (const type of Deno.readDir(root)) {
    if (!type.isDirectory) continue;
    for await (const file of Deno.readDir(`${root}/${type.name}`)) {
      if (!/\.(spec|test)\.[jt]s$/.test(file.name)) continue;
      const text = await Deno.readTextFile(`${root}/${type.name}/${file.name}`);
      const inputs = new Set<string>();
      for (const match of text.matchAll(literal)) {
        const raw = match[1] ?? match[2] ?? match[3] ?? '';
        let value: string;
        try {
          value = JSON.parse(`"${raw.replace(/\\'/g, "'").replace(/\\`/g, '`').replace(/\n/g, '\\n').replace(/"/g, '\\"').replace(/\\\\"/g, '\\"')}"`);
        } catch {
          value = raw;
        }
        const body = value.replace(/^\s*---[\s\S]*?---\s*/, '').replace(/^\s*%%\{[\s\S]*?\}%%\s*/, '').trimStart();
        if (diagramKeyword.test(body)) inputs.add(value);
      }
      copied[`${type.name}/${file.name}`] = [...inputs];
    }
  }
  return Object.fromEntries(Object.entries(copied).sort(([first], [second]) => (first < second ? -1 : 1)));
}
