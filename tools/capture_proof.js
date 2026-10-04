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
 *   reddit   Reddit's own embed (embed.reddit.com) of the post or comment that
 *            says it, found through the Arctic Shift archive; a comment comes
 *            with the comment it answers stacked above it (see captureReddit)
 *   steam    age gate pre-answered by cookie; on a forum thread, a player's
 *            question and the developer's answer are shot together
 *
 * On every page, before the shot: log-in walls and the veil behind them are
 * removed, "Read more" / "See more" buttons are pressed, and every fixed or
 * sticky bar (site headers included) is hidden — each of these once covered or
 * faded a proof (see removeWalls, unfold and hideBars).
 *
 *   node tools/capture_proof.js --pilot            25 connections across every source kind
 *   node tools/capture_proof.js --only hades       connections out of one game
 *   node tools/capture_proof.js --conn balatro---runeborn,hades---going_under
 *                                                  exactly these connections
 *   node tools/capture_proof.js --limit 50         the first 50 with a link
 *   node tools/capture_proof.js --kind reddit       Reddit only
 *   node tools/capture_proof.js --jobs 4 ...       four connections at a time
 *   node tools/capture_proof.js --missing          write docs/proof-missing.md: what has no proof yet
 *   node tools/capture_proof.js --skip youtube,podcast --untried
 *                                                  finish a stopped run, leaving its failures alone
 *   node tools/capture_proof.js --skip youtube,podcast --resume
 *                                                  the full run, leaving out video and audio,
 *                                                  and skipping what already has an image
 *   node tools/capture_proof.js --status weak,no-match
 *                                                  retry what the report last left in these
 *   node tools/capture_proof.js --translate        set the English translations in
 *                                                  tools/proof_translations.json under their proofs
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

function findAndMark({ fragment, fromNames, toNames, claimSrc, ambiguous, maxHeight, anchor }) {
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
  // A forum thread's messages, and the badge Steam puts on a developer's.
  const THREAD = '.forum_op, .commentthread_comment';
  const DEV = '.commentthread_author_developer';
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
    // Text with no block element of its own, set straight into <body> (Shadow
    // of the Wyrm's about page: "<b>Shadow of the Wyrm is …</b> It …"), belongs
    // to the nearest ancestor that is laid out as a block, not to the <b>: an
    // inline element's box is one fragment of the line, and the crop came out
    // cut off at the right edge of it.
    let b = p.closest(BLOCK);
    if (!b) for (b = p; b.parentElement && getComputedStyle(b).display.startsWith('inline'); b = b.parentElement);
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
        // The developer saying it beats a player asking about it: Dungeon
        // Rushers' thread has a player's "work like darkest dungeon?" and,
        // further down, the developer's "more similar to Darkest Dungeon".
        const post = el.closest(THREAD);
        if (post && post.querySelector(DEV)) score += 2;
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
    // An interview is questions and answers, and one without the other is half
    // the proof: FTL -> Abandon Ship's crop was the interviewer's question
    // naming FTL with the answer cut off under it, Has-Been Heroes' the answer
    // with its question sliced off the top. So a paragraph that IS a question
    // takes the next block (the answer) with it, and an answer whose block
    // before is a short question takes that, while the whole still fits.
    // Not in a table: an infobox cell reading "SimCity (?)" is no question.
    if (unitKind === 'paragraph' && !best.el.closest('td, th, table')) {
      const k = order.findIndex(o => o.el === best.el);
      const isQ = t => /[A-Za-z]\?["”’)\s]*$/.test(t.trim()) && t.trim().length < 400;
      const sole = el => !best.el.contains(el) && !el.contains(best.el);
      const grow = (from, to) => {
        const r = document.createRange();
        r.setStartBefore(from.nodes[0]);
        r.setEndAfter(to.nodes[to.nodes.length - 1]);
        return r;
      };
      const next = order.slice(k + 1).find(o => o.text.trim() && sole(o.el));
      const prev = order.slice(0, k).reverse().find(o => o.text.trim() && sole(o.el));
      const own = t.slice(a, z);
      let wider = null;
      // A heading is the same: "Finding inspiration in conversation -- and
      // Rogue" (868-HACK) says nothing until the paragraph under it does.
      const heading = /^H[1-6]$/.test(best.el.nodeName);
      if ((isQ(own) || heading) && next && (z >= t.length - 2)) wider = grow(best, next);
      else if (prev && isQ(prev.text) && a === 0 && !isQ(own)) wider = grow(prev, best);
      if (wider && wider.getBoundingClientRect().height <= MAX) { unit = wider; unitKind = 'passage'; }
    }
    // Still one line, and alone in its block: a wiki infobox cell ("Hack,
    // ADOM") or a tagline. Its container says what it is ("Influences"), so
    // the picture is the largest one around it that is still small.
    if (unitKind === 'paragraph' && para.getBoundingClientRect().height < 120) {
      let up = null;
      for (let e = best.el.parentElement; e && e !== document.body; e = e.parentElement) {
        const r = e.getBoundingClientRect();
        // 560, not 400: a RogueBasin infobox runs ~420px, and stopping short of
        // it left three rows with no title saying whose box it was.
        if (r.height > 560 || r.width > innerWidth * 0.95 || e.innerText.length > 2000) break;
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
  // What a fixed or sticky bar must not be hidden for: the element the text is in.
  window.__proofEl = best.el;

  // A question is half a proof. In a forum thread the other half is shot too
  // and stacked with it, question first:
  //   - the sentence is a player's QUESTION ("do the hero position on party work
  //     like darkest dungeon?"): the developer's first reply after it;
  //   - the sentence is the DEVELOPER's answer: the message the link points at
  //     (#c<id>), or else the nearest earlier question naming either game.
  let partner = null, partnerFirst = false;
  const own = best.el.closest(THREAD);
  const posts = [...document.querySelectorAll(THREAD)];
  if (own && posts.length > 1) {
    const i = posts.indexOf(own);
    const isDev = p => !!p.querySelector(DEV);
    const said = best.text.slice(best.start, best.end).trim();
    const linked = anchor && (document.getElementById('comment_' + anchor) || document.getElementById(anchor));
    const at = linked && linked.closest(THREAD);
    if (!isDev(own) && /\?\W*$/.test(said)) {
      partner = posts.slice(i + 1).find(isDev) || null;
    } else if (isDev(own)) {
      partner = (at && at !== own && posts.indexOf(at) < i) ? at
        : posts.slice(0, i).reverse().find(p => /\?/.test(p.innerText)
          && first(fromNames.concat(toNames), p.innerText)) || null;
      partnerFirst = !!partner;
    }
  }
  if (partner) window.__proofPartnerRect = () => {
    const r = partner.getBoundingClientRect();
    return { x: r.left, y: r.top, w: r.width, h: r.height };
  };
  return {
    how: best.how,
    unit: unitKind,
    text: best.text.slice(best.start, best.end).replace(/\s+/g, ' ').trim().slice(0, 500),
    partner: partner ? (partnerFirst ? 'before' : 'after') : '',
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
  await page.evaluate(hideBars);
  let r = await page.evaluate(() => window.__proofRect());
  const settle = async () => {
    for (let i = 0; i < 6; i++) {
      const at = clear + 40;
      await page.setViewportSize({ width: vw, height: Math.max(900, Math.ceil(Math.min(r.h, maxHeight)) + 2 * PAD + at) });
      await page.evaluate(top => window.scrollBy(0, top), r.y - at);
      await page.waitForTimeout(i ? 500 : 700);
      await page.evaluate(hideBars);
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
    await page.evaluate(hideBars);
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

// Anything fixed or sticky floats over the text once the page is scrolled:
// newsletter pop-ups, chat bubbles and cookie bars (GamesRadar's covered Enter
// the Gungeon -> Hades), and site headers (Game*Spark's menu bar sat over the
// line naming Inscryption). Measuring a header and shooting below it missed
// the ones that start a few pixels down, so every such bar is hidden instead,
// except one the text itself is inside (a page laid out in a fixed shell).
// A video under a caption (a Facebook reel) is hidden too: its frames run
// behind the words and whichever frame is up when the shot is taken can bury
// them (Dungeon Clawler's logo sat across the line naming Dicey Dungeons).
function hideBars() {
  const keep = window.__proofEl;
  // Opacity as well as visibility: a child can set itself visible again
  // (Game*Spark's open sub-menu does), but nothing inside an element at
  // opacity 0 shows.
  const hide = el => { el.style.setProperty('visibility', 'hidden', 'important'); el.style.setProperty('opacity', '0', 'important'); };
  for (const el of document.querySelectorAll('body *')) {
    const pos = getComputedStyle(el).position;
    if (pos !== 'fixed' && pos !== 'sticky') continue;
    // Whatever its size: a sticky wrapper can be 0px tall with its bar
    // overflowing it (Steam's store menu, Game*Spark's).
    if (keep && el.contains(keep)) continue;
    hide(el);
  }
  if (keep) {
    const k = keep.getBoundingClientRect();
    for (const v of document.querySelectorAll('video')) {
      const r = v.getBoundingClientRect();
      if (r.left <= k.left && r.right >= k.right && r.top <= k.top && r.bottom >= k.bottom) hide(v);
    }
  }
}

// Log-in walls and the veil behind them (Facebook's "See more on Facebook" sat
// over Anomaly Collapse's post, and its translucent veil greyed out Dungeon
// Clawler's reel): every modal dialog goes, from its outermost fixed wrapper,
// along with any full-screen fixed layer that holds no text. The page's own
// scroll lock goes with them.
function removeWalls() {
  for (const d of document.querySelectorAll('[role=dialog], [aria-modal=true]')) {
    let top = d;
    for (let e = d; e && e !== document.body; e = e.parentElement) if (getComputedStyle(e).position === 'fixed') top = e;
    top.remove();
  }
  for (const e of document.querySelectorAll('body *')) {
    if (getComputedStyle(e).position !== 'fixed') continue;
    const r = e.getBoundingClientRect();
    if (r.width >= innerWidth * 0.9 && r.height >= innerHeight * 0.9 && !e.innerText.trim()) e.remove();
  }
  // Only a lock is undone: forcing `auto` on a full-height <body> makes it a
  // scroller of its own, and the window then never scrolls to the text.
  for (const e of [document.documentElement, document.body])
    if (/hidden|clip/.test(getComputedStyle(e).overflowY)) e.style.setProperty('overflow', 'visible', 'important');
}

// Folded text: Reddit's embed shows three faded lines of a post and a "Read
// more" (Castle of the Winds -> Dungeonmans was cut mid-sentence under it),
// Facebook a "See more". These are buttons that unfold in place; a LINK reading
// "read more" goes to another page, so only a link with nowhere to go counts.
async function unfold(page) {
  const n = await page.evaluate(() => {
    const MORE = /^(?:…\s*|\.\.\.\s*)?(?:read|see|show) more$/i;
    let k = 0;
    for (const el of document.querySelectorAll('button, [role=button], read-more-button, a:not([href]), a[href="#"], a[href^="javascript"]')) {
      if (!MORE.test((el.innerText || '').trim())) continue;
      if (el.closest('nav, header, footer')) continue;
      el.click();
      k++;
    }
    return k;
  }).catch(() => 0);
  if (n) await page.waitForTimeout(1200);
  return n;
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

// Reddit refuses this machine's address on reddit.com and old.reddit.com
// ("blocked by network security"), but answers on embed.reddit.com, the host
// it serves to other websites. That host renders a POST, folded after three
// lines under "Read more" (unfold() opens it), or one COMMENT, with no thread
// round it. So the thread is read from the Arctic Shift archive of Reddit,
// which says WHICH post or comment carries the proof, and the picture is then
// Reddit's own embed of exactly that one:
//
//   - the post, when the post says it (the title and text, unfolded);
//   - the comment, when a comment says it, with the comment it replies to
//     stacked above it: an AMA's proof is the developer's ANSWER, and an answer
//     needs its question (Balatro -> Runeborn is "how are you planning to stand
//     out?" and then "we were heavily inspired by Balatro");
//   - a player's question naming the game, followed by the original poster's
//     reply to it, when the question is what names it.
//
// The developer is usually the original poster, so their words outrank a
// commenter's at the same score. When the archive has nothing (a post too new
// for it, or the archive down), the post alone is captured from the embed.
const ARCTIC = 'https://arctic-shift.photon-reddit.com/api';
const REDDIT_HOME = 'Reddit refused the embed too: screenshot it yourself';

function redditIds(url) {
  const parts = new URL(url).pathname.split('/').filter(Boolean);
  const i = parts.indexOf('comments');
  if (i < 0 || !/^[a-z0-9]+$/i.test(parts[i + 1] || '')) return null;
  let comment = parts[i + 2] === 'comment' ? parts[i + 3] : parts[i + 3];
  if (comment && !/^[a-z0-9]{4,10}$/i.test(comment)) comment = null;
  return { sub: parts[i - 1], post: parts[i + 1], comment: comment || null };
}

// Reddit markdown to the words a reader sees.
const unmark = t => String(t || '').replace(/\[([^\]]*)\]\([^)]*\)/g, '$1').replace(/&amp;/g, '&')
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#x200B;/g, '').replace(/\\([\\*_~`>#[\]()-])/g, '$1')
  .replace(/[*_~`]+/g, '').replace(/^\s*>\s?/gm, '');

// The same test findAndMark makes on a page, on plain text: 10 for naming the
// influencer, +5 for a claim word beside it, +3 for naming the influencee too;
// 1 for a claim beside the influencee alone (`weak`); 100 for the passage the
// link's own #:~:text= marks.
function scoreText(c, text) {
  const amb = exact(c.fromName, c.toName);
  const re = n => new RegExp('(?<![A-Za-z0-9])' + n.split(/\s+/)
    .map(w => w.split('-').map(p => p.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('-?')).join('[\\s:\\-–—]+')
    + '(?![A-Za-z0-9])', amb.includes(n) ? '' : 'i');
  const from = variants(c.fromName).map(re), to = variants(c.toName).map(re);
  const names = (res, s) => res.some(r => r.test(s));
  const frag = textFragment(c.url);
  const flat = x => x.replace(/\s+/g, ' ').toLowerCase();
  if (frag && frag.start && flat(text).includes(flat(frag.start))) return { score: 100, sentence: frag.start };
  let best = { score: 0, sentence: '' };
  for (const s of text.split(/(?<=[.!?。！？])\s+|\n+/)) {
    let score = 0;
    if (names(from, s)) score = 10 + (CLAIM.test(s) ? 5 : 0) + (names(to, s) ? 3 : 0);
    else if (CLAIM.test(s) && names(to, s)) score = 1;
    if (score > best.score) best = { score, sentence: s.trim() };
  }
  return best;
}

async function redditThread(ctx, ids) {
  const post = ((await getJSON(ctx, `${ARCTIC}/posts/ids?ids=${ids.post}&fields=id,author,title,selftext,subreddit`)).data || [])[0];
  if (!post) return null;
  const tree = (await getJSON(ctx, `${ARCTIC}/comments/tree?link_id=${ids.post}&limit=9999`)).data || [];
  const comments = [];
  const walk = n => {
    if (n.kind !== 't1') return;
    comments.push(n.data);
    const r = n.data.replies;
    if (r && r.data) r.data.children.forEach(walk);
  };
  tree.forEach(walk);
  return { post, comments, byId: new Map(comments.map(x => [x.id, x])) };
}

// One embed, shot whole: the card is the bordered box Reddit draws round it.
// With `mark`, the sentence is highlighted the way a page's is. A card taller
// than a screen or two is cut to the paragraph the sentence is in.
async function shootEmbed(ctx, url, c, file, mark) {
  const page = await ctx.newPage();
  try {
    await page.setViewportSize({ width: 900, height: 900 });
    const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
    if (!resp || resp.status() >= 400) return { status: 'blocked', detail: `HTTP ${resp ? resp.status() : 0}` };
    await page.waitForLoadState('networkidle', { timeout: 12000 }).catch(() => {});
    await unfold(page);
    // A video or picture post's player fills the card and says nothing (Asgard's
    // Fall came out as a green loading square over a line of text): the media
    // goes, the words stay. A post whose proof is in its title still shows it.
    await page.evaluate(() => {
      for (const e of document.querySelectorAll('shreddit-player, shreddit-player-2, video, gallery-carousel, shreddit-aspect-ratio, [slot=post-media-container], figure.rte-media'))
        e.style.setProperty('display', 'none', 'important');
      // and the box that held its place, now tall and empty.
      for (const e of [...document.querySelectorAll('body *')].reverse()) {
        const r = e.getBoundingClientRect();
        if (r.height > 120 && !e.innerText.trim() && !e.querySelector('img:not([src^="data"]), svg'))
          e.style.setProperty('display', 'none', 'important');
      }
    });
    await page.waitForTimeout(300);
    await page.mouse.move(0, 0);
    let found = null;
    if (mark) {
      found = await page.evaluate(findAndMark, {
        fragment: textFragment(c.url), fromNames: variants(c.fromName), toNames: variants(c.toName),
        claimSrc: CLAIM.source, ambiguous: exact(c.fromName, c.toName), maxHeight: MAX_UNIT, anchor: null,
      });
      if (!found) return { status: 'no-match', detail: 'the embed does not show the words the archive has (removed or edited on Reddit)' };
    }
    const card = await page.evaluate(() => {
      let best = null, area = 0;
      for (const e of document.querySelectorAll('body *')) {
        const cs = getComputedStyle(e);
        if (parseFloat(cs.borderTopWidth) < 1 || parseFloat(cs.borderLeftWidth) < 1) continue;
        const r = e.getBoundingClientRect();
        if (r.width * r.height > area) { area = r.width * r.height; best = r; }
      }
      const r = best || document.body.getBoundingClientRect();
      return { x: r.left + scrollX, y: r.top + scrollY, w: r.width, h: r.height };
    });
    const MAX_CARD = 1800;
    if (card.h <= MAX_CARD || !found) {
      await page.setViewportSize({ width: 900, height: Math.ceil(Math.min(card.h, MAX_CARD)) + 40 });
      await page.screenshot({ path: file, fullPage: true, clip: { x: card.x, y: card.y, width: card.w, height: Math.min(card.h, MAX_CARD) } });
    } else await shootUnit(page, file, MAX_UNIT);
    // Whether the card says anything: its lines, less Reddit's own furniture.
    const empty = await page.evaluate(() => !document.body.innerText.split('\n').map(l => l.trim()).filter(l => l
      && !/commented on|^post$|upvotes?$|repl(y|ies)$|^Copy link$|^View .*comments?$|^View more on Reddit$|^\[deleted\]$|^Skip to main content$|^Comment$|^Join$|^\d+$/i.test(l)).length);
    return { status: 'ok', quote: found ? found.text : '', how: found ? found.how : '', empty };
  } catch (e) {
    return { status: 'error', detail: String(e.message || e).split('\n')[0] };
  } finally {
    await page.close();
  }
}

// The embed sometimes paints before the post's text is in (Sodaman's came out
// as a title and nothing else, once in two), so a shot whose words fall short
// of what the archive says the post holds is taken again.
async function shootEmbedSure(ctx, url, c, file, mark, strong) {
  let r;
  for (let i = 0; i < 3; i++) {
    r = await shootEmbed(ctx, url, c, file, mark);
    if (!mark || !strong || (r.status === 'ok' && r.how !== 'weak')) return r;
  }
  return r.status === 'ok' ? { status: 'weak', detail: 'the embed never showed the sentence the archive has', quote: r.quote } : r;
}

async function captureReddit(ctx, c, file) {
  const ids = redditIds(c.url);
  const embedPost = ids && `https://embed.reddit.com/r/${ids.sub}/comments/${ids.post}/`;
  const embedComment = id => `https://embed.reddit.com/r/${ids.sub}/comments/${ids.post}/comment/${id}/`;
  let thread = null;
  if (ids) thread = await redditThread(ctx, ids).catch(() => null);
  if (!thread) {
    if (!ids) return { status: 'blocked', detail: REDDIT_HOME + ' (not a link to a thread)' };
    const r = await shootEmbed(ctx, embedPost, c, file, true);
    return r.status === 'ok' ? { status: 'ok', how: 'embed-post', quote: r.quote } : (r.status === 'blocked' ? { status: 'blocked', detail: REDDIT_HOME } : r);
  }
  const op = thread.post.author;
  const candidates = [{ kind: 'post', data: thread.post, text: unmark(thread.post.title + '\n' + thread.post.selftext) }]
    .concat(thread.comments.map(x => ({ kind: 'comment', data: x, text: unmark(x.body) })));
  let win = null;
  for (const cand of candidates) {
    const s = scoreText(c, cand.text);
    if (!s.score) continue;
    // The developer (usually the original poster) over a commenter, and the
    // comment the link points at over any other.
    let score = s.score + (cand.data.author === op && s.score >= 10 ? 2 : 0);
    if (ids.comment && cand.data.id === ids.comment && s.score >= 10) score += 50;
    if (!win || score > win.score) win = { ...cand, score, sentence: s.sentence };
  }
  if (!win) return { status: 'no-match', detail: 'neither the post nor any of its ' + thread.comments.length + ' archived comments names ' + c.fromName };
  const status = win.score >= 10 ? 'ok' : 'weak';
  if (win.kind === 'post') {
    const r = await shootEmbedSure(ctx, embedPost, c, file, true, status === 'ok');
    if (r.status === 'no-match') return { status: 'no-match', detail: 'the post says it, but Reddit\'s embed shows no text for a video or picture post: screenshot it yourself' };
    return r.status === 'ok' ? { status, how: 'embed-post', quote: r.quote || win.sentence } : r;
  }
  // A comment: its question above it, or the original poster's answer below it.
  const parts = [];
  const parent = /^t1_/.test(win.data.parent_id || '') && thread.byId.get(win.data.parent_id.slice(3));
  const isQuestion = /\?\W*$/.test(win.sentence) && win.data.author !== op;
  const answer = isQuestion && thread.comments.find(x => x.parent_id === 't1_' + win.data.id && x.author === op);
  const shots = [];
  if (parent) shots.push({ id: parent.id, mark: false });
  shots.push({ id: win.data.id, mark: true });
  if (answer) shots.push({ id: answer.id, mark: false });
  let quote = '';
  for (const [k, sh] of shots.entries()) {
    const f = file.replace(/\.png$/, `.part${k}.png`);
    const r = await shootEmbedSure(ctx, embedComment(sh.id), c, f, sh.mark, status === 'ok');
    // A question deleted since is an empty card on Reddit now (the archive
    // still has its words): the answer goes alone.
    if (!sh.mark && r.empty) { if (fs.existsSync(f)) fs.unlinkSync(f); continue; }
    if (r.status !== 'ok') { parts.forEach(p => fs.existsSync(p) && fs.unlinkSync(p)); return r; }
    if (sh.mark) quote = r.quote;
    parts.push(f);
  }
  await stackImages(ctx, parts, file);
  parts.forEach(p => fs.unlinkSync(p));
  return { status, how: 'embed-comment', unit: parts.length > 1 ? 'thread' : 'comment', quote: quote || win.sentence,
    final: `https://www.reddit.com/r/${ids.sub}/comments/${ids.post}/comment/${win.data.id}/` };
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
    await page.evaluate(removeWalls).catch(() => {});
    // Unfolding can bring a wall back (Facebook asks for a log-in on the click).
    if (await unfold(page)) {
      if (page.url().replace(/#.*$/, '') !== url && !page.url().startsWith(url)) {
        await page.goBack({ waitUntil: 'domcontentloaded' }).catch(() => {});
        await page.waitForTimeout(1000);
      }
      await page.evaluate(removeWalls).catch(() => {});
    }
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
      anchor: (c.url.match(/#c?(\d{6,})$/) || [])[1] || null,
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
    if (found.partner) {
      // The other half of a question and its answer, shot the same way and
      // stacked in the thread's order.
      const other = file.replace(/\.png$/, '.partner.png');
      await page.evaluate(() => {
        window.__proofRect = window.__proofPartnerRect;
        window.__proofEl = null;
      });
      await shootUnit(page, other, MAX_UNIT);
      await stackImages(page.context(), found.partner === 'before' ? [other, file] : [file, other], file);
      fs.unlinkSync(other);
    }
    return { status: found.how === 'weak' ? 'weak' : 'ok', how: found.how, unit: found.unit, quote: found.text,
      partner: found.partner || undefined, final: page.url() };
  } catch (e) {
    return { status: 'error', detail: String(e.message || e).split('\n')[0] };
  } finally {
    await page.close();
  }
}

// Several shots as one picture, top to bottom, on white with a gap between, so
// a question and its answer (or a Reddit post and the comment under it) read
// as the thread they were in. Drawn by the browser rather than an image
// library, so the tool needs nothing Playwright doesn't already bring.
async function stackImages(ctx, files, out, gap = 10) {
  const page = await ctx.newPage();
  try {
    const imgs = files.map(f => `<img src="data:image/png;base64,${fs.readFileSync(f).toString('base64')}" style="display:block;margin-bottom:${gap}px">`).join('');
    await page.setContent(`<html><body style="margin:0;background:#9aa0a6"><div id="s" style="display:inline-block;padding:0">${imgs}</div></body></html>`);
    await page.evaluate(() => Promise.all([...document.images].map(i => i.decode())));
    // The page is laid out at device pixel ratio 1, so each shot keeps its own size.
    const box = await page.evaluate(() => { const r = document.getElementById('s').getBoundingClientRect(); return { w: Math.ceil(r.width), h: Math.ceil(r.height) }; });
    await page.setViewportSize({ width: Math.max(box.w, 100), height: Math.max(box.h, 100) });
    await page.screenshot({ path: out, clip: { x: 0, y: 0, width: box.w, height: box.h - gap } });
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
    // A video X can't play in the embed is a grey "The media could not be
    // played" box as tall as the post (Pegs X Stickers, Kill the Music): it
    // goes, and the post's words close up over it.
    const inner0 = await frame.contentFrame();
    if (inner0) await inner0.evaluate(() => {
      for (const e of document.querySelectorAll('*')) {
        if (e.childElementCount || !/^The media could not be played\.?$/.test((e.textContent || '').trim())) continue;
        let box = e;
        for (let p = e.parentElement; p && p !== document.body; p = p.parentElement) {
          if (p.innerText.trim() && !/^The media could not be played\.?\s*Reload$/.test(p.innerText.trim())) break;
          box = p;
        }
        box.style.setProperty('display', 'none', 'important');
      }
    }).catch(() => {});
    await page.waitForTimeout(500);
    const quote = full || (embed.html.match(/<p[^>]*>([\s\S]*?)<\/p>/) || [, ''])[1].replace(/<[^>]+>/g, '');
    // Punctuation aside: "Elden Ring: Nightreign" is the chart's "Elden Ring
    // Nightreign", and missing it sent the post back for its (dead) video.
    const flat = t => ' ' + t.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ') + ' ';
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
  // Only a failure that says something about the PAGE retires a proof: the
  // sentence is gone (no-match, weak) or the page is (404, 410). A bot wall, a
  // rate limit or a 502 on the day of the run says nothing about the picture
  // already in the game, and fifteen good proofs were lost to exactly that.
  const passing = r => r.status === 'blocked' && !/HTTP 40[46]|HTTP 410/.test(r.detail || '') || r.status === 'error';
  const failed = new Set(report.filter(r => !shown(r) && !passing(r)).map(gameFile));
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

// ── translations ──────────────────────────────────────────────────────────────
// A proof in another language keeps the original screenshot, untouched, with an
// English translation set in a box underneath it. The translations are kept in
// tools/proof_translations.json, written by hand (or by Claude) once per proof:
//
//     "brotato---cluckmech_oasis.png": { "from": "Chinese", "text": "…" }
//
// and `--translate` sets each one under its picture. Each entry records the
// fingerprint (sha1) of the picture WITH its translation, so running it again
// leaves a done picture alone, and a picture replaced since (a fresh capture,
// or one you uploaded) gets its translation set under it again. --export runs
// it at the end, so a re-captured proof never loses its translation.
const TRANSLATIONS = path.join(__dirname, 'proof_translations.json');

async function translateProofs(browser) {
  if (!fs.existsSync(TRANSLATIONS)) return;
  const book = JSON.parse(fs.readFileSync(TRANSLATIONS, 'utf8'));
  const ledger = JSON.parse(fs.readFileSync(CAPTURED, 'utf8'));
  const todo = Object.entries(book.files).filter(([f, t]) => fs.existsSync(path.join(GAME_DIR, f)) && sha1(path.join(GAME_DIR, f)) !== t.sha1);
  if (!todo.length) { console.log('translations: all set'); return; }
  const own = !browser;
  if (own) browser = await require('playwright').chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
  const page = await browser.newPage();
  try {
    for (const [f, t] of todo) {
      const file = path.join(GAME_DIR, f);
      const before = sha1(file);
      const img = `data:image/png;base64,${fs.readFileSync(file).toString('base64')}`;
      await page.setViewportSize({ width: 1400, height: 900 });
      await page.setContent(`<html><body style="margin:0;background:#fff">
        <div id="s" style="display:inline-block;background:#fff">
          <img src="${img}" style="display:block">
          <div id="t" style="box-sizing:border-box;border-top:3px solid #c9a227;background:#fff8dc;color:#222;
            padding:10px 14px 12px;font:15px/1.45 'DejaVu Sans',Arial,sans-serif">
            <div style="font-weight:bold;font-size:12px;letter-spacing:.04em;color:#7a5c00;margin-bottom:4px">ENGLISH TRANSLATION (from ${esc(t.from)})</div>
            <div style="white-space:pre-wrap">${esc(t.text)}</div>
          </div>
        </div></body></html>`);
      await page.evaluate(() => document.images[0].decode());
      // The box is as wide as the picture, but never narrower than a readable line.
      await page.evaluate(() => {
        const w = Math.max(document.images[0].naturalWidth, 520);
        document.getElementById('s').style.width = w + 'px';
      });
      const box = await page.evaluate(() => { const r = document.getElementById('s').getBoundingClientRect(); return { w: Math.ceil(r.width), h: Math.ceil(r.height) }; });
      await page.setViewportSize({ width: Math.max(box.w, 100), height: Math.max(box.h, 100) });
      await page.screenshot({ path: file, clip: { x: 0, y: 0, width: box.w, height: box.h } });
      t.sha1 = sha1(file);
      // A captured proof is still the capture's: its fingerprint moves with it.
      if (ledger.files[f] === before) ledger.files[f] = t.sha1;
      console.log(`translation set under ${f}`);
    }
  } finally {
    await page.close();
    if (own) await browser.close();
  }
  fs.writeFileSync(TRANSLATIONS, JSON.stringify(book, null, 1) + '\n');
  fs.writeFileSync(CAPTURED, JSON.stringify(ledger, null, 1) + '\n');
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
    else if (c.kind === 'reddit') groups.reddit.push(line(!r ? 'not captured yet'
      : /video or picture/.test(r.detail || '') ? 'a video or picture post: the embed shows no text'
      : /removed or edited/.test(r.detail || '') ? 'the comment was removed or edited on Reddit'
      : /archived comments names/.test(r.detail || '') ? 'neither the post nor its comments name ' + c.fromName
      : r.status === 'weak' ? 'only ' + c.toName + ' is named' : (r.detail || r.status).slice(0, 70)));
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

` + section('Reddit: screenshot these yourself',
    'Reddit proofs are captured through Reddit\'s own embed of the post or comment that says it, found through the Arctic Shift archive of Reddit. These are the ones that can\'t be: a video or picture post (the embed shows no text for those), a comment removed or edited since it was archived, or a thread the archive never saw. Open the link and screenshot the sentence.', groups.reddit)
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
  if (args.includes('--export')) { exportProofs(); return translateProofs(); }
  if (args.includes('--translate')) return translateProofs();
  const opt = k => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : null; };
  const all = loadConnections();
  let todo = all.filter(c => c.url);
  if (args.includes('--pilot')) todo = pilot(all);
  if (opt('--only')) todo = todo.filter(c => c.from === opt('--only') || c.to === opt('--only'));
  // --conn hades---going_under,balatro---runeborn: exactly these connections.
  if (opt('--conn')) todo = todo.filter(c => opt('--conn').split(',').includes(`${c.from}---${c.to}`));
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
  const newCtx = async () => {
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
    return ctx;
  };

  // A run updates the report rather than replacing it, so a retry of a few
  // connections (--only) keeps every other connection's result.
  const reportPath = path.join(OUT, 'report.json');
  const prior = fs.existsSync(reportPath) ? JSON.parse(fs.readFileSync(reportPath, 'utf8')) : [];
  const key = r => r.from + '__' + r.to;
  const report = new Map(prior.map(r => [key(r), r]));
  const ran = [];
  // --jobs N: N connections at a time, each worker in a browser context of its
  // own, because a connection that times out closes every page in its context.
  const queue = todo.slice();
  const worker = async () => {
    const ctx = await newCtx();
    for (let c; (c = queue.shift());) {
      const file = path.join(OUT, `${c.from}__${c.to}.png`);
      let r;
      if (c.kind === 'x') r = await captureTweet(ctx, c, file);
      else if (c.kind === 'youtube') r = await captureVideo(ctx, c, file);
      else if (c.kind === 'podcast') r = { status: 'audio', detail: 'audio only: nothing to screenshot; needs the moment transcribed or clipped by hand' };
      else if (c.kind === 'reddit') r = await withDeadline(captureReddit(ctx, c, file), 240000, ctx);
      else r = await withDeadline(capturePage(ctx, c, file), 120000, ctx);
      if (!['blocked', 'error', 'no-match', 'audio'].includes(r.status)) r.image = path.relative(OUT, file);
      console.log(`${c.kind.padEnd(15)} ${c.fromName} → ${c.toName} … ` + r.status + (r.detail ? ` (${r.detail})` : ''));
      report.set(key(c), { ...c, ...r });
      ran.push(r);
      if (ran.length % 20 === 0) fs.writeFileSync(reportPath, JSON.stringify([...report.values()], null, 2));
    }
    await ctx.close();
  };
  await Promise.all(Array.from({ length: Math.max(1, +(opt('--jobs') || 1)) }, worker));
  await browser.close();
  fs.writeFileSync(reportPath, JSON.stringify([...report.values()], null, 2));
  const tally = ran.reduce((t, r) => (t[r.status] = (t[r.status] || 0) + 1, t), {});
  console.log('\n' + Object.entries(tally).map(([k, v]) => `${k}: ${v}`).join('  '));
}

if (require.main === module) main().catch(e => { console.error(e); process.exit(1); });
