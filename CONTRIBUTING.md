# Contributing to dgm-telemetry

Thank you for your interest in contributing.
dgm-telemetry is a JSON Schema specification — contributions are schema edits, example updates,
and documentation improvements, not code changes.
Please follow these guidelines to ensure a smooth contribution process.

## Quick start

1. Read **[AGENTS.md](AGENTS.md)** for the repo map, key conventions, and open architectural
   questions.
2. For deeper guidance — Conventional Commits spec, branch-naming edge cases, the `ajv` workflow,
   how to cite the project, and how CI enforces the conventions — see:
   - `docs/agents/conventions.md` — commits, branches, PRs, citation format, `ajv` workflow
   - `docs/agents/enforcement.md` — CI gates, CODEOWNERS, pre-commit hook, semver discipline
   - `docs/agents/glossary.md` — load-bearing vocabulary (Tier 1/2/3, KoTH, Oracle, ELO, etc.)
3. If you are an AI agent, start at `AGENTS.md` rather than this file.


## Filing Issues

When reporting a bug or requesting a feature:

1. **Use GitHub Issues** — open a new issue at this repository.
2. **Include the schema path** — which schema file does this relate to? (e.g., `schemas/tools/bash.schema.json`)
3. **Describe the problem** — what is wrong? What did you expect vs. what happened?
4. **Include a minimal example** — paste the JSON that fails validation or the schema change you propose.

Example issue title: `Schema: bash.schema.json — session_id format should use UUID v4 pattern`

## Submitting Pull Requests

1. **Fork** this repository.
2. **Create a feature branch** from `main`:
   ```
   git checkout -b fix/provenance-schema-typo
   ```
3. **Make your changes** to the relevant schema files, examples, or documentation.
4. **Validate your schemas** (see Schema Validation below).
5. **Commit with a clear message** referencing the issue if applicable:
   ```
   fix: correct type annotation in decision.schema.json (#42)
   ```
6. **Push to your fork** and open a pull request against `main`.

## Schema Validation

All JSON Schema files must be valid against JSON Schema draft 2020-12.

To validate a single schema:
```bash
ajv compile -s schemas/goals/provenance.schema.json
```

To validate all schemas:
```bash
for schema in schemas/**/*.schema.json; do
  ajv compile -s "$schema" || exit 1
done
```

To validate an example against a schema:
```bash
ajv validate -s schemas/tools/bash.schema.json -d examples/tier2-bash.json
```

All schema changes must pass `ajv compile` before a PR will be merged.

## Semantic Versioning Policy

This project uses [Semantic Versioning](https://semver.org):

- **Major** — breaking schema change: remove a required field, change a field type,
  or restructure a schema in a way that breaks existing consumers.
- **Minor** — additive change: add a new optional field, add a new schema file,
  or extend an existing enum.
- **Patch** — non-breaking fix: correct a typo, clarify a description, fix an
  invalid example, or update documentation.

State which category your change falls into in the pull request description.

## License

All contributions to this project are made available under the Apache License,
Version 2.0. See LICENSE for the complete license text. By submitting a pull
request, you agree that your contributions will be licensed under Apache-2.0.
