## Summary

<!-- What does this PR change, and why? -->

## Schemas touched

<!--
Which files changed? Group by area:
  - schemas/base/       (base-metadata.schema.json)
  - schemas/goals/      (provenance, experiment, koth, decision, backward-compat)
  - schemas/telemetry/  (unified-activity-extensions)
  - schemas/tools/      (per-tool schemas — list affected tools)
  - examples/           (worked examples)
  - docs/               (design docs, companion docs, agent docs)
  - .github/            (workflows, templates, CODEOWNERS, dependabot)
  - root                (commitlint.config.js, lefthook.yml, CHANGELOG.md, etc.)
-->

## Validation output

<!--
Paste the output of the relevant checks you ran locally:

  # Compile all schemas
  for schema in schemas/**/*.schema.json; do
    npx ajv-cli compile --spec=draft2020 --strict=false -s "$schema"
  done

  # Validate worked examples
  npx ajv-cli validate --spec=draft2020 --strict=false -s schemas/base/base-metadata.schema.json \
    -d examples/tier1-ask-user-question.json

  # Sanitization gate
  bash scripts/check-sanitization.sh
-->

## Semver classification

<!-- Mark exactly one. See AGENTS.md and CHANGELOG.md for the semver policy. -->

- [ ] **major** — removes a required field, changes a field type, or tightens a constraint in a way that breaks existing valid metadata
- [ ] **minor** — additive, backward-compatible (new optional field, new tool schema, relaxed constraint)
- [ ] **patch** — clarification, editorial, or docs/examples-only change; no schema behaviour change

## Contributor

- [ ] I am an agent acting on behalf of `<handle>`
