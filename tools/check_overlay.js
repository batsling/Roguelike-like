#!/usr/bin/env node
/* THE OBS OVERLAY, ACTUALLY RENDERED (docs/games-first-redesign.md §9).
 *
 * WHY THIS EXISTS. `test/test_obs_companion.gd` is 587 careful lines about the
 * PRODUCER — the payload's shape, that no Resource escapes into it, that the
 * forecast matches the turn the board really takes. Its own header says why that
 * matters: "nothing in obs/overlay.js will fail to compile when a key is renamed
 * out from under it, and nothing on a stream will say so either." That is exactly
 * right, and the conclusion drawn from it was to test the Godot side harder. But
 * the consumer is a browser page, and it was tested nowhere — so every bug this
 * file now guards against shipped, and all of them were invisible to GUT:
 *
 *   - `.cost { display: flex }` outranked the UA `[hidden]` rule, so the lethality
 *     warning never hid and sat there pulsing THIS KILLS YOU over a safe board,
 *     still carrying the previous forecast.
 *   - `drawRoad` restarted the auto-scroll on every payload, so the strip never
 *     walked and every stop past the sixth was unreachable.
 *   - the goal signature omitted `games`, so an event or curse countdown never
 *     redrew.
 *   - `.stop.amulet` won the cascade over `.stop.beaten`, so the stop that ends a
 *     winning run was drawn the same as an Amulet the run never reached.
 *   - a burst of toasts stood the page 900px tall inside an 828px source and the
 *     newest lines were silently clipped.
 *
 * None of these are things a human notices while glancing at their own stream.
 * All of them are three lines of assertion once the page is on a screen.
 *
 * RUNNING IT:
 *
 *     npm install playwright-core          # once, anywhere on the path below
 *     node tools/check_overlay.js
 *
 * It needs a Chromium. It looks for one in the usual Playwright locations and in
 * $CHROMIUM_PATH; pass --browser=/path/to/chrome to say outright. Nothing here is
 * wired into the GUT suite — GUT is Godot and this is a browser — so it is run by
 * hand when obs/ changes. It prints one line per check and exits non-zero on the
 * first failure, so CI can call it the day there is CI.
 *
 * The fixture below is a deliberately HEAVY run: nine goals, seven swings, both
 * shield pools, six statuses, twenty-two stops. Every measurement in the README's
 * layout tables should be taken from a payload at least this size, because the
 * sizes that bite are the ones a real run reaches on hour three. */

'use strict';

const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');

const REPO = path.resolve(__dirname, '..');
const SRC = path.join(REPO, 'obs');

/* The browser source the README tells a streamer to make. 352 wide since the
 * checklist dropped its checkbox column and spent the width on the art; the
 * page is fluid, but this is the width the layout is tuned against and every
 * height below is measured at. It is deliberately 352 and not 350: 350 is the
 * `max-width: 349px` breakpoint where the run card's two halves stack, and a
 * default sitting on its own breakpoint tests a layout nobody runs. */
const WIDTH = 352;
const HEIGHT = 828;

let failures = 0;
function check(name, ok, detail) {
  const mark = ok ? 'ok  ' : 'FAIL';
  console.log('  ' + mark + '  ' + name + (detail === undefined ? '' : '   [' + detail + ']'));
  if (!ok) failures++;
}

/* ASK PLAYWRIGHT FIRST, GUESS SECOND.
 *
 * This used to be the directory scan alone, and the scan knew one Linux layout:
 * `chrome-linux/chrome`. Playwright has since renamed it to `chrome-linux64/`,
 * and it now also ships a separate `chromium_headless_shell-<rev>` build whose
 * binary is called `headless_shell`. A fresh `npx playwright install chromium`
 * therefore produces a browser this function could not see — which is exactly
 * what happened the first time CI ran it, while the same code passed locally
 * only because a STALE older download with the old layout was still on disk.
 * A path-guesser that works on the machine it was written on and nowhere else
 * is the worst kind, so the guessing is now the fallback.
 *
 * `chromium.executablePath()` is Playwright telling us where it actually put the
 * browser for this installed version. It throws when nothing is installed, which
 * is not an error here — it just means try the scan. */
function findBrowser() {
  const flag = process.argv.find((a) => a.startsWith('--browser='));
  if (flag) return flag.slice('--browser='.length);
  if (process.env.CHROMIUM_PATH) return process.env.CHROMIUM_PATH;
  try {
    // Its own require: this runs before main() has one, and a missing
    // playwright-core is reported there with a better message than a throw here.
    const p = require('playwright-core').chromium.executablePath();
    if (p && fs.existsSync(p)) return p;
  } catch (_) { /* not installed, or no browser for this version — try the scan */ }
  const roots = [process.env.PLAYWRIGHT_BROWSERS_PATH, '/opt/pw-browsers',
    path.join(os.homedir(), '.cache/ms-playwright')].filter(Boolean);
  for (const root of roots) {
    if (!fs.existsSync(root)) continue;
    for (const dir of fs.readdirSync(root)) {
      for (const rel of [
        'chrome-linux64/chrome',        // current Playwright
        'chrome-linux/chrome',          // older Playwright
        'chrome-linux/headless_shell',  // the chromium_headless_shell-* build
        'chrome-linux64/headless_shell',
        'chrome-mac/Chromium.app/Contents/MacOS/Chromium',
        'chrome-win/chrome.exe']) {
        const p = path.join(root, dir, rel);
        if (fs.existsSync(p)) return p;
      }
    }
  }
  return null;
}

/* ------------------------------------------------ reading back real pixels -- */

/* A MINIMAL PNG DECODER, because the contrast check has to look at what was
 * actually composited and node ships no image decoding. Playwright screenshots
 * are non-interlaced 8-bit RGB or RGBA (colour type 2 or 6) — which of the two
 * depends on whether the page is fully opaque, so both are handled and anything
 * else throws rather than returning quiet nonsense.
 *
 * The five PNG row filters are the whole of it: each scanline is prefixed with a
 * filter byte saying how it was predicted from the row above and the pixel to the
 * left, and undoing them in order is the decode. */
function decodePng(buf) {
  let pos = 8;                        /* past the signature */
  let w = 0, h = 0, depth = 0, type = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const tag = buf.toString('ascii', pos + 4, pos + 8);
    const body = buf.subarray(pos + 8, pos + 8 + len);
    if (tag === 'IHDR') {
      w = body.readUInt32BE(0); h = body.readUInt32BE(4);
      depth = body[8]; type = body[9];
    } else if (tag === 'IDAT') {
      idat.push(body);
    } else if (tag === 'IEND') break;
    pos += 12 + len;                  /* length + tag + data + CRC */
  }
  if (depth !== 8 || (type !== 6 && type !== 2)) {
    throw new Error('expected 8-bit RGB(A) png, got depth ' + depth + ' type ' + type);
  }
  const raw = require('zlib').inflateSync(Buffer.concat(idat));
  const bpp = type === 6 ? 4 : 3;
  const stride = w * bpp;
  const out = Buffer.alloc(h * stride);
  for (let y = 0; y < h; y++) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? out[y * stride + x - bpp] : 0;          /* left */
      const b = y > 0 ? out[(y - 1) * stride + x] : 0;             /* up */
      const c = (x >= bpp && y > 0) ? out[(y - 1) * stride + x - bpp] : 0;
      let v = line[x];
      if (filter === 1) v += a;
      else if (filter === 2) v += b;
      else if (filter === 3) v += (a + b) >> 1;
      else if (filter === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
      }
      out[y * stride + x] = v & 0xff;
    }
  }
  return { w, h, bpp, data: out };
}

/* THE PAGE OVER A CAPTURE, COMPOSITED HERE RATHER THAN IN THE PAGE.
 *
 * This is the whole point of the `omitBackground` screenshot: OBS puts the scene
 * behind a transparent browser-source texture, so the only faithful way to model
 * it is to take that texture and do the `src-over` ourselves. Setting a
 * background inside the page instead is what produced years of contrast numbers
 * that were about a situation no stream is ever in. */
function compositeOver(png, capture) {
  if (png.bpp !== 4) throw new Error('compositeOver needs an RGBA texture');
  const out = Buffer.alloc(png.w * png.h * 3);
  for (let i = 0, j = 0; i < png.data.length; i += 4, j += 3) {
    const a = png.data[i + 3] / 255;
    for (let k = 0; k < 3; k++) {
      out[j + k] = Math.round(png.data[i + k] * a + capture[k] * (1 - a));
    }
  }
  return { w: png.w, h: png.h, bpp: 3, data: out };
}

const srgb = (v) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; };
const relLum = (r, g, b) => 0.2126 * srgb(r) + 0.7152 * srgb(g) + 0.0722 * srgb(b);

/* THE GLYPH AGAINST WHAT IT SITS ON, read off the composited page.
 *
 * Inside a line of text the pixels fall into two populations: the strokes, and
 * everything the strokes are read against (the halo, then the card, then the
 * capture). Sorting by luminance and taking a high percentile against a low one
 * separates them without needing to know which pixel is which. The percentiles
 * are 98 and 25 rather than something tidier because glyph coverage inside a
 * line box is LOW — even tight to the text a line is mostly the space between
 * letters, so the stroke core is a thin slice at the top of the distribution and
 * a 90th percentile lands on antialiasing.
 *
 * Returns null for a box with no real range in it, which the caller skips rather
 * than scoring. */
function glyphContrast(png, box) {
  const lums = [];
  const x1 = Math.min(png.w, box.x + box.w), y1 = Math.min(png.h, box.y + box.h);
  for (let y = Math.max(0, box.y); y < y1; y++) {
    for (let x = Math.max(0, box.x); x < x1; x++) {
      const i = (y * png.w + x) * png.bpp;
      lums.push(relLum(png.data[i], png.data[i + 1], png.data[i + 2]));
    }
  }
  if (lums.length < 40) return null;
  lums.sort((a, b) => a - b);
  const at = (f) => lums[Math.min(lums.length - 1, Math.floor(lums.length * f))];
  const ink = at(0.98), ground = at(0.25);
  if (ink - ground < 0.02) return null;      /* nothing drawn in this box */
  return (ink + 0.05) / (ground + 0.05);
}

/* ------------------------------------------------------------- the fixture -- */

/* Real art off disk, so the sizes measured are the sizes a stream gets. A missing
 * folder is not a failure of the page — it just means this is a partial check.
 *
 * STAGED BESIDE THE PAGE AND NAMED RELATIVELY, exactly as ObsCompanion._stage
 * does it. This used to hand the fixture `file:///…/images2.0/games/x.png`, and
 * that is the shape that broke OBS and could not be caught here: an absolute
 * file:// subresource loads fine from a file:// document, which is what this
 * harness and a double-clicked overlay.html both are, and is refused outright by
 * a document served any other way — which is what OBS's browser source gives the
 * page. Keeping the fixture in the producer's real shape is what lets the
 * over-http check below mean anything. */
function pick(stageDir, sub, n, only) {
  const full = path.join(REPO, sub);
  if (!fs.existsSync(full)) return [];
  const names = only
    ? (fs.existsSync(path.join(full, only)) ? [only] : [])
    : fs.readdirSync(full).filter((f) => /\.(png|jpg|jpeg)$/i.test(f)).sort();
  const covers = path.join(stageDir, 'covers');
  fs.mkdirSync(covers, { recursive: true });
  const out = [];
  for (let i = 0; i < n && names.length; i++) {
    const name = sub.replace(/\//g, '-') + '-' + names[i % names.length];
    fs.copyFileSync(path.join(full, names[i % names.length]), path.join(covers, name));
    out.push('covers/' + name);
  }
  return out;
}

function fixture(dir) {
  const games = pick(dir, 'images2.0/games', 22);
  const enemies = pick(dir, 'images2.0/enemies', 7);
  const statuses = pick(dir, 'images2.0/statuses', 6);
  const at = Math.floor(Date.now() / 1000);

  const kinds = ['goal', 'goal', 'bonus', 'instead', 'status', 'event', 'curse', 'goal', 'goal'];
  /* EVERY ROW CARRIES ITS OWN ART NOW, and the art it carries depends on the
   * kind — an enemy's face, a status's pip, a curse's, an event's. `addon` rows
   * (a bonus, an `instead`) deliberately have none: they hang off the row above
   * and are indented under it instead of repeating its face. */
  const goals = kinds.map((kind, i) => {
    const addon = kind === 'bonus' || kind === 'instead';
    return {
      kind,
      text: kind === 'curse'
        ? 'Curse of the Ledger — beat a game without dying (if failed, lose 3 Health)'
        : 'Reach the second boss without spending a single healing item this game',
      who: 'The Wretched Cartographer',
      icon: addon ? '' : (kind === 'status' ? statuses[i % statuses.length]
        : enemies[i % enemies.length]),
      addon,
      boss: i === 1,
      front: i === 0,
      done: i >= kinds.length - 2,
      games: (kind === 'event' || kind === 'curse') ? 3 : 0,
      /* A body's row wears its own swing; a status's wears its stack total. */
      damage: kind === 'goal' ? 3 + i : 0,
      blocked: i === 0,
      stacks: kind === 'status' ? 4 : 0,
      good: kind === 'status',
    };
  });

  /* THE CHARACTER'S OWN GOAL, which `ReportChecklist` has always drawn and this
   * page did not until the hero card was folded away. Its art is the portrait. */
  goals.unshift({
    kind: 'levelup', text: 'Level up — beat three games without losing a run',
    who: 'Isaac \u00b7 Level 3', icon: enemies[0] || '', addon: false,
    boss: false, front: false, done: false, games: 0, damage: 0, stacks: 0,
  });

  const swings = enemies.map((icon, i) => ({
    damage: 3 + i, who: 'Body ' + i, blocked: i < 2, icon, instance: i + 1,
  }));

  /* The four road states that matter, and then the tail, so both the cascade and
   * the walk have something to work on. The last stop is the Amulet, unreached. */
  const road = games.map((cover, i) => ({
    id: 'g' + i, name: 'Game ' + i, cover, visit: 1,
    beaten: i % 3 === 0,
    amulet: i === games.length - 1,
    current: i === games.length - 2,
    unreached: i === games.length - 1,
    dropped: 0,
  }));

  return {
    v: 1, at,
    events: [{ tone: 'info', text: 'Now playing', at: at - 1 }],
    hero: { name: 'The Completionist', icon: enemies[3] || '', level: 3, levelup: '' },
    art: {
      timer: pick(dir, 'images2.0/general', 1, 'Timer.png')[0] || '',
      shield: pick(dir, 'images2.0/general', 1, 'Shield.png')[0] || '',
    },
    vitals: { hp: 7, max: 20, shields: 4, shields_kept: 2, shields_timed: 2 },
    run: { played: 8, beaten: 5, gold: 120, hops: 3,
      /* The headline's right-hand half. A deliberately long title, because the
       * destination's column is the narrower of the two and this is where it
       * would bite. */
      amulet: { game: 'The Legend of Zelda: Tears of the Kingdom',
        cover: games[games.length - 1] || '' } },
    now: {
      playing: true, game: 'Vampire Survivors: Legacy of the Moonspell',
      cover: games[0] || '', attempts: 4,
    },
    goals,
    board: { bodies: 5, front: swings.length, incoming: 18 },
    threat: { swings, raw: 18, blocked: 2, damage: 12, hp_after: 0, lethal: true,
      turns_away: 0 },
    statuses: statuses.map((icon, i) => ({
      name: 'Status ' + i, stacks: 2 + i, good: i % 2 === 0, icon,
      letter: 'S', games: i === 1 ? 2 : 0,
    })),
    road,
  };
}

/* ---------------------------------------------------------------- the run -- */

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const exe = findBrowser();
  if (!exe) {
    console.error('No Chromium found. Pass --browser=/path/to/chrome, set '
      + '$CHROMIUM_PATH, or install one with `npx playwright install chromium`.');
    process.exit(2);
  }
  let chromium;
  try {
    ({ chromium } = require('playwright-core'));
  } catch (e) {
    console.error('playwright-core is not installed. `npm install playwright-core`.');
    process.exit(2);
  }

  /* The page is COPIED somewhere writable and run from there, exactly as the game
   * installs it into user://obs/ — state.js has to sit beside it, and obs/ in the
   * repo is not the place to be writing one. */
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'obs-overlay-'));
  for (const f of ['overlay.html', 'overlay.css', 'overlay.js']) {
    fs.copyFileSync(path.join(SRC, f), path.join(dir, f));
  }
  fs.writeFileSync(path.join(dir, 'custom.css'), '');

  const state = fixture(dir);
  const write = (mut) => {
    if (mut) mut(state);
    fs.writeFileSync(path.join(dir, 'state.js'),
      'window.OBS_STATE = ' + JSON.stringify(state, null, 2) + ';\n');
  };
  write();

  const browser = await chromium.launch({ executablePath: exe });
  const page = await browser.newPage({ viewport: { width: WIDTH, height: HEIGHT } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto('file://' + path.join(dir, 'overlay.html'));
  await sleep(1200);

  console.log('the page draws a heavy run');
  check('no uncaught page errors', errors.length === 0, errors.join(' / '));
  const drew = await page.evaluate(() => ({
    cards: document.querySelectorAll('.card:not(.road)').length,
    goals: document.querySelectorAll('.goal').length,
    art: document.querySelectorAll('.goal-art img').length,
    badges: document.querySelectorAll('.goal-badge').length,
    stops: document.querySelectorAll('.stop').length,
    shields: document.querySelectorAll('.shield-pip').length,
    dest: document.getElementById('dest-game').textContent,
    barW: Math.round(document.querySelector('.bar').getBoundingClientRect().width),
  }));
  check('every section has content', drew.goals > 0 && drew.art > 0
    && drew.stops > 0 && drew.shields > 0, JSON.stringify(drew));
  /* TWO CARDS ON THE DEFAULT PAGE, not three: the run and the checklist. The hero
   * card lost its portrait and name to the level-up row and had only a health bar
   * left in it, which is not a card. */
  check('the page is two cards', drew.cards === 2, drew.cards + ' cards');

  /* THE HEADLINE. The premise of the whole run — this game, that far, that game —
   * has to be on the page without scrolling anything. */
  check('the Amulet is named beside the game in play', /Tears of the Kingdom/.test(drew.dest),
    drew.dest);
  /* THE DISTANCE LABELS THE DESTINATION, in the column the destination is in —
   * that adjacency is what lets it drop the words "to the" and stay readable. */
  check('the distance labels the destination column',
    await page.evaluate(() => document.getElementById('hops').textContent)
      === '3 games to Amulet');
  /* THE TWO GAMES ARE ON ONE LINE. Asserted on the boxes rather than on the
   * markup: what matters is that a viewer reads them as a pair, which means
   * their tops line up and the Amulet's is the one on the right. */
  const pair = await page.evaluate(() => {
    const a = document.getElementById('now-cover').getBoundingClientRect();
    const b = document.getElementById('dest-cover').getBoundingClientRect();
    return { dy: Math.round(Math.abs(a.top - b.top)), right: b.left > a.left };
  });
  check('the two games share a line, Amulet on the right',
    pair.dy < 12 && pair.right, JSON.stringify(pair));
  /* NO HEADER ON THE CHECKLIST. A list of ticked and unticked rows is already
   * self-evidently a checklist. */
  check('the checklist has no label above it',
    await page.evaluate(() => !document.querySelector('.goals .label')));

  /* EVERY ROW WEARS ITS OWN ART, except the two that hang off the row above. An
   * addon repeating its parent's face read as another enemy. */
  const rows = await page.evaluate(() => [...document.querySelectorAll('.goal')].map((g) => ({
    kind: g.className.replace('goal ', ''),
    art: !!g.querySelector('.goal-art img'),
    indent: Math.round(parseFloat(getComputedStyle(g).paddingLeft)),
  })));
  check('every non-addon row has a picture',
    rows.filter((r) => !/addon/.test(r.kind)).every((r) => r.art),
    rows.filter((r) => !/addon/.test(r.kind) && !r.art).length + ' without');
  check('an addon carries no face and is indented under its parent',
    rows.filter((r) => /addon/.test(r.kind)).every((r) => !r.art && r.indent > 20),
    JSON.stringify(rows.filter((r) => /addon/.test(r.kind))));

  /* THE CARD IS A TINT AND THE HALO IS WHAT MAKES THAT SAFE. Two mechanism pins;
   * the pixel sampling further down is what actually holds the line.
   *
   * `backdrop-filter` MUST STAY GONE, and that is asserted rather than assumed.
   * It does nothing in an OBS browser source — the page renders to a transparent
   * texture and OBS composites the scene behind it afterwards, so there is no
   * backdrop inside the page to filter — while doing something visible behind a
   * double-clicked overlay.html. A declaration that behaves differently in the
   * preview and on the stream is exactly how this page carried a broken
   * legibility model through two redesigns, so re-adding one should fail here
   * rather than look nice on somebody's desk. */
  const glass = await page.evaluate(() => {
    const cs = getComputedStyle(document.querySelector('.card'));
    const bg = cs.backgroundColor;
    const m = bg.match(/rgba?\(([^)]+)\)/);
    const parts = m ? m[1].split(',').map((n) => parseFloat(n)) : [];
    const filter = cs.backdropFilter || cs.webkitBackdropFilter || 'none';
    return { alpha: parts.length === 4 ? parts[3] : 1, filter };
  });
  check('the card lets the stream through', glass.alpha <= 0.35, 'alpha ' + glass.alpha);
  check('…and does not rely on backdrop-filter, which is inert in OBS',
    glass.filter === 'none', glass.filter);
  check('…and every glyph carries its own ground',
    await page.evaluate(() => {
      const sh = getComputedStyle(document.getElementById('overlay')).textShadow;
      return (sh.match(/rgb/g) || []).length >= 3;
    }), 'the halo is at least three stacked shadows');

  /* THE CHARACTER'S GOAL IS ON THE LIST. The portrait and the name left the hero
   * card for this row, and if it did not draw, both would simply be gone. */
  const lvl = await page.evaluate(() => {
    const n = document.querySelector('.goal.levelup');
    return n ? { art: !!n.querySelector('.goal-art img'),
                 who: n.querySelector('.who') ? n.querySelector('.who').textContent : '' }
             : null;
  });
  check('the level-up goal is a checklist row, wearing the character',
    !!lvl && lvl.art && /Isaac/.test(lvl.who), JSON.stringify(lvl));

  /* STRETCHING: `#fill` makes the page take the whole source and gives the slack
   * to the checklist, which is the only part of it that can use the room. */
  await page.goto('file://' + path.join(dir, 'overlay.html') + '#fill');
  await sleep(900);
  const filled = await page.evaluate(() => ({
    page: Math.round(document.getElementById('overlay').getBoundingClientRect().height),
    scroller: Math.round(document.getElementById('goal-scroll').getBoundingClientRect().height),
  }));
  check('#fill takes the whole source', filled.page === HEIGHT,
    filled.page + ' of ' + HEIGHT);
  check('…and the checklist is what grows into it', filled.scroller > 320,
    filled.scroller + 'px of scroller');
  await page.goto('file://' + path.join(dir, 'overlay.html'));
  await sleep(700);

  /* STRETCHING SIDEWAYS: the page fills whatever width the source is, rather than
   * rendering a 440 column with dead space beside it. */
  await page.setViewportSize({ width: 640, height: HEIGHT });
  await sleep(500);
  const wide = await page.evaluate(() => ({
    page: Math.round(document.getElementById('overlay').getBoundingClientRect().width),
    title: Math.round(document.getElementById('now-game').getBoundingClientRect().width),
  }));
  check('a wider source is filled, not letterboxed', wide.page === 640, wide.page + 'px');
  /* The title is one of TWO columns now, so the slack it takes is half the
   * page's — 640 wide gives each half ~290 before its cover and gutters. */
  check('…and the text columns are what take the slack', wide.title > 200,
    wide.title + 'px of title');
  await page.setViewportSize({ width: WIDTH, height: HEIGHT });
  await sleep(500);

  /* THE ROAD IS OFF THE DEFAULT PAGE — it is a scroller that cannot be read at a
   * glance, and lives at #road now. It must still be IN the document (the strip
   * is built either way) and simply not displayed. */
  check('the road is built but not shown on the default page',
    await page.evaluate(() => document.querySelectorAll('.stop').length > 0
      && getComputedStyle(document.querySelector('.road')).display === 'none'));

  /* 1. `hidden` has to actually hide — the regression that left THIS KILLS YOU on
   *    screen over a board that could not reach the player. */
  console.log('a board that cannot reach you');
  write((s) => {
    s.at++;
    s.threat = { swings: [], raw: 0, blocked: 0, damage: 0, hp_after: s.vitals.hp,
      lethal: false, turns_away: 2 };
    s.vitals = { hp: 18, max: 20, shields: 0, shields_kept: 0, shields_timed: 0 };
    s.statuses = [];
  });
  await sleep(900);
  const gone = await page.evaluate(() => {
    const vis = (id) => {
      const n = document.getElementById(id);
      return { shown: getComputedStyle(n).display !== 'none', h: Math.round(n.getBoundingClientRect().height) };
    };
    return { cost: vis('cost'), lethal: vis('cost-lethal'),
      shields: document.querySelectorAll('.shield-pip').length,
      barW: Math.round(document.querySelector('.bar').getBoundingClientRect().width),
      total: document.getElementById('cost-total').textContent,
      quiet: document.getElementById('cost').classList.contains('quiet') };
  });
  /* THE LINE STAYS AND READS N/A, which is the state to get right: it does not
   * hide (a row that vanishes moves everything under it) and it does not go red.
   * What must still hide is the LETHALITY WARNING — that is the regression this
   * file was written for, where the badge sat pulsing over a safe board still
   * carrying the previous forecast. */
  check('the cost line says N/A rather than hiding',
    gone.cost.shown && gone.total.trim() === 'N/A', gone.total);
  check('…and stops being an alarm while it does', gone.quiet);
  check('the lethality warning is gone, not merely flagged', !gone.lethal.shown,
    JSON.stringify(gone.lethal));
  /* THE SHIELDS SIT BESIDE THE BAR NOW, so an unarmoured run has to give the bar
   * the whole width rather than leave a gap where the sprites would be —
   * `.pips:empty` is what does that, and it is easy to lose. */
  check('no shields are drawn', gone.shields === 0, gone.shields + ' drawn');
  check('…and the bar takes back the width they were using',
    gone.barW > drew.barW, drew.barW + 'px armoured -> ' + gone.barW + 'px bare');
  /* A BOARD THAT CAN NEVER CLOSE READS THE SAME N/A, and that is deliberate:
   * `turns_away` is no longer on the line, so "nothing this turn" and "nothing
   * ever" are one state here. It still rides in the payload. */
  write((s) => { s.at++; s.threat.turns_away = -1; });
  await sleep(900);
  check('a board that never closes reads N/A too',
    'N/A' === (await page.evaluate(() =>
      document.getElementById('cost-total').textContent)).trim());

  /* THE ARITHMETIC, when there is some: a label and two numbers, on one line.
   *
   * Measured WITHOUT the Death badge, because that is the resting state and the
   * one whose height the rest of the card depends on. The lethal state is
   * allowed to wrap and does at 380 — a badge is not a number, it arrives at the
   * one moment the page is meant to shout, and pushing the checklist down 18px
   * while it does is the correct trade. */
  write((s) => { s.at++; Object.assign(s, fixture(dir)); s.threat.lethal = false;
    s.at = Date.now(); });
  await sleep(900);
  const cost = await page.evaluate(() => ({
    text: document.getElementById('cost-total').textContent.trim(),
    h: Math.round(document.getElementById('cost').getBoundingClientRect().height),
  }));
  check('the cost line is the two numbers and nothing else',
    /^−\d+ Shields?, −\d+ Health$|^−\d+ (Shields?|Health)$/.test(cost.text), cost.text);
  /* One line is ~31px (two 11-12px runs on a baseline, 6px of padding, a
   * border); a wrapped one is past 45. */
  check('…on one line', cost.h < 40, cost.h + 'px tall');

  /* 2. the road's outcome colours, including the combinations the cascade used to
   *    lose. --success #4dc76b, --gold #ffcc66, --unbeaten #d97821. */
  console.log('the road says how each stop went');
  /* AT #road, WHICH IS WHERE THE ROAD LIVES NOW. A `display: none` scroller has
   * no scrollWidth, so the walk below cannot be measured on the default page —
   * and the colours are worth asserting on the source that actually shows them. */
  await page.goto('file://' + path.join(dir, 'overlay.html') + '#road');
  await sleep(900);
  write((s) => {
    s.at++;
    const cover = s.road[0].cover;
    const stop = (o) => Object.assign({ id: 'x', name: 'x', cover, visit: 1, beaten: false,
      amulet: false, current: false, unreached: false, dropped: 0 }, o);
    s.road = [
      stop({ id: 'a', name: 'walked away' }),
      stop({ id: 'b', name: 'beaten', beaten: true }),
      stop({ id: 'c', name: 'standing on', current: true }),
      stop({ id: 'd', name: 'amulet beaten', beaten: true, amulet: true }),
      stop({ id: 'e', name: 'amulet unreached', amulet: true, unreached: true }),
    ];
  });
  await sleep(900);
  const stops = await page.evaluate(() => [...document.querySelectorAll('.stop')].map((s) => {
    const cs = getComputedStyle(s.querySelector('img'));
    return { name: s.title, border: cs.borderTopColor, width: cs.borderTopWidth,
             outline: cs.outlineStyle === 'none' ? '' : cs.outlineColor };
  }));
  const byName = (n) => stops.find((s) => s.name === n) || {};
  check('a stop walked away from is --unbeaten',
    byName('walked away').border === 'rgb(217, 120, 33)', byName('walked away').border);
  check('a beaten stop is --success',
    byName('beaten').border === 'rgb(77, 199, 107)', byName('beaten').border);
  check('the stop being played is --gold',
    byName('standing on').border === 'rgb(255, 204, 102)', byName('standing on').border);
  check('a BEATEN Amulet keeps the beaten colour (the cascade used to eat it)',
    byName('amulet beaten').border === 'rgb(77, 199, 107)', byName('amulet beaten').border);
  check('…and still rings as the destination',
    byName('amulet beaten').outline === 'rgb(255, 138, 60)', byName('amulet beaten').outline);
  check('an unreached Amulet is the destination colour',
    byName('amulet unreached').border === 'rgb(255, 138, 60)', byName('amulet unreached').border);
  check('the outcome border survives a stream encode (2px)',
    stops.every((s) => s.width === '2px'), stops.map((s) => s.width).join(','));

  /* 3. an event/curse countdown has to redraw when only the clock moved. */
  console.log('a clock ticking down');
  write((s) => {
    s.at++;
    s.goals = [{ kind: 'curse', text: 'Curse of the Ledger', who: 'Ledger',
      boss: false, front: false, done: false, games: 3 }];
  });
  await sleep(700);
  const clockBefore = await page.evaluate(() => document.querySelector('.goal .who').textContent);
  write((s) => { s.at++; s.goals[0].games = 1; });
  await sleep(900);
  const clockAfter = await page.evaluate(() => document.querySelector('.goal .who').textContent);
  check('the row redraws when only `games` changed',
    clockBefore !== clockAfter && /1 game left/.test(clockAfter),
    clockBefore + ' -> ' + clockAfter);

  /* 4. the road has to walk while the run is moving, which is the only time it
   *    matters. A payload every 2s here is gentler than the real 5s heartbeat. */
  console.log('the road walks while the run moves');
  write((s) => {
    s.at++;
    s.road = fixture(dir).road;   /* long again, so there is something to walk */
  });
  await sleep(3500);           /* clear of SCROLL_PAUSE */
  const walked = [];
  for (let i = 0; i < 4; i++) {
    write((s) => { s.at++; s.vitals.hp = 7 + (i % 2); });   /* the run moves, the road does not */
    await sleep(1000);
    walked.push(await page.evaluate(() => document.getElementById('road-scroll').scrollLeft));
  }
  check('the strip is still moving after four payloads',
    walked[walked.length - 1] > walked[0], 'scrollLeft ' + walked.join(' -> '));

  /* Back to the default page for everything below — the road's own source is not
   * the shape the README's layout tables are about. */
  await page.goto('file://' + path.join(dir, 'overlay.html'));
  await sleep(900);

  /* 5. a burst of toasts must not push the page out of its browser source. */
  console.log('a burst of toasts');
  const base = Math.floor(Date.now() / 1000) + 50;
  write((s) => {
    s.at++;
    /* BACK TO A FULL PAGE FIRST. The checks above shrank the goals and the road to
     * make their own points, and a burst measured against a short page proves
     * nothing — it is the tall page the toasts have to fit under. */
    Object.assign(s, { goals: fixture(dir).goals, road: fixture(dir).road,
      threat: fixture(dir).threat, vitals: fixture(dir).vitals, statuses: fixture(dir).statuses });
    s.events = ['Defeated The Wretched Cartographer', 'Took 4 damage — 2 shields broke',
      'Now playing Vampire Survivors: Legacy of the Moonspell', 'Lost a run — attempt 5',
      'Beat Hollow Knight', 'Found the Golden Idol'].map((text, i) =>
      ({ tone: i % 2 ? 'bad' : 'good', text, at: base + i }));
  });
  await sleep(400);
  const quietH = await page.evaluate(() =>
    Math.round(document.getElementById('overlay').getBoundingClientRect().height));
  await sleep(900);
  const burst = await page.evaluate(() => ({
    toasts: document.querySelectorAll('.toast').length,
    overlayH: Math.round(document.getElementById('overlay').getBoundingClientRect().height),
    tickerTop: Math.round(document.getElementById('ticker').getBoundingClientRect().top),
    tickerBottom: Math.round(document.getElementById('ticker').getBoundingClientRect().bottom),
  }));
  check('the stack is capped', burst.toasts <= 3, burst.toasts + ' toasts');
  check('a burst does not grow the page (the ticker is anchored)',
    burst.overlayH === quietH, quietH + ' -> ' + burst.overlayH);
  check('every toast is inside the browser source',
    burst.tickerTop >= 0 && burst.tickerBottom <= HEIGHT,
    burst.tickerTop + '..' + burst.tickerBottom + ' of ' + HEIGHT);

  /* 6. a payload the page cannot draw must not leave it frozen and looking alive:
   *    the clocks stay put so staleness still fires. */
  console.log('a payload that cannot be drawn');
  const stampBefore = await page.evaluate(() => window.__lastSeen === undefined);
  write((s) => { s.at++; s.goals = 'not an array'; });
  await sleep(900);
  const broke = await page.evaluate(() => ({
    waiting: document.getElementById('overlay').classList.contains('waiting'),
    message: document.getElementById('offline').textContent,
  }));
  check('the failure is said out loud on the page',
    broke.waiting && /could not draw/.test(broke.message), broke.message.slice(0, 60));
  write((s) => { s.at++; s.goals = fixture(dir).goals; });
  await sleep(900);
  const recovered = await page.evaluate(() => ({
    waiting: document.getElementById('overlay').classList.contains('waiting'),
    goals: document.querySelectorAll('.goal').length,
  }));
  check('and the next good payload is a real retry',
    !recovered.waiting && recovered.goals > 0, JSON.stringify(recovered));

  /* 7. the heights the README's layout tables promise. Asserted against the HEAVY
   *    column, not the ceiling: the ceiling is a pathological run and the tables
   *    are what a streamer sizes a scene against. A page that grows past these has
   *    either gained a card or lost the ticker's anchoring, and either way the
   *    README is now wrong — which is the thing that is hard to notice by eye. */
  /* The whole page came down from 777 to 608 on the same heavy run — the road
   * left the default column and the hero card lost its status strip, and the
   * checklist took ~60px of that back as a taller scroller (260 -> 320), which is
   * where the space is worth spending. `#road` is its own source now and is the
   * one that does NOT bound: a 22-stop strip is 1008px wide and 84 tall. */
  const DOCUMENTED = { '': 490, '#top': 202, '#bottom': 304, '#goals': 304,
    '#road': 116 };
  console.log('the shape the README documents');
  write((s) => { s.at++; s.events = []; Object.assign(s, fixture(dir)); s.at = Date.now(); });
  await sleep(1000);
  for (const [hash, label] of [['', 'whole page'], ['#top', '#top'], ['#bottom', '#bottom'],
    ['#goals', '#goals'], ['#road', '#road']]) {
    await page.goto('file://' + path.join(dir, 'overlay.html') + hash);
    await sleep(900);
    const h = await page.evaluate(() =>
      Math.round(document.getElementById('overlay').getBoundingClientRect().height));
    check(label + ' still measures what the README says on a heavy run',
      h === DOCUMENTED[hash], h + 'px, documented ' + DOCUMENTED[hash]);
  }

  /* THE PICTURES ACTUALLY LOAD WHEN THE PAGE IS NOT A file:// DOCUMENT.
   *
   * This is the one check in the file that is not about the page at all — it is
   * about the URLs the producer writes, and it exists because that is what broke
   * on a real stream. The overlay's art used to travel as absolute
   * `file:///…/images2.0/games/x.png`. Chromium treats an absolute file:// URL as
   * a LOCAL RESOURCE LOAD and refuses it from any document that is not itself
   * file://; OBS's browser source does not serve local files as file:// documents,
   * so in OBS — the only place this page is ever used — the text was perfect and
   * EVERY picture was missing. Nothing could see it: double-clicking the page
   * makes it a file:// document, and so did every `page.goto('file://…')` above.
   *
   * So the same fixture is served over http and the images are asked whether they
   * decoded. `naturalWidth` is the question that matters — an <img> with a
   * refused src is still in the DOM, still the size its CSS gives it, and reports
   * 0 there. Serving it also proves the relative form resolves against a base
   * that is not a folder path, which is the property the fix actually relies on. */
  /* #goals IS #bottom WITHOUT THE TICKER, and that is the only difference worth
   * asserting: the ticker is pinned to the foot of the source and would land on
   * a checklist sized to itself. The list must still be there and still walk. */
  console.log('the checklist on its own');
  await page.goto('file://' + path.join(dir, 'overlay.html') + '#goals');
  await sleep(900);
  const only = await page.evaluate(() => ({
    goals: document.querySelectorAll('.goal').length,
    run: !!document.querySelector('.run').getClientRects().length,
    ticker: !!document.querySelector('.ticker').getClientRects().length,
    road: !!document.querySelector('.road').getClientRects().length,
  }));
  check('#goals draws the checklist', only.goals > 0, only.goals + ' rows');
  check('…and nothing else', !only.run && !only.ticker && !only.road,
    JSON.stringify(only));

  /* ------------------------------------------------------------------------
   * THE TEXT HOLDS ITS GROUND OVER ANY CAPTURE.
   *
   * WHY THIS SAMPLES PIXELS INSTEAD OF DOING THE ARITHMETIC. The old page was a
   * near-opaque card, so a WCAG ratio of the text colour against the composited
   * CARD was a fair description of it, and that is where the 4.73 in the docs
   * came from — computed by hand, never asserted here. Two things are wrong with
   * carrying that forward. It was never re-derived after the palette moved:
   * recomputing the same model over today's tokens gives 4.66 for the worst TEXT
   * colour (`--faint`), not 4.73 — the 4.73 belonged to an earlier palette and
   * had been quoted in three documents since. (The lowest token of any kind was
   * `--unbeaten` at 4.06, but that one is a border on the road's thumbnails and
   * never text, so the 4.5 text bar never applied to it; against the 3:1 bar for
   * non-text it passes.) And the model itself is now wrong outright — at 0.12
   * alpha the text is not read against the card, it is read against its own halo,
   * and arithmetic on the card alone scores a page that looks fine at 2.6.
   *
   * AND THE COMPOSITING HAS TO HAPPEN THE WAY OBS DOES IT, which is the second
   * thing this check got wrong and the more expensive one. The obvious way to
   * put a capture behind the page is to set `document.body.background` — and
   * that is what this did, and what the hand-computed 4.73 before it assumed.
   * OBS DOES NOT WORK THAT WAY. A browser source renders to a TRANSPARENT
   * texture and OBS composites the scene behind it afterwards, so inside the
   * page there is nothing behind the cards at all. Measured: screenshot the page
   * with `omitBackground` and the card pixels come back at alpha 0.122 against a
   * `--card-bg` of 0.12 — `backdrop-filter` contributed exactly nothing.
   *
   * That invalidated every contrast number this page has ever had, in both
   * directions: with a background inside the page the worst text measured 4.96,
   * and composited the way OBS does it, 3.00. The filter has never darkened
   * anybody's stream; it only ever darkened the white page behind a
   * double-clicked overlay.html, which is why the design looked right to
   * everyone who checked it that way.
   *
   * So: screenshot with `omitBackground` to get the texture OBS gets, composite
   * it over each capture HERE, and sample that. For each text element take its
   * box, split the pixels by luminance into glyph and ground, and take the WCAG
   * ratio between them. That is a PROXY and is documented as one — there is no
   * single flat ground behind a haloed glyph — but it is measured on what the
   * viewer sees, and it moves the moment the halo, the card or a palette colour
   * does.
   * --------------------------------------------------------------------- */
  console.log('the text holds its ground over any capture');
  const CAPTURES = [['dark', [16, 16, 20]], ['mid', [124, 124, 128]],
    ['bright', [246, 246, 250]]];
  await page.goto('file://' + path.join(dir, 'overlay.html'));
  await sleep(700);
  const texture = decodePng(await page.screenshot({ omitBackground: true,
    clip: { x: 0, y: 0, width: WIDTH, height: Math.min(HEIGHT, 520) } }));
  check('the page hands OBS a transparent texture, not an opaque one',
    texture.bpp === 4, texture.bpp + ' bytes per pixel');
  /* THE RANGE'S RECTS, CLIPPED TO WHAT IS ACTUALLY ON SCREEN. Read once: the
   * page does not change between captures now that the compositing happens out
   * here, only the ground under it does.
   *
   * An element box runs the full width of its column whatever the text in it
   * does, so a short subtitle in a wide row is mostly empty ground — a sampler
   * splitting THAT by percentile finds no glyph and scores the halo against the
   * card. A Range over the node's contents gives the line boxes the glyphs
   * occupy instead.
   *
   * AND THEN THE RECTS MUST BE CLIPPED TO THE ELEMENT, which cost an hour to
   * work out. `.now-game` and `.dest-game` are `-webkit-line-clamp: 2`, and a
   * Range hands back a rect for EVERY line the text would have taken, clipped
   * ones included — so on a long title the sampler was reading rects sitting
   * 40px below the visible box, over the health bar and the cost line, and
   * reporting their unrelated colours as a contrast failure of the title. The
   * real text was scoring 8.9 to 11.3 the whole time. Any rect not inside its
   * own element's border box is not on screen and is dropped. */
  const boxes = await page.evaluate(() => {
    const out = [];
    for (const sel of ['.now-game', '.dest-game', '#hops', '#now-label',
      '.bar-text', '.cost-label', '.cost-total', '.goal .text', '.goal .who']) {
      const n = document.querySelector(sel);
      if (!n || !n.textContent.trim()) continue;
      const box = n.getBoundingClientRect();
      const range = document.createRange();
      range.selectNodeContents(n);
      for (const r of range.getClientRects()) {
        if (r.width < 20 || r.height < 7) continue;
        if (r.top < box.top - 1 || r.bottom > box.bottom + 1) continue;
        out.push({ sel, x: Math.round(r.x), y: Math.round(r.y),
          w: Math.round(r.width), h: Math.round(r.height) });
      }
    }
    return out;
  });
  let worstRatio = Infinity, worstWhere = '';
  for (const [name, capture] of CAPTURES) {
    const shot = compositeOver(texture, capture);
    for (const b of boxes) {
      const r = glyphContrast(shot, b);
      if (r && r < worstRatio) { worstRatio = r; worstWhere = b.sel + ' over ' + name; }
    }
  }
  /* 4.5 is AA for body text, and the page clears it by sampling rather than by
   * assertion — if a future pass lightens the card, weakens the halo or dims a
   * palette colour, this is the check that notices. */
  check('the worst text on the page is still legible over any capture',
    worstRatio >= 4.5, worstRatio.toFixed(2) + ':1 — ' + worstWhere);

  console.log('the art loads from a page that is not a file:// document');
  const server = http.createServer((req, res) => {
    const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '');
    const file = path.join(dir, rel);
    if (!file.startsWith(dir) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404); res.end(); return;
    }
    const type = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript',
      '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg' }[path.extname(file)];
    res.writeHead(200, { 'Content-Type': type || 'application/octet-stream' });
    res.end(fs.readFileSync(file));
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  await page.goto('http://127.0.0.1:' + server.address().port + '/overlay.html');
  await sleep(1200);
  const art = await page.evaluate(() => {
    const imgs = [...document.querySelectorAll('img[src]')];
    return { total: imgs.length,
      broken: imgs.filter((i) => !i.complete || i.naturalWidth === 0).map((i) => i.getAttribute('src')),
      absolute: imgs.map((i) => i.getAttribute('src')).filter((s) => /^[a-z]+:/i.test(s)) };
  });
  check('the page draws some art at all', art.total > 0, art.total + ' <img> with a src');
  check('every picture decoded', art.broken.length === 0,
    art.broken.length + ' broken: ' + art.broken.slice(0, 3).join(', '));
  check('no art url carries a scheme — they are all relative to the page',
    art.absolute.length === 0, art.absolute.slice(0, 3).join(', '));
  await new Promise((r) => server.close(r));

  const shot = path.join(dir, 'overlay.png');
  await page.goto('file://' + path.join(dir, 'overlay.html'));
  await sleep(900);
  await page.screenshot({ path: shot, fullPage: true });
  console.log('\nscreenshot: ' + shot);

  await browser.close();
  console.log(failures === 0 ? '\nall checks passed' : '\n' + failures + ' check(s) failed');
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(2); });
