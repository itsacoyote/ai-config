# Debugging & Flaky Tests

## Debugging workflow (the crown jewel)

When a test is flaky or failing, work the loop — don't guess-and-rerun:

1. **Run** the failing test with a trace enabled (`trace: 'on-first-retry'` in config, plus `screenshot: 'only-on-failure'`). Reproduce under the same conditions it fails (often: with retries, headless, in CI).
2. **Trace** — open the captured trace in the trace viewer (`npx playwright show-trace`) or run in UI mode. The trace gives you the timeline, DOM snapshots, network, and console at each step.
3. **Inspect** — find the exact action that failed and *why*: was the element not yet present/visible/stable? Did data not load? Did a prior test leave state behind? For live poking, drop a `page.pause()` and run headed.
4. **Fix** the root cause (see causes below) — not the symptom. Replacing a real wait condition with a bigger timeout is not a fix.
5. **Verify** by running the test many times (e.g. `--repeat-each=10`) to confirm the flake is actually gone, not just hidden by luck.

## Common flaky causes (and the durable fix)

The through-line: **wait for the condition you actually depend on**, and let auto-waiting locators do it. Almost every flake is a hidden race that a fixed timeout papers over.

**Race conditions** — acting before the element is interactable.
```typescript
await page.click('.submit-btn');                              // ❌ may not exist yet
await page.getByRole('button', { name: 'Submit' }).click();   // ✅ auto-waits
```

**Animations / transitions** — clicking mid-transition. Wait for the stable end state (e.g. assert the target is visible) before acting.

**Network timing** — asserting on data before it loads. Wait for the response or the rendered result, not a guessed delay:
```typescript
await page.goto('/dashboard');
await expect(page.getByTestId('user-name')).toHaveText('John'); // ✅ retries until true
```

**Test isolation** — tests sharing state so order/parallelism changes outcomes. Each test must set up and tear down its own state (reset via API in `beforeEach`); never assume another test ran first.

## Waiting: prefer conditions over timers

Wait on the actual state — `expect(locator).toBeVisible()/toBeEnabled()/toBeHidden()`, `waitForURL`, or `waitForResponse` for a specific request. Never `waitForTimeout(n)`.

⚠️ **`networkidle` caveat:** `waitForLoadState('networkidle')` is unreliable with long-polling, websockets, or streaming (SSE) — the network never goes idle, so the wait hangs or times out. Prefer `expect(locator).toBeVisible()` or `waitForResponse(...)` instead.

## Retries

Retries (`retries: process.env.CI ? 2 : 0`) mask intermittent failures so a suite stays green — they are a safety net for genuinely nondeterministic externals, **not** a substitute for fixing a flake whose root cause you can find.

Confirm current debug flags, config keys, and trace-viewer commands via the Playwright docs / `web-search`.
