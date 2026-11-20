import base from './steps.mjs';

export default {
  ...base,
  name: 'missing',
  steps: [
    { id: 'no-such-element', act: (page, h) => h.expectVisible(page.locator('#nope'), 500) },
  ],
};
