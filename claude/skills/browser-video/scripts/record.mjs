#!/usr/bin/env node
/**
 * Record a scripted browser flow to an H.264 MP4.
 *
 * Usage:
 *   node record.mjs <steps-file> [--out <dir>]
 *   node record.mjs --check
 *
 * Exit (record): 0 MP4 written, 1 run failed, 2 usage error or invalid steps file.
 * Exit (--check): 0 ok, 3 Playwright not resolvable from cwd, 4 Chromium not usable.
 */

import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { setTimeout as sleep } from 'node:timers/promises';
import { createHelpers } from './harness.mjs';

const DEFAULT_VIEWPORT = { width: 1440, height: 900 };
const DEFAULT_HOLD_MS = 1500;
const TRAILING_HOLD_MS = 500;
const STDERR_TAIL_CHARS = 2000;

class UsageError extends Error {}

function parseArgs(argv) {
  const args = { check: false, stepsFile: undefined, out: undefined };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--check') args.check = true;
    else if (arg === '--out') {
      const value = argv[++i];
      if (!value) throw new UsageError('--out needs a directory');
      args.out = value;
    } else if (arg.startsWith('-')) throw new UsageError(`unknown option: ${arg}`);
    else if (args.stepsFile) throw new UsageError('only one steps file is accepted');
    else args.stepsFile = arg;
  }
  if (!args.check && !args.stepsFile) {
    throw new UsageError('usage: record.mjs <steps-file> [--out <dir>] | record.mjs --check');
  }
  return args;
}

// Resolved from cwd, never from this file: the skill directory is symlinked into
// ~/.claude, so a bare import would look in the wrong node_modules.
async function loadChromium() {
  const require = createRequire(join(process.cwd(), 'package.json'));
  for (const id of ['playwright', '@playwright/test', 'playwright-core']) {
    let resolved;
    try {
      resolved = require.resolve(id);
    } catch {
      continue;
    }
    const mod = await import(pathToFileURL(resolved).href);
    const chromium = mod.chromium ?? mod.default?.chromium;
    if (chromium) return chromium;
  }
  return null;
}

async function check() {
  const chromium = await loadChromium();
  if (!chromium) {
    console.log('missing: playwright');
    return 3;
  }
  try {
    const browser = await chromium.launch({ headless: true, timeout: 15000 });
    await browser.close();
  } catch {
    console.log('missing: chromium');
    return 4;
  }
  return 0;
}

function isPositiveEven(n) {
  return Number.isInteger(n) && n > 0 && n % 2 === 0;
}

function validateSteps(def) {
  const fail = (message) => {
    throw new UsageError(`invalid steps file: ${message}`);
  };
  if (!def || typeof def !== 'object') fail('the module must export an object (default export or named exports)');
  const { name, url, viewport = DEFAULT_VIEWPORT, steps } = def;

  if (typeof name !== 'string' || !/^[A-Za-z0-9._-]+$/.test(name) || name.startsWith('.')) {
    fail('"name" must match [A-Za-z0-9._-]+ and not start with "."');
  }
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    fail('"url" must be an absolute http:, https: or file: URL');
  }
  if (!['http:', 'https:', 'file:'].includes(parsed.protocol)) {
    fail('"url" must be an absolute http:, https: or file: URL');
  }
  if (!viewport || !isPositiveEven(viewport.width) || !isPositiveEven(viewport.height)) {
    fail('"viewport" needs positive even integer width and height');
  }
  if (!Array.isArray(steps) || steps.length === 0) fail('"steps" must be a non-empty array');
  steps.forEach((step, i) => {
    if (!step || typeof step.id !== 'string' || step.id === '') fail(`step ${i}: "id" must be a non-empty string`);
    if (typeof step.act !== 'function') fail(`step "${step.id}": "act" must be a function`);
    if (step.hold !== undefined && !(Number.isFinite(step.hold) && step.hold >= 0)) {
      fail(`step "${step.id}": "hold" must be a finite number >= 0`);
    }
  });
  return { name, url, viewport: { width: viewport.width, height: viewport.height }, steps };
}

async function loadSteps(stepsFile) {
  const absolute = resolve(stepsFile);
  console.log(`steps: ${absolute}`);
  let mod;
  try {
    mod = await import(pathToFileURL(absolute).href);
  } catch (error) {
    throw new UsageError(`cannot load steps file ${absolute}: ${error.message}`);
  }
  return validateSteps(mod.default ?? mod);
}

// Playwright writes frames only when the page repaints, so a static tail can be missing
// from the webm (seen on Linux). Cloning the last frame and cutting at the wall-clock
// duration keeps the video as long as the recorded session.
function encode(webm, mp4, seconds) {
  const ffmpegArgs = [
    '-nostdin', '-hide_banner', '-loglevel', 'error', '-y',
    '-i', webm,
    '-vf', 'tpad=stop_mode=clone:stop_duration=60,fps=30,scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p',
    '-t', seconds.toFixed(3),
    '-c:v', 'libx264', '-preset', 'medium', '-crf', '20',
    '-movflags', '+faststart', '-an',
    mp4,
  ];
  return new Promise((resolveEncode, rejectEncode) => {
    const child = spawn('ffmpeg', ffmpegArgs, { stdio: ['ignore', 'ignore', 'pipe'] });
    let stderr = '';
    child.stderr.on('data', (chunk) => {
      stderr = (stderr + chunk).slice(-STDERR_TAIL_CHARS);
    });
    child.on('error', (error) => rejectEncode(new Error(`cannot run ffmpeg (run preflight.sh): ${error.message}`)));
    child.on('close', (code) => {
      if (code === 0) resolveEncode();
      else rejectEncode(new Error(`ffmpeg exited with ${code}:\n${stderr}`));
    });
  });
}

function fileSafe(text) {
  return text.replace(/[^A-Za-z0-9._-]/g, '_');
}

async function record(stepsFile, outArg) {
  const { name, url, viewport, steps } = await loadSteps(stepsFile);

  const chromium = await loadChromium();
  if (!chromium) {
    console.error('error: Playwright is not resolvable from the current directory; run preflight.sh');
    return 1;
  }

  const outDir = outArg ? resolve(outArg) : mkdtempSync(join(tmpdir(), 'browser-video-'));
  mkdirSync(outDir, { recursive: true });

  let browser;
  try {
    browser = await chromium.launch({ headless: true });
  } catch (error) {
    console.error(`error: Chromium failed to launch; run preflight.sh\n${error.message}`);
    return 1;
  }

  const context = await browser.newContext({ viewport, recordVideo: { dir: outDir, size: viewport } });
  let page;
  let failed = false;
  const timeline = [];
  let webm;
  let totalSeconds = 0;
  try {
    page = await context.newPage();
    // Video recording starts when the page is created, so timeline offsets count from here.
    const t0 = performance.now();
    const elapsed = () => (performance.now() - t0) / 1000;
    const h = createHelpers(page);

    await page.goto(url);
    for (const step of steps) {
      const start = elapsed();
      try {
        await step.act(page, h);
        const remaining = (step.hold ?? DEFAULT_HOLD_MS) - (elapsed() - start) * 1000;
        if (remaining > 0) await sleep(remaining);
      } catch (error) {
        failed = true;
        console.error(`error: step "${step.id}" failed: ${error.message}`);
        const shot = join(outDir, `failure-${fileSafe(step.id)}.png`);
        try {
          await page.screenshot({ path: shot });
          console.error(`screenshot: ${shot}`);
        } catch (shotError) {
          console.error(`error: could not take failure screenshot: ${shotError.message}`);
        }
        break;
      }
      const entry = { id: step.id, start, end: elapsed() };
      if (step.caption) entry.caption = step.caption;
      timeline.push(entry);
    }
    if (!failed) await sleep(TRAILING_HOLD_MS);
    totalSeconds = elapsed();
  } catch (error) {
    failed = true;
    console.error(`error: ${error.message}`);
  } finally {
    // The webm is only complete once the context is closed.
    await context.close().catch(() => {});
    if (page) webm = await page.video()?.path().catch(() => undefined);
    await browser.close().catch(() => {});
  }

  if (failed) {
    if (webm) console.error(`webm kept: ${webm}`);
    return 1;
  }

  const mp4 = join(outDir, `${name}.mp4`);
  try {
    await encode(webm, mp4, totalSeconds);
  } catch (error) {
    console.error(`error: encode failed: ${error.message}`);
    console.error(`webm kept: ${webm}`);
    return 1;
  }
  rmSync(webm, { force: true });
  writeFileSync(join(outDir, 'timeline.json'), `${JSON.stringify({ steps: timeline }, null, 2)}\n`);
  console.log(mp4);
  return 0;
}

async function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    process.exitCode = args.check ? await check() : await record(args.stepsFile, args.out);
  } catch (error) {
    if (error instanceof UsageError) {
      console.error(`error: ${error.message}`);
      process.exitCode = 2;
    } else {
      console.error(`error: ${error.message}`);
      process.exitCode = 1;
    }
  }
}

await main();
