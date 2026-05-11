---
name: web-search
description: Search documentation, official guides, and the web for information about third-party libraries, external APIs, or unfamiliar tools needed for a feature. Use during research when the codebase alone doesn't answer how something external works.
argument-hint: [library, API, or topic to search]
allowed-tools: WebSearch WebFetch
---

# Web Search

Search the web for documentation or guidance on `$ARGUMENTS`. If no topic is provided, ask what to look up.

## When to use this

Use web search during research when:

- A third-party library is used (or being considered) and its behavior, API surface, or configuration options need to be understood
- An external API or service is involved and you need to understand its capabilities, rate limits, auth model, or data shape
- A tool, framework feature, or concept appears in the codebase and isn't self-explanatory from reading the code

Do not use web search to find general programming knowledge you already have. Use it when the specific library version, API contract, or external behavior matters.

## How to search

1. **Confirm the project's version first** — before searching, read the project's dependency manifest (`package.json`, `requirements.txt`, `go.mod`, `Gemfile`, `pubspec.yaml`, etc.) to find the exact version in use. If a range is specified (e.g. `^4.2.0`), note the minimum and resolve the likely installed version from a lock file (`package-lock.json`, `yarn.lock`, `poetry.lock`, etc.) if one exists.
2. **Start with official sources** — look for official documentation, changelogs, or GitHub READMEs before reaching for blog posts or Stack Overflow.
3. **Match the version explicitly** — when fetching documentation, verify the page or URL corresponds to the confirmed version. Many doc sites have version switchers; use them. Do not assume the latest docs match the version in the project.
4. **Fetch the relevant page** — don't rely on search snippets alone; fetch and read the actual documentation page for anything that will influence implementation decisions.
5. **Cross-reference** — if something is unclear or seems off, check a second source before documenting it as fact.

## Version mismatch handling

If the documentation found does not clearly match the version in use:

- State the version discrepancy explicitly in the report
- Note what changed between versions if the changelog reveals relevant differences
- Flag this as a risk — do not present docs for a different version as authoritative

## What to report

- The confirmed library version from the project's dependency files
- What was searched and why
- What was found: the key facts that matter for the feature (API surface, required config, limits, gotchas)
- Source URL, whether it's official documentation, and the version it covers
- Any version mismatch or gaps — label clearly if something couldn't be confirmed
