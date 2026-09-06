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
const os = require('os');
const path = require('path');

const REPO = path.resolve(__dirname, '..');
const SRC = path.join(REPO, 'obs');

/* The browser source the README tells a streamer to make. */
const WIDTH = 440;
const HEIGHT = 828;

let failures = 0;
function check(name, ok, detail) {
  const mark = ok ? 'ok  ' : 'FAIL';
  console.log('  ' + mark + '  ' + name + (detail === undefined ? '' : '   [' + detail + ']'));
  if (!ok) failures++;
}

function findBrowser() {
  const flag = process.argv.find((a) => a.startsWith('--browser='));
  if (flag) return flag.slice('--browser='.length);
  if (process.env.CHROMIUM_PATH) return process.env.CHROMIUM_PATH;
  const roots = [process.env.PLAYWRIGHT_BROWSERS_PATH, '/opt/pw-browsers',
    path.join(os.homedir(), '.cache/ms-playwright')].filter(Boolean);
  for (const root of roots) {
    if (!fs.existsSync(root)) continue;
    for (const dir of fs.readdirSync(root)) {
      for (const rel of ['chrome-linux/chrome', 'chrome-mac/Chromium.app/Contents/MacOS/Chromium',
        'chrome-win/chrome.exe']) {
        const p = path.join(root, dir, rel);
        if (fs.existsSync(p)) return p;
      }
    }
  }
  return null;
}

/* ------------------------------------------------------------- the fixture -- */

/* Real art off disk, so the sizes measured are the sizes a stream gets. A missing
 * folder is not a failure of the page — it just means this is a partial check. */
function pick(dir, n) {
  const full = path.join(REPO, dir);
  if (!fs.existsSync(full)) return [];
  const names = fs.readdirSync(full).filter((f) => /\.(png|jpg|jpeg)$/i.test(f)).sort();
  const out = [];
  for (let i = 0; i < n && names.length; i++) {
    out.push('file://' + path.join(full, names[i % names.length]));
  }
  return out;
}

function fixture() {
  const games = pick('images2.0/games', 22);
  const enemies = pick('images2.0/enemies', 7);
  const statuses = pick('images2.0/statuses', 6);
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
      timer: 'file://' + path.join(REPO, 'images2.0/general/Timer.png'),
      shield: 'file://' + path.join(REPO, 'images2.0/general/Shield.png'),
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

  const state = fixture();
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
  check('the distance is on the line that names where it leads',
    await page.evaluate(() => document.getElementById('hops').textContent)
      === '3 games to the Amulet');
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

  /* THE CARD IS TRANSPARENT, AND ONLY THE BACKDROP FILTER MAKES THAT SAFE. The
   * card sits at 0.45 alpha so the stream shows through it, which is only legible
   * because `backdrop-filter` blurs and darkens the capture behind it first —
   * measured, the worst contrast on the page is 4.73 with the filter and 1.20
   * without. The two must therefore never be separated: dropping the filter while
   * keeping the transparency is the one edit here that silently produces an
   * unreadable overlay on a bright game, and it would look completely fine to
   * whoever made it on a dark one. */
  const glass = await page.evaluate(() => {
    const cs = getComputedStyle(document.querySelector('.card'));
    const bg = cs.backgroundColor;
    const m = bg.match(/rgba?\(([^)]+)\)/);
    const parts = m ? m[1].split(',').map((n) => parseFloat(n)) : [];
    const filter = cs.backdropFilter || cs.webkitBackdropFilter || 'none';
    return { alpha: parts.length === 4 ? parts[3] : 1, filter };
  });
  check('the card lets the stream through', glass.alpha < 0.6, 'alpha ' + glass.alpha);
  check('…and darkens what it lets through, which is what keeps it readable',
    /blur/.test(glass.filter) && /brightness/.test(glass.filter), glass.filter);

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
  check('…and the text columns are what take the slack', wide.title > 400,
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
  /* THE LINE NO LONGER HIDES ITSELF HERE, and that is the change: a board with
   * nothing in reach is still a board walking towards you, and how many lost runs
   * of quiet are left is the question that follows. What must still hide is the
   * LETHALITY WARNING — that is the regression this file was written for, where
   * THIS KILLS YOU sat pulsing over a safe board carrying the previous forecast. */
  check('the cost line says how long the quiet lasts',
    gone.cost.shown && /at least 2 more lost runs/.test(gone.total), gone.total);
  check('…and stops being an alarm while it does', gone.quiet);
  check('the lethality warning is gone, not merely flagged', !gone.lethal.shown,
    JSON.stringify(gone.lethal));
  /* THE SHIELDS SIT BESIDE THE BAR NOW, so an unarmoured run has to give the bar
   * the whole width rather than leave a gap where the sprites would be —
   * `.pips:empty` is what does that, and it is easy to lose. */
  check('no shields are drawn', gone.shields === 0, gone.shields + ' drawn');
  check('…and the bar takes back the width they were using',
    gone.barW > drew.barW, drew.barW + 'px armoured -> ' + gone.barW + 'px bare');
  /* The forecast reads the OTHER way when nothing is ever coming, rather than
   * promising a wait of minus one turn. */
  write((s) => { s.at++; s.threat.turns_away = -1; });
  await sleep(900);
  check('a board that never closes says so',
    /nothing on the board can reach you/.test(
      await page.evaluate(() => document.getElementById('cost-total').textContent)));

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
    s.road = fixture().road;   /* long again, so there is something to walk */
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
    Object.assign(s, { goals: fixture().goals, road: fixture().road,
      threat: fixture().threat, vitals: fixture().vitals, statuses: fixture().statuses });
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
  write((s) => { s.at++; s.goals = fixture().goals; });
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
  const DOCUMENTED = { '': 608, '#top': 258, '#bottom': 366, '#road': 118 };
  console.log('the shape the README documents');
  write((s) => { s.at++; s.events = []; Object.assign(s, fixture()); s.at = Date.now(); });
  await sleep(1000);
  for (const [hash, label] of [['', 'whole page'], ['#top', '#top'], ['#bottom', '#bottom'],
    ['#road', '#road']]) {
    await page.goto('file://' + path.join(dir, 'overlay.html') + hash);
    await sleep(900);
    const h = await page.evaluate(() =>
      Math.round(document.getElementById('overlay').getBoundingClientRect().height));
    check(label + ' still measures what the README says on a heavy run',
      h === DOCUMENTED[hash], h + 'px, documented ' + DOCUMENTED[hash]);
  }

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
