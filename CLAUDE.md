@AGENTS.md

## Claude-specific notes

- **No runtime, no build.** This repo is a JSON Schema specification. Do not run
  `cargo`, `npm install`, `python -m`, `pytest`, or any build/test command —
  there is no implementation here. The only verification commands are
  `ajv compile -s <schema-path>` and `ajv validate -s <schema> -d <example>`
  (Node `ajv-cli`, opt-in; not required to be installed).

- **No in-repo issue tracker.** There is no `bd` / beads database and no
  `.beads/` directory. Do not invoke `bd`, `bv`, or any tracker tooling. Work
  is tracked in GitHub Issues once the repo is public.

- **Citations.** Internal references use `file:line` — e.g.
  `schemas/goals/koth.schema.json:42`. External or academic references use a
  full bibliographic citation. Never assert a schema fact without pointing at
  the file that proves it.

- **Prose edits.** Use the `writing-clearly-and-concisely` skill for
  human-facing prose changes and `human-writing` for tone passes, when those
  skills are available.

- **Staging artifacts are out of scope.** The `.claude-tmp/` directory holds
  staging-only files — the finalized manifest, the adversarial-critique trail,
  the whitepaper, the publication plan, and interview decisions. These are
  `.gitignore`'d and must never be published. The `.gitignore` boundary is the
  source of truth for what ships: if a file is ignored, it is staging-only.

- **Frozen content.** `schemas/**`, `docs/**`, and `examples/**` passed an
  adversarial review. Change them only with explicit maintainer approval and a
  semver-classified `CHANGELOG.md` entry.
