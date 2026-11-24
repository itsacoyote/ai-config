import base from './steps.mjs';

export default {
  ...base,
  name: 'highlight-missing',
  steps: [
    { id: 'no-highlight-target', act: (page, h) => h.highlight(page.locator('#nope')) },
  ],
};
