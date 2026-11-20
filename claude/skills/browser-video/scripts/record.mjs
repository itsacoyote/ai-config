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
import { lstatSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { setTimeout as sleep } from 'node:timers/promises';
import { addOverlay, clearCard, createHelpers, ensureOverlay, setCaption } from './harness.mjs';

const DEFAULT_VIEWPORT = { width: 1440, height: 900 };
const DEFAULT_HOLD_MS = 1500;
const TRAILING_HOLD_MS = 500;
const STDERR_TAIL_CHARS = 2000;
const SAFE_NAME = /^[A-Za-z0-9._-]+$/;

// Linux containers and CI commonly lack the user namespaces Chromium's sandbox needs.
const LAUNCH_OPTIONS = { headless: true, chromiumSandbox: process.platform !== 'linux' };

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
    const browser = await chromium.launch({ ...LAUNCH_OPTIONS, timeout: 15000 });
    await browser.close();
  } catch {
    console.log('missing: chromium');
    return 4;
  }
  return 0;
}

function isSafeName(value) {
  return typeof value === 'string' && SAFE_NAME.test(value) && !value.startsWith('.');
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

  if (!isSafeName(name)) {
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
    if (!step || !isSafeName(step.id)) fail(`step ${i}: "id" must match [A-Za-z0-9._-]+ and not start with "."`);
    if (typeof step.act !== 'function') fail(`step "${step.id}": "act" must be a function`);
    if (step.hold !== undefined && !(Number.isFinite(step.hold) && step.hold >= 0)) {
      fail(`step "${step.id}": "hold" must be a finite number >= 0`);
    }
    if (step.caption !== undefined && (typeof step.caption !== 'string' || step.caption === '')) {
      fail(`step "${step.id}": "caption" must be a non-empty string`);
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

// Playwright drops a static tail from the webm (seen on Linux); clone the last frame and cut at wall-clock duration.
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

// Recordings can show logged-in pages, so refuse an out dir another user or a symlink could redirect.
function prepareOutDir(outArg) {
  if (!outArg) return mkdtempSync(join(tmpdir(), 'browser-video-'));
  const dir = resolve(outArg);
  let stat;
  try {
    stat = lstatSync(dir);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  if (!stat) {
    mkdirSync(dir, { recursive: true, mode: 0o700 });
    return dir;
  }
  if (stat.isSymbolicLink()) throw new UsageError(`--out must not be a symlink: ${dir}`);
  if (!stat.isDirectory()) throw new UsageError(`--out is not a directory: ${dir}`);
  if (stat.uid !== process.getuid()) throw new UsageError(`--out is not owned by the current user: ${dir}`);
  return dir;
}

// ffmpeg and writeFileSync both follow a symlink at the target path, so unlink one first.
function clearSymlink(path) {
  try {
    if (lstatSync(path).isSymbolicLink()) rmSync(path);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

// Navigation errors echo the url, which may carry credentials or tokens.
function makeRedactor(url) {
  const safe = new URL(url);
  safe.username = '';
  safe.password = '';
  safe.search = '';
  safe.hash = '';
  const href = new URL(url).href;
  return (text) => text.split(url).join(safe.href).split(href).join(safe.href);
}

async function record(stepsFile, outArg) {
  const { name, url, viewport, steps } = await loadSteps(stepsFile);

  const outDir = prepareOutDir(outArg);
  const redact = makeRedactor(url);
  const report = (message) => console.error(redact(message));

  const chromium = await loadChromium();
  if (!chromium) {
    report('error: Playwright is not resolvable from the current directory; run preflight.sh');
    return 1;
  }

  let browser;
  try {
    browser = await chromium.launch(LAUNCH_OPTIONS);
  } catch (error) {
    report(`error: Chromium failed to launch; run preflight.sh\n${error.message}`);
    return 1;
  }

  let context;
  let page;
  let failed = false;
  const timeline = [];
  let webm;
  let totalSeconds = 0;
  try {
    context = await browser.newContext({ viewport, recordVideo: { dir: outDir, size: viewport } });
    await addOverlay(context);
    page = await context.newPage();
    // Video recording starts when the page is created, so timeline offsets count from here.
    const t0 = performance.now();
    const elapsedSeconds = () => (performance.now() - t0) / 1000;
    const h = createHelpers(page);

    await page.goto(url);
    for (const step of steps) {
      const startSeconds = elapsedSeconds();
      try {
        await setCaption(page, step.caption);
        await step.act(page, h);
        // A navigation in act() replaces the document, so the overlay and caption are re-applied.
        await ensureOverlay(page);
        await setCaption(page, step.caption);
        const remainingMs = (step.hold ?? DEFAULT_HOLD_MS) - (elapsedSeconds() - startSeconds) * 1000;
        if (remainingMs > 0) await sleep(remainingMs);
        await setCaption(page, null);
        await clearCard(page);
      } catch (error) {
        failed = true;
        report(`error: step "${step.id}" failed: ${error.message}`);
        const shot = join(outDir, `failure-${step.id}.png`);
        try {
          await page.screenshot({ path: shot });
          report(`screenshot: ${shot}`);
        } catch (shotError) {
          report(`error: could not take failure screenshot: ${shotError.message}`);
        }
        break;
      }
      const entry = { id: step.id, start: startSeconds, end: elapsedSeconds() };
      if (step.caption) entry.caption = step.caption;
      timeline.push(entry);
    }
    if (!failed) await sleep(TRAILING_HOLD_MS);
    totalSeconds = elapsedSeconds();
  } catch (error) {
    failed = true;
    report(`error: ${error.message}`);
  } finally {
    // The webm is only complete once the context is closed.
    await context?.close().catch(() => {});
    if (page) webm = await page.video()?.path().catch(() => undefined);
    await browser.close().catch(() => {});
  }

  if (failed) {
    if (webm) console.error(`webm kept: ${webm}`);
    return 1;
  }

  const mp4 = join(outDir, `${name}.mp4`);
  const timelinePath = join(outDir, 'timeline.json');
  clearSymlink(mp4);
  clearSymlink(timelinePath);
  try {
    await encode(webm, mp4, totalSeconds);
  } catch (error) {
    report(`error: encode failed: ${error.message}`);
    console.error(`webm kept: ${webm}`);
    return 1;
  }
  rmSync(webm, { force: true });
  writeFileSync(timelinePath, `${JSON.stringify({ steps: timeline }, null, 2)}\n`);
  console.log(mp4);
  return 0;
}

async function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    process.exitCode = args.check ? await check() : await record(args.stepsFile, args.out);
  } catch (error) {
    console.error(`error: ${error.message}`);
    process.exitCode = error instanceof UsageError ? 2 : 1;
  }
}

await main();
