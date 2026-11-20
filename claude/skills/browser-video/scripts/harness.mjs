/**
 * Helpers passed to each step's act(page, h).
 */

export function createHelpers(page) {
  return {
    async expectVisible(locator, timeout = 5000) {
      try {
        await locator.waitFor({ state: 'visible', timeout });
      } catch (error) {
        throw new Error(`expected element to be visible within ${timeout} ms: ${error.message}`);
      }
    },
  };
}
