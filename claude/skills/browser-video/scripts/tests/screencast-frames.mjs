// Prints how many CDP screencast frames Chromium sends for a static page with the overlay installed.
// Run from the project that has Playwright: node screencast-frames.mjs <page file>
import { createRequire } from 'node:module';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { setTimeout as sleep } from 'node:timers/promises';
import { addOverlay } from '../harness.mjs';

const SETTLE_MS = 300;
const WINDOW_MS = 1500;

const require = createRequire(join(process.cwd(), 'package.json'));
const { chromium } = require('playwright');

const browser = await chromium.launch({ headless: true, chromiumSandbox: process.platform !== 'linux' });
try {
  const context = await browser.newContext({ viewport: { width: 800, height: 450 } });
  await addOverlay(context);
  const page = await context.newPage();
  await page.goto(pathToFileURL(resolve(process.argv[2])).href);
  await sleep(SETTLE_MS);
  const cdp = await context.newCDPSession(page);
  let frames = 0;
  cdp.on('Page.screencastFrame', async ({ sessionId }) => {
    frames++;
    await cdp.send('Page.screencastFrameAck', { sessionId }).catch(() => {});
  });
  await cdp.send('Page.startScreencast', { format: 'jpeg', quality: 10, maxWidth: 800, maxHeight: 450 });
  await sleep(WINDOW_MS);
  await cdp.send('Page.stopScreencast');
  console.log(frames);
} finally {
  await browser.close();
}
