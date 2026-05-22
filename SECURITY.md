# Security Policy

## Scope

This repository contains a **JSON Schema specification** only. There is no
runtime code, no server, and no deployable artifact. Security-relevant defects
are limited to schema design issues that could cause harm if a naive
implementation follows the schema literally — for example:

- An identifier or reference field that should be hashed or pseudonymised before
  storage but is not marked as such in the schema description or documentation.
- A field whose `examples` or `default` value contains real or realistic PII
  (names, email addresses, device fingerprints, IP addresses).
- A required field that inadvertently forces callers to log sensitive data in
  plaintext.

**Out of scope:** vulnerabilities in third-party tools (e.g. `ajv`), issues in
consumer implementations that wire this schema into their own pipelines, or
general JSON Schema validator bugs. Report those to the respective upstream
projects.

## Reporting a Vulnerability

Use **GitHub Security Advisories** for this repository:

1. Navigate to
   `https://github.com/jonathan-kellerai/dgm-telemetry/security/advisories/new`
2. Describe the schema field or design pattern that creates the risk.
3. Include a concrete example of how a naive implementation would expose PII or
   leak sensitive data if it followed the schema as written.
4. Suggest a remediation if you have one (e.g. adding a `"format": "uuid"`
   constraint, updating the field description to require hashing, redacting an
   example value).

Do **not** open a public GitHub Issue for security reports — use the private
advisory channel above.

## Response Commitment

- Acknowledgement within **5 business days**.
- Assessment (in-scope / out-of-scope, severity) within **14 calendar days**.
- Schema patch or documented mitigation within **30 calendar days** for confirmed
  in-scope findings.

Reporters who responsibly disclose valid findings will be credited in the
`CHANGELOG.md` entry for the fixing release, unless they prefer to remain
anonymous.
