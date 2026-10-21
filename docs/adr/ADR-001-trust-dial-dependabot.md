---
title: "ADR-001 — Trust-dial-gated Dependabot auto-merge"
status: Proposed
date: 2026-05-22
---

## Context

`kellerai-oss-template` ships a Dependabot configuration that *proposes* dependency
updates and stops there: `.github/dependabot.yml:1-16` declares one ecosystem
(`github-actions`), a weekly schedule, a single update group, and `chore` commit prefix
— with **no reviewers, no labels, and no auto-merge gating**. Every Dependabot PR is
therefore either merged by hand or left to rot. There is no record of *why* an update
was accepted, no ladder of increasing automation, and no automatic response when an
accepted update later breaks CI.

The whitepaper *The Trust Dial: Earned Autonomy for Self-Improving AI
Primitives* (`the-trust-dial.md`, 2026-05-21) frames exactly this gap. A Dependabot PR
is a self-improvement proposal — an automated improver mutating a primitive (the repo's
pinned dependency set). The whitepaper's thesis is that such a loop is only safe to run
when its autonomy is *earned and enforced*, not asserted: *"a designed control that is
not enforced is documentation, not a control"* (`the-trust-dial.md:33`). It mandates
four enforcement layers — an append-only decision trace, ADRs, policy-as-code evaluated
by an engine external to the improver, and use-written telemetry — and a four-tier
autonomy dial (Observed → Assisted → Supervised → Trusted) that *"a new deployment
starts at Observed"* (`the-trust-dial.md:208`) and that *"is not a ratchet"*
(`the-trust-dial.md:212`).

A decision is needed now because the template is the conformance authority for an entire
family of repositories: whatever auto-merge posture it adopts is inherited by every repo
`scripts/bootstrap.sh` stamps. Shipping ungoverned auto-merge — or no auto-merge at all —
both fail the house standard. The repo already has the substrate to do this right: an
OPA/Rego policy engine (`conformance/conformance.rego`), a SHA-256 policy-integrity
self-tamper check (`conformance.rego:243-254`), a data-driven manifest
(`conformance/data.json`), and a zero-runtime-dependency design (OPA + bash + `gh` only).

## Considered options

| Option | Notes |
| ------ | ----- |
| **A — Leave Dependabot ungated** | Status quo. Zero build cost. But it scales as O(humans): every update is a manual review forever, and the whitepaper's §3 argues this is the unscalable reactive posture. Provides no trace, no audit, no earned autonomy. Rejected — it abdicates the house standard the template exists to set. |
| **B — Blanket auto-merge of all patch/minor updates** | Common GitHub-marketplace pattern (`dependabot/fetch-metadata` + a one-line auto-merge action). Cheap and fast. But it asserts a fixed autonomy level with no earned-trust ladder, no decision trace, no demotion-on-regression, and no policy engine — the exact "autonomy as a property, not a budget" anti-pattern the whitepaper rejects (`the-trust-dial.md:264`). Rejected. |
| **C — Trust-dial-gated auto-merge (OPA verdict policy + state file + decision trace + outcome-driven promotion/demotion)** | Implements all four whitepaper enforcement layers for the dependency-update loop. A pure-function Rego policy returns a verdict per `(tier × update-type × ecosystem)`; an append-only committed trace records every decision; a committed state file makes the tier a Git-auditable fact; post-merge CI outcome drives an earned promotion/demotion ladder with a budget cap and a count-based circuit breaker. Higher build cost; touches frozen content; requires a major version bump. |
| **D — External governance service** | A hosted policy/decision service outside the repo. Maximally centralized. Rejected — violates the zero-runtime-dependency invariant and the single-owner, non-replicable reference model; introduces an availability dependency the template must not have. |

## Decision

Adopt **Option C**: a trust-dial-gated Dependabot auto-merge system, implemented as
policy-as-code (`conformance/trust_dial.rego`), a committed append-only decision trace
(`audit/decision-trace.jsonl`) plus a retained per-run GitHub Actions artifact, a
committed trust-dial state file (`audit/trust-dial-state.json`), and two GitHub Actions
workflows — a gate (`trust-dial-gate.yml`) that evaluates the verdict and acts on it, and
an outcome workflow (`trust-dial-outcome.yml`) that drives earned promotion and automatic
demotion from post-merge CI results. A freshly bootstrapped repo starts at **Observed**,
whitepaper-mandated. The full design is specified in `trust-dial-dependabot-spec.md`.

Option C won because it is the only option that satisfies the whitepaper's "enforced, not
asserted" requirement: the verdict matrix is not a slide but a Rego file that the gate
workflow *runs* on every Dependabot PR, and a new conformance deny family
(`trust_dial_wired`) proves the gate is wired rather than merely present. It is the only
option that produces an audit trail, the only one with an earned-autonomy ladder that
demotes on regression, and the only one that respects the zero-runtime-dependency and
single-owner invariants. Options A and B fail the house standard the template exists to
define; option D breaks two named invariants.

## Consequences

**Easier.** Dependency hygiene becomes a governed, observable loop: every gate decision
is traced, the current autonomy tier is a queryable Git fact, and a repo earns less
human toil over time by accumulating a clean merge streak. The decision trace makes "why
did this update merge?" a query against a record, not an interrogation. The design closes
or advances five of the fourteen cross-discipline gaps in `gap-roadmap.md` — G-02
(dependency-hygiene audit), G-08 (conformance/decision observability), G-10
(decision-traceability for policy-class changes), G-11 (audit trail of policy-integrity
refreezes), and G-12 (templatization scope boundary).

**Harder.** The build touches frozen content — `conformance/**`, `template/**`,
`scripts/**` — each change paired with a semver-classified `CHANGELOG.md` entry, and the
whole build is a **major** version bump because it adds new *required* files and a new
error-level deny family. Editing `conformance/conformance.rego` mandates the
policy-integrity SHA-256 refreeze (`conformance.rego:243-254`,
`conformance/data.json:90-93`) in the same commit, or CI blocks. The CI write-back loop
(workflows committing state back to the repo) requires three independent recursion
guards. Governed auto-merge is slower than blanket auto-merge — a deliberate cost the
whitepaper names (`the-trust-dial.md:244`).

**Follow-up action items.**

- Implement per the phased build checklist in `trust-dial-dependabot-spec.md` §8 — ten
  reviewable PRs, steps 7–10 each carrying a CHANGELOG entry.
- Execute the policy-integrity digest refreeze in the same commit as the
  `conformance.rego` edit (checklist step 9); record the refreeze in the decision trace.
- Resolve open questions OQ-1..OQ-6 (`trust-dial-dependabot-spec.md` §9) before the
  tiers above Observed are exercised in anger — in particular OQ-2 (`outcome_signal` →
  ELO/KoTH mapping) and OQ-3 (reusable-workflow factoring).
- Extend `docs/adoption-guide.md` with the migration path for already-bootstrapped repos
  (add `audit/` + the two workflows or fail conformance).
