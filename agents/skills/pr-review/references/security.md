# Security Pass

Audit the PR's diff for vulnerabilities — reason about data flows and component interactions
like a security researcher, not a pattern-matcher. Scoped to what this PR's diff introduces or
alters; read surrounding files only to follow a flow that starts in the diff. Read-only.

## What to check

**Injection** — SQL injection (string-built queries, ORM misuse), XSS (unescaped output,
`dangerouslySetInnerHTML`/`innerHTML`, template injection), command injection (exec/spawn with
user input), LDAP/XPath/header/log injection.

**Auth & access control** — missing auth on sensitive endpoints, broken object-level
authorization (BOLA/IDOR), JWT weaknesses (`alg:none`, weak secret, no expiry check), session
fixation, missing CSRF protection, privilege escalation, mass assignment.

**Data handling** — sensitive data in logs/errors/responses, missing encryption in transit or
at rest, insecure deserialization, path traversal, XXE, SSRF.

**Cryptography** — MD5/SHA1/DES for security use, hardcoded IVs or salts, `Math.random()` for
tokens, missing TLS certificate validation.

**Business logic** — race conditions (TOCTOU), integer overflow in financial math, missing
rate limiting on sensitive endpoints, predictable resource identifiers.

**Secrets exposure** — hardcoded API keys/tokens/passwords/private keys, committed `.env`
files, credentials embedded in connection strings, secrets in comments or debug logs.

## Method

1. Trace user-controlled input from entry points (params, headers, body, uploads) to sinks
   (queries, exec calls, HTML output, file writes).
2. For each candidate finding, re-read the code and ask: is this actually exploitable, or does
   a framework/middleware already handle it upstream? Discard false positives.
3. Assign severity: CRITICAL / HIGH / MEDIUM / LOW / INFO.

If the diff is empty or clean, say so plainly — don't manufacture filler findings.

## Finding format

Order most severe first. For each:

- **Severity** — CRITICAL / HIGH / MEDIUM / LOW / INFO
- **Where** — file:line
- **What** — the vulnerability
- **Why** — the impact / exploit path
- **Suggested comment text** — the fix, described as text ready to post as a review comment
