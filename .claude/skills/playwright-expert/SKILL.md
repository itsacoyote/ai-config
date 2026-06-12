---
name: playwright-expert
description: Use when writing E2E tests with Playwright, setting up browser-test infrastructure, or debugging flaky tests — writing test scripts, Page Object Model, fixtures, reporters, CI integration, API mocking, or visual regression testing.
---

# Playwright Expert

E2E testing specialist with deep expertise in Playwright for robust, maintainable browser automation.

## When to Use

- Writing E2E / browser tests with Playwright
- Setting up test infrastructure — config, fixtures, reporters
- Building Page Object Models for maintainable tests
- Mocking APIs or intercepting network requests
- Adding Playwright to a CI pipeline
- Debugging flaky tests with traces and the trace viewer
- Visual regression testing

## Core Workflow

1. **Analyze requirements** - Identify user flows to test
2. **Setup** - Configure Playwright with proper settings
3. **Write tests** - Use POM pattern, proper selectors, auto-waiting
4. **Debug** - Run test → check trace → identify issue → fix → verify fix
5. **Integrate** - Add to CI/CD pipeline

## Reference Guide

Load detailed guidance based on context:

| Topic | Reference | Load When |
|-------|-----------|-----------|
| Selectors | `references/selectors-locators.md` | Writing selectors, locator priority |
| Page Objects | `references/page-object-model.md` | POM patterns, fixtures |
| Debugging | `references/debugging-flaky.md` | Flaky tests, trace viewer |

## Code Examples

### Selector: Role-based (correct) vs CSS class (brittle)

```typescript
// ✅ Role-based selector — resilient to styling changes
await page.getByRole('button', { name: 'Submit' }).click();
await page.getByLabel('Email address').fill('user@example.com');

// ❌ CSS class selector — breaks on refactor
await page.locator('.btn-primary.submit-btn').click();
await page.locator('.email-input').fill('user@example.com');
```

### Wait properly — never on a fixed timer

```typescript
// ❌ Flaky — guesses how long an action takes
await page.waitForTimeout(2000);
await page.getByRole('button', { name: 'Save' }).click();

// ✅ Reliable — auto-waits for the actual state it needs
await page.getByRole('button', { name: 'Save' }).click();
```

Auto-waiting beats fixed timeouts because it waits for the *condition* (element visible, enabled, network settled), not a wall-clock guess that's simultaneously too slow on a fast machine and too short under CI load. See `references/page-object-model.md` for the POM pattern and `references/debugging-flaky.md` for the flaky-test workflow. Confirm current API via the Playwright docs / `web-search`.

## Constraints

### MUST DO
- Use role-based selectors when possible
- Leverage auto-waiting (don't add arbitrary timeouts)
- Keep tests independent (no shared state)
- Use Page Object Model for maintainability
- Enable traces/screenshots for debugging
- Run tests in parallel

### MUST NOT DO
- Use `waitForTimeout()` (use proper waits)
- Rely on CSS class selectors (brittle)
- Share state between tests
- Ignore flaky tests
- Use `first()`, `nth()` without good reason

## Output Order

When implementing Playwright tests, provide: Page Object classes → test files with proper assertions → fixture setup (if needed) → configuration recommendations.

## Related Skills

- **`writing-tests`** — general test design and how much to test; this skill covers the Playwright-specific syntax (locators, fixtures, config).
- **`browser-testing-with-devtools`** — real-time DOM/console/network inspection of a running page via the chrome-devtools MCP, versus the automated test runs here.
- **`qa-review`** — verifies coverage and quality and runs the e2e suite this skill produces.
