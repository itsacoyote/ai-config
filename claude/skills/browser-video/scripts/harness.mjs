/**
 * Recording overlay (pointer, caption bar, highlight ring, title card) and the
 * paced helpers passed to each step's act(page, h).
 */

import { setTimeout as sleep } from 'node:timers/promises';

const POINTER_START = { x: 48, y: 48 };
const RING_PAD_PX = 6;
// installOverlay runs in the page, so its inputs travel as an argument rather than as module constants.
const OVERLAY_ARGS = { start: POINTER_START, ringPad: RING_PAD_PX };
const ACTION_TIMEOUT_MS = 5000;
const GLIDE_MIN_MS = 250;
const GLIDE_MAX_MS = 900;
const GLIDE_MS_PER_PX = 0.5;
const TYPE_DELAY_MS = 60;
const SCROLL_STEP_PX = 50;
const SCROLL_STEP_PAUSE_MS = 30;
const SCROLL_SETTLE_MS = 150;
const DEFAULT_HIGHLIGHT_MS = 1200;

// Runs inside the page, so it must stay self-contained: addInitScript and page.evaluate serialise it.
export function installOverlay({ start, ringPad }) {
  const key = Symbol.for('browser-video');
  if (window.top !== window || window[key]) return;

  const host = document.createElement('browser-video-overlay');
  host.setAttribute('aria-hidden', 'true');
  // "all" first: page CSS must not restyle the host. CSSOM writes (not style text) keep CSP and Trusted Types pages working.
  for (const [prop, value] of [
    ['all', 'initial'],
    ['position', 'fixed'],
    ['inset', '0'],
    ['pointer-events', 'none'],
    ['z-index', '2147483647'],
  ]) {
    host.style.setProperty(prop, value);
  }

  // Closed so Playwright locators cannot match caption or card text.
  const root = host.attachShadow({ mode: 'closed' });
  const sheet = new CSSStyleSheet();
  sheet.replaceSync(`
    .ring { position: fixed; display: none; box-sizing: border-box; border: 4px solid #ff9f1a; border-radius: 10px;
            box-shadow: 0 0 0 4px rgba(255, 159, 26, 0.35); }
    .pointer { position: fixed; left: 0; top: 0; width: 20px; height: 28px; overflow: visible;
               filter: drop-shadow(0 2px 3px rgba(0, 0, 0, 0.45)); }
    .card { position: fixed; inset: 0; display: none; flex-direction: column; align-items: center; justify-content: center;
            gap: 32px; padding: 0 10%; background: #14181f; color: #fff; text-align: center;
            font-family: system-ui, sans-serif; }
    .card-title { font-size: 72px; font-weight: 700; line-height: 1.15; }
    .card-body { max-width: 1000px; font-size: 34px; line-height: 1.4; color: #c8d0dc; }
    .caption { position: fixed; left: 50%; bottom: 40px; display: none; transform: translateX(-50%);
               box-sizing: border-box; max-width: min(960px, 80vw); padding: 16px 28px; overflow: hidden;
               border-radius: 12px; background: rgba(17, 20, 26, 0.9); color: #fff; text-align: center;
               font: 600 28px/1.35 system-ui, sans-serif; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }
    .tick { position: fixed; right: 0; top: 0; width: 1px; height: 1px; animation: tick 100ms steps(1) infinite; }
    @keyframes tick { 0% { background: rgba(0, 0, 0, 0.01); } 50% { background: transparent; } }
  `);
  root.adoptedStyleSheets = [sheet];

  const make = (className) => {
    const el = document.createElement('div');
    el.className = className;
    return el;
  };
  const ring = make('ring');

  const svgNs = 'http://www.w3.org/2000/svg';
  const pointer = document.createElementNS(svgNs, 'svg');
  pointer.setAttribute('class', 'pointer');
  pointer.setAttribute('viewBox', '0 0 14 20');
  const arrow = document.createElementNS(svgNs, 'path');
  arrow.setAttribute('d', 'M0 0 L0 17 L4.5 13 L7.5 20 L10.5 18.8 L7.5 12 L13 12 Z');
  arrow.setAttribute('fill', '#111');
  arrow.setAttribute('stroke', '#fff');
  arrow.setAttribute('stroke-width', '1.2');
  arrow.setAttribute('stroke-linejoin', 'round');
  pointer.append(arrow);

  const card = make('card');
  const cardTitle = make('card-title');
  const cardBody = make('card-body');
  card.append(cardTitle, cardBody);
  // Caption last so it stays readable over a card.
  const caption = make('caption');
  // Chromium emits no screencast frame for a static page, and the webm starts at its first frame: a quiet opening
  // step is cut from the video and every later offset leads timeline.json. A repainting pixel keeps frames flowing.
  root.append(ring, pointer, card, caption, make('tick'));

  const placePointer = (x, y, ms) => {
    pointer.style.transition = ms > 0 ? `transform ${ms}ms cubic-bezier(0.4, 0, 0.2, 1)` : 'none';
    pointer.style.transform = `translate(${x}px, ${y}px)`;
  };
  placePointer(start.x, start.y, 0);

  const api = {
    setCaption(text) {
      caption.textContent = text ?? '';
      caption.style.display = text ? '-webkit-box' : 'none';
    },
    movePointer: placePointer,
    ring(rect) {
      if (!rect) {
        ring.style.display = 'none';
        return;
      }
      ring.style.left = `${rect.x - ringPad}px`;
      ring.style.top = `${rect.y - ringPad}px`;
      ring.style.width = `${rect.width + ringPad * 2}px`;
      ring.style.height = `${rect.height + ringPad * 2}px`;
      ring.style.display = 'block';
    },
    showCard(title, body) {
      cardTitle.textContent = title;
      cardBody.textContent = body;
      cardBody.style.display = body ? 'block' : 'none';
      card.style.display = 'flex';
    },
    clearCard() {
      card.style.display = 'none';
    },
  };
  Object.defineProperty(window, key, { value: api });

  // Init scripts run before <html> exists on a fresh document.
  const attach = () => document.documentElement.append(host);
  if (document.documentElement) {
    attach();
  } else {
    new MutationObserver((_, observer) => {
      if (!document.documentElement) return;
      observer.disconnect();
      attach();
    }).observe(document, { childList: true });
  }
}

export function addOverlay(context) {
  return context.addInitScript(installOverlay, OVERLAY_ARGS);
}

// Node owns the pointer position: a new document starts at POINTER_START until ensureOverlay restores it.
const pointerAt = new WeakMap();

const callOverlay = (page, method, ...args) =>
  page.evaluate(([name, rest]) => window[Symbol.for('browser-video')]?.[name](...rest), [method, args]);

export async function ensureOverlay(page) {
  await page.evaluate(installOverlay, OVERLAY_ARGS);
  const at = pointerAt.get(page) ?? POINTER_START;
  await callOverlay(page, 'movePointer', at.x, at.y, 0);
}

export function setCaption(page, text) {
  return callOverlay(page, 'setCaption', text ?? null);
}

export function clearCard(page) {
  return callOverlay(page, 'clearCard');
}

export function createHelpers(page) {
  const expectVisible = async (locator, timeout = ACTION_TIMEOUT_MS) => {
    try {
      await locator.waitFor({ state: 'visible', timeout });
    } catch (error) {
      throw new Error(`expected element to be visible within ${timeout} ms: ${error.message}`);
    }
  };

  const boxOf = async (locator, action) => {
    await locator.scrollIntoViewIfNeeded({ timeout: ACTION_TIMEOUT_MS });
    const box = await locator.boundingBox();
    if (!box) throw new Error(`cannot ${action}: the element has no bounding box (it is hidden or detached)`);
    return box;
  };

  return {
    expectVisible,

    async click(locator) {
      const box = await boxOf(locator, 'click');
      const x = box.x + box.width / 2;
      const y = box.y + box.height / 2;
      await ensureOverlay(page);
      const from = pointerAt.get(page) ?? POINTER_START;
      const glideMs = Math.round(
        Math.min(GLIDE_MAX_MS, GLIDE_MIN_MS + Math.hypot(x - from.x, y - from.y) * GLIDE_MS_PER_PX),
      );
      pointerAt.set(page, { x, y });
      await callOverlay(page, 'movePointer', x, y, glideMs);
      await page.mouse.move(x, y);
      await sleep(glideMs);
      await locator.click({ timeout: ACTION_TIMEOUT_MS });
    },

    async type(locator, text) {
      await locator.scrollIntoViewIfNeeded({ timeout: ACTION_TIMEOUT_MS });
      await locator.pressSequentially(text, { delay: TYPE_DELAY_MS, timeout: ACTION_TIMEOUT_MS });
    },

    async scroll(pixels) {
      const steps = Math.max(1, Math.ceil(Math.abs(pixels) / SCROLL_STEP_PX));
      for (let i = 0; i < steps; i++) {
        await page.mouse.wheel(0, pixels / steps);
        await sleep(SCROLL_STEP_PAUSE_MS);
      }
      await sleep(SCROLL_SETTLE_MS);
    },

    async highlight(locator, ms = DEFAULT_HIGHLIGHT_MS) {
      await expectVisible(locator);
      const box = await boxOf(locator, 'highlight');
      await ensureOverlay(page);
      await callOverlay(page, 'ring', box);
      await sleep(ms);
      await callOverlay(page, 'ring', null);
    },

    async card({ title, body } = {}) {
      if (typeof title !== 'string' || title === '') throw new Error('card needs a non-empty "title" string');
      await ensureOverlay(page);
      await callOverlay(page, 'showCard', title, body ?? '');
    },
  };
}
