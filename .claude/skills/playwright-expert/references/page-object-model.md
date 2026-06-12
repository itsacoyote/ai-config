# Page Object Model

## What it is

A Page Object encapsulates *how* to interact with a page or component behind a named API, so tests read as intent (`loginPage.login(email, pw)`) instead of a wall of low-level locator calls. When the UI changes, you update one class — not every test.

```typescript
export class LoginPage {
  readonly emailInput = this.page.getByLabel('Email');
  readonly submitButton = this.page.getByRole('button', { name: 'Log in' });

  constructor(private page: Page) {}

  async goto() { await this.page.goto('/login'); }
  async login(email: string, password: string) {
    await this.emailInput.fill(email);
    await this.page.getByLabel('Password').fill(password);
    await this.submitButton.click();
  }
}
```

## What belongs in a Page Object

- **Locators** — declared as fields/getters, evaluated lazily (so they resolve at use time, not construction).
- **Actions** — methods that perform a user flow (`login`, `addToCart`). Named for intent.
- **NOT assertions.** Keep `expect(...)` in the test, not the Page Object — the same page is exercised by tests with different expectations, so baking in assertions kills reuse.

## Composition

- **Component objects** for reusable UI (nav bar, modal) — compose them into page objects rather than duplicating locators.
- **Fixtures** to share setup (e.g. an already-authenticated page) across tests instead of repeating `beforeEach` boilerplate — this keeps setup DRY and tests independent.

Confirm current fixture / `test.extend` API via the Playwright docs / `web-search`.
