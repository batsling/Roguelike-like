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
 *   reddit   read through old.reddit.com, which renders without a login wall
 *   steam    age gate pre-answered by cookie
 *
 *   node tools/capture_proof.js --pilot            25 connections across every source kind
 *   node tools/capture_proof.js --only hades       connections out of one game
 *   node tools/capture_proof.js --limit 50         the first 50 with a link
 *   node tools/capture_proof.js --skip youtube,podcast --resume
 *                                                  the full run, leaving out video and audio,
 *                                                  and skipping what already has an image
 *   node tools/capture_proof.js --webp             copy the captures into the game as
 *                                                  images2.0/proof/<from>__<to>.webp
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

async function capturePage(ctx, c, file) {
  let url = c.url.replace(/#.*$/, '');
  // reddit.com and old.reddit.com both answer 403 to a cloud address; the embed
  // host Reddit serves to other websites does not, and it renders a comment
  // permalink as that one comment.
  if (c.kind === 'reddit') url = url.replace(/\/\/(www\.|old\.|new\.)?reddit\.com/, '//embed.reddit.com');
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
    if (!found && c.kind === 'reddit') {
      const r = await captureRedditComment(ctx, c, file);
      if (r) return r;
    }
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

// The proof in a Reddit thread is often the developer's own COMMENT under a
// video post, and the embed host only renders posts (a comment link answers
// 403). Arctic Shift's archive has the text, so the comment is shown as a quote
// card: plainly a transcription with its link, not dressed up as Reddit's page.
async function captureRedditComment(ctx, c, file) {
  const id = (c.url.match(/comments\/([a-z0-9]+)/i) || [])[1];
  if (!id) return null;
  const api = 'https://arctic-shift.photon-reddit.com/api/';
  let post, comments;
  try {
    post = ((await getJSON(ctx, `${api}posts/ids?ids=${id}`)).data || [])[0];
    comments = (await getJSON(ctx, `${api}comments/search?link_id=${id}&limit=100`)).data || [];
  } catch (e) {
    return null;
  }
  const names = variants(c.fromName);
  const named = t => names.some(n => new RegExp('(?<![A-Za-z0-9])' + n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(?![A-Za-z0-9])', 'i').test(t));
  const op = post && post.author;
  const pick = [...comments].sort((a, b) => (b.author === op) - (a.author === op)).find(x => named(x.body || ''));
  if (!pick) return null;
  const body = pick.body.replace(/\*\*|__|\\(?=_)/g, '');
  const sentences = body.split(/(?<=[.!?])\s+|\n+/).filter(x => x.trim());
  const at = sentences.findIndex(named);
  const quote = sentences.slice(Math.max(0, at - 1), at + 2).join(' ');
  const mark = esc(quote).replace(new RegExp('(' + names.map(n => esc(n).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|') + ')', 'gi'), '<mark>$1</mark>');
  const when = new Date(pick.created_utc * 1000).toISOString().slice(0, 10);
  const page = await ctx.newPage();
  try {
    await page.setContent(`<html><body style="margin:0;background:#fff;font-family:Georgia,serif">
      <div id="card" style="width:620px;padding:24px 28px;border-left:6px solid #888;background:#fafafa">
        <div style="font-size:19px;line-height:1.5;color:#111">“${mark}”</div>
        <div style="font-family:sans-serif;font-size:13px;color:#555;margin-top:14px">
          u/${esc(pick.author)}${pick.author === op ? ' (posted the thread)' : ''} · r/${esc(post.subreddit)} · ${when}<br>
          Reddit comment, transcribed from the Arctic Shift archive · reddit.com/r/${esc(post.subreddit)}/comments/${id}/comment/${esc(pick.id)}
        </div></div>
      <style>mark{background:#ffd600;color:#000;padding:0 2px}</style></body></html>`);
    await (await page.$('#card')).screenshot({ path: file });
    return { status: 'quote-card', how: 'archive', quote, detail: pick.author === op ? '' : 'the comment is not by the poster: check who wrote it' };
  } finally {
    await page.close();
  }
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
// GameChoiceModal shows images2.0/proof/<from>__<to>.webp under the connection's
// claim. Lossy WebP at 0.9 keeps screenshot text crisp at a fraction of the
// PNG's size, which matters at a thousand files. Chromium does the encoding, so
// nothing beyond Playwright is needed. Video and audio cards are left out: the
// owner sources those moments by hand.
const GAME_DIR = path.join(ROOT, 'images2.0', 'proof');

async function exportWebp() {
  const report = JSON.parse(fs.readFileSync(path.join(OUT, 'report.json'), 'utf8'));
  const keep = report.filter(r => r.image && !['youtube', 'podcast'].includes(r.kind));
  fs.mkdirSync(GAME_DIR, { recursive: true });
  const { chromium } = require('playwright');
  const browser = await chromium.launch();
  const page = await browser.newPage();
  let bytes = 0;
  for (const r of keep) {
    const png = fs.readFileSync(path.join(OUT, r.image)).toString('base64');
    const webp = await page.evaluate(async src => {
      const img = new Image();
      img.src = src;
      await img.decode();
      const c = document.createElement('canvas');
      c.width = img.naturalWidth;
      c.height = img.naturalHeight;
      c.getContext('2d').drawImage(img, 0, 0);
      return c.toDataURL('image/webp', 0.9).split(',')[1];
    }, 'data:image/png;base64,' + png);
    const out = Buffer.from(webp, 'base64');
    bytes += out.length;
    fs.writeFileSync(path.join(GAME_DIR, `${r.from}__${r.to}.webp`), out);
  }
  await browser.close();
  // A connection re-captured as a failure, or taken out of the sheet, loses its image.
  const want = new Set(keep.map(r => `${r.from}__${r.to}.webp`));
  for (const f of fs.readdirSync(GAME_DIR)) if (f.endsWith('.webp') && !want.has(f)) fs.unlinkSync(path.join(GAME_DIR, f));
  console.log(`${keep.length} proofs -> images2.0/proof/ (${(bytes / 1048576).toFixed(1)} MB)`);
}

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--webp')) return exportWebp();
  const opt = k => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : null; };
  const all = loadConnections();
  let todo = all.filter(c => c.url);
  if (args.includes('--pilot')) todo = pilot(all);
  if (opt('--only')) todo = todo.filter(c => c.from === opt('--only') || c.to === opt('--only'));
  // --skip youtube,podcast: the owner sources video moments by hand.
  if (opt('--skip')) todo = todo.filter(c => !opt('--skip').split(',').includes(c.kind));
  // --resume: leave connections the report already has an image for.
  if (args.includes('--resume') && fs.existsSync(path.join(OUT, 'report.json'))) {
    const have = new Set(JSON.parse(fs.readFileSync(path.join(OUT, 'report.json'), 'utf8'))
      .filter(r => r.image).map(r => r.from + '__' + r.to));
    todo = todo.filter(c => !have.has(c.from + '__' + c.to));
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
    else r = await capturePage(ctx, c, file);
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
