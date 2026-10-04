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
 *   node tools/capture_proof.js --status weak,no-match
 *                                                  retry what the report last left in these
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
// Names written another way on the very pages that prove them: a short game
// name spelled out, or a developer's own slip. Add to it when a capture comes
// back `weak` because the page says the name differently.
const ALIASES = {
  'FTL': ['Faster Than Light'],
  'Magic Survival': ['Magical Survival'],
  'Backpack Hero': ['Backpack Heroes'],
};

function variants(name) {
  const v = new Set([name, ...(ALIASES[name] || [])]);
  const noThe = name.replace(/^The\s+/i, '');
  v.add(noThe);
  // "Spelunky Classic" is written "Spelunky"; a remaster by its original's name.
  const bare = noThe.replace(/\s+(Classic|Remastered|Remake|HD|Deluxe|Original|(Definitive|Enhanced|Complete) Edition)$/i, '');
  if (bare.length > 3 && !AMBIGUOUS.has(bare)) v.add(bare);
  for (const n of [name, noThe]) {
    const [head, ...rest] = n.split(/\s*[:\-–—]\s+/);
    if (head.length > 3 && !AMBIGUOUS.has(head)) v.add(head);
    // "FTL: Faster Than Light" is written "FTL": a short head in capitals counts.
    if (/^[A-Z0-9]{3,5}$/.test(head)) v.add(head);
    // "Mystery Dungeon 2: Shiren the Wanderer" is written "Shiren the Wanderer".
    const tail = rest.join(' ');
    if (tail.split(/\s+/).length >= 2) v.add(tail);
  }
  // "Ancient Domains of Mystery" is written "ADOM" (HyperRogue's blog never
  // spells it out), "Dungeon Crawl Stone Soup" "DCSS". A name of three words
  // or more also counts by its initials, matched in capitals only (see exact()).
  const acr = acronym(name);
  if (acr) v.add(acr);
  return [...v].filter(s => s.length > 2);
}

function acronym(name) {
  const words = name.replace(/[:\-–—]/g, ' ').split(/\s+/).filter(w => /^[A-Za-z]/.test(w));
  return words.length >= 3 ? words.map(w => w[0].toUpperCase()).join('') : '';
}

// Names matched case-sensitively: the ordinary words, and every acronym.
const exact = (...names) => [...AMBIGUOUS, ...names.map(acronym).filter(Boolean),
  ...names.flatMap(variants).filter(v => /^[A-Z0-9]{3,5}$/.test(v))];

function textFragment(url) {
  const m = url.match(/#:~:text=([^&#]+)/);
  if (!m) return null;
  // text=[prefix-,]start[,end][,-suffix]; prefix/suffix are context only.
  const parts = m[1].split(',').map(s => decodeURIComponent(s.replace(/\+/g, ' ')));
  const core = parts.filter(p => !p.endsWith('-') && !p.startsWith('-'));
  const prefix = (parts.find(p => p.endsWith('-')) || '').slice(0, -1);
  return { start: core[0] || '', end: core[1] || '', prefix };
}

// ── the page side: find, highlight, measure ───────────────────────────────────
// Runs inside the browser. Highlights one SENTENCE, and frames the message or
// paragraph it sits in (see the unit choice at the end), so the reader gets what
// it is part of.
// Highlighting is done with the CSS Custom Highlight API rather than by
// wrapping nodes, because a sentence often crosses a <b> or an <a>.

function findAndMark({ fragment, fromNames, toNames, claimSrc, ambiguous, maxHeight }) {
  const claim = new RegExp(claimSrc, 'i');
  const pat = n => {
    const gap = '[\\s:\\-–—]+';
    // A hyphen inside a word is optional: "Bum-Bo" is written "Bumbo".
    const word = w => w.split('-').map(p => p.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('-?');
    const body = n.split(/(?:\s*[:–—]\s*|\s+-\s+|\s+)/).map(word).join(gap);
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
  // A <br> is a line end in its block, and two in a row are a paragraph break:
  // Steam forum posts and store pages are one <div> of text split only by them.
  const blocks = new Map();
  const breaks = new Map();
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
  for (let n; (n = walker.nextNode());) {
    if (n.nodeType === 1) {
      if (n.nodeName === 'BR') { const b = n.closest(BLOCK) || n.parentElement; breaks.set(b, (breaks.get(b) || 0) + 1); }
      continue;
    }
    if (!n.nodeValue.trim()) continue;
    const p = n.parentElement;
    if (!p || p.closest('script,style,noscript,nav,footer,template')) continue;
    const b = p.closest(BLOCK) || p;
    if (!blocks.has(b)) blocks.set(b, []);
    blocks.get(b).push({ node: n, br: breaks.get(b) || 0 });
    breaks.delete(b);
  }

  // A sentence ends at its punctuation, at a line end, or at the end of the block.
  const SENT = /[^.!?。！？\n]*(?:[.!?。！？]+|(?=\n)|$)/g;
  let best = null;
  const order = [];
  for (const [el, items] of blocks) {
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0 || getComputedStyle(el).visibility === 'hidden') continue;
    let text = '';
    const offs = [];
    const nodes = [];
    for (const { node, br } of items) {
      // Without the line end "…Kill the Brickman<br>One more thing!" reads as
      // one sentence.
      if (text && br) text += '\n'.repeat(Math.min(br, 2));
      offs.push(text.length);
      nodes.push(node);
      text += node.nodeValue;
    }
    const consider = (start, end, score, how, names) => {
      if (end <= start) return;
      // A tie goes to the EARLIER mention: an interview names its influence
      // where it explains it, and comes back to it later in passing.
      if (!best || score > best.score)
        best = { el, nodes, offs, text, start, end, score, how, names };
    };
    order.push({ el, nodes, offs, text });
    SENT.lastIndex = 0;
    for (let m; (m = SENT.exec(text));) {
      if (!m[0]) { SENT.lastIndex++; continue; }
      const s = m.index, e = s + m[0].length;
      const sentence = m[0];
      if (sentence.length > 1200) continue;
      if (first(fromNames, text, s, e)) {
        let score = 10;
        // A wiki infobox says it in its row label: "Influences | Angband".
        const row = el.closest('tr');
        if (claim.test(sentence) || (row && row.innerText.length < 300 && claim.test(row.innerText))) score += 5;
        // A reply quoting the developer is second to the developer's own post,
        // and so is Steam's pinned "Answer" box, which quotes it.
        if (el.closest('blockquote, .answer_quote')) score -= 1;
        if (first(toNames, text, s, e)) score += 3;
        consider(s, e, score, 'name', fromNames);
      } else if (claim.test(sentence) && first(toNames, text, s, e)) {
        consider(s, e, 1, 'weak', toNames);
      }
    }
  }
  // The URL's own #:~:text= passage, which the owner marked by hand, wins over
  // any guess. It can run over several paragraphs (Lone Ruin's interview answer
  // does), so its end is looked for in the blocks after its start too; and its
  // prefix ("Escaped Lunatic-", the poster's title) tells the post apart from
  // the page title that repeats the same words.
  if (fragment && fragment.start) {
    const words = s => s.trim().split(/\s+/).map(w => w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('\\s+');
    const reEnd = fragment.end && new RegExp(words(fragment.end), 'i');
    const rePre = fragment.prefix && new RegExp(words(fragment.prefix) + '[\\s\\W]*$', 'i');
    const find = usePrefix => {
      for (let i = 0; i < order.length; i++) {
        const B = order[i];
        const reS = new RegExp(words(fragment.start), 'gi');
        for (let m; (m = reS.exec(B.text));) {
          if (usePrefix) {
            const before = order.slice(Math.max(0, i - 3), i).map(x => x.text).join(' ') + ' ' + B.text.slice(0, m.index);
            if (!rePre.test(before.slice(-400).trimEnd())) continue;
          }
          const from = m.index + m[0].length;
          if (!reEnd) return { i, start: m.index, j: i, end: from };
          for (let j = i; j < Math.min(order.length, i + 30); j++) {
            const t = j === i ? order[j].text.slice(from) : order[j].text;
            const me = reEnd.exec(t);
            if (me) return { i, start: m.index, j, end: (j === i ? from : 0) + me.index + me[0].length };
          }
        }
      }
      return null;
    };
    const f = (rePre && find(true)) || find(false);
    if (f) {
      const B = order[f.i];
      best = { ...B, start: f.start, end: f.j === f.i ? f.end : B.text.length, score: 100, how: 'fragment', names: fromNames,
        across: f.j === f.i ? null : { block: order[f.j], end: f.end } };
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
  if (best.across) {
    const E = best.across.block;
    let k = E.offs.length - 1;
    while (k > 0 && E.offs[k] > best.across.end) k--;
    sentence.setEnd(E.nodes[k], Math.min(best.across.end - E.offs[k], E.nodes[k].nodeValue.length));
  }
  const hit = first(best.names, best.text, best.start, best.end);
  const style = document.createElement('style');
  style.textContent = '::highlight(proof-line){background-color:rgba(255,214,0,.30)}'
    + '::highlight(proof-name){background-color:#ffd600;color:#000}';
  document.head.appendChild(style);
  CSS.highlights.set('proof-line', new Highlight(sentence));
  if (hit) CSS.highlights.set('proof-name', new Highlight(range(hit.at, hit.at + hit.len)));

  // What the picture shows, the first that fits in MAX px of height:
  //   1. the whole MESSAGE, when the sentence is in a forum post, a comment or
  //      a reply (author and date included where the site puts them there);
  //   2. the whole PARAGRAPH: the block, or the run of it between two blank
  //      lines when the block is a post laid out with <br>s;
  //   3. the sentence with a few lines either side.
  // Only the element or Range is kept, never a measurement: a page still
  // settling (Steam's store loads its carousels late) moves everything, so
  // window.__proofRect() measures it again right before the shot.
  const MAX = maxHeight;
  // A quote is the message it quotes: a Steam reply that quotes the developer
  // is the developer's post, set inside someone else's.
  const MESSAGE = 'blockquote, .commentthread_comment, .forum_op, .thing.comment > .entry, .thing.link > .entry, '
    + '.topic-post, .post, .postbody, .comment, .comment-body, [itemprop=comment]';
  const tall = x => x.getBoundingClientRect().height;
  const msg = best.el.closest(MESSAGE);
  let unit, unitKind;
  if (msg && tall(msg) <= MAX) { unit = msg; unitKind = 'message'; }
  else if (best.across) {
    // The passage, framed out to the whole of its first and last blocks.
    const whole = document.createRange();
    whole.setStartBefore(best.nodes[0]);
    whole.setEndAfter(best.across.block.nodes[best.across.block.nodes.length - 1]);
    if (whole.getBoundingClientRect().height <= MAX) { unit = whole; unitKind = 'passage'; }
    else if (sentence.getBoundingClientRect().height <= MAX) { unit = sentence; unitKind = 'passage'; }
    else { unit = sentence; unitKind = 'sentence'; }
  }
  else {
    const t = best.text;
    const back = i => { const k = t.lastIndexOf('\n\n', i); return k < 0 ? 0 : k + 2; };
    const fwd = i => { const k = t.indexOf('\n\n', i); return k < 0 ? t.length : k; };
    const trimmed = (a, z) => {
      while (a < z && /\s/.test(t[a])) a++;
      while (z > a && /\s/.test(t[z - 1])) z--;
      return range(a, z);
    };
    let a = back(best.start), z = fwd(best.end);
    let para = trimmed(a, z);
    // A one-line paragraph ("Pesticide Not Required is inspired by …") is a
    // sentence with nothing round it: take the paragraphs either side of it too,
    // while they fit.
    for (let i = 0; i < 2 && para.getBoundingClientRect().height < 120; i++) {
      const a2 = a > 0 ? back(a - 3) : a, z2 = z < t.length ? fwd(z + 2) : z;
      if (a2 === a && z2 === z) break;
      const wider = trimmed(a2, z2);
      if (wider.getBoundingClientRect().height > Math.min(MAX, 400)) break;
      a = a2; z = z2; para = wider;
    }
    if (para.getBoundingClientRect().height <= MAX) { unit = para; unitKind = 'paragraph'; }
    else { unit = sentence; unitKind = 'sentence'; }
    // Still one line, and alone in its block: a wiki infobox cell ("Hack,
    // ADOM") or a tagline. Its container says what it is ("Influences"), so
    // the picture is the largest one around it that is still small.
    if (unitKind === 'paragraph' && para.getBoundingClientRect().height < 120) {
      let up = null;
      for (let e = best.el.parentElement; e && e !== document.body; e = e.parentElement) {
        const r = e.getBoundingClientRect();
        if (r.height > 400 || r.width > innerWidth * 0.95 || e.innerText.length > 2000) break;
        up = e;
      }
      // An infobox too tall to take whole still gives its row: "Influences | Hack".
      const pr = para.getBoundingClientRect();
      if (up && (up.getBoundingClientRect().height > pr.height + 10 || up.getBoundingClientRect().width > pr.width + 40)) { unit = up; unitKind = 'message'; }
    }
  }
  const column = unitKind === 'message' ? unit : best.el;
  window.__proofRect = () => {
    const u = unit.getBoundingClientRect();
    const c = column.getBoundingClientRect();
    const pad = unitKind === 'sentence' ? 90 : 0;
    const top = u.top - pad, bottom = u.bottom + pad;
    return { x: Math.min(c.left, u.left), y: top, w: Math.max(c.right, u.right) - Math.min(c.left, u.left), h: bottom - top };
  };
  return {
    how: best.how,
    unit: unitKind,
    text: best.text.slice(best.start, best.end).replace(/\s+/g, ' ').trim().slice(0, 500),
  };
}

// Puts the unit findAndMark chose in the viewport and shoots it there, not off a
// full-page shot: Playwright's fullPage resizes the viewport, which re-lays a
// responsive page out, and the clip measured before it lands on whatever moved
// in (Atomicrops -> Pesticide Not Required came out as the "More from" carousel).
// It is measured, scrolled to, and measured again until it holds still.
async function shootUnit(page, file, maxHeight) {
  const PAD = 20;
  const vw = page.viewportSize().width;
  // A sticky header (Steam's store menu bar, which only turns sticky once the
  // page is scrolled) sits over the top of the viewport and would cover the
  // first line, so it is measured after each scroll and the unit put below it.
  const header = () => page.evaluate(() => {
    let low = 0;
    for (const x of [innerWidth * 0.1, innerWidth * 0.5, innerWidth * 0.9])
      // Steam's sticky wrapper is 0px tall with its 58px bar overflowing it, so
      // the bar's depth is the deepest of what was walked through to reach it.
      for (let e = document.elementFromPoint(x, 2), deep = 0; e && e !== document.body; e = e.parentElement) {
        const r = e.getBoundingClientRect();
        if (r.bottom < 250) deep = Math.max(deep, r.bottom);
        const pos = getComputedStyle(e).position;
        if ((pos === 'fixed' || pos === 'sticky') && r.top <= 4) { low = Math.max(low, deep); break; }
      }
    return Math.ceil(low);
  });
  let clear = 0;
  let r = await page.evaluate(() => window.__proofRect());
  const settle = async () => {
    for (let i = 0; i < 6; i++) {
      const at = clear + 40;
      await page.setViewportSize({ width: vw, height: Math.max(900, Math.ceil(Math.min(r.h, maxHeight)) + 2 * PAD + at) });
      await page.evaluate(top => window.scrollBy(0, top), r.y - at);
      await page.waitForTimeout(i ? 500 : 700);
      clear = await header();
      const again = await page.evaluate(() => window.__proofRect());
      const still = Math.abs(again.y - (clear + 40)) < 2 && Math.abs(again.h - r.h) < 2;
      r = again;
      if (still) return;
    }
  };
  // A page loading ads late (mcvuk.com) can move the unit after it held still
  // for one look, and the shot was then a 9px strip of nothing. So it is
  // measured once more after the shot, and shot again if it moved.
  for (let shot = 0; shot < 3; shot++) {
    await settle();
    // Newsletter pop-ups, chat bubbles and cookie bars float over the text
    // (GamesRadar's covered Enter the Gungeon -> Hades): anything fixed that
    // covers part of the screen is hidden. A fixed element taller than most of
    // the viewport is left alone, in case it is the page itself.
    await page.evaluate(() => {
      for (const el of document.querySelectorAll('body *')) {
        if (getComputedStyle(el).position !== 'fixed') continue;
        const r = el.getBoundingClientRect();
        if (r.height > 0 && r.height < innerHeight * 0.6 && r.top > 4) el.style.setProperty('visibility', 'hidden', 'important');
      }
    });
    const vh = page.viewportSize().height;
    const x = Math.max(0, r.x - PAD);
    const y = Math.max(clear, r.y - PAD);
    const w = Math.max(Math.min(vw, r.x + r.w + PAD) - x, 360);
    const h = Math.min(r.y + r.h + PAD, vh) - y;
    await page.screenshot({ path: file, clip: { x, y, width: Math.min(w, vw - x), height: Math.max(h, 1) } });
    const after = await page.evaluate(() => window.__proofRect());
    if (Math.abs(after.y - r.y) < 2 && Math.abs(after.h - r.h) < 2 && h >= Math.min(r.h, maxHeight)) break;
    r = after;
  }
}

// ── capture, per kind ─────────────────────────────────────────────────────────

// The tallest crop, in CSS px: a whole message or paragraph up to this, past it
// the sentence with a few lines either side.
const MAX_UNIT = 900;

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
  // A Steam link copied from a Finnish client says ?l=finnish, which outranks
  // the English cookie: the page is read in English either way.
  let url = (at || c.url).replace(/#.*$/, '');
  if (/steam(community|powered)\.com/.test(url)) url = url.replace(/([?&])l=[a-z]+&?/, '$1').replace(/[?&]$/, '');
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
    await page.addStyleTag({ content: '#game_area_description, .game_page_autocollapse { max-height: none !important; overflow: visible !important }'
      + ' .game_page_autocollapse_fade, .game_page_autocollapse_readmore { display: none !important }' }).catch(() => {});
    const look = () => page.evaluate(findAndMark, {
      fragment: textFragment(c.url),
      fromNames: variants(c.fromName),
      toNames: variants(c.toName),
      claimSrc: CLAIM.source,
      ambiguous: exact(c.fromName, c.toName),
      maxHeight: MAX_UNIT,
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
    await shootUnit(page, file, MAX_UNIT);
    return { status: found.how === 'weak' ? 'weak' : 'ok', how: found.how, unit: found.unit, quote: found.text, final: page.url() };
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

// A long post (an X "note tweet") is cut at "Show more" in the embed, and the
// sentence is often past the cut: Soulash's "inspired by ADOM and UnReal World,
// my two favorite roguelikes" stopped at "ADOM". The embed's own data has only
// the cut text, so the full text comes from api.fxtwitter.com (which reads it
// for link previews) and is handed to the embed in place of the cut one: the
// picture is still X's own widget, showing all of the post.
async function fullTweetText(ctx, user, id) {
  try {
    const t = (await getJSON(ctx, `https://api.fxtwitter.com/${user}/status/${id}`)).tweet;
    return (t.raw_text && t.raw_text.text) || t.text || '';
  } catch (e) { return ''; }
}

async function captureTweet(ctx, c, file, media = false) {
  const m = c.url.match(/(?:x|twitter)\.com\/([^/]+)\/status(?:es)?\/(\d+)/);
  if (!m) return { status: 'error', detail: 'not a tweet URL' };
  let embed;
  try {
    embed = await getJSON(ctx, `https://publish.twitter.com/oembed?dnt=1&hide_media=${media ? 0 : 1}&hide_thread=1&url=` + encodeURIComponent(`https://twitter.com/${m[1]}/status/${m[2]}`));
  } catch (e) {
    return { status: 'blocked', detail: 'embed endpoint: ' + e.message };
  }
  const page = await ctx.newPage();
  let full = '';
  await page.route('**/tweet-result*', async route => {
    const resp = await route.fetch();
    let data;
    try { data = await resp.json(); } catch (e) { return route.fulfill({ response: resp }); }
    if (data && data.note_tweet) {
      full = await fullTweetText(ctx, m[1], m[2]);
      if (full && full.startsWith(data.text.replace(/\s*\S*$/, ''))) {
        data.text = full;
        data.display_text_range = [0, Array.from(full).length];
        delete data.note_tweet;
      } else full = '';
    }
    route.fulfill({ response: resp, json: data });
  });
  try {
    await page.setContent(`<html><body style="margin:0;padding:24px;background:#fff;width:600px">${embed.html}</body></html>`);
    const frame = await page.waitForSelector('iframe[id^=twitter-widget]', { timeout: 20000 }).catch(() => null);
    if (!frame) return { status: 'error', detail: 'embed did not render' };
    await page.waitForTimeout(2500);
    const quote = full || (embed.html.match(/<p[^>]*>([\s\S]*?)<\/p>/) || [, ''])[1].replace(/<[^>]+>/g, '');
    const flat = t => t.replace(/\s+/g, ' ').toLowerCase();
    const named = variants(c.fromName).some(n => flat(quote).includes(flat(n)));
    // A whole long post is a page or more: past MAX_UNIT the picture runs from
    // the top of the post (who said it) down to the end of the paragraph that
    // names the game, and is highlighted there like any page.
    const box = await frame.boundingBox();
    let clip = null;
    if (full && box.height > MAX_UNIT) {
      const inner = await frame.contentFrame();
      const found = inner && await inner.evaluate(findAndMark, {
        fragment: null, fromNames: variants(c.fromName), toNames: variants(c.toName),
        claimSrc: CLAIM.source, ambiguous: exact(c.fromName, c.toName), maxHeight: MAX_UNIT,
      }).catch(() => null);
      if (found) {
        const r = await inner.evaluate(() => { scrollTo(0, 0); return window.__proofRect(); });
        const bottom = box.y + r.y + r.h + 16;
        clip = bottom - box.y <= MAX_UNIT
          ? { x: box.x, y: box.y, width: box.width, height: bottom - box.y }
          : { x: box.x, y: box.y + r.y - 16, width: box.width, height: r.h + 32 };
      }
    }
    // Text that doesn't name the game, on a post with a picture: the name is
    // usually in the picture (a list of influences, a slide), so it is shown.
    if (!named && !media && /pic\.(x|twitter)\.com/.test(embed.html)) return await captureTweet(ctx, c, file, true);
    if (clip) await page.screenshot({ path: file, fullPage: true, clip });
    else await frame.screenshot({ path: file });
    return { status: named ? 'ok' : 'weak', how: full ? 'embed-full' : 'embed', quote: quote.slice(0, 500),
      detail: named ? '' : 'tweet text does not name ' + c.fromName + ' (may be in an image or a reply)' };
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
  // A `weak` page capture names only the newer game, which proves nothing by
  // itself (ADOM -> HyperRogue showed a sentence about HyperRogue and no ADOM): it
  // stays in the report for a look, and is listed in docs/proof-missing.md, not
  // shipped. A weak TWEET still ships: the picture is the whole post, and the
  // name the text check missed is usually right there ("Isaac", or in the
  // attached picture).
  const shown = r => r.image && (r.status !== 'weak' || r.kind === 'x') && r.status !== 'quote-card';
  const keep = report.filter(r => shown(r) && !['youtube', 'podcast'].includes(r.kind) && !owners(gameFile(r)));
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
  const failed = new Set(report.filter(r => !shown(r)).map(gameFile));
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
  const groups = { reddit: [], dead: [], refused: [], down: [], weak: [], nomatch: [], video: [], note: [], none: [] };
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
    else if (r.status === 'weak') groups.weak.push(line(`only ${c.toName} is named`));
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
    + section('Only the newer game is named',
    'The page talks about the influenced game and never names the influencer, so the capture is in `.influence_work/proof/` for a look but not in the game. Often the influencer is written another way (an abbreviation, a series name) or sits in an image.', groups.weak)
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
  // --status weak,no-match: only connections the report last left in one of these.
  if (opt('--status') && fs.existsSync(path.join(OUT, 'report.json'))) {
    const want = opt('--status').split(',');
    const hit = new Set(JSON.parse(fs.readFileSync(path.join(OUT, 'report.json'), 'utf8'))
      .filter(r => want.includes(r.status)).map(r => r.from + '__' + r.to));
    todo = todo.filter(c => hit.has(c.from + '__' + c.to));
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
