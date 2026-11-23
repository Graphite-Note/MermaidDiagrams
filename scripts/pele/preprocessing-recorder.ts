/**
 * File: preprocessing-recorder.ts
 * --------------------------------
 * Layer: Tooling
 * Description: Reads YAML texts with Pele's own reader (src/util/yaml.ts) and diagram texts with its preprocessing
 *              (src/preprocess.ts), and records what each made of them, or that they refused them, for the package's
 *              ports to be compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 *
 * MIT licensed, as the package is. pele-runner.ts loads it for `--preprocessing`.
 */

/** The texts of Pele's tests/util/yaml.test.ts, then front matter and node data written in ways those leave out. */
const yamlCases: string[] = [
  '{\n shape: rounded \n}',
  '{\nshape: rounded , label: "DD"\n}',
  '{\n label: "This is }", other: "clock"\n}',
  '{\n animate: true, animation: fast, w: 100, h: 50.5, x: null, y: ~\n}',
  "{\n label: 'single quoted', icon: \"fa:fa-user\", form: circle, pos: t \n}",
  '{\n a: [1, 2, three], b: {c: d, e: [f]}\n}',
  '{\n}',
  '\n        shape: circle\n        other: "clock"\n     \n',
  '\n        label: |\n          This is a\n          multiline string\n        other: "clock"\n     \n',
  '\n        label: >\n          folded\n          text\n\n          second paragraph\n        other: 1\n',
  '\n        label: "This is a<br/>multiline string"\n        other: "clock"\n',
  'title: Hello world\nconfig:\n  theme: dark\n  flowchart:\n    curve: linear\n    htmlLabels: false\n',
  'title: "Quoted: title"\ndisplayMode: compact\n',
  'config:\n  themeVariables:\n    primaryColor: "#ff0000"\n    fontSize: 16px\n  look: handDrawn # trailing comment\n',
  'list:\n  - a\n  - b: 1\n    c: 2\n  - [x, y]\nempty:\n',
  'a: 0x1f\nb: -12\nc: 1e3\nd: .5\ne: "12"\nf: True\ng: FALSE\nh: Null\n',
  'key with spaces: plain value\nurl: http://example.com/a#b\n',
  'multi: this is\n  continued on the next line\nnext: 1\n',
  '# only a comment\n',
  '',
  'just a scalar',
  '- 1\n- 2\n',
  'a: {\n  b: 1,\n  c: [2,\n    3]\n}\nd: "two\n  lines"\ne: 5\n',
  '{\n a: 1, # comment\n b: 2\n}',
  // Quoted scalars folded across lines, a backslash before a line break, escapes, a key with nothing after it.
  'title: "first\n  second\n\n  third"\n',
  "title: 'it''s\n  folded'\n",
  'title: "joined \\\n   here"\n',
  'title: "tab\\tand \\x41\\u00e9 and \\"quoted\\""\n',
  'title:\nconfig:\n  theme:\n',
  'title: "bad \\q escape"\n',
  'a: 1\n  b: 2\n',
  'a:\n\tb: 1\n',
  'title: "never closed\n',
  'a: [1, 2\nb: 3\n',
  'a: |-\n  kept\n\n',
  'a: |+\n  kept\n\n',
  'a: >2\n    indented\n   less\n',
  'title: -12.5e+3\nwidth: +.5\nhex: -0x10\noctal: 0o17\nbinary: 0b101\nnot: 08\nalso: 1.\n',
  '"quoted key": 1\n\'single key\': 2\n',
  'seq:\n- a\n- b\n',
  '{ a: 1 } trailing',
  '{ a: 1, , b: 2 }',
  '{ a: 1 b: 2 }',
  '...\n',
  'a: 1\n...\n',
  'a: 1\n---\nb: 2\n',
  'url: a:b\nport: :8080\n',
  '- - nested\n  - again\n- last\n',
  'a: "x" # comment\nb: "y" extra\n',
  // Node data as flowchart/db.ts hands it over: several lines as they are, one line wrapped in braces.
  ' icon: "fa:user",\n  shape: cyl \n',
  "{\n shape: 'rect' \n}",
  '{\n shape: diam, label: "Is it, really?" \n}',
];

export function recordYaml(parseYaml: (source: string) => unknown): { source: string; value?: unknown; error?: string }[] {
  return yamlCases.map((source) => {
    try {
      return { source, value: parseYaml(source) ?? null };
    } catch (error) {
      return { source, error: String((error as Error).message ?? error).slice(0, 120) };
    }
  });
}

/** Diagram texts for Pele's preprocessing: directives anywhere, line breaks, front matter, and the semicolon a style
 *  or class definition with a colour loses. */
const preprocessingCases: string[] = [
  '%%{init: {"theme":"dark"}}%%\nflowchart LR\nA-->B',
  'flowchart LR\nA-->B %%{init: {"flowchart": {"curve": "basis"}}}%% \nB-->C',
  'flowchart LR\n  %%{\n    init: {"theme": "forest"}\n  }%%\nA-->B',
  '%%{init: {"a": 1} \nflowchart LR\nA',
  '%%{wrap}%%\nsequenceDiagram\nA->>B: hi',
  '%%{ }%%\nflowchart LR\nA',
  "%%{init: {'theme': 'dark'}}%%\nflowchart LR\nA",
  'flowchart LR\r\nA-->B\rB-->C\r\n',
  'flowchart LR\nstyle A fill:#f00;B-->C',
  'flowchart LR\nclassDef c fill:#fff,stroke:#000;\nA-->B;',
  'flowchart LR\nA-->B; style A fill:#f00; B-->C;',
  'flowchart LR\nstyle A fill: #f00;B-->C',
  '---\ntitle: a\n---\nflowchart LR\nA',
  '---\ntitle: [unclosed\n---\nflowchart LR\nA',
  '---\ntitle: "multi\n  line"\n---\nflowchart LR\nA',
  '---\ntitle: 12\n---\nflowchart LR\nA',
  '---\ntitle:\n---\nflowchart LR\nA',
  '---\ntitle\n---\nflowchart LR\nA',
  '  ---\n  title: indented\n  ---\nflowchart LR\nA',
  '\n---\ntitle: after a blank line\n---\nflowchart LR\nA',
  '---\ntitle: x\n---',
  '---\ndisplayMode: compact\n---\ngantt\ntask: a, 1d',
  '---\nconfig:\n  flowchart:\n    curve: linear\n---\n%%{init: {"flowchart": {"htmlLabels": false}}}%%\nflowchart LR\nA',
  '---\na: 1\n  b: 2\n---\nflowchart LR\nA',
  'flowchart LR\n%% a comment\nA-->B\n%%\n%%{not a directive\nB',
  '---\r\ntitle: crlf\r\n---\r\nflowchart LR\r\nA',
  'railroad-beta\ns = terminal("%%{kept}") ;\nt = terminal("c") ;',
  'venn-beta\ntitle A\rset B',
  'gantt\n%%{init: {}}%%',
  'flowchart LR\nfoo%%{init: {}}%%bar-->B',
  'flowchart LR\nA-->%%{init:\n{"a": 1}}%%B',
  'flowchart LR\nA[<span style="color:red">x</span>]-->B["<a href="u" title="t">y</a>"]',
  'sequenceDiagram\nA->>B: <b class="x">hi</b> and "q" <i id="z>',
];

export function recordPreprocessing(
  preprocess: (source: string) => { text: string; title?: string; config: unknown },
  encodeEntities: (text: string) => string
): { source: string; text?: string; title?: string | null; config?: unknown; error?: string }[] {
  return preprocessingCases.map((source) => {
    try {
      const pre = preprocess(source);
      return { source, text: encodeEntities(pre.text), title: pre.title ?? null, config: pre.config };
    } catch (error) {
      return { source, error: String((error as Error).message ?? error).slice(0, 120) };
    }
  });
}

/** Texts JavaScript's `new Date(text)` reads (V8's ISO and legacy parsers), which Pele's Gantt chart falls back to for a
 *  start date that does not fit its `dateFormat`; run with TZ=UTC. */
const dateCases: string[] = [
  'March 7, 2014', 'March 7 2014', 'Mar 7, 2014 10:30', '7 March 2014', '7 Mar 2014 10:30 PM', 'Fri, 07 Mar 2014 10:00:00 GMT',
  'Friday, March 7, 2014', '3/7/2014', '3/7/14', '2014/3/7', '2014-3-7', '2014-03-07', '2014-03-07T10:00', '2014-03-07T10:00Z',
  '2014-03-07 10:00', 'March 2014', '2014', 'Mar 7', '7 Mar', 'March 7, 2014 10:30:15.250', 'Mar 7, 2014 GMT+0100',
  'Mar 7, 2014 UTC-5', 'Mar 7, 2014 (CET)', 'Mar 7, 2014 EST', 'Sept 7 2014', 'Septem 7 2014', '7.3.2014', '2014 Mar 7',
  'Mar 32 2014', 'Feb 30, 2014', '12 noon', 'tomorrow', '', '  March 7, 2014  ', 'March 7,2014', 'March,7,2014',
  '07-Mar-2014', 'Mar-07-2014', '2014-Mar-07', '10:30 March 7 2014', 'March 7 2014 12:00 AM', 'March 7 2014 12:00 PM',
  '99', '1 2 3', '50/1/1', '1/1/50', '+002014-03-07', 'Mar 7, 2014 10:30 +01:00',
];

export function recordDates(): { text: string; milliseconds: number | null }[] {
  return dateCases.map((text) => {
    const time = new Date(text).getTime();
    return { text, milliseconds: Number.isNaN(time) ? null : time };
  });
}
