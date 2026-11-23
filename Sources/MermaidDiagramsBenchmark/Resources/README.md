# Resources

`flowchart-docs.json`: the 114 flowchart examples of Mermaid's documentation, as Pele collects them for its benchmark (`tests/corpus/flowchart-docs.json` in https://github.com/obsidianmd/pele, MIT licensed, see `PELE-LICENSE`; the examples come from Mermaid's documentation, also MIT licensed). Used unchanged, so that the benchmark runs on the same inputs as Pele's.

`state-docs.json`: the 22 state diagram examples of Mermaid's documentation, as Pele collects them (`tests/corpus/state-docs.json` in the same repository, MIT licensed, the examples from Mermaid's documentation). Used unchanged.
`class-docs.json`: the 38 class diagram examples of Mermaid's documentation, as Pele collects them (`tests/corpus/class-docs.json` in the same repository, MIT licensed; the examples come from Mermaid's documentation, also MIT licensed). Used unchanged.
`sequence-docs.json`: the 38 sequence diagram examples of Mermaid's documentation, as Pele collects them for its benchmark (`tests/corpus/sequence-docs.json` in the same repository, MIT licensed; the examples come from Mermaid's documentation, also MIT licensed). Used unchanged.
`er-docs.json`: the 25 entity relationship examples of Mermaid's documentation, as Pele collects them (`tests/corpus/er-docs.json` in the same repository, MIT licensed; the examples come from Mermaid's documentation, also MIT licensed). Used unchanged.
`mindmap-docs.json`: the 13 mindmap examples of Mermaid's documentation, as Pele collects them (`tests/corpus/mindmap-docs.json` in Pele, same licenses). Used unchanged.

`timeline-docs.json`: the 14 timeline examples of Mermaid's documentation, as Pele collects them (`tests/corpus/timeline-docs.json` in Pele, same licenses). Used unchanged.
`pie-docs.json`: the 2 pie chart examples of Mermaid's documentation, as Pele collects them (`tests/corpus/pie-docs.json`, same licenses), used unchanged.

`gantt-docs.json`: the 11 Gantt chart examples of Mermaid's documentation, as Pele collects them (`tests/corpus/gantt-docs.json`, same licenses), used unchanged.

`git-docs.json`: the 35 Git graph examples of Mermaid's documentation, as Pele collects them (`tests/corpus/git-docs.json`, same licenses), used unchanged.
`journey-docs.json`: the user journey example of Mermaid's documentation, as Pele collects it (`tests/corpus/journey-docs.json`, same licenses), used unchanged.
`quadrant-docs.json`: the 3 quadrant chart examples of Mermaid's documentation, as Pele collects them (`tests/corpus/quadrant-docs.json`, same licenses), used unchanged.
`xychart-docs.json`: the 8 XY chart examples of Mermaid's documentation, as Pele collects them (`tests/corpus/xychart-docs.json`, same licenses), used unchanged.
`wardley-docs.json`: the 19 Wardley map examples of Mermaid's documentation, as Pele collects them (`tests/corpus/wardley-docs.json`, same licenses), used unchanged.
`cynefin-docs.json`: the 3 Cynefin framework examples of Mermaid's documentation, as Pele collects them (`tests/corpus/cynefin-docs.json`, same licenses), used unchanged.
`venn-docs.json`: the 8 Venn diagram examples of Mermaid's documentation, as Pele collects them (`tests/corpus/venn-docs.json`, same licenses), used unchanged.

`sankey-docs.json`: the 8 Sankey diagram examples of Mermaid's documentation, as Pele collects them (`tests/corpus/sankey-docs.json`, same licenses), used unchanged. `sankey-energy.csv`: the energy flows Mermaid 12.1.0's `sankey.spec.ts` reads (`energy.csv` in Mermaid, MIT licensed, as Pele ports the spec in `tests/compat/sankey/upstream`), used unchanged.
`kanban-docs.json`: the 3 kanban examples of Mermaid's documentation, as Pele collects them (`tests/corpus/kanban-docs.json`, same licenses), used unchanged.
`treeview-docs.json`: the 13 tree view examples of Mermaid's documentation, as Pele collects them (`tests/corpus/treeview-docs.json`, same licenses), used unchanged.
`ishikawa-docs.json`: the Ishikawa diagram example of Mermaid's documentation, as Pele collects it (`tests/corpus/ishikawa-docs.json`, same licenses), used unchanged.
`info-docs.json`: the 2 info diagram examples of Mermaid's documentation, as Pele collects them (`tests/corpus/info-docs.json`, same licenses), used unchanged.
`packet-docs.json`: the 4 packet diagram examples of Mermaid's documentation, as Pele collects them (`tests/corpus/packet-docs.json`, same licenses), used unchanged.
`radar-docs.json`: the 3 radar chart examples of Mermaid's documentation, as Pele collects them (`tests/corpus/radar-docs.json`, same licenses), used unchanged.
`treemap-docs.json`: the 8 treemap examples of Mermaid's documentation, as Pele collects them (`tests/corpus/treemap-docs.json`, same licenses), used unchanged.
`eventmodeling-docs.json`: the 12 event model examples of Mermaid's documentation, as Pele collects them (`tests/corpus/eventmodeling-docs.json`, same licenses), used unchanged.
`railroad-docs.json`: the 14 railroad diagram examples of Mermaid's documentation, in its four notations, as Pele collects them (`tests/corpus/railroad-docs.json`, same licenses), used unchanged.
`c4-docs.json`: the 6 C4 diagram examples of Mermaid's documentation, as Pele collects them (`tests/corpus/c4-docs.json`, same licenses), used unchanged.
`block-docs.json`: the 30 block diagram examples of Mermaid's documentation, as Pele collects them (`tests/corpus/block-docs.json`, same licenses), used unchanged.
`architecture-docs.json`: the 6 architecture diagram examples of Mermaid's documentation, as Pele collects them (`tests/corpus/architecture-docs.json`, same licenses), used unchanged.
`requirement-docs.json`: the 9 requirement diagram examples of Mermaid's documentation, as Pele collects them (`tests/corpus/requirement-docs.json`, same licenses), used unchanged.
`swimlane-docs.json`: the 13 swimlane diagram examples of Mermaid's documentation, as Pele collects them (`tests/corpus/swimlane-docs.json`, same licenses), used unchanged.
`usecase-docs.json`: the 24 use case diagram examples of Mermaid's documentation, as Pele collects them (`tests/corpus/usecase-docs.json`, same licenses), used unchanged.
`agentflow-docs.json`: the 12 agent flow examples of Mermaid's documentation, as Pele collects them (`tests/corpus/agentflow-docs.json`, same licenses), used unchanged. `agentflow-reference.json`: the 239 inputs of Pele's agent flow reference (`tests/corpus/agentflow-reference.json`, same licenses: its compatibility fixtures, documentation examples and mutated texts) with what Mermaid 12.1.0's browser build made of each, without its semantic model and the zero text offsets of its element positions.

`pele-corpus.json`, `pele-bench.json`, `pele-compat-inputs.json` and `pele-flowchart-compat.json`: what Pele 1.13.0 itself
drew for every input of Pele's `tests/corpus` and the generated graphs of its benchmark, how long it took on the Mac that
ran it, every diagram text of its `tests/compat` (Mermaid's specs, MIT licensed), and what its flowchart database made of
each text Mermaid's flowchart specs parse, written by `scripts/pele/run.sh` (see `scripts/pele/README.md`).
`pele-narrow.json`: what Pele 1.13.0 shows of every documentation example in a container 280, 390 and 600 points wide,
written by `scripts/pele/run.sh --max-width=280,390,600`.
`PeleKnownDifferences.md`: every input whose scene differs from Pele's beyond the differential tests' tolerance (in a
narrow column too), every
flowchart spec text read otherwise than Pele reads it, and every compat file without copied texts, each with why.
