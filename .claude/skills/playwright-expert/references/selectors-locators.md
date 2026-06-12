# Selectors & Locators

## Selector Priority (Best to Worst)

Prefer selectors in this order: **role > label/placeholder > text > test-id > CSS/XPath**.

1. **Role** (`getByRole`) — queries the accessibility tree the way a user/screen-reader perceives the page. Most resilient: survives restyling and DOM restructuring, and a failing role selector often signals a real a11y gap.
2. **Label / placeholder** (`getByLabel`, `getByPlaceholder`) — best for form fields; ties the test to the visible/accessible label, not markup.
3. **Text** (`getByText`) — good for static, user-visible copy.
4. **Test ID** (`getByTestId`) — explicit contract for non-semantic elements with no good role/label. Stable, but invisible to users so it can drift from real UX.
5. **CSS / XPath** (`locator`) — last resort. Brittle: couples the test to styling and DOM shape, which refactors break.

```typescript
// ✅ Role-based — resilient to styling/DOM changes
await page.getByRole('button', { name: 'Submit' }).click();

// ❌ CSS class — breaks on any refactor
await page.locator('.btn-primary.submit-btn').click();
```

## Filtering and multiple matches

When one query matches several elements, narrow by *meaning* (filter by text, by a child locator, or chain into a container) rather than reaching for positional `nth()`/`first()` — position is fragile and hides intent. `filter({ has })` / `filter({ hasText })` and locator chaining are the durable tools here.

Confirm exact method signatures (`getByRole` options, `filter`, custom `testIdAttribute` config) via the Playwright docs / `web-search`.
