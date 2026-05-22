# Citing dgm-telemetry

Tier-2 detail for `AGENTS.md`.
How to cite this repository when referencing it in a paper, downstream tool, or codebase.

## Licence

The repository is licensed **Apache-2.0** (see `LICENSE` and `NOTICE`).
You may use, share, and adapt the material — including commercially — under the terms of that
licence. Attribution is required; see the templates below.

## Plain-text attribution

> *dgm-telemetry* — JSON Schema specification for metadata on agentic AI tool calls
> (version 0.1.0). Jonathan A. Bowe, 2026.
> Licensed Apache-2.0. https://github.com/jonathan-kellerai/dgm-telemetry

When citing a specific schema field, add the file and line:
`schemas/goals/koth.schema.json:42` for the `outcome_signal` enum.

## BibTeX

```bibtex
@misc{dgm-telemetry2026,
  author       = {Bowe, Jonathan A.},
  title        = {{dgm-telemetry: JSON Schema specification for agentic AI
                   tool-call metadata (provenance, A/B testing, KoTH/Oracle
                   attribution, decision logging, backward-compatible migration)}},
  year         = {2026},
  version      = {0.1.0},
  howpublished = {\url{https://github.com/jonathan-kellerai/dgm-telemetry}},
  note         = {Licensed Apache-2.0}
}
```

Pin the version. The schema interfaces may change before `1.0.0`.

## Citation slug

`dgm-telemetry 0.1.0` — always include the version number.

## Machine-readable citation

The repository ships `CITATION.cff` at its root (Citation File Format 1.2.0).
GitHub's "Cite this repository" widget and Zenodo archiving both read it automatically.
The `CITATION.cff` is the authoritative citation source; the templates above restate it for
convenience.

Verify `CITATION.cff` against https://citation-file-format.github.io/ before modifying it.
Do not invent fields from memory.

## Citing a specific schema

If you are citing a single schema rather than the suite as a whole:

> dgm-telemetry `schemas/goals/provenance.schema.json` (Goal 1 — Provenance), version 0.1.0.
> https://github.com/jonathan-kellerai/dgm-telemetry

Reference specific fields by file and line range — e.g.
`schemas/goals/koth.schema.json:18-34` for the `agents_in_options` array definition.

## Citing the design rationale

The design goals and rationale are documented in `docs/design-goals.md` and the five companion
docs (`docs/01-provenance.md` … `docs/05-backward-compat.md`). Cite these as:

> *dgm-telemetry Design Goals* (v0.1.0). Jonathan A. Bowe.
> `docs/design-goals.md`.
> https://github.com/jonathan-kellerai/dgm-telemetry

## Attribution in source code

When embedding dgm-telemetry schemas in a pipeline or ingestor, add a comment block:

```python
# Metadata schema: dgm-telemetry v0.1.0 — Apache-2.0
# https://github.com/jonathan-kellerai/dgm-telemetry
```

This satisfies the Apache-2.0 notice requirement for derivative source artifacts.
