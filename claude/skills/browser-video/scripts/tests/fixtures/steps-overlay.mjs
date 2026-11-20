import { appendFileSync } from 'node:fs';
import base from './steps.mjs';

const seen = (key, value) => {
  if (process.env.BV_OBS) appendFileSync(process.env.BV_OBS, `${JSON.stringify({ key, value })}\n`);
};

// "idle" and "aim" show the same page, so a frame compare between them isolates the caption and the pointer.
export default {
  ...base,
  name: 'overlay-flow',
  steps: [
    {
      id: 'idle',
      hold: 1800,
      act: (page, h) => h.expectVisible(page.locator('#title')),
    },
    {
      id: 'aim',
      caption: 'Save changes',
      hold: 2400,
      act: async (page, h) => {
        await h.click(page.locator('#inert'));
        seen('captionCount', await page.getByText('Save changes').count());
      },
    },
    {
      id: 'type',
      hold: 2200,
      act: async (page, h) => {
        await h.highlight(page.locator('#name'), 500);
        await h.type(page.locator('#name'), 'Ada Lovelace');
        seen('typed', await page.locator('#name').inputValue());
      },
    },
    {
      id: 'card',
      hold: 1800,
      act: async (page, h) => {
        await h.card({ title: 'Chapter two' });
        seen('cardTextCount', await page.getByText('Chapter two').count());
      },
    },
    {
      id: 'save',
      caption: 'Save changes',
      hold: 1200,
      act: async (page, h) => {
        seen('valueAfterCard', await page.locator('#name').inputValue());
        await h.click(page.locator('#save'));
        seen('label', await page.locator('#save').textContent());
      },
    },
    {
      id: 'scroll',
      hold: 800,
      act: async (page, h) => {
        await h.scroll(700);
        seen('scrolled', await page.evaluate(() => window.scrollY > 0));
      },
    },
    // Last, so its caption is only cleared by the end-of-step clear: no later step resets it.
    { id: 'finish', caption: 'Done', hold: 1200, act: () => {} },
  ],
};
