export default {
  name: 'fixture-flow',
  url: new URL('./page.html', import.meta.url).href,
  steps: [
    {
      id: 'open',
      hold: 800,
      act: (page, h) => h.expectVisible(page.locator('#title')),
    },
    {
      id: 'go',
      hold: 900,
      act: async (page, h) => {
        await page.click('#go');
        await h.expectVisible(page.locator('#result'));
      },
    },
  ],
};
