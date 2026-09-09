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
  drawMap(s.route || {}, s.run || {});
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
 * state the TOTAL and nothing else.
 *
 * IT IS A LABEL AND TWO NUMBERS, and every state of it is one short line:
 * "On next loss  −2 Shields, −7 Health", or "On next loss  N/A". It was a
 * sentence, which read better and wrapped to two lines on a busy board — and
 * this line sits at the top of the card, where a height that changes is a page
 * that moves under a viewer who looked up for two seconds.
 *
 * `turns_away` (how many lost runs of quiet are left, floored — see
 * ObsCompanion._turns_away) used to be spelled out here on an empty forecast.
 * It rides in the payload still, for anyone restyling this page who wants it. */
function drawCost(threat) {
  const box = el('cost');
  box.hidden = false;
  const total = el('cost-total');
  const kill = el('cost-lethal');

  /* THE TWO NUMBERS, AND NOTHING ELSE. "−2 Shields, −7 Health" — the same
   * arithmetic the sentence used to spell out ("2 shields break, −7 Health"),
   * at a width that cannot wrap. The rule nobody guesses — one shield stops one
   * hit whatever its size — is carried by the shields being counted separately
   * from the Health, which is the part that has to survive; the checklist below
   * already draws each body's own damage against its face for anyone who wants
   * the breakdown.
   *
   * "Health" rather than "damage" on purpose: the bar directly above says
   * "7 / 20" and never uses the word damage, so the two numbers a viewer has to
   * connect were being given different names. */
  const dmg = num(threat.damage);
  const broke = num(threat.blocked);
  const parts = [];
  if (broke > 0) parts.push('−' + broke + (broke === 1 ? ' Shield' : ' Shields'));
  if (dmg > 0) parts.push('−' + dmg + ' Health');

  /* NOTHING LANDS: N/A, and the line goes quiet rather than red.
   *
   * It used to answer the question that follows instead — "nothing reaches you
   * for at least 2 more lost runs", from `turns_away` — on the grounds that an
   * empty forecast is not an empty board. That is true and it is still true;
   * it is just not worth the widest line on the card, and `turns_away` rides in
   * the payload for anyone restyling this page who wants it back. */
  if (parts.length === 0) {
    total.textContent = 'N/A';
    total.className = 'cost-total safe';
    kill.hidden = true;
    box.classList.remove('lethal');
    box.classList.add('quiet');
    return;
  }
  box.classList.remove('quiet');

  total.textContent = parts.join(', ');
  total.className = 'cost-total';

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

/* JUST THE HEALTH NOW. The portrait, the name and the level pill went with the
 * hero card when it merged into the run card: which character is being played is
 * a detail of the run rather than its premise, and all three now ride the
 * checklist's LEVEL-UP row — the character's own goal, wearing the character's
 * own face, with "Isaac · Level 3" as its subtitle. `s.hero` stays in the payload
 * for anyone restyling this page. */
function drawHero(hero, vitals) {
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
  /* "Current game" is the resting label. "Standing on" is kept for the gap
     between games, because it is the one moment the two are different things —
     the run is parked on a node nobody is playing, and a label that still said
     "current game" would be claiming a session that is not happening. */
  el('now-label').textContent = now.playing ? 'Current game' : 'Standing on';
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

  /* THE DISTANCE, USED AS THE DESTINATION'S LABEL. It sits directly above the
   * cover and name it is counting towards, which is what lets it be this short:
   * on a line of its own it needed "to the Amulet" spelled out or it read as a
   * game title with a number in front of it, and here the thing underneath says
   * which game is meant. The word Amulet stays because the run is FOR the
   * Amulet — "3 games left" would be a countdown to nothing named. */
  const hops = num(run.hops, -1);
  el('hops').textContent = hops < 0 ? 'No route to Amulet'
    : hops === 0 ? 'At the Amulet'
    : hops + (hops === 1 ? ' game to Amulet' : ' games to Amulet');
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
    /* A row that was NOT done a moment ago and is now: flash it, so crossing it
     * off is something the viewer sees HAPPEN rather than notices afterwards.
     * Worth more now that there is no checkbox to flip: the resting difference
     * between a done row and a live one is a strike-through and a drained
     * picture, both of which are easy to miss the moment of. Never on the first
     * draw, where every done row would flash at once. */
    if (g.done && !firstDraw && !doneRows.has(key)) li.classList.add('flash');

    /* NO CHECKBOX COLUMN. Every row used to open with a `□` or a `✓` in its own
     * 15px column, which is 21px of every row (the box and its gutter) spent
     * saying what the row already says twice over: a done row is struck through
     * and dimmed, and its art is drained of colour. The art is the row's left
     * edge now, and it got the width back — see `--goal-art` in overlay.css. */

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

/* ---------------------------------------------------------- the route map --
 *
 * THE ROAD AHEAD, at overlay.html#map: every optimal road from the game in play
 * to the Amulet, as the layered graph the game's own RunMapModal draws.
 *
 * IT IS A GRAPH AND NOT A STRIP, which is the whole reason it is not just the
 * road pointed the other way. A layer is two or three games wide — several ways
 * on, all the same distance — and picking between them is the run's core
 * decision. A single line would draw a forced march.
 *
 * NODES ARE KEYED (depth, id), NEVER id. A route forced through a pinned game
 * walks there and then walks on, and the way on may come straight back over the
 * games that led in: the same game legitimately holds two rungs at two depths.
 * `RouteLadder.node_key` says the same thing in GDScript, and for the same
 * reason — keying by id merges the two and draws arrows into a step of the route
 * that does not exist.
 *
 * THE ARROWS ARE DRAWN FROM MEASURED BOXES, in an SVG behind the rows, because
 * an edge joins two PARTICULAR games across a layer and not every box to every
 * box. That means a second pass after layout, and it means the wires have to be
 * redrawn whenever the geometry moves — a rebuild, a resize, or the fit below
 * changing scale. `layoutWires` is that pass and is safe to call at any time. */
let routeSignature = '';

function drawMap(route, run) {
  const rows = el('map-rows');
  const note = el('map-note');
  const sub = el('map-sub');
  const layers = Array.isArray(route.layers) ? route.layers : [];

  /* The subtitle is cheap and changes on its own clock (the hop count ticks as
   * the run moves even when the ladder's shape does not), so it is written
   * every payload, outside the signature check below. */
  const amulet = (run.amulet && run.amulet.game) || '';
  const hops = num(run.hops, -1);
  sub.textContent = !amulet ? ''
    : route.arrived ? 'You are standing on ' + amulet
    : hops < 0 ? amulet + ' — no road from here'
    : hops + (hops === 1 ? ' game to ' : ' games to ') + amulet;

  const sig = [route.arrived, route.dropped, route.waypoint_depth,
    layers.map(l => l.map(n => [n.id, n.here, n.amulet, n.pinned, n.beaten]
      .join('~')).join(',')).join('|'),
    (route.edges || []).map(e => [e.from_depth, e.from, e.to_depth, e.to]
      .join('~')).join(',')].join('\x01');
  if (sig === routeSignature) return;
  routeSignature = sig;

  rows.innerHTML = '';
  el('map-wires').innerHTML = '';

  /* THE TWO EMPTY STATES ARE DIFFERENT THINGS and the panel must not draw the
   * same blank for both. Standing on the Amulet is the run's best moment; no
   * road at all is a dead end the streamer needs to know about. Neither is "the
   * source is broken", which is what an empty panel reads as. */
  if (!layers.length) {
    note.hidden = false;
    note.textContent = route.arrived
      ? 'The Amulet is under your feet. Beat it and the run is won.'
      : 'No road from here to the Amulet.';
    return;
  }

  layers.forEach((layer, depth) => {
    const row = document.createElement('div');
    row.className = 'map-row';
    layer.forEach((n) => {
      const box = document.createElement('div');
      box.className = 'rung'
        + (n.here ? ' here' : '')
        + (n.amulet ? ' amulet' : '')
        + (n.pinned ? ' pinned' : '')
        + (n.beaten ? ' beaten' : '');
      box.dataset.key = depth + '|' + n.id;
      box.title = n.name;
      const img = document.createElement('img');
      img.alt = n.name;
      setImg(img, n.cover);
      box.appendChild(img);
      const text = document.createElement('span');
      text.className = 'rung-name';
      /* An inner span so the clamp and the centring can be two different boxes —
       * `-webkit-line-clamp` requires `display: -webkit-box` on the element it
       * clamps, which cannot also be the flex box centring it. */
      const label = document.createElement('span');
      label.textContent = n.name;
      text.appendChild(label);
      box.appendChild(text);
      /* WHAT THIS RUNG IS, in one word, for the three that are not just "a game
       * on the way". Drawn rather than left to colour alone: this page's own
       * checklist learned that lesson (six row kinds told apart by text colour
       * with nothing saying what a colour meant), and a map read across a room
       * through a lossy encode is the worst case for it. */
      const tag = n.here ? 'Here' : n.amulet ? 'Amulet' : n.pinned ? 'Pinned'
        : n.beaten ? 'Beaten' : '';
      if (tag) {
        const flag = document.createElement('span');
        flag.className = 'rung-tag';
        flag.textContent = tag;
        box.appendChild(flag);
      }
      row.appendChild(box);
    });
    rows.appendChild(row);
  });

  /* THE FAR END, WHEN IT WAS TRIMMED. `_route` keeps the near layers — the ones
   * a decision is made out of — so what is missing is the approach to the
   * Amulet, and saying so is the difference between a trimmed map and a wrong
   * one. Nothing realistic reaches it; it exists so that if it ever does, the
   * page says it out loud. */
  const dropped = num(route.dropped);
  note.hidden = dropped <= 0;
  if (dropped > 0) {
    note.textContent = '+' + dropped + (dropped === 1 ? ' more layer' : ' more layers')
      + ' to the Amulet, not drawn';
  }

  layoutWires(route.edges || []);
}

/* SIZE THE LADDER TO THE SOURCE, then position the arrows.
 *
 * THIS IS WHAT MAKES THE MAP LEGIBLE, and the bug it fixes was not the type
 * size. Every rung used to be a flat 152px and the fit only ever scaled DOWN,
 * so a 1920x1080 source drew exactly the ladder a 640x720 one did and put a
 * thousand pixels of empty card around it. Going full screen made it WORSE:
 * more emptiness, same small covers.
 *
 * So the rung is solved for instead. Everything in the ladder is a fraction of
 * `--rung` (see overlay.css), so picking one number sizes the covers, the type,
 * the gaps and the arrows together, and the ladder is the same object at 100px
 * and at 300px rather than a different layout at each size.
 *
 * SOLVED ON BOTH AXES, because either can be the binding one: a shallow wide
 * route is bound by its tallest layer and a deep narrow one by its length. The
 * smaller of the two answers is the one that fits.
 *
 * AND SIZED RATHER THAN TRANSFORMED wherever there is room to grow. A
 * `transform: scale()` above 1 resamples text, which is precisely the wrong
 * tool for a pass about being able to read something. The transform survives
 * only as the squeeze at the far end, for a route so deep that even the floor
 * below does not fit — the whole route is always drawn, so something has to
 * give, and giving it up in pixels is better than dropping layers. */

/* The rung's height as a multiple of its width, which the CSS above fixes: the
 * padding, a 3:4 cover, the gaps, two lines of name and the tag. Kept here as
 * one number because the fit has to know it BEFORE anything is laid out. If the
 * rung's CSS proportions change, this changes with them. */
const RUNG_ASPECT = 1.50;
const LAYER_GAP = 0.32;   /* between layers, in rungs — the arrows' room */
const CHOICE_GAP = 0.08;  /* between the choices within one layer */
/* The floor is a legibility floor: below about 90px a cover is a smudge and the
 * name is unreadable, so there is no point shrinking further — past this the
 * transform takes over and the honest answer is that the route is very long.
 * The ceiling stops a two-layer route from being blown up into wall art. */
const RUNG_MIN = 90;
const RUNG_MAX = 300;

let lastEdges = [];

function layoutWires(edges) {
  if (edges) lastEdges = edges;
  const fit = el('map-fit');
  const rows = el('map-rows');
  const body = el('map-body');
  const svg = el('map-wires');
  const layers = [...rows.children];
  if (!layers.length) return;

  /* The shape to solve for: how many layers deep, and how many choices in the
   * fattest one. */
  const depth = layers.length;
  const width = Math.max(...layers.map((l) => l.children.length));
  const room = { w: body.clientWidth, h: body.clientHeight };
  if (room.w <= 0 || room.h <= 0) return;   /* hidden — nothing to measure */

  /* THE HEADING'S SIZE, FROM THE WINDOW AND NOT FROM THE LADDER. The head sits
   * above `.map-body`, so its height is part of what is subtracted from the room
   * solved into below — sizing it from `--rung` would put the two in a loop,
   * each redraw nudging the other. `window.innerHeight` is the one number here
   * that nothing on the page can move.
   *
   * 15px at a 720-tall source and about 30 at 1080, which is the slope this
   * expression is: a heading that stayed 15px on a full-screen map was the same
   * mistake as a rung that stayed 152. */
  const head = Math.max(13, Math.min(38, window.innerHeight * 0.0417 - 15));
  document.querySelector('.map').style.setProperty('--head', head + 'px');

  const byWidth = room.w / (depth + LAYER_GAP * (depth - 1));
  const byHeight = room.h / (RUNG_ASPECT * width + CHOICE_GAP * (width - 1));
  const ideal = Math.min(byWidth, byHeight);
  const rung = Math.max(RUNG_MIN, Math.min(RUNG_MAX, ideal));
  fit.style.setProperty('--rung', rung + 'px');

  /* THE SQUEEZE, and only when the floor was not enough. `ideal` is what would
   * have fitted; if the floor overrode it, the ladder is now bigger than the
   * panel by exactly that ratio. */
  const scale = ideal < RUNG_MIN ? Math.max(0.35, ideal / RUNG_MIN) : 1;
  fit.style.transform = 'scale(' + scale + ')';

  const origin = rows.getBoundingClientRect();
  const at = (key) => {
    const n = rows.querySelector('[data-key="' + cssEscape(key) + '"]');
    if (!n) return null;
    const r = n.getBoundingClientRect();
    return {
      cy: (r.top + r.height / 2 - origin.top) / scale,
      left: (r.left - origin.left) / scale,
      right: (r.right - origin.left) / scale,
    };
  };

  const w = origin.width / scale;
  const h = origin.height / scale;
  svg.setAttribute('viewBox', '0 0 ' + w + ' ' + h);
  svg.setAttribute('width', w);
  svg.setAttribute('height', h);
  svg.innerHTML = '';

  for (const e of lastEdges) {
    const a = at(e.from_depth + '|' + e.from);
    const b = at(e.to_depth + '|' + e.to);
    if (!a || !b) continue;
    /* A CURVE, NOT A STRAIGHT LINE, and not for decoration: a layer three high
     * sends edges diagonally across the gap, and a straight run from one box's
     * right edge to another's left crosses its neighbours' corners on the way.
     * Leaving each box horizontally and arriving horizontally keeps the
     * crossings in the empty band between layers, where they can be read. */
    const mid = (a.right + b.left) / 2;
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute('d', 'M' + a.right + ' ' + a.cy
      + ' C' + mid + ' ' + a.cy + ' ' + mid + ' ' + b.cy + ' ' + b.left + ' ' + b.cy);
    path.setAttribute('class', 'wire');
    svg.appendChild(path);
  }
}

/* `CSS.escape` is not on every CEF OBS ships (the same reason `:has()` and
 * `color-mix()` are avoided in overlay.css), and a game id can carry a colon or
 * a dot. Quote what a bare attribute selector cannot hold. */
function cssEscape(s) {
  return String(s).replace(/["\\]/g, '\\$&');
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
 *   overlay.html#top     the run card — the game, the road ahead, the stake
 *   overlay.html#bottom  the checklist and the ticker
 *   overlay.html#goals   the checklist, and nothing else
 *   overlay.html#road    the road, and nothing else
 *   overlay.html         everything EXCEPT the road (the default)
 *
 * `#goals` and `#bottom` differ by the ticker alone, and that is the whole
 * reason `#goals` exists: the ticker is pinned to the BOTTOM of the browser
 * source and floats over whatever is above it, so a source sized to the
 * checklist has toasts landing on the checklist. `#goals` is the one to point a
 * source at when the checklist has to share a scene with something else.
 *
 * AND `#fill`, WHICH IS A MODIFIER RATHER THAN A CHOICE, so it combines:
 * `#fill`, `#bottom,fill`, `#road,fill`. The default page is content-height and
 * leaves transparent space under itself in a taller source; `fill` makes it take
 * the whole source and gives the slack to the checklist, which is the only part
 * of the page that can use it. Hence the token parsing below rather than a
 * straight equality test — the fragment is a SET of words now.
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
  /* TWO WAYS IN, AND THE FILE IS THE ONE THAT WORKS IN OBS.
   *
   * `window.OBS_VIEW` is set by a one-line script in map.html, goals.html and
   * the rest — standalone pages the game generates from this one at every boot
   * (ObsCompanion.SPLIT_VIEWS). They exist because THE FRAGMENT DOES NOT REACH
   * THIS PAGE THROUGH OBS. With "Local file" ticked the field is a path and not
   * a URL, so the `#` is escaped and never becomes a fragment; unticking it and
   * pasting a `file:///…#map` URL into the URL box does not get there either.
   * That is not a thing this page can fix from the inside, so the split it
   * cannot receive is baked into a file whose name a streamer can simply browse
   * to.
   *
   * The hash still works, and is still the way to COMBINE — `map.html#fill` is
   * the baked view plus the modifier, which is why these are unioned rather
   * than one overriding the other. */
  const parts = new Set((location.hash || '').replace('#', '').toLowerCase()
    .split(/[^a-z]+/).filter(Boolean));
  if (typeof window.OBS_VIEW === 'string') {
    for (const w of window.OBS_VIEW.toLowerCase().split(/[^a-z]+/)) {
      if (w) parts.add(w);
    }
  }
  overlay.classList.toggle('only-top', parts.has('top'));
  overlay.classList.toggle('only-bottom', parts.has('bottom'));
  overlay.classList.toggle('only-goals', parts.has('goals'));
  overlay.classList.toggle('only-road', parts.has('road'));
  overlay.classList.toggle('only-map', parts.has('map'));
  overlay.classList.toggle('fill', parts.has('fill'));
  /* THE MAP IS MEASURED, so it has to be re-laid the moment it becomes visible.
   * A `display: none` ladder has no geometry at all — every box reports a zero
   * rect — so wires drawn while the map was hidden are drawn from nothing, and
   * switching the fragment to #map would show a ladder with no arrows on it
   * until the route happened to change. */
  layoutWires();
}
applySplit();
window.addEventListener('hashchange', applySplit);
/* Same reason: the source can be resized in OBS while the page is running, and
 * both the fit and every arrow depend on the box the ladder is laid out in. */
window.addEventListener('resize', () => layoutWires());

/* The two self-scrolling boxes, registered before the first payload lands so
 * `frame` has something to walk from the very first tick. */
makeScroller('goal-scroll', 'y');
makeScroller('road-scroll', 'x');

poll();
setInterval(poll, POLL_MS);
requestAnimationFrame(frame);
