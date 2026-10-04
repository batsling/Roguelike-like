#!/usr/bin/env node
/*
 * capture_proof.js — a screenshot of the PROOF behind each influence connection.
 *
 * Every connection carries a Source (`influence_sources` on the influencer's
 * GameData, index-aligned with `games_influenced`). When it is a link, the proof
 * is a sentence on that page: the developer saying where their game came from.
 * This opens the link in headless Chromium, finds that sentence, highlights it
 * and saves a cropped screenshot, one per connection:
 *
 *     .influence_work/proof/<from>__<to>.png
 *     .influence_work/proof/report.json     every connection tried, and why one failed
 *
 * Which sentence:
 *   1. the URL's own `#:~:text=` fragment, when it has one. The owner marked the
 *      passage by hand, so it wins over any guess;
 *   2. otherwise the passage naming the influencer, scored up for a claim word
 *      ("inspired", "influenced", the CLAIM list in influence_research.py) and
 *      for naming the influencee too;
 *   3. otherwise the influencee's name, reported as `weak` — a page about the
 *      newer game that never names the older one proves nothing by itself.
 *
 * Per source kind:
 *   x        the official embed (publish.twitter.com/oembed + widgets.js); x.com
 *            itself shows nothing without a login
 *   youtube  a card: thumbnail, title, channel and the timestamp. Clips are not
 *            downloaded — that is against YouTube's terms — so a clip of the
 *            moment has to be recorded by hand
 *   reddit   old.reddit.com, which refuses cloud addresses, so the Reddit
 *            connections are captured from the owner's own computer with
 *            --kind reddit; from the cloud only a post's own text (via the
 *            embed host) can be captured
 *   steam    age gate pre-answered by cookie
 *
 *   node tools/capture_proof.js --pilot            25 connections across every source kind
 *   node tools/capture_proof.js --only hades       connections out of one game
 *   node tools/capture_proof.js --limit 50         the first 50 with a link
 *   node tools/capture_proof.js --kind reddit       Reddit, from your own computer, then --export
 *   node tools/capture_proof.js --missing          write docs/proof-missing.md: what has no proof yet
 *   node tools/capture_proof.js --skip youtube,podcast --untried
 *                                                  finish a stopped run, leaving its failures alone
 *   node tools/capture_proof.js --skip youtube,podcast --resume
 *                                                  the full run, leaving out video and audio,
 *                                                  and skipping what already has an image
 *   node tools/capture_proof.js --export           copy the captures into the game as
 *                                                  images2.0/proof/<influencer id>---<influenced id>.png,
 *                                                  beside (never over) the owner's own
 *
 * Needs Playwright (`npm install playwright` or NODE_PATH pointing at one) and a
 * Chromium; in the cloud container NODE_PATH=/opt/node-tools/node_modules works.
 *
 * In a cloud session, Chromium fails every page with ERR_CERT_AUTHORITY_INVALID
 * until it trusts the agent proxy's interception CA. That CA is not in the
 * system bundle (curl never sees it; only Chromium's traffic is re-signed), and
 * Chromium reads its own NSS store rather than the bundle. Pull the CA out of a
 * failing load (`--log-net-log` records the chain) and add it once per container:
 *
 *     certutil -d sql:$HOME/.pki/nssdb -N --empty-password
 *     certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n ccr-proxy -i proxy-ca.pem
 *
 * Never work around it with ignoreHTTPSErrors: that turns verification off for
 * every site, not just the proxy.
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, '.influence_work', 'proof');

// The same claim words as influence_research.py's CLAIM, English half: a passage
// that says one of these beside the name is the proof, not a passing mention.
const CLAIM = /inspir|influenc|homage|love letter|tribute|spiritual successor|big fans? of|heavily based|took (?:a lot )?from|borrow|in the vein|cues from|blend of|mix of|\bmeets\b|cross between|from the (?:creators|makers|developers?|team) of|sequel|predecessor|影響|インスパイア|灵感|启发|영감|영향/i;

// Chart names that are ordinary words: matched case-sensitively, as in the research tool.
const AMBIGUOUS = new Set(['Rogue', 'Hack', 'Roll', 'Crawl', 'Omega', 'Haste', 'Rounds', 'Ringer',
  'Morsels', 'Gnomes', 'Underdogs', 'Drapline', 'Wireworks', 'Overworld', 'Powder', 'Talented',
  'Eldritch', 'Cataclysm', 'Sil', 'Convoy', 'Ragnarok', 'From The Top', 'Neophyte', 'Heading Out',
  'Diablo', 'Moria', 'Larn']);

// ── the connections, read off data/games ──────────────────────────────────────

function strings(src) {
  return [...src.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map(m => m[1].replace(/\\(.)/g, '$1'));
}

function loadConnections() {
  const dir = path.join(ROOT, 'data', 'games');
  const games = {};
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.tres'))) {
    const t = fs.readFileSync(path.join(dir, f), 'utf8');
    const id = (t.match(/^id = &"([^"]+)"/m) || [])[1];
    if (!id) continue;
    const field = re => (t.match(re) || [, ''])[1];
    games[id] = {
      id,
      name: strings(field(/^display_name = (".*")$/m))[0] || id,
      out: [...field(/^games_influenced = Array\[StringName\]\(\[(.*)\]\)$/m).matchAll(/&"([^"]+)"/g)].map(m => m[1]),
      sources: strings(field(/^influence_sources = PackedStringArray\((.*)\)$/m)),
      relations: strings(field(/^influence_relations = PackedStringArray\((.*)\)$/m)),
    };
  }
  const conns = [];
  for (const g of Object.values(games)) {
    g.out.forEach((to, i) => {
      const source = g.sources[i] || '';
      const url = (source.match(/https?:\/\/\S+/) || [])[0] || '';
      conns.push({
        from: g.id, fromName: g.name, to, toName: (games[to] || {}).name || to,
        source, url, relation: g.relations[i] || '', kind: kindOf(url),
      });
    });
  }
  return conns.sort((a, b) => (a.from + a.to).localeCompare(b.from + b.to));
}

function kindOf(url) {
  if (!url) return 'none';
  const h = new URL(url).hostname.replace(/^www\./, '');
  const p = new URL(url).pathname;
  if (/(^|\.)(x|twitter)\.com$/.test(h)) return 'x';
  if (/youtube\.com$|youtu\.be$/.test(h)) return 'youtube';
  if (/spotify\.com$|roguelikeradio\.com$|podcasts\.apple\.com$/.test(h) || /\.(mp3|m4a|ogg)$/i.test(p)) return 'podcast';
  if (/reddit\.com$/.test(h)) return 'reddit';
  if (h === 'store.steampowered.com' && p.startsWith('/news')) return 'steam_announce';
  if (h === 'store.steampowered.com') return 'steam_store';
  if (h === 'steamcommunity.com' && p.includes('/announcements')) return 'steam_announce';
  if (h === 'steamcommunity.com') return 'steam_forum';
  if (/roguebasin\.com$|wikipedia\.org$|fandom\.com$/.test(h)) return 'wiki';
  return 'article';
}

// ── picking the pilot ─────────────────────────────────────────────────────────

const PILOT = { steam_announce: 3, steam_store: 3, steam_forum: 2, reddit: 3, x: 3,
  youtube: 3, article: 5, wiki: 2, podcast: 1 };

function seeded(seed) {
  return () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
}

function pilot(conns) {
  const rnd = seeded(20261004);
  const picked = [];
  for (const [kind, n] of Object.entries(PILOT)) {
    const pool = conns.filter(c => c.kind === kind);
    for (let i = 0; i < n && pool.length; i++) picked.push(pool.splice(Math.floor(rnd() * pool.length), 1)[0]);
  }
  return picked;
}

// ── names to look for on the page ─────────────────────────────────────────────

// "The Binding of Isaac" is written "Binding of Isaac"; "Moonlighter 2: The
// Endless Vault" is written "Moonlighter 2". Both short forms count, unless
// the short form is two letters long or an ordinary word.
function variants(name) {
  const v = new Set([name]);
  const noThe = name.replace(/^The\s+/i, '');
  v.add(noThe);
  // "Spelunky Classic" is written "Spelunky"; a remaster by its original's name.
  const bare = noThe.replace(/\s+(Classic|Remastered|Remake|HD|Deluxe|Original|(Definitive|Enhanced|Complete) Edition)$/i, '');
  if (bare.length > 3 && !AMBIGUOUS.has(bare)) v.add(bare);
  for (const n of [name, noThe]) {
    const head = n.split(/\s*[:\-–—]\s+/)[0];
    if (head.length > 3 && !AMBIGUOUS.has(head)) v.add(head);
  }
  return [...v].filter(s => s.length > 2);
}

function textFragment(url) {
  const m = url.match(/#:~:text=([^&#]+)/);
  if (!m) return null;
  // text=[prefix-,]start[,end][,-suffix]; prefix/suffix are context only.
  const parts = m[1].split(',').map(s => decodeURIComponent(s.replace(/\+/g, ' ')));
  const core = parts.filter(p => !p.endsWith('-') && !p.startsWith('-'));
  return { start: core[0] || '', end: core[1] || '' };
}

// ── the page side: find, highlight, measure ───────────────────────────────────
// Runs inside the browser. Picks one SENTENCE, not a whole post: a forum reply
// or a patch note runs to a screen or more, and the proof is one line of it.
// Highlighting is done with the CSS Custom Highlight API rather than by
// wrapping nodes, because a sentence often crosses a <b> or an <a>.

function findAndMark({ fragment, fromNames, toNames, claimSrc, ambiguous }) {
  const claim = new RegExp(claimSrc, 'i');
  const pat = n => {
    const gap = '[\\s:\\-–—]+';
    const body = n.split(/[\s:\-–—]+/).map(w => w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join(gap);
    // Latin names need word edges; a name in Japanese or Chinese text sits
    // between 『』 or straight against kana, so the edge test is only on \w.
    return new RegExp('(?<![A-Za-z0-9])' + body + '(?![A-Za-z0-9])', ambiguous.includes(n) ? 'g' : 'gi');
  };
  const first = (names, text, from = 0, to = text.length) => {
    let hit = null;
    for (const n of names) {
      const re = pat(n);
      re.lastIndex = from;
      for (let m; (m = re.exec(text));) {
        if (m.index >= to) break;
        if (!hit || m.index < hit.at) hit = { at: m.index, len: m[0].length };
        break;
      }
    }
    return hit;
  };

  // Each text node belongs to its nearest block; a block's text is its own
  // nodes, flattened, with each node's offset kept so a range can be built back.
  const BLOCK = 'p,li,blockquote,td,dd,dt,h1,h2,h3,h4,h5,h6,figcaption,pre,div,section,article';
  const blocks = new Map();
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let n; (n = walker.nextNode());) {
    if (!n.nodeValue.trim()) continue;
    const p = n.parentElement;
    if (!p || p.closest('script,style,noscript,nav,footer,template')) continue;
    const b = p.closest(BLOCK) || p;
    if (!blocks.has(b)) blocks.set(b, []);
    blocks.get(b).push(n);
  }

  // A sentence ends at its punctuation, at a line end, or at the end of the block.
  const SENT = /[^.!?。！？\n]*(?:[.!?。！？]+|(?=\n)|$)/g;
  let best = null;
  for (const [el, nodes] of blocks) {
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0 || getComputedStyle(el).visibility === 'hidden') continue;
    let text = '';
    const offs = [];
    for (const n of nodes) {
      // A <br> between two text nodes is a line end; without it "…Kill the
      // Brickman<br>One more thing!" reads as one sentence.
      if (text && n.previousSibling && n.previousSibling.nodeName === 'BR') text += '\n';
      offs.push(text.length);
      text += n.nodeValue;
    }
    const consider = (start, end, score, how, names) => {
      if (end <= start) return;
      // A tie goes to the EARLIER mention: an interview names its influence
      // where it explains it, and comes back to it later in passing.
      if (!best || score > best.score)
        best = { el, nodes, offs, text, start, end, score, how, names };
    };
    if (fragment && fragment.start) {
      const words = s => s.trim().split(/\s+/).map(w => w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('\\s+');
      const m = new RegExp(words(fragment.start), 'i').exec(text);
      if (m) {
        let end = m.index + m[0].length;
        if (fragment.end) {
          const e = new RegExp(words(fragment.end), 'i');
          e.lastIndex = end;
          const me = e.exec(text.slice(end));
          if (me) end += me.index + me[0].length;
        }
        consider(m.index, end, 100, 'fragment', fromNames);
      }
    }
    SENT.lastIndex = 0;
    for (let m; (m = SENT.exec(text));) {
      if (!m[0]) { SENT.lastIndex++; continue; }
      const s = m.index, e = s + m[0].length;
      const sentence = m[0];
      if (sentence.length > 1200) continue;
      if (first(fromNames, text, s, e)) {
        let score = 10;
        if (claim.test(sentence)) score += 5;
        if (first(toNames, text, s, e)) score += 3;
        consider(s, e, score, 'name', fromNames);
      } else if (claim.test(sentence) && first(toNames, text, s, e)) {
        consider(s, e, 1, 'weak', toNames);
      }
    }
  }
  if (!best) return null;

  // Trim the sentence's leading blanks so the band starts on a letter.
  while (best.start < best.end && /\s/.test(best.text[best.start])) best.start++;
  const point = i => {
    let k = best.offs.length - 1;
    while (k > 0 && best.offs[k] > i) k--;
    return [best.nodes[k], Math.min(i - best.offs[k], best.nodes[k].nodeValue.length)];
  };
  const range = (a, b) => {
    const r = document.createRange();
    r.setStart(...point(a));
    r.setEnd(...point(b));
    return r;
  };
  const sentence = range(best.start, best.end);
  const hit = first(best.names, best.text, best.start, best.end);
  const style = document.createElement('style');
  style.textContent = '::highlight(proof-line){background-color:rgba(255,214,0,.30)}'
    + '::highlight(proof-name){background-color:#ffd600;color:#000}';
  document.head.appendChild(style);
  CSS.highlights.set('proof-line', new Highlight(sentence));
  if (hit) CSS.highlights.set('proof-name', new Highlight(range(hit.at, hit.at + hit.len)));

  // Opened <details>, "read more" clamps and the like would hide it; the
  // sentence is scrolled to the middle so lazy images above it have settled.
  sentence.startContainer.parentElement.scrollIntoView({ block: 'center' });
  const s = sentence.getBoundingClientRect();
  const b = best.el.getBoundingClientRect();
  return {
    how: best.how,
    text: best.text.slice(best.start, best.end).replace(/\s+/g, ' ').trim().slice(0, 500),
    line: { x: s.x + scrollX, y: s.y + scrollY, w: s.width, h: s.height },
    block: { x: b.x + scrollX, y: b.y + scrollY, w: b.width, h: b.height },
  };
}

// ── capture, per kind ─────────────────────────────────────────────────────────

const COOKIE_BUTTONS = /^(accept( all)?( cookies)?|i agree|agree( & close)?|allow all|got it|ok|consent|continue)$/i;

async function dismissBanners(page) {
  for (const frame of page.frames()) {
    try {
      const buttons = await frame.$$('button, a[role=button], [role=button]');
      for (const b of buttons.slice(0, 200)) {
        const t = ((await b.textContent()) || '').trim();
        if (COOKIE_BUTTONS.test(t) && await b.isVisible()) { await b.click({ timeout: 1500 }).catch(() => {}); break; }
      }
    } catch (e) { /* a detached frame: nothing to dismiss */ }
  }
}

// Reddit, in the order that gives a real screenshot of the real page:
//   1. old.reddit.com, which renders the whole thread, comments included, with
//      no login wall. It refuses cloud addresses ("blocked by network security")
//      and works from a home connection, which is why the owner runs
//      `--kind reddit` on their own computer;
//   2. embed.reddit.com, the host Reddit serves to other websites. It answers a
//      cloud address, but renders the POST only, so it catches proof in a
//      post's title or text and nothing in its comments.
// The proof is often the developer's own comment under a video post, so a
// thread neither can show is reported as blocked, to capture from home. (It
// used to fall back to a quote card transcribed from an archive; the owner
// wants screenshots of the page.)
const REDDIT_HOME = 'Reddit refuses this machine: capture it from your own computer with node tools/capture_proof.js --kind reddit';

async function captureReddit(ctx, c, file) {
  const old = await capturePage(ctx, c, file, c.url.replace(/\/\/(www\.|old\.|new\.)?reddit\.com/, '//old.reddit.com'));
  if (!['blocked', 'error', 'no-match'].includes(old.status)) return old;
  const embed = await capturePage(ctx, c, file, c.url.replace(/\/\/(www\.|old\.|new\.)?reddit\.com/, '//embed.reddit.com'));
  if (!['blocked', 'error', 'no-match'].includes(embed.status)) return embed;
  // old.reddit's own answer says whether it was the block or the page.
  return old.status === 'blocked' ? { status: 'blocked', detail: REDDIT_HOME } : old;
}

async function capturePage(ctx, c, file, at) {
  const url = (at || c.url).replace(/#.*$/, '');
  const page = await ctx.newPage();
  try {
    const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
    const status = resp ? resp.status() : 0;
    await page.waitForLoadState('networkidle', { timeout: 12000 }).catch(() => {});
    if (status >= 400) return { status: 'blocked', detail: `HTTP ${status}` };
    await dismissBanners(page);
    await page.waitForTimeout(800);
    // Collapsed text: Steam's "Read more", Reddit's "load more comments" are not
    // proof-bearing often enough to chase; the store page's About section is.
    await page.$$eval('#game_area_description', els => els.forEach(e => { e.style.maxHeight = 'none'; e.style.overflow = 'visible'; })).catch(() => {});
    const look = () => page.evaluate(findAndMark, {
      fragment: textFragment(c.url),
      fromNames: variants(c.fromName),
      toNames: variants(c.toName),
      claimSrc: CLAIM.source,
      ambiguous: [...AMBIGUOUS],
    });
    // Steam announcements and most article sites fill their body in by script
    // after the load settles; one slower second look catches them.
    let found = await look();
    if (!found) { await page.waitForTimeout(4000); found = await look(); }
    if (!found && /Application error|You've been blocked|Access denied|Just a moment/i.test(await page.evaluate(() => document.body.innerText.slice(0, 2000)))) {
      await page.screenshot({ path: file.replace(/\.png$/, '.miss.png') });
      return { status: 'blocked', detail: 'the page refused the browser (bot wall or script error)', final: page.url() };
    }
    if (!found) {
      await page.screenshot({ path: file.replace(/\.png$/, '.miss.png') });
      return { status: 'no-match', detail: 'neither name found on the page', final: page.url() };
    }
    await page.waitForTimeout(300);
    // Crop: the passage's column, from a few lines above the sentence to a few
    // below, so the reader sees what it is part of without a page of it.
    const vw = page.viewportSize().width;
    const CONTEXT = 90, PAD = 20;
    const x = Math.max(0, Math.min(found.block.x, found.line.x) - PAD);
    const right = Math.min(vw, Math.max(found.block.x + found.block.w, found.line.x + found.line.w) + PAD);
    const top = Math.max(0, Math.max(found.block.y - PAD, found.line.y - CONTEXT));
    const bottom = Math.min(found.block.y + found.block.h + PAD, found.line.y + found.line.h + CONTEXT);
    const height = Math.min(Math.max(bottom - top, found.line.h + 2 * PAD), 600);
    await page.screenshot({ path: file, fullPage: true,
      clip: { x, y: top, width: Math.max(right - x, 360), height } });
    return { status: found.how === 'weak' ? 'weak' : 'ok', how: found.how, quote: found.text, final: page.url() };
  } catch (e) {
    return { status: 'error', detail: String(e.message || e).split('\n')[0] };
  } finally {
    await page.close();
  }
}

// One page's script can hang the evaluate that reads it forever (Brotato ->
// Gnomes did, for 13 minutes, with no timeout of Playwright's covering it).
// Past the deadline the connection is recorded as timed out, and every page
// still open is closed, which is what makes the stuck evaluate give up.
async function withDeadline(work, ms, ctx) {
  let timer;
  const late = new Promise(resolve => { timer = setTimeout(() => resolve({ status: 'error', detail: `timed out after ${ms / 1000}s` }), ms); });
  const r = await Promise.race([work, late]);
  clearTimeout(timer);
  if (r.detail && r.detail.startsWith('timed out')) for (const p of ctx.pages()) await p.close().catch(() => {});
  return r;
}

async function getJSON(ctx, url) {
  const r = await ctx.request.get(url, { timeout: 20000 });
  if (!r.ok()) throw new Error(`HTTP ${r.status()}`);
  return r.json();
}

async function captureTweet(ctx, c, file) {
  const m = c.url.match(/(?:x|twitter)\.com\/([^/]+)\/status(?:es)?\/(\d+)/);
  if (!m) return { status: 'error', detail: 'not a tweet URL' };
  let embed;
  try {
    embed = await getJSON(ctx, 'https://publish.twitter.com/oembed?dnt=1&hide_media=1&hide_thread=1&url=' + encodeURIComponent(`https://twitter.com/${m[1]}/status/${m[2]}`));
  } catch (e) {
    return { status: 'blocked', detail: 'embed endpoint: ' + e.message };
  }
  const page = await ctx.newPage();
  try {
    await page.setContent(`<html><body style="margin:0;padding:24px;background:#fff;width:600px">${embed.html}</body></html>`);
    const frame = await page.waitForSelector('iframe[id^=twitter-widget]', { timeout: 20000 }).catch(() => null);
    if (!frame) return { status: 'error', detail: 'embed did not render' };
    await page.waitForTimeout(2500);
    await frame.screenshot({ path: file });
    const quote = (embed.html.match(/<p[^>]*>([\s\S]*?)<\/p>/) || [, ''])[1].replace(/<[^>]+>/g, '');
    const named = variants(c.fromName).some(n => quote.toLowerCase().includes(n.toLowerCase()));
    return { status: named ? 'ok' : 'weak', how: 'embed', quote, detail: named ? '' : 'tweet text does not name ' + c.fromName + ' (may be in an image or a reply)' };
  } finally {
    await page.close();
  }
}

function ytId(url) {
  const u = new URL(url);
  if (u.hostname.endsWith('youtu.be')) return u.pathname.slice(1);
  return u.searchParams.get('v') || (u.pathname.match(/\/(?:embed|shorts|live)\/([^/?]+)/) || [])[1];
}

function ytTime(url) {
  const t = new URL(url).searchParams.get('t') || (url.match(/[#&?]t=([^&#]+)/) || [])[1];
  if (!t) return null;
  if (/^\d+$/.test(t)) return +t;
  const m = t.match(/(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?/);
  return (+(m[1] || 0)) * 3600 + (+(m[2] || 0)) * 60 + (+(m[3] || 0));
}

const esc = s => String(s).replace(/[&<>"]/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[ch]));

async function captureVideo(ctx, c, file) {
  const id = ytId(c.url);
  if (!id) return { status: 'error', detail: 'no video id' };
  let meta;
  try {
    meta = await getJSON(ctx, 'https://www.youtube.com/oembed?format=json&url=' + encodeURIComponent('https://www.youtube.com/watch?v=' + id));
  } catch (e) {
    return { status: 'blocked', detail: 'oembed: ' + e.message + ' (private or removed?)' };
  }
  const t = ytTime(c.url);
  const stamp = t == null ? '' : `${Math.floor(t / 3600) ? Math.floor(t / 3600) + ':' : ''}${String(Math.floor(t / 60) % 60).padStart(Math.floor(t / 3600) ? 2 : 1, '0')}:${String(t % 60).padStart(2, '0')}`;
  const page = await ctx.newPage();
  try {
    await page.setContent(`<html><body style="margin:0;background:#111;font-family:sans-serif;color:#eee">
      <div id="card" style="width:640px;padding:16px">
        <div style="position:relative"><img src="https://i.ytimg.com/vi/${esc(id)}/hqdefault.jpg" style="width:640px;display:block;border-radius:6px">
        ${stamp ? `<div style="position:absolute;right:10px;bottom:10px;background:#000c;padding:4px 10px;border-radius:4px;font-size:22px">▶ ${stamp}</div>` : ''}</div>
        <div style="font-size:20px;margin-top:10px">${esc(meta.title)}</div>
        <div style="font-size:15px;color:#aaa;margin-top:4px">${esc(meta.author_name)} · YouTube${stamp ? ' · from ' + stamp : ''}</div>
      </div></body></html>`);
    await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
    await (await page.$('#card')).screenshot({ path: file });
    return { status: stamp ? 'card' : 'card-no-time', how: 'card', quote: meta.title,
      detail: stamp ? '' : 'no timestamp: the moment it is said is not marked' };
  } finally {
    await page.close();
  }
}

// ── main ──────────────────────────────────────────────────────────────────────

// ── into the game ─────────────────────────────────────────────────────────────
// GameChoiceModal shows images2.0/proof/<influencer id>---<influenced id>.png
// under the connection's claim (slay_the_spire---tic_tactic.png). An id is only
// lower-case letters, digits and underscores, so the three hyphens split a name
// one way only, and the owner can type these by hand. PNG is the owner's call; the
// files are copied byte for byte. Video and audio cards are left out: the owner
// sources those moments by hand.
//
// WHOSE FILE IS WHOSE. Captured and owner's proofs share the folder and the
// name format, so the name can't tell them apart. tools/proof_captured.json
// can: every file this export copies in is recorded there with a sha1 of its
// bytes, and only a file still listed with that same sha1 is ever replaced or
// deleted. Everything else is the owner's — a file they dropped in under the
// right name, or a captured one they uploaded over (its bytes no longer match,
// so it drops off the list and is theirs from then on).
const GAME_DIR = path.join(ROOT, 'images2.0', 'proof');
const CAPTURED = path.join(__dirname, 'proof_captured.json');
const gameFile = r => `${r.from}---${r.to}.png`;
const isProofName = f => /^[a-z0-9_]+---[a-z0-9_]+\.png$/.test(f);
const sha1 = file => require('crypto').createHash('sha1').update(fs.readFileSync(file)).digest('hex');

function exportProofs() {
  const report = JSON.parse(fs.readFileSync(path.join(OUT, 'report.json'), 'utf8'));
  const ledger = JSON.parse(fs.readFileSync(CAPTURED, 'utf8'));
  const ours = f => ledger.files[f] && fs.existsSync(path.join(GAME_DIR, f)) && sha1(path.join(GAME_DIR, f)) === ledger.files[f];
  // A listed file whose bytes changed was uploaded over: the owner's now.
  for (const f of Object.keys(ledger.files)) if (fs.existsSync(path.join(GAME_DIR, f)) && !ours(f)) delete ledger.files[f];
  fs.mkdirSync(GAME_DIR, { recursive: true });
  const owners = f => fs.existsSync(path.join(GAME_DIR, f)) && !ledger.files[f];
  const keep = report.filter(r => r.image && !['youtube', 'podcast'].includes(r.kind) && r.status !== 'quote-card' && !owners(gameFile(r)));
  let bytes = 0;
  for (const r of keep) {
    const dest = path.join(GAME_DIR, gameFile(r));
    fs.copyFileSync(path.join(OUT, r.image), dest);
    ledger.files[gameFile(r)] = sha1(dest);
    bytes += fs.statSync(dest).size;
  }
  // A captured file goes only when its connection is KNOWN to have nothing:
  // re-captured as a failure, or taken out of the sheet. Not merely because this
  // machine's report doesn't mention it — the owner exports from their own
  // computer after a `--kind reddit` run, with a report that knows only Reddit,
  // and that must add the Reddit proofs without wiping the rest.
  const want = new Set(keep.map(gameFile));
  const onSheet = new Set(loadConnections().map(gameFile));
  const failed = new Set(report.filter(r => !r.image || r.status === 'quote-card').map(gameFile));
  for (const f of Object.keys(ledger.files)) {
    if (want.has(f) || !ours(f)) continue;
    if (failed.has(f) || !onSheet.has(f)) { fs.unlinkSync(path.join(GAME_DIR, f)); delete ledger.files[f]; }
  }
  for (const f of Object.keys(ledger.files)) if (!fs.existsSync(path.join(GAME_DIR, f))) delete ledger.files[f];
  ledger.files = Object.fromEntries(Object.entries(ledger.files).sort());
  fs.writeFileSync(CAPTURED, JSON.stringify(ledger, null, 1) + '\n');
  const all = fs.readdirSync(GAME_DIR).filter(f => f.endsWith('.png'));
  const misnamed = all.filter(f => !isProofName(f) || !onSheet.has(f));
  console.log(`${keep.length} captured proofs -> images2.0/proof/ (${(bytes / 1048576).toFixed(1)} MB); ` +
    `${all.length - Object.keys(ledger.files).length - misnamed.length} of yours beside them`);
  if (misnamed.length) console.log(`Not <influencer id>---<influenced id>.png for a connection on the sheet, so not shown in game ` +
    `(python3 tools/proof_owner_match.py renames free-named uploads):\n  ${misnamed.join('\n  ')}`);
}

// ── what is still missing ─────────────────────────────────────────────────────
// docs/proof-missing.md: every connection with no proof in the game, grouped by
// what it needs from the owner. Regenerated, not edited: run it after a capture
// run or after adding screenshots, and it drops whatever has a proof now.
function writeMissing() {
  const report = new Map(JSON.parse(fs.readFileSync(path.join(OUT, 'report.json'), 'utf8')).map(r => [`${r.from}__${r.to}`, r]));
  const file = gameFile;
  const inGame = new Set(fs.readdirSync(GAME_DIR));
  const groups = { reddit: [], dead: [], refused: [], down: [], nomatch: [], video: [], note: [], none: [] };
  for (const c of loadConnections()) {
    if (inGame.has(file(c))) continue;
    const r = report.get(`${c.from}__${c.to}`);
    const line = (why) => `- [ ] **${c.fromName} → ${c.toName}**${why ? ` — ${why}` : ''}${c.url ? ` — [${new URL(c.url).hostname.replace(/^www\./, '')}](${c.url})` : ''}`;
    if (!c.url) {
      const note = c.source.trim();
      (note ? groups.note : groups.none).push(line(note ? `"${note.length > 80 ? note.slice(0, 79) + '…' : note}"` : ''));
    } else if (['youtube', 'podcast'].includes(c.kind)) groups.video.push(line(''));
    else if (c.kind === 'reddit') groups.reddit.push(line(r && r.status === 'no-match' ? 'the post loaded but neither name is in it' : ''));
    else if (!r) groups.down.push(line('not captured yet'));
    else if (r.status === 'no-match') groups.nomatch.push(line(''));
    else if (/HTTP 40[46]|HTTP 410|not a tweet URL/.test(r.detail || '')) groups.dead.push(line(
      c.kind === 'x' ? (/not a tweet/.test(r.detail) ? 'the link is an account, not a tweet' : 'the tweet is deleted') : 'the page is gone'));
    else if (/HTTP (5\d\d)|timed out|ERR_NAME|ERR_CONNECTION|ERR_TIMED|net::/.test(r.detail || '')) groups.down.push(line(r.detail.split(' at ')[0].slice(0, 70)));
    else groups.refused.push(line((r.detail || r.status).slice(0, 70)));
  }
  const total = Object.values(groups).reduce((n, g) => n + g.length, 0);
  const section = (title, intro, lines) => lines.length ? `## ${title} (${lines.length})\n\n${intro}\n\n${lines.join('\n')}\n\n` : '';
  const doc = `# Connections with no proof in the game

Generated by \`node tools/capture_proof.js --missing\` from the capture report and
the files in \`images2.0/proof/\`, so **don't edit it by hand**: add the proof,
then run it again and the connection drops off. ${inGame.size ? `${[...inGame].filter(isProofName).length} connections have a proof in the game; ` : ''}${total} don't, below,
grouped by what each needs. A proof you screenshot yourself goes in
\`images2.0/proof/\` as \`<influencer id>---<influenced id>.png\` (the ids are the
game's file names in \`data/games/\`, e.g. \`slay_the_spire---tic_tactic.png\`), or
under any name followed by \`python3 tools/proof_owner_match.py --write\` (see
\`docs/influence-research.md\`).

` + section('Reddit: capture from your own computer',
    'Reddit blocks the cloud container. `node tools/capture_proof.js --kind reddit` on your own computer captures these as real screenshots, then `--export`. The same run also re-captures the Reddit proofs already in the game, which came through Reddit\'s embed page from here and can come out faded where a long post is folded under "Read more".', groups.reddit)
    + section('The link is dead',
    'The page or tweet is gone. These need a new source, or an archived copy if you can find one.', groups.dead)
    + section('The site refused the browser',
    'Bot walls, 403s and rate limits. Open the link in your own browser and screenshot the sentence.', groups.refused)
    + section('The site was down or never answered',
    'Worth one retry later (`--only <game id>`); if it stays down, the link may need replacing. RogueBasin was down for everyone during the run.', groups.down)
    + section('The page loaded, but the sentence wasn\'t found',
    'Neither game is named in the page\'s text. Usually a dead or moved page, a name written differently, or the proof sitting in an image or a video on the page.', groups.nomatch)
    + section('Videos and podcasts',
    'Yours to source: the moment it is said, as a screenshot or a clip.', groups.video)
    + section('The Source is a note, not a link',
    'Notes like "look at it" or "check folder" with no screenshot in the folder for this connection yet.', groups.note)
    + section('No Source at all', 'Nothing in the sheet\'s Source column for these.', groups.none);
  fs.writeFileSync(path.join(ROOT, 'docs', 'proof-missing.md'), doc.trimEnd() + '\n');
  console.log(`docs/proof-missing.md: ${total} connections without a proof (` + Object.entries(groups).map(([k, v]) => `${k} ${v.length}`).join(', ') + ')');
}

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--missing')) return writeMissing();
  if (args.includes('--export')) return exportProofs();
  const opt = k => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : null; };
  const all = loadConnections();
  let todo = all.filter(c => c.url);
  if (args.includes('--pilot')) todo = pilot(all);
  if (opt('--only')) todo = todo.filter(c => c.from === opt('--only') || c.to === opt('--only'));
  // --kind reddit: only these kinds (Reddit, run from a home connection).
  if (opt('--kind')) todo = todo.filter(c => opt('--kind').split(',').includes(c.kind));
  // --skip youtube,podcast: the owner sources video moments by hand.
  if (opt('--skip')) todo = todo.filter(c => !opt('--skip').split(',').includes(c.kind));
  // --resume: leave connections the report already has an image for.
  if (args.includes('--resume') && fs.existsSync(path.join(OUT, 'report.json'))) {
    const have = new Set(JSON.parse(fs.readFileSync(path.join(OUT, 'report.json'), 'utf8'))
      .filter(r => r.image).map(r => r.from + '__' + r.to));
    todo = todo.filter(c => !have.has(c.from + '__' + c.to));
  }
  // --untried: only connections the report has never seen (finishing a run that
  // was stopped), leaving earlier failures alone.
  if (args.includes('--untried') && fs.existsSync(path.join(OUT, 'report.json'))) {
    const seen = new Set(JSON.parse(fs.readFileSync(path.join(OUT, 'report.json'), 'utf8')).map(r => r.from + '__' + r.to));
    todo = todo.filter(c => !seen.has(c.from + '__' + c.to));
  }
  if (opt('--limit')) todo = todo.slice(0, +opt('--limit'));

  fs.mkdirSync(OUT, { recursive: true });
  const { chromium } = require('playwright');
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
  const ctx = await browser.newContext({
    viewport: { width: 1280, height: 900 },
    locale: 'en-US',
    userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36',
  });
  // Steam's age gate and language, answered up front.
  await ctx.addCookies(['store.steampowered.com', 'steamcommunity.com'].flatMap(domain => [
    { name: 'birthtime', value: '0', domain, path: '/' },
    { name: 'wants_mature_content', value: '1', domain, path: '/' },
    { name: 'lastagecheckage', value: '1-0-1990', domain, path: '/' },
    { name: 'Steam_Language', value: 'english', domain, path: '/' },
  ]));

  // A run updates the report rather than replacing it, so a retry of a few
  // connections (--only) keeps every other connection's result.
  const reportPath = path.join(OUT, 'report.json');
  const prior = fs.existsSync(reportPath) ? JSON.parse(fs.readFileSync(reportPath, 'utf8')) : [];
  const key = r => r.from + '__' + r.to;
  const report = new Map(prior.map(r => [key(r), r]));
  const ran = [];
  for (const c of todo) {
    const file = path.join(OUT, `${c.from}__${c.to}.png`);
    process.stdout.write(`${c.kind.padEnd(15)} ${c.fromName} → ${c.toName} … `);
    let r;
    if (c.kind === 'x') r = await captureTweet(ctx, c, file);
    else if (c.kind === 'youtube') r = await captureVideo(ctx, c, file);
    else if (c.kind === 'podcast') r = { status: 'audio', detail: 'audio only: nothing to screenshot; needs the moment transcribed or clipped by hand' };
    else if (c.kind === 'reddit') r = await withDeadline(captureReddit(ctx, c, file), 150000, ctx);
    else r = await withDeadline(capturePage(ctx, c, file), 90000, ctx);
    if (!['blocked', 'error', 'no-match', 'audio'].includes(r.status)) r.image = path.relative(OUT, file);
    console.log(r.status + (r.detail ? ` (${r.detail})` : ''));
    report.set(key(c), { ...c, ...r });
    ran.push(r);
    if (ran.length % 20 === 0) fs.writeFileSync(reportPath, JSON.stringify([...report.values()], null, 2));
  }
  await browser.close();
  fs.writeFileSync(reportPath, JSON.stringify([...report.values()], null, 2));
  const tally = ran.reduce((t, r) => (t[r.status] = (t[r.status] || 0) + 1, t), {});
  console.log('\n' + Object.entries(tally).map(([k, v]) => `${k}: ${v}`).join('  '));
}

if (require.main === module) main().catch(e => { console.error(e); process.exit(1); });
