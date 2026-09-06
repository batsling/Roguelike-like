/* THE OBS COMPANION OVERLAY — the ticker (docs/games-first-redesign.md §9).
 *
 * INSTALLED, NOT AUTHORED IN PLACE: the game overwrites user://obs/overlay.js
 * from res://obs/overlay.js at every boot. Edit the repo's copy.
 *
 * HOW THE STATE GETS HERE, and why it is not fetch(). OBS renders this page from
 * a file:// URL, and Chromium refuses every fetch()/XHR a file:// page makes at
 * a sibling file — there is no origin to grant, so it is a CORS failure with no
 * way round it short of launching OBS with --allow-file-access-from-files, which
 * is not something a setup guide should ask for. A <script> tag has no such
 * restriction: a file:// page may always load a sibling script. So the game
 * writes its state AS a script — `window.OBS_STATE = {...}` — and this file
 * re-loads it on a timer with a cache-buster on the end.
 *
 * That is the whole transport. No server, no port, no websocket. */

'use strict';

/* The payload shape this page knows how to draw (ObsCompanion.PAYLOAD_VERSION).
 * A newer payload is refused rather than half-drawn: an overlay that quietly
 * shows the wrong health is worse than one that says it is out of date. */
const KNOWN_VERSION = 1;

const POLL_MS = 250;
/* Longer than ObsCompanion's five-second heartbeat, with room for a slow frame.
 * Below this the game is alive and simply has nothing new to say. */
const STALE_MS = 20000;
const TOAST_MS = 6000;

const el = (id) => document.getElementById(id);
const overlay = el('overlay');

/* The text `#offline` carries when the only thing wrong is that nothing has been
 * read yet. Held here because the two failure branches below overwrite it and
 * have to be able to put it back. */
const OFFLINE_TEXT = 'waiting for the game…';

/* At most this many toasts on screen at once. The ticker is the last item in a
 * content-height column inside a fixed-height browser source, and `overflow:
 * hidden` means anything past the bottom is thrown away with no sign that it
 * existed — so a burst has to be trimmed at the top, where the trimming is
 * visible, rather than at the bottom, where it is not. */
const MAX_TOASTS = 3;

let lastStamp = null;     /* payload `at` of the last state we drew */
let lastSeenAt = 0;       /* wall-clock ms when that arrived */
let firstDraw = true;
let shownEvents = new Set();
let doneRows = new Set();
let goalSignature = '';
let roadSignature = '';

/* ----------------------------------------------------------- the polling -- */

function poll() {
  const s = document.createElement('script');
  /* Chromium strips the query when it resolves a file:// path but still keys its
   * cache on the whole URL, which is exactly the behaviour this needs. */
  s.src = 'state.js?t=' + Date.now();
  s.onload = () => { s.remove(); consume(); };
  s.onerror = () => { s.remove(); };
  document.head.appendChild(s);
}

function consume() {
  const state = window.OBS_STATE;
  if (!state) return;
  if (state.v > KNOWN_VERSION) {
    el('offline').textContent =
      'This overlay page is older than the game — reinstall it from the settings screen.';
    overlay.classList.add('waiting');
    return;
  }
  if (state.at === lastStamp) return;   /* the heartbeat has not ticked */
  /* THE CLOCKS MOVE ONLY ON A DRAW THAT SUCCEEDED, and that ordering is the whole
   * point of this block. They used to be set first — so a throw anywhere inside
   * `render` (one unexpected shape, one null nobody guarded) left the page frozen
   * on the half-drawn last payload, `lastStamp` already advanced so it would
   * never retry, and `lastSeenAt` still ticking so `checkStale` never dimmed it.
   * A frozen overlay that looks alive is the worst state this page has, and it is
   * exactly the state the heartbeat was built to make impossible.
   *
   * Left as they are, a bad payload retries four times a second and the page goes
   * stale on schedule if it never comes good — which is the honest outcome. */
  try {
    render(state);
  } catch (err) {
    /* Nobody can open devtools on a browser source, so the error has to be on the
     * page or it does not exist. */
    el('offline').textContent = 'The overlay could not draw the run: '
      + ((err && err.message) ? err.message : String(err));
    overlay.classList.add('waiting');
    return;
  }
  el('offline').textContent = OFFLINE_TEXT;
  lastStamp = state.at;
  lastSeenAt = Date.now();
}

/* The overlay dims when the heartbeat stops, and comes back on its own if the
 * game is restarted — there is nothing to reset in OBS. */
function checkStale() {
  const stale = lastSeenAt > 0 && (Date.now() - lastSeenAt) > STALE_MS;
  overlay.classList.toggle('stale', stale);
}

/* ---------------------------------------------------------- the drawing --- */

function render(s) {
  overlay.classList.toggle('waiting', s.state === 'idle');
  drawVerdict(s.state);
  drawEvents(s.events || []);
  if (s.state === 'idle') { firstDraw = false; return; }

  drawHero(s.hero || {}, s.vitals || {});
  drawBarThreat(s.vitals || {}, s.threat || {});
  drawCost(s.threat || {});
  drawShields(s.vitals || {}, s.art || {});
  drawNow(s.now || {}, s.run || {});
  drawGoals(s.goals || [], s.art || {});
  drawRoad(s.road || []);
  firstDraw = false;
}
/* `s.statuses` IS DELIBERATELY NOT DRAWN. It is still in the payload for anyone
 * restyling this page, but every player-side status is claimable and therefore
 * already has a checklist row — wearing this strip's art and carrying its stack
 * total (see `goal.stacks`). Drawing both was drawing every status twice. */

/* ONE SPRITE PER SHIELD, in the board's order: the pool that stays comes first
 * and bare, the timed ones follow wearing the clock. Position and badge say the
 * same thing twice — the further from the portrait a shield is, the sooner it
 * goes — which is what makes the row readable with no tooltip to hover. */
function drawShields(vitals, art) {
  const box = el('hero-shields');
  box.innerHTML = '';
  /* No `hidden` to set any more: the box sits beside the health bar and
   * `.pips:empty` takes it out of the flex row when there is no armour, so an
   * unarmoured run gives the bar the whole width instead of leaving a gap where
   * the shields would be. */
  if (!art || !art.shield) return;
  const rows = [[num(vitals.shields_kept), false], [num(vitals.shields_timed), true]];
  for (const [count, timed] of rows) {
    for (let i = 0; i < count; i++) {
      const s = document.createElement('span');
      s.className = 'shield-pip';
      s.title = timed ? 'Temporary shield — goes when you report this game'
                      : 'Shield — nothing takes it but a hit';
      const img = document.createElement('img');
      img.alt = 'shield';
      img.src = art.shield;
      s.appendChild(img);
      if (timed && art.timer) {
        const clock = document.createElement('img');
        clock.className = 'pip-clock';
        clock.alt = '';
        clock.src = art.timer;
        s.appendChild(clock);
      }
      box.appendChild(s);
    }
  }
}

/* WHAT A LOST RUN COSTS, STATED. This used to be one mark per swing — a strip of
 * enemy faces, each badged with its damage or with the shield that eats it —
 * because it was the only place on the page that said WHO was hitting you, and
 * "who" is half of what the player is deciding about.
 *
 * The checklist answers that now. Every body has a row there with its own face
 * and its own `damage` beside it, which is a better place for it in two ways: the
 * damage sits next to the sentence naming the body rather than in a parallel strip
 * the viewer had to match up against the list, and it leaves this line free to
 * state the ARITHMETIC in words. The rule that nobody guesses — one shield stops
 * one hit whatever its size — reads better as "2 shields break, −7 Health" than
 * as a row of badges you have to count.
 *
 * AND WHEN NOTHING CAN REACH YOU IT DOES NOT GO QUIET. The line used to hide
 * itself entirely on an empty forecast, which is honest about this turn and silent
 * about the only question that follows from it: the board is still walking
 * towards you. `turns_away` is how many lost runs of quiet are left, floored (see
 * ObsCompanion._turns_away — a blocked lane or a spent turn makes the real wait
 * longer, never shorter), so it is worded as "at least". */
function drawCost(threat) {
  const box = el('cost');
  const swings = (threat && threat.swings) || [];

  box.hidden = false;
  const total = el('cost-total');
  const kill = el('cost-lethal');

  /* NOTHING IN REACH. Say how long that lasts rather than saying nothing. */
  if (swings.length === 0) {
    const away = num(threat.turns_away, -1);
    total.className = 'cost-total safe';
    total.textContent = away < 0 ? 'nothing on the board can reach you'
      : away === 0 ? 'nothing lands this turn'
      : 'nothing reaches you for at least ' + away
        + (away === 1 ? ' more lost run' : ' more lost runs');
    kill.hidden = true;
    box.classList.remove('lethal');
    box.classList.add('quiet');
    return;
  }
  box.classList.remove('quiet');

  const dmg = num(threat.damage);
  const broke = num(threat.blocked);
  /* THE ARITHMETIC IN WORDS, and "Health" rather than "damage" on purpose: the
   * bar directly above says "7 / 20" and never uses the word damage, so the two
   * numbers a viewer has to connect were being given different names. */
  const parts = [];
  if (broke > 0) parts.push(broke + (broke === 1 ? ' shield breaks' : ' shields break'));
  parts.push(dmg > 0 ? '−' + dmg + ' Health' : 'no Health lost');
  total.textContent = parts.join(', ');
  total.className = 'cost-total' + (dmg === 0 ? ' safe' : '');

  /* THE ONE STATE ALLOWED TO SHOUT. A hatched bar covering the whole of a short
   * health total does say "all of it goes", but only to someone already reading
   * the bar — and this is the moment the overlay exists for. */
  kill.hidden = !threat.lethal;
  box.classList.toggle('lethal', !!threat.lethal);
}

/* The same forecast on the bar: a hatched notch covering the Health that would
 * go, parked at the leading edge of the fill. */
function drawBarThreat(vitals, threat) {
  const node = el('hp-threat');
  const max = Math.max(1, num(vitals.max));
  const hp = num(vitals.hp);
  const dmg = Math.min(hp, num(threat && threat.damage));
  node.hidden = dmg <= 0;
  if (node.hidden) return;
  const pct = (v) => Math.max(0, Math.min(100, (v / max) * 100));
  node.style.left = pct(hp - dmg) + '%';
  node.style.width = (pct(hp) - pct(hp - dmg)) + '%';
  node.classList.toggle('lethal', !!(threat && threat.lethal));
}

function drawHero(hero, vitals) {
  setImg(el('hero-icon'), hero.icon);
  el('hero-name').textContent = hero.name || '';
  const lvl = el('hero-level');
  lvl.textContent = hero.level > 1 ? ('Level ' + hero.level) : '';
  lvl.hidden = !(hero.level > 1);

  const hp = num(vitals.hp), max = Math.max(1, num(vitals.max));
  const bar = el('hp-fill').parentElement;
  el('hp-fill').style.width = Math.max(0, Math.min(100, (hp / max) * 100)) + '%';
  el('hp-text').textContent = hp + ' / ' + max;
  bar.classList.toggle('low', hp > 0 && hp / max <= 0.3);

  /* NO "N BODIES FOLLOWING" CHIP. It was jargon a viewer had no way to cash —
   * "following" is a board concept — and it sat next to a cost line drawing a
   * DIFFERENT count (the bodies in reach, which is not the bodies on the board).
   * Two numbers about enemies, neither labelled in a way that told them apart.
   * The checklist is the honest version of the same fact: one row per body, each
   * with its face and, when it can reach you, its damage. `board.bodies` is still
   * in the payload for anyone restyling this page. */
}

/* THE HEADLINE: where the run is, and what it is for. Two covers with the
 * distance on the arrow between them.
 *
 * This is the one line that gives a viewer who has just tuned in the premise —
 * they are playing a real game, to get to THAT real game — and nothing else on
 * the page carries it. The Amulet used to be legible only off the end of the road
 * strip, which scrolls, so most of the time the destination was off screen and
 * the distance to it was a dim 12px chip below a two-line title. */
function drawNow(now, run) {
  setImg(el('now-cover'), now.cover);
  el('now-label').textContent = now.playing ? 'Now playing' : 'Standing on';
  el('now-game').textContent = now.game || '—';

  /* WHICH ATTEMPT THIS IS, under the game it is being spent on. `now.attempts`
   * counts the ones already spent, so the one being played is the next one up.
   *
   * It belongs to the GAME, not to the forecast. On the cost line it was a number
   * inside a sentence about damage, which made it read as part of the arithmetic;
   * here it is what it actually is — the honour system's tension in plain sight,
   * climbing while the streamer swears at a boss. Hidden on the first attempt:
   * "Attempt 1" is every game's opening state and says nothing. */
  const spent = num(now.attempts);
  const att = el('attempts');
  att.hidden = spent === 0;
  if (spent > 0) {
    att.textContent = 'Attempt ' + (spent + 1);
    att.title = spent + (spent === 1 ? ' run lost here so far'
                                     : ' runs lost here so far');
  }

  const dest = (run && run.amulet) || {};
  setImg(el('dest-cover'), dest.cover);
  el('dest-game').textContent = dest.game || '—';

  /* The distance, on the line that names where it leads — so the number is read
   * as the gap it measures rather than as a chip beside an unrelated title. It
   * carries the words "to the Amulet" because nothing else on this line does: the
   * cover and the name that follow are the Amulet, and without them said out loud
   * the row is a game title with a number in front of it. */
  const hops = num(run.hops, -1);
  el('hops').textContent = hops < 0 ? 'no route to the Amulet'
    : hops === 0 ? 'you are AT the Amulet'
    : hops + (hops === 1 ? ' game to the Amulet' : ' games to the Amulet');
}

/* THE CHECKLIST, AND THE PAGE'S CENTRE OF GRAVITY.
 *
 * EVERY ROW WEARS ITS OWN ART, which is the layout's one big idea. A goal IS an
 * enemy — a game has no goal of its own (§7.2) — and a column of sentences never
 * said so; with the face on the row the list reads as the board. A status's row
 * wears the pip art the hero card used to carry (and its stack total, so cutting
 * that strip lost nothing), a curse's and an event's wear theirs.
 *
 * It also fixes the weakest encoding on the page. The six kinds of row — goal,
 * bonus, instead, status, event, curse — used to be told apart by TEXT COLOUR
 * ALONE, on an identical checkbox at an identical weight, with nothing anywhere
 * saying what a colour meant. Purple-curse against blue-status is not a
 * distinction that survives being read across a room through a lossy encode. The
 * art says it first now and the colour agrees with it, which is the same "say it
 * twice" rule the road's stops and the blocked swings already followed. */
function drawGoals(goals, art) {
  const list = el('goal-list');
  /* Rebuild only when the LIST changed. Redrawing every quarter second would
   * restart the tick-flash animation forever and fight the auto-scroll.
   *
   * EVERYTHING `subtitle()` DRAWS BELONGS IN HERE. It was kind/text/done alone,
   * which left `games` — the countdown on an event or a curse — outside the
   * comparison: the clock was in the payload, ticking down, and the row on screen
   * never redrew to show it. A curse sat on "3 games left" until some unrelated
   * row happened to change, then jumped. */
  const sig = goals.map(g => [g.kind, g.text, g.done, g.who, g.games,
    g.damage, g.blocked, g.stacks, g.icon].join('|')).join('\x01');
  if (sig === goalSignature) return;
  goalSignature = sig;

  /* HOW MANY OF THEM ARE DONE, in the card's own label. The list scrolls, so
   * without this the one question a viewer most wants answered — how close is
   * this game to finished — could only be got by watching a whole scroll cycle
   * and counting. */
  const done = goals.filter(g => g.done).length;
  el('goal-count').textContent = goals.length ? done + ' / ' + goals.length : '';

  const nowDone = new Set(goals.filter(g => g.done).map(g => g.kind + '|' + g.text));
  list.innerHTML = '';
  for (const g of goals) {
    const key = g.kind + '|' + g.text;
    const li = document.createElement('li');
    li.className = 'goal ' + g.kind
      + (g.done ? ' done' : '')
      + (g.front && !g.done ? ' front' : '')
      + (g.addon ? ' addon' : '')
      + (g.boss ? ' boss' : '');
    /* A row that was NOT done a moment ago and is now: flash it, so the tick is
     * something the viewer sees happen. Never on the first draw, where every
     * done row would flash at once. */
    if (g.done && !firstDraw && !doneRows.has(key)) li.classList.add('flash');

    const tick = document.createElement('span');
    tick.className = 'tick';
    tick.textContent = g.done ? '✓' : '□';
    li.appendChild(tick);

    /* THE ROW'S OWN ART. An `addon` row deliberately has none: a bonus and an
     * `instead` hang off the body whose row is directly above, so repeating its
     * face would draw one enemy two and three times running and read as two and
     * three enemies. They are indented under their parent instead, which is what
     * "hangs off" looks like. */
    if (!g.addon) {
      const pic = document.createElement('span');
      pic.className = 'goal-art';
      if (g.icon) {
        const img = document.createElement('img');
        img.alt = g.who || '';
        img.src = g.icon;
        pic.appendChild(img);
      } else {
        /* Nothing authored yet: the initial, the way a status pip has always
         * fallen back, so a row is legible the day its content is written. */
        const letter = document.createElement('span');
        letter.className = 'goal-letter';
        letter.textContent = (g.who || g.text || '?').slice(0, 1).toUpperCase();
        pic.appendChild(letter);
      }
      /* WHAT THIS BODY DOES TO YOU IF THE RUN IS LOST, on the corner of its own
       * face — the half of the old cost strip worth keeping, moved to the row
       * that names the body rather than sitting in a parallel strip the viewer
       * had to match up against this list. A shield means the swing is eaten
       * whole; a number is that much Health. */
      const dmg = num(g.damage);
      if (dmg > 0) {
        const badge = document.createElement('span');
        if (g.blocked && art && art.shield) {
          badge.className = 'goal-badge shield';
          const sh = document.createElement('img');
          sh.alt = 'blocked';
          sh.src = art.shield;
          badge.appendChild(sh);
        } else {
          badge.className = 'goal-badge dmg';
          badge.textContent = dmg;
        }
        pic.appendChild(badge);
      } else if (num(g.stacks) > 0) {
        /* A status's row carries the pip's number instead: what the run holds in
         * TOTAL, across the permanent bucket and every borrowed application. The
         * row itself is one instance, so without this the four stacks of a
         * Strength 1 + 3 would appear nowhere at all. */
        const badge = document.createElement('span');
        badge.className = 'goal-badge stacks' + (g.good ? ' good' : '');
        badge.textContent = g.stacks;
        pic.appendChild(badge);
      }
      li.appendChild(pic);
    }

    const body = document.createElement('span');
    body.className = 'body';
    const text = document.createElement('span');
    text.className = 'text';
    text.textContent = g.text || '';
    body.appendChild(text);

    const note = subtitle(g);
    if (note) {
      const who = document.createElement('span');
      who.className = 'who';
      who.textContent = note;
      body.appendChild(who);
    }
    li.appendChild(body);
    list.appendChild(li);
  }
  doneRows = nowDone;
  restartScroll('goal-scroll');
}

/* The small grey line under a goal: whose it is, and how long is left on it. */
function subtitle(g) {
  const bits = [];
  if (g.who) bits.push(g.who);
  const games = num(g.games, 0);
  if (g.kind === 'event' || g.kind === 'curse') {
    bits.push(games < 0 ? 'permanent'
      : games + (games === 1 ? ' game left' : ' games left'));
  } else if (g.kind === 'status' && games > 0) {
    /* A BORROWED status wears its clock here rather than on the corner of its
     * art, where the pip used to put it: that corner now carries the stack total,
     * and the two would sit on top of each other. Only when there IS a clock —
     * `games` is 0 for the permanent bucket, and "0 games left" on a status that
     * is not going anywhere would read as one about to expire. */
    bits.push(games + (games === 1 ? ' game left' : ' games left'));
  }
  return bits.join(' · ');
}

function drawRoad(road) {
  const strip = el('road-strip');
  /* REBUILT ONLY WHEN THE ROAD CHANGED, for the reason `drawGoals` is — and this
   * one was missing it, which quietly cost the strip the entire feature below.
   *
   * `restartScroll` at the end of this function used to run on EVERY payload.
   * SCROLL_PAUSE is 2500ms and the game writes up to four times a second while a
   * run moves, and at minimum every five seconds from the heartbeat even when it
   * does not — so the walker was reset before it could ever finish its opening
   * pause. Measured against a payload every two seconds (gentler than the real
   * heartbeat) the strip sat at scrollLeft 0 for as long as you cared to watch;
   * with 610px of road to walk it needed three quarters of a minute of total
   * silence to reach the end, which never happens. The stops past the sixth were
   * exactly as invisible as the "+7" this scroller was built to replace, and less
   * honest, because nothing said they were there. */
  const sig = road.map(s => [s.id, s.beaten, s.current, s.amulet, s.unreached,
    s.dropped].join('|')).join('\x01');
  if (sig === roadSignature) return;
  roadSignature = sig;

  strip.innerHTML = '';
  /* NO "+N earlier" HEAD ANY MORE. The strip scrolls the whole road instead of
   * trimming it to a count — a stop turned into a number is a stop the viewer
   * cannot see, and the road is the one part of this page that is about where
   * the run has actually been. `dropped` survives in the payload as the safety
   * valve for a run longer than MAX_ROAD, which nothing realistic reaches. */
  if (road.length && num(road[0].dropped) > 0) {
    const more = document.createElement('span');
    more.className = 'dropped';
    more.textContent = '+' + road[0].dropped;
    strip.appendChild(more);
  }
  road.forEach((stop, i) => {
    if (i > 0) {
      const arrow = document.createElement('span');
      arrow.className = 'arrow' + (stop.unreached ? ' dashed' : '');
      arrow.textContent = stop.unreached ? '⇢' : '→';
      strip.appendChild(arrow);
    }
    const box = document.createElement('span');
    box.className = 'stop'
      + (stop.beaten ? ' beaten' : '')
      + (stop.current ? ' current' : '')
      + (stop.amulet ? ' amulet' : '')
      + (stop.unreached ? ' unreached' : '');
    box.title = stop.name;
    const img = document.createElement('img');
    img.alt = stop.name;
    setImg(img, stop.cover);
    box.appendChild(img);
    /* NO VISIT BADGE. A game the run stood on twice is already TWO STOPS on this
     * strip — `_road` emits one per entry in `path_taken`, never a merged one —
     * so a "2" on the second cover was labelling something the strip had already
     * said by drawing it again, and read as though the two visits had been
     * collapsed into one. The payload still carries `visit` for anyone
     * restyling; the road just walks now, so there is room to show the stops
     * themselves. */
    strip.appendChild(box);
  });
  restartScroll('road-scroll');
}

function drawVerdict(state) {
  const v = el('verdict');
  v.hidden = (state !== 'won' && state !== 'lost');
  if (v.hidden) return;
  v.className = 'verdict ' + state;
  v.textContent = state === 'won' ? 'THE AMULET IS YOURS' : 'THE RUN IS OVER';
}

/* Toasts. Events ride along in every payload; the ones already shown are
 * remembered by (timestamp, text) so a heartbeat does not replay them. On the
 * FIRST payload they are all marked seen without being drawn — a page opened
 * mid-run should not fire eight stale notifications at once. */
function drawEvents(events) {
  const ticker = el('ticker');
  for (const ev of events) {
    const key = ev.at + '|' + ev.text;
    if (shownEvents.has(key)) continue;
    shownEvents.add(key);
    if (firstDraw) continue;
    const t = document.createElement('div');
    t.className = 'toast ' + (ev.tone || 'info');
    t.textContent = ev.text;
    ticker.appendChild(t);
    /* TRIMMED AT THE TOP, NOT THE BOTTOM. The ticker is the last item in a
     * content-height column inside a browser source of a fixed height, and the
     * page's `overflow: hidden` throws away anything past that edge without a
     * mark — measured, a heavy run with four toasts up stood 900px tall against
     * the recommended 828px source, so the two newest lines, the ones a viewer
     * most wants, were the ones cut. Dropping the OLDEST instead keeps the page
     * inside its box and keeps the trimming where it can be seen. */
    while (ticker.children.length > MAX_TOASTS) ticker.firstChild.remove();
    setTimeout(() => {
      t.classList.add('out');
      setTimeout(() => t.remove(), 600);
    }, TOAST_MS);
  }
  /* The set is unbounded otherwise, and this page runs for a whole stream. The
   * payload only ever carries the last handful, so anything older cannot come
   * back and be mistaken for new. */
  if (shownEvents.size > 200) shownEvents = new Set(events.map(e => e.at + '|' + e.text));
}

/* ------------------------------------------------------- the auto-scroll -- */

/* THE SELF-SCROLLING BOXES. A run eight games deep has more goals than fits the
 * card and more road than fits the strip, and a list that silently cuts off is a
 * list that lies. So when the content is bigger than the box it walks: pause at
 * the start, creep along, pause at the end, snap back. Slow enough to read at a
 * glance while doing something else, which is the whole use case.
 *
 * ONE WALKER, BOTH AXES. The checklist scrolls down and the road scrolls right;
 * everything else about them — the pauses, the speed, the edge fades that appear
 * only where content is actually hidden — is the same behaviour, and two copies
 * of this state machine would be two places for it to drift. */
const SCROLL_PAUSE = 2500;
const SCROLL_SPEED = 14;      /* px per second */

const scrollers = {};

function makeScroller(id, axis) {
  scrollers[id] = { axis: axis, phase: 'start', since: performance.now(),
                    pos: 0, last: 0 };
  const box = el(id);
  if (box) { box.scrollTop = 0; box.scrollLeft = 0; }
}

function restartScroll(id) {
  const st = scrollers[id];
  if (!st) return;
  const box = el(id);
  if (box) { box.scrollTop = 0; box.scrollLeft = 0; }
  st.phase = 'start';
  st.since = performance.now();
  st.pos = 0;
}

/* Fade an edge only when something is actually hidden behind it — a fixed mask
 * would fade the first row of a list parked at the start, which is the most
 * important row on the page. */
function setFades(box, room, at, vertical) {
  const a = room > 1 && at > 1 ? '12px' : '0px';
  const b = room > 1 && at < room - 1 ? '12px' : '0px';
  box.style.setProperty(vertical ? '--fade-top' : '--fade-start', a);
  box.style.setProperty(vertical ? '--fade-bot' : '--fade-end', b);
}

function stepOne(id, now) {
  const st = scrollers[id];
  const box = el(id);
  if (!st || !box) return;
  const vertical = st.axis === 'y';
  const room = vertical ? box.scrollHeight - box.clientHeight
                        : box.scrollWidth - box.clientWidth;
  const at = () => vertical ? box.scrollTop : box.scrollLeft;
  if (room <= 1) {
    if (vertical) box.scrollTop = 0; else box.scrollLeft = 0;
    setFades(box, room, 0, vertical);
    return;
  }
  const dt = (now - (st.last || now)) / 1000;
  st.last = now;
  switch (st.phase) {
    case 'start':
      if (now - st.since > SCROLL_PAUSE) { st.phase = 'run'; st.since = now; }
      break;
    case 'run':
      st.pos = Math.min(room, st.pos + SCROLL_SPEED * dt);
      if (vertical) box.scrollTop = st.pos; else box.scrollLeft = st.pos;
      if (st.pos >= room) { st.phase = 'end'; st.since = now; }
      break;
    case 'end':
      if (now - st.since > SCROLL_PAUSE) {
        st.phase = 'start'; st.since = now; st.pos = 0;
        if (vertical) box.scrollTop = 0; else box.scrollLeft = 0;
      }
      break;
  }
  setFades(box, room, at(), vertical);
}

function frame(now) {
  for (const id in scrollers) stepOne(id, now);
  checkStale();
  requestAnimationFrame(frame);
}

/* ------------------------------------------------------------- helpers --- */

function num(v, fallback) { return typeof v === 'number' ? v : (fallback || 0); }

/* An <img> with no `src` at all rather than an empty one: the CSS hides those,
 * where an empty src makes Chromium draw a broken-image glyph. */
function setImg(img, url) {
  if (url) { img.src = url; } else { img.removeAttribute('src'); }
}

/* RENDERING PART OF THE PAGE, so other sources can sit between its pieces.
 *
 * The overlay is one column, but a stream layout usually wants the camera partway
 * down that column rather than under all of it. OBS cannot interleave scene items
 * with the inside of a browser source — so instead the page can render only part
 * of itself, and you point SEVERAL browser sources at the same file:
 *
 *   overlay.html#top     the hero card and the headline
 *   overlay.html#bottom  the checklist and the ticker
 *   overlay.html#road    the road, and nothing else
 *   overlay.html         everything EXCEPT the road (the default)
 *
 * THE ROAD IS OPT-IN, and that is the one asymmetry here. It is a horizontal
 * scroller on a 440px source, and measured on a 22-stop run the stop you are
 * standing on was fully visible for 6 seconds in every 50 — taking 42 to first
 * appear, and snapping back to the start of the run every time the road changed,
 * which is exactly when someone looks up. It cannot be read at a glance and no
 * amount of styling makes a 1008px strip fit 390px. What it uniquely says —
 * which games were beaten and which the run walked away from — is worth a source
 * of its own on a between-games screen, at a width where it does not have to
 * scroll, and is not worth the space on the always-on column. The distance it
 * used to carry now sits on the headline's arrow, in a number that never moves.
 *
 * Every fragment reads the same state.js and they stay in step for free, because
 * they are the same page reading the same file. */
function applySplit() {
  const half = (location.hash || '').replace('#', '').toLowerCase();
  overlay.classList.toggle('only-top', half === 'top');
  overlay.classList.toggle('only-bottom', half === 'bottom');
  overlay.classList.toggle('only-road', half === 'road');
}
applySplit();
window.addEventListener('hashchange', applySplit);

/* The two self-scrolling boxes, registered before the first payload lands so
 * `frame` has something to walk from the very first tick. */
makeScroller('goal-scroll', 'y');
makeScroller('road-scroll', 'x');

poll();
setInterval(poll, POLL_MS);
requestAnimationFrame(frame);
