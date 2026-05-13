---
name: security-review
description: 'AI-powered security scanner that reasons about code like a security researcher — tracing data flows, understanding component interactions, and catching vulnerabilities that pattern-matching tools miss. Used by the senior-reviewer agent during the Validate step to audit changed files for injection flaws, authentication and access control bugs, secrets exposure, weak cryptography, insecure dependencies, and business logic issues across JavaScript, TypeScript, and Ruby.'
---

# Security Review

An AI-powered security scanner that reasons about your codebase the way a human security
researcher would — tracing data flows, understanding component interactions, and catching
vulnerabilities that pattern-matching tools miss.

## When to Use This Skill

This skill is invoked by the `senior-reviewer` agent during the Validate step. It runs against the PR diff — all files changed in the current branch — and outputs a structured findings report that the senior reviewer includes in its verdict.

It can also be invoked directly when asked to:

- Scan a specific file or directory for security vulnerabilities
- Check for SQL injection, XSS, command injection, or other injection flaws
- Find exposed API keys, hardcoded secrets, or credentials in code
- Audit dependencies for known CVEs
- Review authentication, authorization, or access control logic

## How This Skill Works

Unlike traditional static analysis tools that match patterns, this skill:

1. **Reads code like a security researcher** — understanding context, intent, and data flow
2. **Traces across files** — following how user input moves through your application
3. **Self-verifies findings** — re-examines each result to filter false positives
4. **Assigns severity ratings** — CRITICAL / HIGH / MEDIUM / LOW / INFO
5. **Proposes targeted patches** — every CRITICAL and HIGH finding includes a concrete fix for the Implement agent to apply

## Execution Workflow

All `references/` paths below are relative to this skill's base directory (provided in the skill header). Use the Read tool with the full absolute path when loading them.

Follow these steps **in order** every time:

### Step 1 — Scope Resolution

Determine what to scan:

- **When called from senior-reviewer**: scan only the files changed in the current PR diff (`git diff main...HEAD --name-only`). Cross-file data flow analysis (Step 5) may read adjacent files for context, but the primary scan targets the diff.
- **When called with a path**: scan only that scope
- **When called with no path**: scan the entire project from the root
- Identify the language(s) and framework(s) in use (check `package.json`, `Gemfile`, etc.)
- Read `references/language-patterns.md` to load language-specific vulnerability patterns

### Step 2 — Dependency Audit

Before scanning source code, audit dependencies first (fast wins):

- **Node.js**: Check `package.json` + `package-lock.json` for known vulnerable packages
- **Ruby**: Check `Gemfile.lock`
- Flag packages with known CVEs, deprecated crypto libs, or suspiciously old pinned versions
- Read `references/vulnerable-packages.md` for a curated watchlist

### Step 3 — Secrets & Exposure Scan

Scan ALL files (including config, env, CI/CD, Dockerfiles, IaC) for:

- Hardcoded API keys, tokens, passwords, private keys
- `.env` files accidentally committed
- Secrets in comments or debug logs
- Cloud credentials (AWS, GCP, Azure, Stripe, Twilio, etc.)
- Database connection strings with credentials embedded
- Read `references/secret-patterns.md` for regex patterns and entropy heuristics to apply

### Step 4 — Vulnerability Deep Scan

This is the core scan. Reason about the code — don't just pattern-match.
Read `references/vuln-categories.md` for full details on each category.

**Injection Flaws**

- SQL Injection: raw queries with string interpolation, ORM misuse, second-order SQLi
- XSS: unescaped output, dangerouslySetInnerHTML, innerHTML, template injection
- Command Injection: exec/spawn/system with user input
- LDAP, XPath, Header, Log injection

**Authentication & Access Control**

- Missing authentication on sensitive endpoints
- Broken object-level authorization (BOLA/IDOR)
- JWT weaknesses (alg:none, weak secrets, no expiry validation)
- Session fixation, missing CSRF protection
- Privilege escalation paths
- Mass assignment / parameter pollution

**Data Handling**

- Sensitive data in logs, error messages, or API responses
- Missing encryption at rest or in transit
- Insecure deserialization
- Path traversal / directory traversal
- XXE (XML External Entity) processing
- SSRF (Server-Side Request Forgery)

**Cryptography**

- Use of MD5, SHA1, DES for security purposes
- Hardcoded IVs or salts
- Weak random number generation (Math.random() for tokens)
- Missing TLS certificate validation

**Business Logic**

- Race conditions (TOCTOU)
- Integer overflow in financial calculations
- Missing rate limiting on sensitive endpoints
- Predictable resource identifiers

### Step 5 — Cross-File Data Flow Analysis

After the per-file scan, perform a **holistic review**:

- Trace user-controlled input from entry points (HTTP params, headers, body, file uploads)
  all the way to sinks (DB queries, exec calls, HTML output, file writes)
- Identify vulnerabilities that only appear when looking at multiple files together
- Check for insecure trust boundaries between services or modules

### Step 6 — Self-Verification Pass

For EACH finding:

1. Re-read the relevant code with fresh eyes
2. Ask: "Is this actually exploitable, or is there sanitization I missed?"
3. Check if a framework or middleware already handles this upstream
4. Downgrade or discard findings that aren't genuine vulnerabilities
5. Assign final severity: CRITICAL / HIGH / MEDIUM / LOW / INFO

### Step 7 — Generate Security Report

Output the full report in the format defined in `references/report-format.md`.

### Step 8 — Propose Patches

For every CRITICAL and HIGH finding, generate a concrete patch:

- Show the vulnerable code (before)
- Show the fixed code (after)
- Explain what changed and why
- Preserve the original code style, variable names, and structure

These patches are included in the senior reviewer's verdict. The senior reviewer marks each CRITICAL and HIGH finding as a blocker. The Implement agent applies accepted fixes before the next review pass.

## Severity Guide

| Severity    | Meaning                                         | Example                          |
| ----------- | ----------------------------------------------- | -------------------------------- |
| 🔴 CRITICAL | Immediate exploitation risk, data breach likely | SQLi, RCE, auth bypass           |
| 🟠 HIGH     | Serious vulnerability, exploit path exists      | XSS, IDOR, hardcoded secrets     |
| 🟡 MEDIUM   | Exploitable with conditions or chaining         | CSRF, open redirect, weak crypto |
| 🔵 LOW      | Best practice violation, low direct risk        | Verbose errors, missing headers  |
| ⚪ INFO     | Observation worth noting, not a vulnerability   | Outdated dependency (no CVE)     |

## Output Rules

- **Always** produce a findings summary table first (counts by severity)
- **Always** include a confidence rating per finding (High / Medium / Low)
- **Group findings** by category, not by file
- **Be specific** — include file path, line number, and the exact vulnerable code snippet
- **Explain the risk** in plain English — what could an attacker do with this?
- If the scanned scope is clean, say so clearly: "No vulnerabilities found" with what was scanned
- Output is consumed by the senior reviewer — structure it so findings slot directly into the review verdict

## Reference Files

For detailed detection guidance, load the following reference files as needed:

- `references/vuln-categories.md` — Deep reference for every vulnerability category with detection signals, safe patterns, and escalation checkers
  - Search patterns: `SQL injection`, `XSS`, `command injection`, `SSRF`, `BOLA`, `IDOR`, `JWT`, `CSRF`, `secrets`, `cryptography`, `race condition`, `path traversal`
- `references/secret-patterns.md` — Regex patterns, entropy-based detection, and CI/CD secret risks
  - Search patterns: `API key`, `token`, `private key`, `connection string`, `entropy`, `.env`, `GitHub Actions`, `Docker`, `Terraform`
- `references/language-patterns.md` — Framework-specific vulnerability patterns for JavaScript, TypeScript, and Ruby
  - Search patterns: `Express`, `React`, `Next.js`, `Rails`
- `references/vulnerable-packages.md` — Curated CVE watchlist for npm and Rubygems
  - Search patterns: `lodash`, `axios`, `jsonwebtoken`, `nokogiri`, `CVE`
- `references/report-format.md` — Structured output template for security reports with finding cards, dependency audit, secrets scan, and patch proposal formatting
  - Search patterns: `report`, `format`, `template`, `finding`, `patch`, `summary`, `confidence`
