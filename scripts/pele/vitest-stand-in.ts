/**
 * File: vitest-stand-in.ts
 * ------------------------
 * Layer: Tooling
 * Description: What two of Mermaid's flowchart specs import from vitest (`vi.spyOn`), as a stand-in that watches
 *              nothing: compat-recorder.ts records what the specs parse, not what they assert.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

const anything: unknown = new Proxy(() => {}, { get: (_target, name) => (name === 'then' ? undefined : anything), apply: () => anything });

export const vi = anything;
