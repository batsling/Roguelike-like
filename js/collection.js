// ===== COLLECTION.JS - Collection UI, Stats Tracking, and Detail Panels =====
//
// This module handles:
// - Collection modal with tabs (Games, Characters, Cards, Items, Loot,
//   Enemies, Curses, Reference, Spells, Events)
// - Per-tab search, filtering, and sorting
// - Loot sub-tabs (Fish, Scrolls, Potions)
// - Reference tab — Statuses and Addons driven by Excel-generated data
//   (STATUSES_DATA / ADDONS_DATA); Moves remain hardcoded
// - Detail panels for games, enemies, items, spells, cards, characters, allies
// - Game stats tracking (beaten count, amulets) via localStorage
// - Fish stats tracking (caught count per size) via localStorage
// - Enemy stats tracking (defeats / player kills) via gameState
//
// Depends on: modals.js (createGameModal/closeGameModal), main.js globals
// (games, items, enemies, curses, gameState, saveCurrentGame, GameStorage),
// and data files (STATUSES_DATA, ADDONS_DATA, CARDS_DATA, etc.)

function showCollection() {
  const charCount = typeof CHARACTERS_DATA !== 'undefined' ? Object.keys(CHARACTERS_DATA).length : 0;
  const cardCount = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA.filter(c => c.rarity !== 'Starter').length : 0;
  const spellCount = typeof SPELLS_DATA !== 'undefined' ? SPELLS_DATA.length : 0;
  const eventCount = typeof EVENTS_DATA !== 'undefined' ? EVENTS_DATA.filter(e => e.image).length : 0;

  const collectionHTML = `
    <style>
      .col-tab-btn { padding: 6px 12px; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px; transition: all 0.15s; }
      .col-tab-btn:hover { filter: brightness(1.2); }
      .col-card-hover { transition: transform 0.18s, box-shadow 0.18s; cursor: pointer; }
      .col-card-hover:hover { transform: translateY(-3px); box-shadow: 0 6px 18px rgba(0,0,0,0.6); }
      @keyframes shimmer { 0%,100%{opacity:1} 50%{opacity:0.55} }
      .rarity-shimmer { animation: shimmer 2.4s ease-in-out infinite; }
      .glass-panel { background: rgba(15,15,20,0.65); backdrop-filter: blur(8px); border: 1px solid rgba(255,255,255,0.08); }
    </style>
    <div style="width: 90vw; max-width: 1400px; max-height: 85vh; overflow: hidden; display: flex; flex-direction: column;">
      <div style="display: flex; gap: 6px; padding-bottom: 10px; margin-bottom: 12px; border-bottom: 2px solid #333; align-items: center; flex-wrap: wrap;">
        <h2 style="color: #ff9800; margin: 0; flex: 1; min-width: 110px; font-size: 18px;">📚 Collection</h2>
        <button class="col-tab-btn" onclick="switchCollectionTab('games')" id="tab-games" style="background:#ff9800;">Games (${games.length})</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('characters')" id="tab-characters" style="background:#555;">Characters (${charCount})</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('cards')" id="tab-cards" style="background:#555;">Cards (${cardCount})</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('items')" id="tab-items" style="background:#555;">Items (${items.length})</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('loot')" id="tab-loot" style="background:#555;">Loot</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('enemies')" id="tab-enemies" style="background:#555;">Enemies (${enemies.length})</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('curses')" id="tab-curses" style="background:#555;">Curses (${curses.length})</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('statuses')" id="tab-statuses" style="background:#555;">Reference</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('spells')" id="tab-spells" style="background:#555;">Spells (${spellCount})</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('events')" id="tab-events" style="background:#555;">Events (${eventCount})</button>
        <button class="col-tab-btn" onclick="closeGameModal();" style="background:#333; margin-left: 4px;">✕ Close</button>
      </div>
      <div id="collection-content" style="flex: 1; overflow: hidden; display: flex; gap: 16px;">
      </div>
    </div>
  `;

  createGameModal(collectionHTML);
  switchCollectionTab('games');
}

function switchCollectionTab(tab) {
  // Save focus state before re-rendering
  const activeElement = document.activeElement;
  const activeId = activeElement ? activeElement.id : null;
  const selectionStart = activeElement && activeElement.selectionStart !== undefined ? activeElement.selectionStart : null;
  const selectionEnd = activeElement && activeElement.selectionEnd !== undefined ? activeElement.selectionEnd : null;

  // Update tab buttons
  const tabs = ['games', 'characters', 'cards', 'items', 'loot', 'enemies', 'curses', 'statuses', 'spells', 'events'];
  tabs.forEach(t => {
    const btn = document.getElementById(`tab-${t}`);
    if (btn) btn.style.background = t === tab ? '#ff9800' : '#555';
  });

  const content = document.getElementById('collection-content');
  if (!content) return;

  // Helper to restore focus after content update
  const restoreFocus = () => {
    if (activeId) {
      const element = document.getElementById(activeId);
      if (element) {
        element.focus();
        if (selectionStart !== null && element.setSelectionRange) {
          element.setSelectionRange(selectionStart, selectionEnd);
        }
      }
    }
  };

  if (tab === 'games') {
    // Initialize search/filter state
    if (typeof window.gamesSearchTerm === 'undefined') window.gamesSearchTerm = '';
    if (typeof window.gamesTypeFilter === 'undefined') window.gamesTypeFilter = 'all';
    if (typeof window.gamesTagFilter === 'undefined') window.gamesTagFilter = 'all';

    // Collect all unique types and tags for filter buttons
    const allTypes = [...new Set(games.map(g => g.type).filter(Boolean))].sort();
    const allTags = [...new Set(games.flatMap(g => g.tags || []).filter(Boolean))].sort();

    // Filter and sort games
    const searchTerm = window.gamesSearchTerm.toLowerCase();
    let filteredGames = [...games];
    if (searchTerm) filteredGames = filteredGames.filter(g => g.name.toLowerCase().includes(searchTerm));
    if (window.gamesTypeFilter !== 'all') filteredGames = filteredGames.filter(g => g.type === window.gamesTypeFilter);
    if (window.gamesTagFilter !== 'all') filteredGames = filteredGames.filter(g => g.tags && g.tags.includes(window.gamesTagFilter));
    const sortedGames = filteredGames.sort((a, b) => a.name.localeCompare(b.name));

    // Get game stats for amulet icons
    const allStats = getGameStats();

    const typeFilterBtnStyle = (active) => `padding:4px 10px; border:none; border-radius:12px; cursor:pointer; font-size:11px; font-weight:bold; background:${active?'#ff9800':'rgba(100,100,100,0.3)'}; color:${active?'#000':'#ccc'}; transition:background 0.15s;`;

    content.innerHTML = `
      <!-- Left side: Game grid -->
      <div id="games-grid" style="flex: 2; overflow-y: auto; padding: 10px; display: flex; flex-direction: column;">
        <!-- Search bar -->
        <div style="display: flex; gap: 10px; margin-bottom: 15px; padding: 10px; background: rgba(0,0,0,0.3); border-radius: 8px; align-items: center;">
          <span style="color: #aaa; font-size: 13px;">🔍</span>
          <input type="text" id="games-search" placeholder="Search games..." value="${window.gamesSearchTerm}"
            oninput="window.gamesSearchTerm = this.value; switchCollectionTab('games');"
            style="flex: 1; padding: 8px 12px; background: rgba(0,0,0,0.3); border: 1px solid #555; border-radius: 6px; color: white; font-size: 13px; outline: none;"
          />
          <span style="color: #666; font-size: 11px;">${sortedGames.length} of ${games.length}</span>
        </div>
        <!-- Type filter -->
        <div style="display:flex; flex-wrap:wrap; gap:6px; margin-bottom:8px; padding:8px 10px; background:rgba(0,0,0,0.25); border-radius:8px; align-items:center;">
          <span style="color:#888; font-size:11px; margin-right:2px;">Type:</span>
          <button style="${typeFilterBtnStyle(window.gamesTypeFilter==='all')}" onclick="window.gamesTypeFilter='all'; switchCollectionTab('games');">All</button>
          ${allTypes.map(t => `<button style="${typeFilterBtnStyle(window.gamesTypeFilter===t)}" onclick="window.gamesTypeFilter='${t.replace(/'/g, "\\'")}'; switchCollectionTab('games');">${t}</button>`).join('')}
        </div>
        <!-- Tag filter (separate from type) -->
        ${allTags.length > 0 ? `
        <div style="display:flex; flex-wrap:wrap; gap:6px; margin-bottom:12px; padding:8px 10px; background:rgba(0,0,0,0.25); border-radius:8px; align-items:center;">
          <span style="color:#888; font-size:11px; margin-right:2px;">Tag:</span>
          <button style="${typeFilterBtnStyle(window.gamesTagFilter==='all')}" onclick="window.gamesTagFilter='all'; switchCollectionTab('games');">All</button>
          ${allTags.map(t => `<button style="${typeFilterBtnStyle(window.gamesTagFilter===t)}" onclick="window.gamesTagFilter='${t.replace(/'/g, "\\'")}'; switchCollectionTab('games');">${t}</button>`).join('')}
        </div>` : ''}
        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 15px; overflow-y: auto;">
          ${sortedGames.map(game => {
            const gameStats = allStats[game.name] || { beaten: 0, amulets: 0 };
            return `
            <div
              class="collection-game-card"
              data-game-name="${game.name.replace(/"/g, '&quot;')}"
              onclick="showGameDetails('${game.name.replace(/'/g, "\\'")}')"
              style="
                position: relative;
                background: rgba(0,0,0,0.3);
                border: 1px solid #444;
                border-radius: 8px;
                padding: 10px;
                display: flex;
                flex-direction: column;
                align-items: center;
                gap: 8px;
                transition: transform 0.2s, border-color 0.2s;
                cursor: pointer;
              "
              onmouseover="this.style.transform='translateY(-5px)'; this.style.borderColor='#ff9800';"
              onmouseout="this.style.transform=''; if(!this.classList.contains('game-selected')) this.style.borderColor='#444';">
              ${gameStats.amulets > 0 ? `
                <div style="
                  position: absolute;
                  top: 5px;
                  left: 5px;
                  background: linear-gradient(145deg, gold, #cc9900);
                  border: 2px solid #000;
                  border-radius: 50%;
                  width: 28px;
                  height: 28px;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  font-size: 16px;
                  z-index: 10;
                  box-shadow: 0 2px 6px rgba(0,0,0,0.5);
                ">🏺</div>
              ` : ''}
              <img
                src="${game.coverImage || 'images/covers/no-cover.svg'}"
                alt="${game.name}"
                style="
                  width: 100%;
                  aspect-ratio: 2/3;
                  object-fit: contain;
                  border-radius: 6px;
                  background: #1a1a1a;
                  image-rendering: -webkit-optimize-contrast;
                  image-rendering: smooth;
                "
              />
              <div style="text-align: center; font-size: 12px; font-weight: bold; color: #ddd; word-wrap: break-word; width: 100%;">
                ${game.name}
              </div>
              <div style="display:flex; align-items:center; gap:5px; flex-wrap:wrap; justify-content:center;">
                <span style="font-size:10px; color:#888;">${game.year}</span>
                ${game.type ? `<span style="
                  font-size:10px; font-weight:bold; padding:2px 7px;
                  border-radius:10px; background:rgba(255,152,0,0.18);
                  border:1px solid rgba(255,152,0,0.45); color:#ff9800;
                ">${game.type}</span>` : ''}
              </div>
            </div>
          `;}).join('')}
        </div>
      </div>

      <!-- Right side: Game details -->
      <div id="game-details" style="flex: 1; overflow-y: auto; padding: 20px; background: rgba(0,0,0,0.2); border: 1px solid #444; border-radius: 8px; min-width: 300px;">
        <div style="text-align: center; color: #888; padding: 40px 20px;">
          <p>Click a game to view details</p>
        </div>
      </div>
    `;
  } else if (tab === 'characters') {
    if (typeof window.charactersSearchTerm === 'undefined') window.charactersSearchTerm = '';
    if (!window.characterSortType) window.characterSortType = 'alphabetical';

    const rawChars = typeof CHARACTERS_DATA !== 'undefined' ? Object.values(CHARACTERS_DATA) : [];
    const searchTerm = window.charactersSearchTerm.toLowerCase();
    let filtered = searchTerm
      ? rawChars.filter(c => c.name.toLowerCase().includes(searchTerm) || (c.game || '').toLowerCase().includes(searchTerm))
      : [...rawChars];

    if (window.characterSortType === 'game') {
      filtered.sort((a, b) => (a.game || '').localeCompare(b.game || '') || a.name.localeCompare(b.name));
    } else {
      filtered.sort((a, b) => a.name.localeCompare(b.name));
    }

    content.innerHTML = `
      <div style="flex: 2; overflow-y: auto; padding: 10px; display: flex; flex-direction: column;">
        <div style="display: flex; gap: 8px; margin-bottom: 12px; padding: 8px 12px; background: rgba(0,0,0,0.35); border-radius: 8px; align-items: center; flex-wrap: wrap;">
          <input type="text" placeholder="🔍 Search characters…" value="${window.charactersSearchTerm}"
            oninput="window.charactersSearchTerm = this.value; switchCollectionTab('characters');"
            style="flex:1; min-width:130px; padding:6px 10px; background:rgba(0,0,0,0.4); border:1px solid #444; border-radius:6px; color:white; font-size:12px; outline:none;"/>
          <span style="color:#555; font-size:13px;">|</span>
          <button onclick="window.characterSortType='alphabetical'; switchCollectionTab('characters');" style="padding:5px 10px; background:${window.characterSortType==='alphabetical'?'#4CAF50':'#444'}; border:none; border-radius:5px; color:white; cursor:pointer; font-size:11px; font-weight:bold;">A-Z</button>
          <button onclick="window.characterSortType='game'; switchCollectionTab('characters');" style="padding:5px 10px; background:${window.characterSortType==='game'?'#4CAF50':'#444'}; border:none; border-radius:5px; color:white; cursor:pointer; font-size:11px; font-weight:bold;">Game</button>
          <span style="color:#555; font-size:11px; margin-left:auto;">${filtered.length}/${rawChars.length}</span>
        </div>
        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 12px; overflow-y: auto;">
          ${filtered.map(char => `
            <div class="col-card-hover glass-panel" onclick="showCharacterDetails('${char.name.replace(/'/g,"\\'")}') "
              style="border-radius:10px; padding:14px 10px; display:flex; flex-direction:column; align-items:center; gap:8px;
                     border: 2px solid rgba(76,175,80,0.5); box-shadow: 0 0 10px rgba(76,175,80,0.12);">
              <img src="${char.icon || 'images/characters/Icon/' + char.name + '.png'}" alt="${char.name}"
                style="width:90px; height:90px; object-fit:contain; border-radius:8px; background:rgba(0,0,0,0.3); image-rendering:pixelated;"
                onerror="this.style.opacity='0.25';"/>
              <div style="font-size:12px; font-weight:bold; color:#4CAF50; text-align:center;">${char.name}</div>
              <div style="font-size:10px; color:#888; text-align:center;">${char.game || ''}</div>
              <div style="font-size:10px; color:#aaa;">❤ ${char.health || '?'} &nbsp;⚡ ${char.energy || 0}</div>
            </div>
          `).join('')}
        </div>
      </div>
      <div id="character-details" class="glass-panel" style="flex:1; overflow-y:auto; padding:20px; border-radius:10px; min-width:280px;">
        <div style="text-align:center; color:#666; padding:40px 20px; font-size:13px;">Select a character to view details</div>
      </div>
    `;
  } else if (tab === 'cards') {
    if (typeof window.cardsSearchTerm === 'undefined') window.cardsSearchTerm = '';
    if (typeof window.cardsTypeFilter === 'undefined') window.cardsTypeFilter = 'all';
    if (typeof window.cardsRarityFilter === 'undefined') window.cardsRarityFilter = 'all';
    if (typeof window.cardsSortType === 'undefined') window.cardsSortType = 'rarity';

    const allCards = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA : [];
    let filteredCards = [...allCards];

    const searchTerm = window.cardsSearchTerm.toLowerCase();
    if (searchTerm) {
      filteredCards = filteredCards.filter(c =>
        c.name.toLowerCase().includes(searchTerm) ||
        (c.description || '').toLowerCase().includes(searchTerm)
      );
    }
    if (window.cardsTypeFilter !== 'all') {
      filteredCards = filteredCards.filter(c => (c.type || '').toLowerCase() === window.cardsTypeFilter);
    }
    if (window.cardsRarityFilter !== 'all') {
      filteredCards = filteredCards.filter(c => (c.rarity || '').toLowerCase() === window.cardsRarityFilter);
    }

    const rarityOrder = { 'legendary':5,'rare':4,'uncommon':3,'common':2,'starter':1 };
    const typeOrder = { 'attack':1,'skill':2,'power':3,'training':4,'dice':5 };
    if (window.cardsSortType === 'rarity') {
      filteredCards.sort((a,b) => (rarityOrder[(b.rarity||'').toLowerCase()]||0) - (rarityOrder[(a.rarity||'').toLowerCase()]||0) || a.name.localeCompare(b.name));
    } else if (window.cardsSortType === 'type') {
      filteredCards.sort((a,b) => (typeOrder[(a.type||'').toLowerCase()]||9) - (typeOrder[(b.type||'').toLowerCase()]||9) || a.name.localeCompare(b.name));
    } else if (window.cardsSortType === 'cost') {
      filteredCards.sort((a,b) => (a.cost||0) - (b.cost||0) || a.name.localeCompare(b.name));
    } else {
      filteredCards.sort((a,b) => a.name.localeCompare(b.name));
    }

    const getRarityColor = (r) => {
      switch((r||'').toLowerCase()) {
        case 'legendary': return '#ff6b00';
        case 'rare': return '#9b59b6';
        case 'uncommon': return '#4CAF50';
        case 'common': return '#aaa';
        case 'starter': return '#2196F3';
        default: return '#666';
      }
    };
    const getTypeColor = (t) => {
      switch((t||'').toLowerCase()) {
        case 'attack': return '#e74c3c';
        case 'skill': return '#2980b9';
        case 'power': return '#8e44ad';
        case 'training': return '#27ae60';
        case 'dice': return '#d35400';
        default: return '#888';
      }
    };

    const cardTypes = [...new Set(allCards.map(c=>c.type).filter(Boolean))].sort();
    const rarities = [...new Set(allCards.map(c=>c.rarity).filter(Boolean))].sort();

    content.innerHTML = `
      <div style="flex:2; overflow-y:auto; padding:10px; display:flex; flex-direction:column;">
        <!-- Controls -->
        <div style="display:flex; gap:6px; margin-bottom:12px; padding:8px 12px; background:rgba(0,0,0,0.35); border-radius:8px; align-items:center; flex-wrap:wrap;">
          <input id="cards-search-input" type="text" placeholder="🔍 Search cards…" value="${window.cardsSearchTerm}"
            oninput="window.cardsSearchTerm=this.value; switchCollectionTab('cards');"
            style="flex:1; min-width:120px; padding:6px 10px; background:rgba(0,0,0,0.4); border:1px solid #444; border-radius:6px; color:white; font-size:12px; outline:none;"/>
          <span style="color:#555;">|</span>
          <select onchange="window.cardsTypeFilter=this.value; switchCollectionTab('cards');" style="padding:5px 8px; background:#333; border:1px solid #444; border-radius:6px; color:white; font-size:11px; cursor:pointer;">
            <option value="all" ${window.cardsTypeFilter==='all'?'selected':''}>All Types</option>
            ${cardTypes.map(t=>`<option value="${t.toLowerCase()}" ${window.cardsTypeFilter===t.toLowerCase()?'selected':''}>${t}</option>`).join('')}
          </select>
          <select onchange="window.cardsRarityFilter=this.value; switchCollectionTab('cards');" style="padding:5px 8px; background:#333; border:1px solid #444; border-radius:6px; color:white; font-size:11px; cursor:pointer;">
            <option value="all" ${window.cardsRarityFilter==='all'?'selected':''}>All Rarities</option>
            ${rarities.map(r=>`<option value="${r.toLowerCase()}" ${window.cardsRarityFilter===r.toLowerCase()?'selected':''}>${r}</option>`).join('')}
          </select>
          <span style="color:#555;">|</span>
          <button onclick="window.cardsSortType='rarity'; switchCollectionTab('cards');" style="padding:5px 9px; background:${window.cardsSortType==='rarity'?'#ff9800':'#444'}; border:none; border-radius:5px; color:white; cursor:pointer; font-size:11px; font-weight:bold;">Rarity</button>
          <button onclick="window.cardsSortType='type'; switchCollectionTab('cards');" style="padding:5px 9px; background:${window.cardsSortType==='type'?'#ff9800':'#444'}; border:none; border-radius:5px; color:white; cursor:pointer; font-size:11px; font-weight:bold;">Type</button>
          <button onclick="window.cardsSortType='cost'; switchCollectionTab('cards');" style="padding:5px 9px; background:${window.cardsSortType==='cost'?'#ff9800':'#444'}; border:none; border-radius:5px; color:white; cursor:pointer; font-size:11px; font-weight:bold;">Cost</button>
          <button onclick="window.cardsSortType='alpha'; switchCollectionTab('cards');" style="padding:5px 9px; background:${window.cardsSortType==='alpha'?'#ff9800':'#444'}; border:none; border-radius:5px; color:white; cursor:pointer; font-size:11px; font-weight:bold;">A-Z</button>
          <span style="color:#555; font-size:11px; margin-left:auto;">${filteredCards.length}/${allCards.length}</span>
        </div>
        <!-- Card grid -->
        <div style="display:grid; grid-template-columns:repeat(auto-fill, minmax(120px, 1fr)); gap:10px; overflow-y:auto;">
          ${filteredCards.map(card => {
            const rc = getRarityColor(card.rarity);
            const tc = getTypeColor(card.type);
            return `
            <div class="col-card-hover" onclick="showCardDetails('${card.name.replace(/'/g,"\\'")}') "
              style="border-radius:10px; border:2px solid ${rc}; background:rgba(10,10,15,0.8);
                     box-shadow: 0 0 8px ${rc}44; display:flex; flex-direction:column; overflow:hidden; min-height:160px; position:relative;">
              <!-- Cost bubble -->
              <div style="position:absolute; top:6px; left:6px; width:22px; height:22px; border-radius:50%;
                           background:${tc}; border:2px solid rgba(255,255,255,0.3); display:flex; align-items:center; justify-content:center;
                           font-size:11px; font-weight:bold; color:white; z-index:2;">
                ${card.cost !== null && card.cost !== undefined ? card.cost : '?'}
              </div>
              <!-- Card image -->
              ${card.imageUrl ? `
                <img src="${card.imageUrl}" alt="${card.name}"
                  style="width:100%; height:80px; object-fit:contain; background:rgba(0,0,0,0.3); image-rendering:pixelated;"
                  onerror="if(this.dataset.t){this.style.display='none';}else{this.dataset.t=1;this.src='images/heroes/'+this.alt+'.png';}"/>
              ` : `<div style="width:100%; height:80px; background:linear-gradient(135deg,${tc}33,${rc}22); display:flex; align-items:center; justify-content:center; font-size:28px; color:${tc}88;">
                ${{attack:'⚔',skill:'🛡',power:'✨',dice:'🎲',training:'📖'}[(card.type||'').toLowerCase()]||'🃏'}
              </div>`}
              <!-- Card info -->
              <div style="padding:6px; flex:1; display:flex; flex-direction:column; gap:3px;">
                <div style="font-size:11px; font-weight:bold; color:#eee; line-height:1.2;">${card.name}</div>
                <div style="font-size:9px; color:${tc}; text-transform:uppercase; font-weight:bold;">${card.type || ''}</div>
                <div style="font-size:9px; color:${rc}; text-transform:uppercase;">${card.rarity || ''}</div>
              </div>
            </div>
          `;}).join('')}
        </div>
      </div>
      <div id="card-details" class="glass-panel" style="flex:1; overflow-y:auto; padding:20px; border-radius:10px; min-width:280px;">
        <div style="text-align:center; color:#666; padding:40px 20px; font-size:13px;">Select a card to view details</div>
      </div>
    `;

    // Re-focus search input if the user was typing (avoids focus loss on each keystroke)
    if (window.cardsSearchTerm) {
      requestAnimationFrame(() => {
        const inp = document.getElementById('cards-search-input');
        if (inp) { inp.focus(); inp.setSelectionRange(inp.value.length, inp.value.length); }
      });
    }

  } else if (tab === 'items') {
    // Initialize filter state if not set
    if (typeof window.itemsShowNA === 'undefined') window.itemsShowNA = false;
    if (typeof window.itemsSearchTerm === 'undefined') window.itemsSearchTerm = '';
    if (typeof window.itemsTypeFilter === 'undefined') window.itemsTypeFilter = 'all';
    if (!window.itemsSortType) window.itemsSortType = 'alphabetical';

    // Get rarity color function (case-insensitive)
    const getRarityColor = (rarity) => {
      const rarityLower = (rarity || '').toLowerCase();
      switch(rarityLower) {
        case 'legendary': return '#ff6b00';
        case 'rare': return '#9b59b6';
        case 'uncommon': return '#4CAF50';
        case 'common': return '#aaa';
        default: return '#888';
      }
    };

    // Get unique item types
    const itemTypes = [...new Set(items.map(i => i.type).filter(t => t))].sort();

    // Filter items
    let filteredItems = [...items];

    // Filter by N/A
    if (!window.itemsShowNA) {
      filteredItems = filteredItems.filter(item => (item.rarity || '').toLowerCase() !== 'n/a');
    }

    // Filter by search term
    const searchTerm = window.itemsSearchTerm.toLowerCase();
    if (searchTerm) {
      filteredItems = filteredItems.filter(item =>
        item.name.toLowerCase().includes(searchTerm) ||
        (item.description && item.description.toLowerCase().includes(searchTerm)) ||
        (item.game && item.game.toLowerCase().includes(searchTerm))
      );
    }

    // Filter by type
    if (window.itemsTypeFilter !== 'all') {
      filteredItems = filteredItems.filter(item => item.type === window.itemsTypeFilter);
    }

    // Sort items
    let sortedItems;
    if (window.itemsSortType === 'alphabetical') {
      sortedItems = filteredItems.sort((a, b) => a.name.localeCompare(b.name));
    } else if (window.itemsSortType === 'rarity') {
      const rarityOrder = { 'legendary': 4, 'rare': 3, 'uncommon': 2, 'common': 1 };
      sortedItems = filteredItems.sort((a, b) => {
        const rarityDiff = (rarityOrder[(b.rarity || '').toLowerCase()] || 0) - (rarityOrder[(a.rarity || '').toLowerCase()] || 0);
        return rarityDiff !== 0 ? rarityDiff : a.name.localeCompare(b.name);
      });
    } else if (window.itemsSortType === 'game') {
      sortedItems = filteredItems.sort((a, b) => {
        const gameA = a.game || 'Unknown';
        const gameB = b.game || 'Unknown';
        const gameDiff = gameA.localeCompare(gameB);
        return gameDiff !== 0 ? gameDiff : a.name.localeCompare(b.name);
      });
    } else {
      sortedItems = filteredItems.sort((a, b) => a.name.localeCompare(b.name));
    }

    const naCount = items.filter(item => (item.rarity || '').toLowerCase() === 'n/a').length;

    content.innerHTML = `
      <!-- Left side: Item grid -->
      <div id="items-grid-container" style="flex: 2; overflow-y: auto; padding: 10px; display: flex; flex-direction: column;">
        <!-- Search, Sort and Filter controls -->
        <div style="display: flex; gap: 8px; margin-bottom: 15px; padding: 10px; background: rgba(0,0,0,0.3); border-radius: 8px; align-items: center; flex-wrap: wrap;">
          <span style="color: #aaa; font-size: 13px;">🔍</span>
          <input type="text" id="items-search" placeholder="Search items..." value="${window.itemsSearchTerm}"
            oninput="window.itemsSearchTerm = this.value; switchCollectionTab('items');"
            style="flex: 1; min-width: 120px; padding: 6px 10px; background: rgba(0,0,0,0.3); border: 1px solid #555; border-radius: 6px; color: white; font-size: 12px; outline: none;"
          />
          <div style="border-left: 1px solid #555; height: 20px; margin: 0 3px;"></div>
          <span style="color: #aaa; font-size: 12px; font-weight: bold;">Sort:</span>
          <button onclick="window.itemsSortType = 'alphabetical'; switchCollectionTab('items');" style="padding: 5px 10px; background: ${window.itemsSortType === 'alphabetical' ? '#ff9800' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 11px;">A-Z</button>
          <button onclick="window.itemsSortType = 'rarity'; switchCollectionTab('items');" style="padding: 5px 10px; background: ${window.itemsSortType === 'rarity' ? '#ff9800' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 11px;">Rarity</button>
          <button onclick="window.itemsSortType = 'game'; switchCollectionTab('items');" style="padding: 5px 10px; background: ${window.itemsSortType === 'game' ? '#ff9800' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 11px;">Game</button>
          <div style="border-left: 1px solid #555; height: 20px; margin: 0 3px;"></div>
          <span style="color: #aaa; font-size: 12px; font-weight: bold;">Type:</span>
          <select onchange="window.itemsTypeFilter = this.value; switchCollectionTab('items');" style="padding: 5px 8px; background: #444; border: 1px solid #555; border-radius: 6px; color: white; font-size: 11px; cursor: pointer;">
            <option value="all" ${window.itemsTypeFilter === 'all' ? 'selected' : ''}>All</option>
            ${itemTypes.map(type => `<option value="${type}" ${window.itemsTypeFilter === type ? 'selected' : ''}>${type}</option>`).join('')}
          </select>
          <button onclick="toggleItemsNA()" style="padding: 5px 10px; background: ${window.itemsShowNA ? '#ff9800' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 11px;">
            N/A (${naCount})
          </button>
          <span style="color: #666; font-size: 10px; margin-left: auto;">${sortedItems.length} of ${items.length}</span>
        </div>

        <div id="items-grid" style="display: grid; grid-template-columns: repeat(auto-fill, minmax(110px, 1fr)); gap: 10px; overflow-y: auto;">
          ${sortedItems.map(item => {
            const rarityColor = getRarityColor(item.rarity);
            return `
            <div class="col-card-hover"
              onclick="showItemDetails('${item.name.replace(/'/g, "\\'")}')"
              style="background:rgba(10,10,15,0.8); border:2px solid ${rarityColor};
                     box-shadow:0 0 8px ${rarityColor}44; border-radius:10px; padding:10px;
                     display:flex; flex-direction:column; align-items:center; gap:6px;">
              <img src="${item.image || ''}" alt="${item.name}"
                style="width:72px; height:72px; object-fit:contain; border-radius:6px; background:rgba(0,0,0,0.3); image-rendering:pixelated;"
                onerror="this.style.display='none';"/>
              <div style="text-align:center; font-size:11px; font-weight:bold; color:${rarityColor}; word-break:break-word; width:100%;">${item.name}</div>
              <div style="font-size:9px; color:${rarityColor}; text-transform:uppercase; font-weight:bold;">${item.rarity||''}</div>
            </div>
          `;
          }).join('')}
        </div>
      </div>
      <div id="item-details" class="glass-panel" style="flex:1; overflow-y:auto; padding:20px; border-radius:10px; min-width:280px;">
        <div style="text-align:center; color:#666; padding:40px 20px; font-size:13px;">Select an item to view details</div>
      </div>
    `;

    if (window.itemsSearchTerm) {
      requestAnimationFrame(() => {
        const inp = document.getElementById('items-search');
        if (inp) { inp.focus(); inp.setSelectionRange(inp.value.length, inp.value.length); }
      });
    }
  } else if (tab === 'loot') {
    // Initialize loot sub-tab if not set
    if (!window.currentLootSubTab) {
      window.currentLootSubTab = 'fish';
    }

    const scrollCount = typeof SCROLLS_DATA !== 'undefined' ? SCROLLS_DATA.length : 0;
    const potionCount = typeof POTIONS_DATA !== 'undefined' ? POTIONS_DATA.length : 0;

    const lootTabBtn = (id, label, color) => {
      const active = window.currentLootSubTab === id;
      return `<button onclick="switchLootSubTab('${id}')" id="loot-subtab-${id}" style="padding:6px 14px; background:${active ? color : '#555'}; border:none; border-radius:6px; color:white; cursor:pointer; font-weight:bold; font-size:12px;">${label}</button>`;
    };

    content.innerHTML = `
      <div style="flex: 1; display: flex; flex-direction: column; overflow: hidden;">
        <!-- Loot Sub-tabs -->
        <div style="display: flex; gap: 10px; margin-bottom: 15px; padding-bottom: 10px; border-bottom: 1px solid #444;">
          ${lootTabBtn('fish', '🐟 Fish', '#66b3ff')}
          ${lootTabBtn('scrolls', `📜 Scrolls (${scrollCount})`, '#c39be0')}
          ${lootTabBtn('potions', `🧪 Potions (${potionCount})`, '#e07b7b')}
        </div>

        <!-- Loot Sub-tab Content -->
        <div id="loot-subtab-content" style="flex: 1; overflow-y: auto;">
          <!-- Content will be populated by switchLootSubTab -->
        </div>
      </div>
    `;

    // Load the current sub-tab content
    switchLootSubTab(window.currentLootSubTab);
  } else if (tab === 'enemies') {
    // Initialize sort/filter state
    if (!window.enemySortType) window.enemySortType = 'name';
    if (typeof window.enemyTagFilter === 'undefined') window.enemyTagFilter = 'all';

    // Filter out variants (they'll be shown in the details panel of their base enemy)
    let baseEnemies = enemies.filter(e => !e.variantOf);
    if (window.enemyTagFilter !== 'all') baseEnemies = baseEnemies.filter(e => e.tag === window.enemyTagFilter);

    // Collect all unique tags for filter buttons
    const allEnemyTags = [...new Set(enemies.filter(e => !e.variantOf && e.tag).map(e => e.tag))].sort();

    // Get difficulty color
    const getDifficultyColor = (difficulty) => {
      switch((difficulty || '').toLowerCase()) {
        case 'low': return '#4CAF50';
        case 'medium': return '#ff9800';
        case 'high': return '#f44336';
        case 'boss': return '#9b59b6';
        default: return '#888';
      }
    };

    // Sort enemies based on current sort type
    const difficultyOrder = { 'low': 1, 'medium': 2, 'high': 3, 'boss': 4 };
    let sortedEnemies;
    if (window.enemySortType === 'name') {
      sortedEnemies = [...baseEnemies].sort((a, b) => a.name.localeCompare(b.name));
    } else if (window.enemySortType === 'type') {
      sortedEnemies = [...baseEnemies].sort((a, b) => {
        const typeDiff = (a.type || '').localeCompare(b.type || '');
        return typeDiff !== 0 ? typeDiff : a.name.localeCompare(b.name);
      });
    } else if (window.enemySortType === 'game') {
      sortedEnemies = [...baseEnemies].sort((a, b) => {
        const gameDiff = (a.game || '').localeCompare(b.game || '');
        return gameDiff !== 0 ? gameDiff : a.name.localeCompare(b.name);
      });
    } else if (window.enemySortType === 'difficulty') {
      sortedEnemies = [...baseEnemies].sort((a, b) => {
        const diffA = difficultyOrder[(a.difficulty || '').toLowerCase()] || 0;
        const diffB = difficultyOrder[(b.difficulty || '').toLowerCase()] || 0;
        return diffA !== diffB ? diffA - diffB : a.name.localeCompare(b.name);
      });
    } else {
      sortedEnemies = [...baseEnemies].sort((a, b) => a.name.localeCompare(b.name));
    }

    content.innerHTML = `
      <!-- Left side: Enemy grid (8 per row) -->
      <div id="enemies-grid-container" style="flex: 2; overflow-y: auto; padding: 10px;">
        <!-- Sort controls -->
        <div style="display: flex; gap: 10px; margin-bottom: 8px; padding: 10px; background: rgba(0,0,0,0.3); border-radius: 8px; align-items: center;">
          <span style="color: #aaa; font-size: 13px; font-weight: bold;">Sort:</span>
          <button onclick="sortEnemies('name')" id="enemy-sort-name" style="padding: 6px 12px; background: ${window.enemySortType === 'name' ? '#f44336' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Name</button>
          <button onclick="sortEnemies('type')" id="enemy-sort-type" style="padding: 6px 12px; background: ${window.enemySortType === 'type' ? '#f44336' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Type</button>
          <button onclick="sortEnemies('game')" id="enemy-sort-game" style="padding: 6px 12px; background: ${window.enemySortType === 'game' ? '#f44336' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Game</button>
          <button onclick="sortEnemies('difficulty')" id="enemy-sort-difficulty" style="padding: 6px 12px; background: ${window.enemySortType === 'difficulty' ? '#f44336' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Difficulty</button>
          <span style="color: #666; font-size: 11px; margin-left: auto;">${sortedEnemies.length} enemies</span>
        </div>
        <!-- Tag filter -->
        ${allEnemyTags.length > 0 ? `
        <div style="display:flex; flex-wrap:wrap; gap:6px; margin-bottom:12px; padding:8px 10px; background:rgba(0,0,0,0.25); border-radius:8px; align-items:center;">
          <span style="color:#888; font-size:11px; margin-right:2px;">Tag:</span>
          <button style="padding:4px 10px;border:none;border-radius:12px;cursor:pointer;font-size:11px;font-weight:bold;background:${window.enemyTagFilter==='all'?'#f44336':'rgba(100,100,100,0.3)'};color:${window.enemyTagFilter==='all'?'#fff':'#ccc'};" onclick="window.enemyTagFilter='all'; switchCollectionTab('enemies');">All</button>
          ${allEnemyTags.map(t => `<button style="padding:4px 10px;border:none;border-radius:12px;cursor:pointer;font-size:11px;font-weight:bold;background:${window.enemyTagFilter===t?'#f44336':'rgba(100,100,100,0.3)'};color:${window.enemyTagFilter===t?'#fff':'#ccc'};" onclick="window.enemyTagFilter='${t.replace(/'/g, "\\'")}'; switchCollectionTab('enemies');">${t}</button>`).join('')}
        </div>` : ''}
        <div style="display: grid; grid-template-columns: repeat(8, 1fr); gap: 10px;">
          ${sortedEnemies.map(enemy => {
            const diffColor = getDifficultyColor(enemy.difficulty);
            return `
            <div
              class="collection-enemy-card"
              data-enemy-name="${enemy.name.replace(/"/g, '&quot;')}"
              onclick="showEnemyDetails('${enemy.name.replace(/'/g, "\\'")}')"
              style="
                background: rgba(0,0,0,0.3);
                border: 2px solid ${diffColor};
                border-radius: 8px;
                padding: 8px;
                display: flex;
                flex-direction: column;
                align-items: center;
                gap: 6px;
                transition: transform 0.2s, box-shadow 0.2s;
                cursor: pointer;
              "
              onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 4px 12px rgba(0,0,0,0.5)';"
              onmouseout="this.style.transform=''; this.style.boxShadow='';">
              <img
                src="${enemy.imageUrl || getEnemyImagePath(enemy.name)}"
                alt="${enemy.name}"
                onerror="this.style.opacity='0.3'"
                style="
                  width: 100%;
                  height: 80px;
                  object-fit: contain;
                  border-radius: 4px;
                  background: rgba(0,0,0,0.2);
                  image-rendering: pixelated;
                  image-rendering: crisp-edges;
                "
              />
              <div style="text-align: center; font-size: 11px; font-weight: bold; color: #ddd; word-wrap: break-word; width: 100%; line-height: 1.2;">
                ${enemy.name}
              </div>
              <div style="font-size: 9px; color: ${diffColor}; text-align: center; text-transform: uppercase; font-weight: bold;">
                ${enemy.difficulty || 'Unknown'}
              </div>
            </div>
          `;}).join('')}
        </div>
      </div>

      <!-- Right side: Enemy details -->
      <div id="enemy-details" style="flex: 1; overflow-y: auto; padding: 20px; background: rgba(0,0,0,0.2); border: 1px solid #444; border-radius: 8px; min-width: 350px;">
        <div style="text-align: center; color: #888; padding: 40px 20px;">
          <p>Click an enemy to view details</p>
        </div>
      </div>
    `;
  } else if (tab === 'allies') {
    // Allies tab removed — redirect to characters
    switchCollectionTab('characters');
    return;
  } else if (tab === '_allies_removed') {
    // Allies tab removed — no-op
  } else if (tab === 'curses') {
    // Group curses by base name (without I, II, III)
    const curseGroups = new Map();

    curses.forEach(curse => {
      // Extract base name and tier
      const match = curse.name.match(/^(.+?)\s+(I{1,3})$/);
      if (match) {
        const baseName = match[1];
        const tier = match[2];

        if (!curseGroups.has(baseName)) {
          curseGroups.set(baseName, {});
        }
        curseGroups.get(baseName)[tier] = curse;
      }
    });

    // Sort curse groups alphabetically by base name
    const sortedGroups = Array.from(curseGroups.entries()).sort((a, b) => a[0].localeCompare(b[0]));

    // Store curse data globally for tier switching
    window.allCurseData = {};
    sortedGroups.forEach(([baseName, tiers], index) => {
      window.allCurseData[index] = tiers;
    });

    content.innerHTML = `
      <div style="flex: 1; overflow-y: auto; padding: 10px;">
        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 20px;">
          ${sortedGroups.map(([baseName, tiers], index) => {
            const firstTier = tiers['I'] || tiers['II'] || tiers['III'];
            return `
            <div style="display: flex; flex-direction: column;">
              <!-- Tier tabs above the box -->
              <div style="display: flex; gap: 3px; justify-content: center; margin-bottom: -1px; z-index: 1; position: relative;">
                ${['I', 'II', 'III'].map(tier => tiers[tier] ? `
                  <button
                    onclick="switchCurseTier(${index}, '${tier}')"
                    id="curse-${index}-tab-${tier}"
                    style="
                      padding: 5px 14px;
                      background: ${tier === 'I' ? 'rgba(0,0,0,0.3)' : '#555'};
                      border: 1px solid ${tier === 'I' ? '#9c27b0' : '#444'};
                      border-bottom: ${tier === 'I' ? '1px solid rgba(0,0,0,0.3)' : '1px solid #444'};
                      border-radius: 6px 6px 0 0;
                      color: ${tier === 'I' ? '#9c27b0' : '#aaa'};
                      cursor: pointer;
                      font-size: 11px;
                      font-weight: bold;
                      transition: all 0.2s;
                    ">
                    ${tier}
                  </button>
                ` : '').join('')}
              </div>

              <!-- Curse card box -->
              <div id="curse-card-${index}" style="
                background: rgba(0,0,0,0.3);
                border: 1px solid #444;
                border-radius: 0 8px 8px 8px;
                padding: 15px;
                display: flex;
                flex-direction: column;
                gap: 8px;
                transition: transform 0.2s, border-color 0.2s;
                position: relative;
                z-index: 0;
              " onmouseover="this.style.borderColor='#9c27b0';" onmouseout="this.style.borderColor='#444';">
                <div style="text-align: center; font-size: 13px; font-weight: bold; color: #ddd; word-wrap: break-word;">
                  ${baseName}
                </div>

                <!-- Curse details (tier I shown by default) -->
                <div id="curse-${index}-details">
                  <div style="font-size: 11px; color: #9c27b0; text-align: center;">
                    ${firstTier.stat} • ${firstTier.power}
                  </div>
                  <div style="font-size: 10px; color: #888; text-align: center;">
                    ${firstTier.duration}
                  </div>
                  <div style="font-size: 10px; color: #aaa; text-align: center; line-height: 1.4; margin-top: 5px; padding-top: 8px; border-top: 1px solid #444;">
                    ${firstTier.description}
                  </div>
                </div>
              </div>
            </div>
          `;}).join('')}
        </div>
      </div>
    `;
  } else if (tab === 'statuses') {
    // Drives Reference tab from Excel-generated data
    const REF_STATUSES = typeof STATUSES_DATA !== 'undefined' ? Object.values(STATUSES_DATA) : [];
    const REF_MOVES = [
      {name:'Dmg',desc:'Deals X damage to target',target:'Enemy',file:'Attack',scaling:'Strength',rarity:'Common'},
      {name:'Block',desc:'Give target X block — X amount of damage a target can take before it affects their health',target:'Ally/Self',file:'Defense',scaling:'Dexterity',rarity:'Common'},
      {name:'Reroll',desc:'Gains X rerolls',target:'Self',file:'Status',scaling:'Charisma',rarity:'Rare'},
      {name:'Heal',desc:'Give target X health',target:'Ally/Self',file:'Health',scaling:'Intelligence',rarity:'Uncommon'},
      {name:'Spawn',desc:'Spawn X Creature — if used by enemies, the new enemy will show "Doing nothing"',target:'Self',file:'Status',scaling:'N/A',rarity:''},
      {name:'Alter',desc:'Alter target into X with the same Health as the original target, but Max Health of X',target:'Self',file:'Status',scaling:'N/A',rarity:''},
      {name:'Get',desc:'Give X status to self',target:'Self',file:'Status',scaling:'Charisma',rarity:'Common'},
      {name:'Inflict',desc:'Inflict X status to target',target:'Enemy',file:'Status',scaling:'Charisma',rarity:'Common'},
      {name:'Cleanse',desc:'Removes X stacks of all debuff statuses',target:'Ally/Self',file:'Status',scaling:'Charisma',rarity:'Uncommon'},
      {name:'Mana',desc:'Gain X Mana',target:'Self',file:'Mana',scaling:'Intelligence',rarity:'Common'},
      {name:'Pain',desc:'Target deals X damage to self (not Melee or Ranged)',target:'Self',file:'Status',scaling:'Strength',rarity:''},
      {name:'Assassinate',desc:'Kill an enemy with at least X health left',target:'Enemy',file:'Assassinate',scaling:'Strength',rarity:'Rare'},
      {name:'Vitality',desc:'Gain X Max Health',target:'Ally/Self',file:'Vitality',scaling:'Intelligence',rarity:'Rare'},
      {name:'Add X to Y',desc:'Target gives X card to your Y (Deck, Hand, or Discard)',target:'Player',file:'Status',scaling:'N/A',rarity:''},
      {name:'Steal X in Y',desc:'Enemy steals X card from the player\'s Y (Deck, Hand, Discard, Any) for the duration of the battle',target:'Player',file:'Status',scaling:'N/A',rarity:''},
      {name:'Consume X in Y for Z',desc:'Steal X from player\'s Y and destroy it permanently, then Get Z status if successful',target:'Player',file:'Status',scaling:'N/A',rarity:''},
      {name:'Lose',desc:'Lose X status Y times (# or All)',target:'Self',file:'Status',scaling:'N/A',rarity:''},
      {name:'Conjure X Y to Z',desc:'Create X number of named Y cards and add them to your Z (Hand, Discard, or Draw)',target:'Self',file:'Status',scaling:'N/A',rarity:''},
    ];
    const REF_ADDONS = typeof ADDONS_DATA !== 'undefined' ? Object.values(ADDONS_DATA).filter(a => a.canBeAttachedTo !== 'Spell') : [];

    if (!window.refSubtab) window.refSubtab = 'statuses';
    if (typeof window.refSearch === 'undefined') window.refSearch = '';
    if (!window.refTypeFilter) window.refTypeFilter = 'all';

    const getTypeColor = (type) => {
      switch((type||'').toLowerCase()) {
        case 'buff': return '#4CAF50';
        case 'debuff': return '#f44336';
        case 'ability': return '#9c6bff';
        case 'intent': return '#888';
        default: return '#7ea8be';
      }
    };
    const getRarityColor = (r) => {
      switch((r||'').toLowerCase()) {
        case 'common': return '#aaa';
        case 'uncommon': return '#4CAF50';
        case 'rare': return '#5b9bd5';
        default: return '#555';
      }
    };

    const subBtnStyle = (active) => 'padding:7px 18px;border:none;border-radius:6px 6px 0 0;cursor:pointer;font-weight:bold;font-size:13px;transition:background 0.2s;' +
      (active ? 'background:#ff9800;color:#111;' : 'background:rgba(0,0,0,0.35);color:#aaa;');

    const searchTerm = window.refSearch.toLowerCase();

    let innerHtml = '';

    if (window.refSubtab === 'statuses') {
      let data = REF_STATUSES;
      if (searchTerm) data = data.filter(s => s.name.toLowerCase().includes(searchTerm) || (s.description || '').toLowerCase().includes(searchTerm));
      if (window.refTypeFilter !== 'all') data = data.filter(s => s.type.toLowerCase() === window.refTypeFilter);

      const typeFilters = ['all','buff','debuff','ability'];
      innerHtml = `
        <div style="display:flex;gap:8px;margin-bottom:12px;flex-wrap:wrap;align-items:center;">
          <span style="color:#aaa;font-size:12px;">Filter:</span>
          ${typeFilters.map(f => '<button onclick="window.refTypeFilter=\'' + f + '\';switchCollectionTab(\'statuses\');" style="padding:5px 12px;border:none;border-radius:5px;cursor:pointer;font-size:11px;font-weight:bold;background:' + (window.refTypeFilter===f ? getTypeColor(f==='all'?'':f) || '#ff9800' : '#444') + ';color:white;">' + (f==='all'?'All':f.charAt(0).toUpperCase()+f.slice(1)) + '</button>').join('')}
          <span style="color:#666;font-size:11px;margin-left:auto;">${data.length} entries</span>
        </div>
        <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:12px;overflow-y:auto;">
          ${data.map(s => {
            const tc = getTypeColor(s.type);
            const rc = getRarityColor(s.rarity);
            return '<div style="background:rgba(0,0,0,0.35);border:1px solid ' + tc + '44;border-left:3px solid ' + tc + ';border-radius:8px;padding:12px;display:flex;gap:10px;align-items:flex-start;transition:transform 0.15s,box-shadow 0.15s;" onmouseover="this.style.transform=\'translateY(-2px)\';this.style.boxShadow=\'0 4px 12px rgba(0,0,0,0.5)\';" onmouseout="this.style.transform=\'\';this.style.boxShadow=\'\';"><img src="' + (s.imageUrl || '') + '" alt="' + s.name + '" style="width:44px;height:44px;object-fit:contain;border-radius:5px;background:rgba(0,0,0,0.2);image-rendering:pixelated;flex-shrink:0;" onerror="this.style.opacity=\'0.2\';"/><div style="flex:1;min-width:0;"><div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:5px;gap:6px;"><span style="font-size:13px;font-weight:bold;color:' + tc + ';">' + s.name + '</span><span style="font-size:10px;color:' + tc + ';text-transform:uppercase;font-weight:bold;padding:2px 6px;background:' + tc + '22;border-radius:4px;white-space:nowrap;">' + s.type + '</span></div><div style="font-size:11px;color:#ccc;line-height:1.5;margin-bottom:6px;">' + (s.description || '') + '</div><div style="display:flex;gap:8px;flex-wrap:wrap;font-size:10px;"><span style="color:#888;">Affects: ' + s.who + '</span>' + (s.stackable ? '<span style="color:#66b3ff;">Stackable</span>' : '') + (s.decay && s.decay!=='None' ? '<span style="color:#aaa;" title="' + s.decay + '">Decays</span>' : '') + (s.rarity ? '<span style="color:' + rc + ';margin-left:auto;">' + s.rarity + '</span>' : '') + '</div></div></div>';
          }).join('')}
        </div>
      `;
    } else if (window.refSubtab === 'moves') {
      let data = REF_MOVES;
      if (searchTerm) data = data.filter(m => m.name.toLowerCase().includes(searchTerm) || m.desc.toLowerCase().includes(searchTerm));
      innerHtml = `
        <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:12px;overflow-y:auto;">
          ${data.map(m => {
            const rc = getRarityColor(m.rarity);
            return '<div style="background:rgba(0,0,0,0.35);border:1px solid #7ea8be44;border-left:3px solid #7ea8be;border-radius:8px;padding:12px;transition:transform 0.15s,box-shadow 0.15s;" onmouseover="this.style.transform=\'translateY(-2px)\';this.style.boxShadow=\'0 4px 12px rgba(0,0,0,0.5)\';" onmouseout="this.style.transform=\'\';this.style.boxShadow=\'\';"><div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;"><span style="font-size:14px;font-weight:bold;color:#c9d6e3;">' + m.name + '</span>' + (m.rarity ? '<span style="font-size:10px;color:' + rc + ';font-weight:bold;">' + m.rarity + '</span>' : '') + '</div><div style="font-size:11px;color:#ccc;line-height:1.5;margin-bottom:8px;">' + m.desc + '</div><div style="display:flex;gap:10px;flex-wrap:wrap;font-size:10px;color:#888;"><span>Target: <span style="color:#b8d4e8;">' + m.target + '</span></span>' + (m.scaling && m.scaling!=='N/A' ? '<span>Scales: <span style="color:#b8d4e8;">' + m.scaling + '</span></span>' : '') + '</div></div>';
          }).join('')}
        </div>
      `;
    } else if (window.refSubtab === 'addons') {
      let data = REF_ADDONS;
      if (searchTerm) data = data.filter(a => a.name.toLowerCase().includes(searchTerm) || (a.description || '').toLowerCase().includes(searchTerm));
      innerHtml = `
        <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:12px;overflow-y:auto;">
          ${data.map(a => '<div style="background:rgba(0,0,0,0.35);border:1px solid #b8860b44;border-left:3px solid #b8860b;border-radius:8px;padding:12px;transition:transform 0.15s,box-shadow 0.15s;" onmouseover="this.style.transform=\'translateY(-2px)\';this.style.boxShadow=\'0 4px 12px rgba(0,0,0,0.5)\';" onmouseout="this.style.transform=\'\';this.style.boxShadow=\'\';"><div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;"><span style="font-size:14px;font-weight:bold;color:#f0c040;">' + a.name + '</span><span style="font-size:10px;color:#888;">Attaches to: <span style="color:#d4b060;">' + (a.canBeAttachedTo || '') + '</span></span></div><div style="font-size:11px;color:#ccc;line-height:1.5;margin-bottom:6px;">' + (a.description || '') + '</div>' + (a.forms ? '<div style="font-size:10px;color:#888;">Forms: <span style="color:#c8a040;">' + a.forms + '</span></div>' : '') + '</div>').join('')}
        </div>
      `;
    }

    content.innerHTML = `
      <div style="flex:1;overflow-y:auto;padding:10px;display:flex;flex-direction:column;">
        <!-- Subtab buttons -->
        <div style="display:flex;gap:0;margin-bottom:0;border-bottom:2px solid #ff9800;">
          <button onclick="window.refSubtab='statuses';window.refTypeFilter='all';switchCollectionTab('statuses');" style="${subBtnStyle(window.refSubtab==='statuses')}">Statuses</button>
          <button onclick="window.refSubtab='moves';switchCollectionTab('statuses');" style="${subBtnStyle(window.refSubtab==='moves')}">Moves</button>
          <button onclick="window.refSubtab='addons';switchCollectionTab('statuses');" style="${subBtnStyle(window.refSubtab==='addons')}">Addons</button>
        </div>
        <!-- Search bar -->
        <div style="display:flex;gap:10px;margin:12px 0;padding:8px 12px;background:rgba(0,0,0,0.3);border-radius:8px;align-items:center;">
          <span style="color:#aaa;font-size:13px;">&#128269;</span>
          <input type="text" placeholder="Search..." value="${window.refSearch}"
            oninput="window.refSearch=this.value;switchCollectionTab('statuses');"
            style="flex:1;padding:6px 10px;background:rgba(0,0,0,0.3);border:1px solid #555;border-radius:6px;color:white;font-size:13px;outline:none;"
          />
        </div>
        ${innerHtml}
      </div>
    `;
  } else if (tab === 'spells') {
    // Initialize state
    if (!window.spellSortType) window.spellSortType = 'alphabetical';
    if (typeof window.spellsSearchTerm === 'undefined') window.spellsSearchTerm = '';
    if (typeof window.spellElementFilter === 'undefined') window.spellElementFilter = 'all';
    if (typeof window.spellSubTab === 'undefined') window.spellSubTab = 'spells';

    // Get rarity color function
    const getRarityColor = (rarity) => {
      const rarityLower = (rarity || '').toLowerCase();
      switch(rarityLower) {
        case 'rare': return '#9b59b6';
        case 'uncommon': return '#4CAF50';
        case 'common': return '#aaa';
        default: return '#888';
      }
    };

    // Get element color function
    const getElementColor = (element) => {
      switch((element || '').toLowerCase()) {
        case 'fire': return '#ff4444';
        case 'water': return '#4488ff';
        case 'earth': return '#88aa44';
        case 'dark': return '#8844aa';
        case 'blood': return '#cc2222';
        case 'poison': return '#44aa44';
        case 'electric': return '#ffcc00';
        default: return '#888';
      }
    };

    // Get spells and keywords data
    const spellsData = typeof SPELLS_DATA !== 'undefined' ? SPELLS_DATA : [];
    const keywordsData = typeof ADDONS_DATA !== 'undefined'
      ? Object.fromEntries(Object.entries(ADDONS_DATA).filter(([, v]) => v.canBeAttachedTo === 'Spell'))
      : (typeof SPELL_KEYWORDS_DATA !== 'undefined' ? SPELL_KEYWORDS_DATA : {});
    const searchTerm = window.spellsSearchTerm.toLowerCase();

    // Get unique elements for filter
    const elements = [...new Set(spellsData.map(s => s.element).filter(e => e && e !== 'N/A'))].sort();

    // Filter spells
    let filteredSpells = [...spellsData];

    // Filter by search
    if (searchTerm) {
      filteredSpells = filteredSpells.filter(s =>
        s.name.toLowerCase().includes(searchTerm) ||
        (s.description && s.description.toLowerCase().includes(searchTerm))
      );
    }

    // Filter by element
    if (window.spellElementFilter !== 'all') {
      if (window.spellElementFilter === 'none') {
        filteredSpells = filteredSpells.filter(s => !s.element || s.element === 'N/A');
      } else {
        filteredSpells = filteredSpells.filter(s => s.element === window.spellElementFilter);
      }
    }

    // Sort spells
    let sortedSpells;
    if (window.spellSortType === 'alphabetical') {
      sortedSpells = filteredSpells.sort((a, b) => a.name.localeCompare(b.name));
    } else if (window.spellSortType === 'rarity') {
      const rarityOrder = { 'rare': 3, 'uncommon': 2, 'common': 1 };
      sortedSpells = filteredSpells.sort((a, b) => {
        const rarityDiff = (rarityOrder[(b.rarity || '').toLowerCase()] || 0) - (rarityOrder[(a.rarity || '').toLowerCase()] || 0);
        return rarityDiff !== 0 ? rarityDiff : a.name.localeCompare(b.name);
      });
    } else if (window.spellSortType === 'element') {
      sortedSpells = filteredSpells.sort((a, b) => {
        const elemA = a.element || 'N/A';
        const elemB = b.element || 'N/A';
        return elemA.localeCompare(elemB) || a.name.localeCompare(b.name);
      });
    } else if (window.spellSortType === 'cost') {
      sortedSpells = filteredSpells.sort((a, b) => (a.cost || 0) - (b.cost || 0) || a.name.localeCompare(b.name));
    } else if (window.spellSortType === 'game') {
      sortedSpells = filteredSpells.sort((a, b) => (a.game || '').localeCompare(b.game || '') || a.name.localeCompare(b.name));
    } else {
      sortedSpells = filteredSpells.sort((a, b) => a.name.localeCompare(b.name));
    }

    // Build keywords array from the object
    const keywordsArray = Object.values(keywordsData);

    if (window.spellSubTab === 'keywords') {
      // Show keywords sub-tab
      content.innerHTML = `
        <div style="flex: 1; overflow-y: auto; padding: 10px; display: flex; flex-direction: column;">
          <!-- Sub-tab navigation -->
          <div style="display: flex; gap: 10px; margin-bottom: 15px; padding: 10px; background: rgba(0,0,0,0.3); border-radius: 8px; align-items: center;">
            <button onclick="window.spellSubTab = 'spells'; switchCollectionTab('spells');" style="padding: 8px 16px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 13px;">Spells (${spellsData.length})</button>
            <button onclick="window.spellSubTab = 'keywords'; switchCollectionTab('spells');" style="padding: 8px 16px; background: #9b59b6; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 13px;">Keywords (${keywordsArray.length})</button>
          </div>

          <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 15px; overflow-y: auto;">
            ${keywordsArray.map(kw => `
              <div style="
                background: rgba(0,0,0,0.3);
                border: 2px solid #9b59b6;
                border-radius: 8px;
                padding: 15px;
                display: flex;
                flex-direction: column;
                gap: 8px;
              ">
                <div style="font-size: 16px; font-weight: bold; color: #9b59b6;">${kw.name}</div>
                <div style="font-size: 13px; color: #ddd; line-height: 1.5;">${kw.description}</div>
              </div>
            `).join('')}
          </div>
        </div>
      `;
    } else {
      // Show spells sub-tab
      content.innerHTML = `
        <!-- Left side: Spell grid -->
        <div id="spells-grid-container" style="flex: 2; overflow-y: auto; padding: 10px; display: flex; flex-direction: column;">
          <!-- Sub-tab navigation -->
          <div style="display: flex; gap: 10px; margin-bottom: 10px; padding: 8px 10px; background: rgba(0,0,0,0.2); border-radius: 6px; align-items: center;">
            <button onclick="window.spellSubTab = 'spells'; switchCollectionTab('spells');" style="padding: 6px 14px; background: #9b59b6; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Spells (${spellsData.length})</button>
            <button onclick="window.spellSubTab = 'keywords'; switchCollectionTab('spells');" style="padding: 6px 14px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Keywords (${keywordsArray.length})</button>
          </div>

          <!-- Search, Sort and Filter controls -->
          <div style="display: flex; gap: 8px; margin-bottom: 15px; padding: 10px; background: rgba(0,0,0,0.3); border-radius: 8px; align-items: center; flex-wrap: wrap;">
            <span style="color: #aaa; font-size: 13px;">🔍</span>
            <input type="text" id="spells-search" placeholder="Search spells..." value="${window.spellsSearchTerm}"
              oninput="window.spellsSearchTerm = this.value; switchCollectionTab('spells');"
              style="flex: 1; min-width: 120px; padding: 6px 10px; background: rgba(0,0,0,0.3); border: 1px solid #555; border-radius: 6px; color: white; font-size: 12px; outline: none;"
            />
            <div style="border-left: 1px solid #555; height: 20px; margin: 0 3px;"></div>
            <span style="color: #aaa; font-size: 12px; font-weight: bold;">Sort:</span>
            <button onclick="window.spellSortType = 'alphabetical'; switchCollectionTab('spells');" style="padding: 5px 10px; background: ${window.spellSortType === 'alphabetical' ? '#9b59b6' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 11px;">A-Z</button>
            <button onclick="window.spellSortType = 'rarity'; switchCollectionTab('spells');" style="padding: 5px 10px; background: ${window.spellSortType === 'rarity' ? '#9b59b6' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 11px;">Rarity</button>
            <button onclick="window.spellSortType = 'cost'; switchCollectionTab('spells');" style="padding: 5px 10px; background: ${window.spellSortType === 'cost' ? '#9b59b6' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 11px;">Cost</button>
            <div style="border-left: 1px solid #555; height: 20px; margin: 0 3px;"></div>
            <span style="color: #aaa; font-size: 12px; font-weight: bold;">Element:</span>
            <select onchange="window.spellElementFilter = this.value; switchCollectionTab('spells');" style="padding: 5px 8px; background: #444; border: 1px solid #555; border-radius: 6px; color: white; font-size: 11px; cursor: pointer;">
              <option value="all" ${window.spellElementFilter === 'all' ? 'selected' : ''}>All</option>
              <option value="none" ${window.spellElementFilter === 'none' ? 'selected' : ''}>None</option>
              ${elements.map(elem => `<option value="${elem}" ${window.spellElementFilter === elem ? 'selected' : ''} style="color: ${getElementColor(elem)}">${elem}</option>`).join('')}
            </select>
            <span style="color: #666; font-size: 10px; margin-left: auto;">${sortedSpells.length} of ${spellsData.length}</span>
          </div>

          <div id="spells-grid" style="display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); gap: 10px; overflow-y: auto;">
            ${sortedSpells.map(spell => {
              const rarityColor = getRarityColor(spell.rarity);
              const elementColor = getElementColor(spell.element);
              return `
              <div
                class="collection-spell-card"
                data-spell-name="${spell.name.replace(/"/g, '&quot;')}"
                onclick="showSpellDetails('${spell.name.replace(/'/g, "\\'")}')"
                style="
                  background: rgba(0,0,0,0.3);
                  border: 2px solid ${rarityColor};
                  border-radius: 8px;
                  padding: 8px;
                  display: flex;
                  flex-direction: column;
                  align-items: center;
                  gap: 6px;
                  transition: transform 0.2s, box-shadow 0.2s;
                  cursor: pointer;
                "
                onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 6px 15px rgba(0,0,0,0.5)';"
                onmouseout="this.style.transform=''; this.style.boxShadow='';"
              >
                <img
                  src="${spell.imageUrl || spell.image || 'images/spells/no-spell.svg'}"
                  alt="${spell.name}"
                  style="
                    width: 80px;
                    height: 80px;
                    object-fit: contain;
                    border-radius: 6px;
                    background: rgba(0,0,0,0.2);
                    image-rendering: pixelated;
                  "
                  onerror="this.style.opacity='0.3';"
                />
                <div style="text-align: center; font-size: 11px; font-weight: bold; color: ${rarityColor}; word-wrap: break-word; width: 100%;">
                  ${spell.name}
                </div>
                <div style="display: flex; gap: 6px; justify-content: center; align-items: center;">
                  <span style="font-size: 10px; color: #66b3ff; font-weight: bold;">${spell.cost} Mana</span>
                  ${spell.element && spell.element !== 'N/A' ? `<span style="font-size: 9px; color: ${elementColor}; font-weight: bold;">${spell.element}</span>` : ''}
                </div>
                <div style="font-size: 9px; color: ${rarityColor}; text-align: center; text-transform: uppercase; font-weight: bold;">
                  ${spell.rarity}
                </div>
              </div>
            `;
            }).join('')}
          </div>
        </div>

        <!-- Right side: Spell details -->
        <div id="spell-details" style="flex: 1; overflow-y: auto; padding: 20px; background: rgba(0,0,0,0.2); border: 1px solid #444; border-radius: 8px; min-width: 300px;">
          <div style="text-align: center; color: #888; padding: 40px 20px;">
            <p>Click a spell to view details</p>
          </div>
        </div>
      `;
    }
  } else if (tab === 'events') {
    if (typeof window.eventSortType === 'undefined') window.eventSortType = 'alphabetical';
    if (typeof window.eventRarityFilter === 'undefined') window.eventRarityFilter = 'all';
    if (typeof window.eventTypeFilter === 'undefined') window.eventTypeFilter = 'all';
    if (typeof window.eventSearch === 'undefined') window.eventSearch = '';

    const allEvents = (typeof EVENTS_DATA !== 'undefined' ? EVENTS_DATA : []).filter(e => e.image);

    const getRarityColor = r => {
      switch ((r || '').toLowerCase()) {
        case 'legendary': return '#ff6b00';
        case 'rare':      return '#9b59b6';
        case 'uncommon':  return '#4CAF50';
        case 'common':    return '#aaa';
        default:          return '#888';
      }
    };

    const allTypes    = [...new Set(allEvents.map(e => e.type).filter(Boolean))].sort();
    const allRarities = ['Common', 'Uncommon', 'Rare', 'Legendary'].filter(r =>
      allEvents.some(e => (e.rarity || '').toLowerCase() === r.toLowerCase())
    );

    const searchTerm = (window.eventSearch || '').toLowerCase();
    let filtered = allEvents.filter(e => {
      if (window.eventRarityFilter !== 'all' && (e.rarity || '').toLowerCase() !== window.eventRarityFilter.toLowerCase()) return false;
      if (window.eventTypeFilter !== 'all' && (e.type || '') !== window.eventTypeFilter) return false;
      if (searchTerm && !e.name.toLowerCase().includes(searchTerm) && !(e.game || '').toLowerCase().includes(searchTerm) && !(e.tags || []).some(t => t.toLowerCase().includes(searchTerm))) return false;
      return true;
    });

    const rarityOrder = { legendary: 4, rare: 3, uncommon: 2, common: 1 };
    if (window.eventSortType === 'rarity') {
      filtered.sort((a, b) => {
        const rd = (rarityOrder[(b.rarity || '').toLowerCase()] || 0) - (rarityOrder[(a.rarity || '').toLowerCase()] || 0);
        return rd !== 0 ? rd : a.name.localeCompare(b.name);
      });
    } else if (window.eventSortType === 'game') {
      filtered.sort((a, b) => {
        const gd = (a.game || '').localeCompare(b.game || '');
        return gd !== 0 ? gd : a.name.localeCompare(b.name);
      });
    } else {
      filtered.sort((a, b) => a.name.localeCompare(b.name));
    }

    const btnStyle = (active, color) =>
      `padding:4px 10px;border:none;border-radius:12px;cursor:pointer;font-size:11px;font-weight:bold;` +
      `background:${active ? (color || '#c39bd3') : 'rgba(100,100,100,0.3)'};` +
      `color:${active ? '#fff' : '#ccc'};transition:background 0.15s;`;

    const rarityBadge = r => {
      const c = getRarityColor(r);
      return `<span style="font-size:10px;font-weight:bold;color:${c};padding:2px 6px;background:${c}22;border-radius:4px;white-space:nowrap;">${r || ''}</span>`;
    };

    const tagBadge = t =>
      `<span style="font-size:10px;padding:1px 6px;background:rgba(195,155,211,0.15);border:1px solid rgba(195,155,211,0.3);border-radius:10px;color:#c39bd3;">${t}</span>`;

    const pillList = (label, items, color) =>
      items && items.length
        ? `<div style="display:flex;flex-wrap:wrap;gap:4px;align-items:center;margin-top:4px;">
             <span style="font-size:10px;color:#888;flex-shrink:0;">${label}:</span>
             ${items.map(s => `<span style="font-size:10px;padding:1px 6px;background:${color}22;border:1px solid ${color}55;border-radius:10px;color:${color};">${s}</span>`).join('')}
           </div>`
        : '';

    content.innerHTML = `
      <div style="flex:1;overflow-y:auto;padding:10px;display:flex;flex-direction:column;">
        <!-- Controls bar -->
        <div style="display:flex;flex-wrap:wrap;gap:8px;margin-bottom:10px;padding:10px;background:rgba(0,0,0,0.3);border-radius:8px;align-items:center;">
          <span style="color:#aaa;font-size:13px;">🔍</span>
          <input type="text" id="event-search" placeholder="Search events…" value="${window.eventSearch}"
            oninput="window.eventSearch=this.value;switchCollectionTab('events');"
            style="flex:1;min-width:120px;padding:6px 10px;background:rgba(0,0,0,0.3);border:1px solid #555;border-radius:6px;color:white;font-size:13px;outline:none;"
          />
          <button onclick="window.eventSortType='alphabetical';switchCollectionTab('events');" style="${btnStyle(window.eventSortType==='alphabetical','#c39bd3')}">A–Z</button>
          <button onclick="window.eventSortType='rarity';switchCollectionTab('events');" style="${btnStyle(window.eventSortType==='rarity','#c39bd3')}">Rarity</button>
          <button onclick="window.eventSortType='game';switchCollectionTab('events');" style="${btnStyle(window.eventSortType==='game','#c39bd3')}">Game</button>
          <span style="color:#666;font-size:11px;margin-left:auto;">${filtered.length} / ${allEvents.length}</span>
        </div>
        <!-- Rarity filter -->
        ${allRarities.length > 1 ? `
        <div style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px;padding:7px 10px;background:rgba(0,0,0,0.25);border-radius:8px;align-items:center;">
          <span style="color:#888;font-size:11px;">Rarity:</span>
          <button style="${btnStyle(window.eventRarityFilter==='all','#c39bd3')}" onclick="window.eventRarityFilter='all';switchCollectionTab('events');">All</button>
          ${allRarities.map(r => `<button style="${btnStyle(window.eventRarityFilter===r,getRarityColor(r))}" onclick="window.eventRarityFilter='${r}';switchCollectionTab('events');">${r}</button>`).join('')}
        </div>` : ''}
        <!-- Type filter -->
        ${allTypes.length > 1 ? `
        <div style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:10px;padding:7px 10px;background:rgba(0,0,0,0.25);border-radius:8px;align-items:center;">
          <span style="color:#888;font-size:11px;">Type:</span>
          <button style="${btnStyle(window.eventTypeFilter==='all','#c39bd3')}" onclick="window.eventTypeFilter='all';switchCollectionTab('events');">All</button>
          ${allTypes.map(t => `<button style="${btnStyle(window.eventTypeFilter===t,'#c39bd3')}" onclick="window.eventTypeFilter='${t.replace(/'/g,"\\'")}';switchCollectionTab('events');">${t}</button>`).join('')}
        </div>` : ''}
        <!-- Event grid -->
        <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:12px;overflow-y:auto;">
          ${filtered.length === 0
            ? `<div style="grid-column:1/-1;text-align:center;color:#666;padding:40px;">No events match the current filters.</div>`
            : filtered.map(ev => {
                const rc = getRarityColor(ev.rarity);
                return `
                <div style="
                  background:rgba(0,0,0,0.35);
                  border:1px solid ${rc}55;
                  border-top:3px solid ${rc};
                  border-radius:8px;
                  overflow:hidden;
                  display:flex;flex-direction:column;
                  transition:transform 0.15s,box-shadow 0.15s;
                "
                onmouseover="this.style.transform='translateY(-3px)';this.style.boxShadow='0 6px 18px rgba(0,0,0,0.6)';"
                onmouseout="this.style.transform='';this.style.boxShadow='';">
                  <!-- Image -->
                  <div style="background:#0d0d1a;display:flex;align-items:center;justify-content:center;height:130px;overflow:hidden;">
                    <img src="${ev.image}" alt="${ev.name}"
                      onerror="this.style.opacity='0.2'"
                      style="max-height:130px;max-width:100%;object-fit:contain;image-rendering:-webkit-optimize-contrast;image-rendering:smooth;"
                    />
                  </div>
                  <!-- Info -->
                  <div style="padding:10px 12px;display:flex;flex-direction:column;gap:6px;flex:1;">
                    <!-- Name + rarity -->
                    <div style="display:flex;align-items:center;justify-content:space-between;gap:6px;">
                      <span style="font-size:14px;font-weight:bold;color:#eee;flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${ev.name}</span>
                      ${rarityBadge(ev.rarity)}
                    </div>
                    <!-- Game + type -->
                    <div style="display:flex;gap:6px;flex-wrap:wrap;align-items:center;">
                      ${ev.game ? `<span style="font-size:11px;color:#aaa;">${ev.game}</span>` : ''}
                      ${ev.type ? `<span style="font-size:10px;font-weight:bold;padding:2px 7px;border-radius:10px;background:rgba(195,155,211,0.15);border:1px solid rgba(195,155,211,0.35);color:#c39bd3;">${ev.type}</span>` : ''}
                    </div>
                    <!-- Inputs / Outputs -->
                    ${pillList('Inputs', ev.inputs, '#e67e22')}
                    ${pillList('Outputs', ev.outputs, '#2ecc71')}
                    <!-- Tags -->
                    ${ev.tags && ev.tags.length ? `
                    <div style="display:flex;flex-wrap:wrap;gap:4px;margin-top:2px;">
                      ${ev.tags.map(tagBadge).join('')}
                    </div>` : ''}
                  </div>
                </div>`;
              }).join('')
          }
        </div>
      </div>
    `;
  }

  // Restore focus after content update
  restoreFocus();
}

// Sort collection spells
function sortCollectionSpells(sortType) {
  window.spellSortType = sortType;
  switchCollectionTab('spells');
}

// Switch between loot sub-tabs
function switchLootSubTab(subTab, sortType = null) {
  window.currentLootSubTab = subTab;

  // Initialize or preserve sort type
  if (!window.currentFishSortType) {
    window.currentFishSortType = 'alphabetical';
  }
  if (sortType) {
    window.currentFishSortType = sortType;
  }

  // Update sub-tab buttons
  const _lootTabColors = { fish: '#66b3ff', scrolls: '#c39be0', potions: '#e07b7b' };
  ['fish', 'scrolls', 'potions'].forEach(t => {
    const btn = document.getElementById(`loot-subtab-${t}`);
    if (btn) btn.style.background = t === subTab ? (_lootTabColors[t] || '#66b3ff') : '#555';
  });

  const subTabContent = document.getElementById('loot-subtab-content');
  if (!subTabContent) return;

  if (subTab === 'fish') {
    // Get fish stats for catch counts
    const fishStats = getFishStats();

    // Sort fish based on current sort type
    let sortedFish;
    const currentSort = window.currentFishSortType;

    if (currentSort === 'rarity') {
      const rarityOrder = { 'Rare': 3, 'Uncommon': 2, 'Common': 1 };
      sortedFish = [...FISH_DATA].sort((a, b) => {
        const rarityDiff = (rarityOrder[b.rarity] || 0) - (rarityOrder[a.rarity] || 0);
        if (rarityDiff !== 0) return rarityDiff;
        return a.name.localeCompare(b.name);
      });
    } else if (currentSort === 'game') {
      sortedFish = [...FISH_DATA].sort((a, b) => {
        const gameDiff = a.game.localeCompare(b.game);
        if (gameDiff !== 0) return gameDiff;
        return a.name.localeCompare(b.name);
      });
    } else if (currentSort === 'caught') {
      sortedFish = [...FISH_DATA].sort((a, b) => {
        const aCount = (fishStats[a.name]?.caught || 0);
        const bCount = (fishStats[b.name]?.caught || 0);
        const countDiff = bCount - aCount;
        if (countDiff !== 0) return countDiff;
        return a.name.localeCompare(b.name);
      });
    } else {
      // Default: alphabetical
      sortedFish = [...FISH_DATA].sort((a, b) => a.name.localeCompare(b.name));
    }

    subTabContent.innerHTML = `
      <div style="padding: 10px;">
        <!-- Sorting controls -->
        <div style="display: flex; gap: 8px; margin-bottom: 15px; justify-content: center; flex-wrap: wrap;">
          <button onclick="switchLootSubTab('fish', 'alphabetical')" style="padding: 6px 12px; background: ${currentSort === 'alphabetical' ? '#66b3ff' : '#555'}; border: none; border-radius: 4px; color: white; cursor: pointer; font-size: 12px; font-weight: bold; transition: background 0.2s;">A-Z</button>
          <button onclick="switchLootSubTab('fish', 'rarity')" style="padding: 6px 12px; background: ${currentSort === 'rarity' ? '#66b3ff' : '#555'}; border: none; border-radius: 4px; color: white; cursor: pointer; font-size: 12px; font-weight: bold; transition: background 0.2s;">Rarity</button>
          <button onclick="switchLootSubTab('fish', 'game')" style="padding: 6px 12px; background: ${currentSort === 'game' ? '#66b3ff' : '#555'}; border: none; border-radius: 4px; color: white; cursor: pointer; font-size: 12px; font-weight: bold; transition: background 0.2s;">Game</button>
          <button onclick="switchLootSubTab('fish', 'caught')" style="padding: 6px 12px; background: ${currentSort === 'caught' ? '#66b3ff' : '#555'}; border: none; border-radius: 4px; color: white; cursor: pointer; font-size: 12px; font-weight: bold; transition: background 0.2s;"># Caught</button>
        </div>

        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 15px;">
          ${sortedFish.map(fish => {
            const stats = fishStats[fish.name] || { caught: 0, sizes: { Small: 0, Medium: 0, Large: 0 } };
            const caughtCount = stats.caught || 0;
            const sizes = stats.sizes || { Small: 0, Medium: 0, Large: 0 };

            let rarityColor = '#aaa';
            if (fish.rarity === 'Rare') rarityColor = '#ffd700';
            else if (fish.rarity === 'Uncommon') rarityColor = '#66ddff';
            else if (fish.rarity === 'Common') rarityColor = '#aaa';

            return `
              <div style="
                background: rgba(0,0,0,0.3);
                border: 2px solid ${rarityColor};
                border-radius: 8px;
                padding: 15px;
                display: flex;
                flex-direction: column;
                align-items: center;
                gap: 8px;
                transition: transform 0.2s, box-shadow 0.2s;
                position: relative;
              " onmouseover="this.style.transform='translateY(-5px)'; this.style.boxShadow='0 0 20px ${rarityColor}80';" onmouseout="this.style.transform=''; this.style.boxShadow='';">

                <!-- Caught count badge -->
                <div style="
                  position: absolute;
                  top: 10px;
                  right: 10px;
                  background: linear-gradient(135deg, #667eea, #764ba2);
                  border: 2px solid #fff;
                  border-radius: 50%;
                  width: 40px;
                  height: 40px;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  font-weight: bold;
                  font-size: 14px;
                  color: #fff;
                  box-shadow: 0 2px 8px rgba(0,0,0,0.3);
                ">
                  ${caughtCount}
                </div>

                <!-- Fish image -->
                <img
                  src="images/fish/${fish.image}.png"
                  alt="${fish.name}"
                  style="
                    width: 120px;
                    height: 120px;
                    object-fit: contain;
                    border-radius: 6px;
                  "
                  onerror="this.style.display='none';"
                />

                <!-- Fish name -->
                <div style="text-align: center; font-size: 14px; font-weight: bold; color: ${rarityColor}; word-wrap: break-word;">
                  ${fish.name}
                </div>

                <!-- Rarity -->
                <div style="font-size: 11px; color: ${rarityColor}; text-align: center; text-transform: uppercase; font-weight: bold;">
                  ${fish.rarity}
                </div>

                <!-- Game reference -->
                <div style="font-size: 10px; color: #888; text-align: center; font-style: italic;">
                  ${fish.game}
                </div>

                <!-- Location type -->
                <div style="font-size: 10px; color: #aaa; text-align: center;">
                  ${fish.type} Waters
                </div>

                <!-- Times caught text -->
                <div style="font-size: 11px; color: #ddd; text-align: center; margin-top: 5px; padding-top: 8px; border-top: 1px solid #444; width: 100%;">
                  ${caughtCount === 0 ? 'Not yet caught' : caughtCount === 1 ? 'Caught once' : `Caught ${caughtCount} times`}
                </div>

                <!-- Size breakdown -->
                ${caughtCount > 0 ? `
                  <div style="width: 100%; padding: 8px 0; border-top: 1px solid #444; display: flex; justify-content: space-around; font-size: 10px; color: #bbb;">
                    <div style="text-align: center;">
                      <div style="color: #88ff88; font-weight: bold;">S</div>
                      <div>${sizes.Small || 0}</div>
                    </div>
                    <div style="text-align: center;">
                      <div style="color: #ffdd88; font-weight: bold;">M</div>
                      <div>${sizes.Medium || 0}</div>
                    </div>
                    <div style="text-align: center;">
                      <div style="color: #ff8888; font-weight: bold;">L</div>
                      <div>${sizes.Large || 0}</div>
                    </div>
                  </div>
                ` : ''}
              </div>
            `;
          }).join('')}
        </div>
      </div>
    `;
  } else if (subTab === 'scrolls') {
    const scrolls = typeof SCROLLS_DATA !== 'undefined' ? SCROLLS_DATA : [];
    const rarityColor = (r) => {
      switch ((r || '').toLowerCase()) {
        case 'legendary': return '#ff6b00';
        case 'rare':      return '#9b59b6';
        case 'uncommon':  return '#4CAF50';
        default:          return '#aaa';
      }
    };
    subTabContent.innerHTML = `
      <div style="padding:10px;">
        <div style="display:grid; grid-template-columns:repeat(auto-fill,minmax(210px,1fr)); gap:14px;">
          ${scrolls.map(s => {
            const col = rarityColor(s.rarity);
            const imgPath = `images/scrolls/${s.file || s.name.replace(/\s+/g,'_')}.png`;
            return `
              <div style="background:rgba(0,0,0,0.35); border:2px solid ${col}; border-radius:8px; padding:14px; display:flex; flex-direction:column; align-items:center; gap:8px;">
                <img src="${imgPath}" alt="${s.name}" style="width:80px;height:80px;object-fit:contain;" onerror="this.style.display='none'">
                <div style="font-weight:bold;font-size:14px;color:${col};text-align:center;">${s.name}</div>
                <div style="font-size:11px;color:${col};font-weight:bold;text-transform:uppercase;">${s.rarity}</div>
                <div style="font-size:11px;color:#aaa;text-align:center;line-height:1.4;">${s.preference || ''}</div>
              </div>
            `;
          }).join('')}
        </div>
      </div>
    `;
  } else if (subTab === 'potions') {
    const potions = typeof POTIONS_DATA !== 'undefined' ? POTIONS_DATA : [];
    const rarityColor = (r) => {
      switch ((r || '').toLowerCase()) {
        case 'legendary': return '#ff6b00';
        case 'rare':      return '#9b59b6';
        case 'uncommon':  return '#4CAF50';
        default:          return '#aaa';
      }
    };
    subTabContent.innerHTML = `
      <div style="padding:10px;">
        <div style="display:grid; grid-template-columns:repeat(auto-fill,minmax(210px,1fr)); gap:14px;">
          ${potions.map(p => {
            const col = rarityColor(p.rarity);
            const imgPath = `images/potions/${p.file || p.name.replace(/\s+/g,'_')}.png`;
            return `
              <div style="background:rgba(0,0,0,0.35); border:2px solid ${col}; border-radius:8px; padding:14px; display:flex; flex-direction:column; align-items:center; gap:8px;">
                <img src="${imgPath}" alt="${p.name}" style="width:80px;height:80px;object-fit:contain;" onerror="this.style.display='none'">
                <div style="font-weight:bold;font-size:14px;color:${col};text-align:center;">${p.name}</div>
                <div style="font-size:11px;color:${col};font-weight:bold;text-transform:uppercase;">${p.rarity}</div>
                <div style="font-size:11px;color:#ccc;text-align:center;line-height:1.4;">${p.effect || ''}</div>
              </div>
            `;
          }).join('')}
        </div>
      </div>
    `;
  }
}

// Sort collection items
function sortCollectionItems(sortType) {
  // Get rarity color function (case-insensitive)
  const getRarityColor = (rarity) => {
    const rarityLower = (rarity || '').toLowerCase();
    switch(rarityLower) {
      case 'legendary': return '#ff6b00';
      case 'rare': return '#9b59b6';
      case 'uncommon': return '#4CAF50';
      case 'common': return '#aaa';
      default: return '#888';
    }
  };

  // Update sort button styles
  ['alpha', 'rarity', 'game'].forEach(type => {
    const btn = document.getElementById(`sort-${type}`);
    if (btn) {
      btn.style.background = type === sortType.substring(0, type.length) || (sortType === 'alphabetical' && type === 'alpha') ? '#ff9800' : '#555';
    }
  });

  // Filter N/A items if needed
  let filteredItems = window.itemsShowNA ? [...items] : items.filter(item => {
    const rarity = (item.rarity || '').toLowerCase();
    return rarity !== 'n/a';
  });

  let sortedItems;
  if (sortType === 'alphabetical') {
    sortedItems = filteredItems.sort((a, b) => a.name.localeCompare(b.name));
  } else if (sortType === 'rarity') {
    const rarityOrder = { 'legendary': 4, 'rare': 3, 'uncommon': 2, 'common': 1 };
    sortedItems = filteredItems.sort((a, b) => {
      const rarityDiff = (rarityOrder[(b.rarity || '').toLowerCase()] || 0) - (rarityOrder[(a.rarity || '').toLowerCase()] || 0);
      if (rarityDiff !== 0) return rarityDiff;
      return a.name.localeCompare(b.name);
    });
  } else if (sortType === 'game') {
    sortedItems = filteredItems.sort((a, b) => {
      const gameA = a.game || 'Unknown';
      const gameB = b.game || 'Unknown';
      const gameDiff = gameA.localeCompare(gameB);
      if (gameDiff !== 0) return gameDiff;
      return a.name.localeCompare(b.name);
    });
  }

  // Update the grid
  const grid = document.getElementById('items-grid');
  if (grid) {
    grid.innerHTML = sortedItems.map(item => {
      const rarityColor = getRarityColor(item.rarity);
      return `
        <div
          class="collection-item-card"
          data-item-name="${item.name.replace(/"/g, '&quot;')}"
          onclick="showItemDetails('${item.name.replace(/'/g, "\\'")}')"
          style="
            background: rgba(0,0,0,0.3);
            border: 2px solid ${rarityColor};
            border-radius: 8px;
            padding: 8px;
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 6px;
            transition: transform 0.2s, box-shadow 0.2s;
            cursor: pointer;
          "
          onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 6px 15px rgba(0,0,0,0.5)';"
          onmouseout="this.style.transform=''; this.style.boxShadow='';"
        >
          <img
            src="${item.image || 'images/items/no-item.svg'}"
            alt="${item.name}"
            style="
              width: 80px;
              height: 80px;
              object-fit: contain;
              border-radius: 6px;
              background: rgba(0,0,0,0.2);
              image-rendering: pixelated;
            "
            onerror="this.style.display='none';"
          />
          <div style="text-align: center; font-size: 11px; font-weight: bold; color: ${rarityColor}; word-wrap: break-word; width: 100%;">
            ${item.name}
          </div>
          <div style="font-size: 9px; color: ${rarityColor}; text-align: center; text-transform: uppercase; font-weight: bold;">
            ${item.rarity}
          </div>
        </div>
      `;
    }).join('');
  }
}

// Toggle N/A items visibility
function toggleItemsNA() {
  window.itemsShowNA = !window.itemsShowNA;
  switchCollectionTab('items');
}

// Sort enemies in collection
function sortEnemies(sortType) {
  window.enemySortType = sortType;
  switchCollectionTab('enemies');
}

// Switch between curse tiers (I, II, III)
function switchCurseTier(cardIndex, tier) {
  if (!window.allCurseData || !window.allCurseData[cardIndex]) {
    console.error('Curse data not found for card', cardIndex);
    return;
  }

  const tiersData = window.allCurseData[cardIndex];
  if (!tiersData[tier]) {
    console.error('Tier not found:', tier);
    return;
  }

  const curse = tiersData[tier];
  const detailsDiv = document.getElementById(`curse-${cardIndex}-details`);

  if (detailsDiv) {
    detailsDiv.innerHTML = `
      <div style="font-size: 11px; color: #9c27b0; text-align: center;">
        ${curse.stat} • ${curse.power}
      </div>
      <div style="font-size: 10px; color: #888; text-align: center;">
        ${curse.duration}
      </div>
      <div style="font-size: 10px; color: #aaa; text-align: center; line-height: 1.4; margin-top: 5px; padding-top: 8px; border-top: 1px solid #444;">
        ${curse.description}
      </div>
    `;
  }

  // Update tab button styles
  ['I', 'II', 'III'].forEach(t => {
    const tabBtn = document.getElementById(`curse-${cardIndex}-tab-${t}`);
    if (tabBtn) {
      const isActive = t === tier;
      tabBtn.style.background = isActive ? 'rgba(0,0,0,0.3)' : '#555';
      tabBtn.style.borderColor = isActive ? '#9c27b0' : '#444';
      tabBtn.style.borderBottomColor = isActive ? 'rgba(0,0,0,0.3)' : '#444';
      tabBtn.style.color = isActive ? '#9c27b0' : '#aaa';
    }
  });
}


/**
 * Get game stats from localStorage
 * @returns {Object} Game stats object with game names as keys
 */
function getGameStats() {
  return GameStorage.load(STORAGE_KEYS.GAME_STATS, {});
}

/**
 * Save game stats to localStorage
 * @param {Object} stats - Game stats object
 */
function saveGameStats(stats) {
  const result = GameStorage.save(STORAGE_KEYS.GAME_STATS, stats);
  if (!result.success) {
    console.error('Error saving game stats:', result.error);
  }
}

/**
 * Increment beaten count for a game
 * @param {string} gameName - Name of the game
 * @param {boolean} hasAmulet - Whether this was an amulet game
 */
function incrementGameBeaten(gameName, hasAmulet = false) {
  const stats = getGameStats();

  if (!stats[gameName]) {
    stats[gameName] = { beaten: 0, amulets: 0 };
  }

  stats[gameName].beaten = (stats[gameName].beaten || 0) + 1;

  if (hasAmulet) {
    stats[gameName].amulets = (stats[gameName].amulets || 0) + 1;
  }

  saveGameStats(stats);

}

// ===== FISH STATS TRACKING SYSTEM =====

/**
 * Get fish stats from localStorage
 * @returns {Object} Fish stats object with fish names as keys
 */
function getFishStats() {
  return GameStorage.load(STORAGE_KEYS.FISH_STATS, {});
}

/**
 * Save fish stats to localStorage
 * @param {Object} stats - Fish stats object
 */
function saveFishStats(stats) {
  const result = GameStorage.save(STORAGE_KEYS.FISH_STATS, stats);
  if (!result.success) {
    console.error('Error saving fish stats:', result.error);
  }
}

/**
 * Increment caught count for a fish
 * @param {string} fishName - Name of the fish
 * @param {string} size - Size of the fish (Small, Medium, or Large)
 */
function incrementFishCaught(fishName, size = 'Medium') {
  const stats = getFishStats();

  if (!stats[fishName]) {
    stats[fishName] = {
      caught: 0,
      sizes: {
        Small: 0,
        Medium: 0,
        Large: 0
      }
    };
  }

  // Initialize sizes if missing (for backward compatibility)
  if (!stats[fishName].sizes) {
    stats[fishName].sizes = {
      Small: 0,
      Medium: 0,
      Large: 0
    };
  }

  stats[fishName].caught = (stats[fishName].caught || 0) + 1;
  stats[fishName].sizes[size] = (stats[fishName].sizes[size] || 0) + 1;

  saveFishStats(stats);

}

/**
 * Show game details in the collection panel
 * @param {string} gameName - Name of the game to show details for
 */
function showGameDetails(gameName) {
  const game = games.find(g => g.name === gameName);
  if (!game) return;

  const stats = getGameStats();
  const gameStats = stats[gameName] || { beaten: 0 };

  // Get influenced by and influences lists
  const influencedBy = getInfluencedByGames(gameName);
  const influences = game.gamesInfluenced || [];

  const detailsPanel = document.getElementById('game-details');
  if (!detailsPanel) return;

  let connectionsHTML = '';

  if (influencedBy.length > 0) {
    connectionsHTML += `
      <div style="margin-top: 15px;">
        <strong style="color: #4CAF50;">Influenced By:</strong>
        <div style="margin-top: 8px; display: grid; grid-template-columns: repeat(2, 1fr); gap: 5px;">
          ${influencedBy.map(g => `
            <div style="font-size: 11px; padding: 5px 8px; background: rgba(76, 175, 80, 0.1);
              border: 1px solid rgba(76, 175, 80, 0.3); border-radius: 4px; color: #ddd;">
              ${g}
            </div>
          `).join('')}
        </div>
      </div>`;
  }

  if (influences.length > 0) {
    connectionsHTML += `
      <div style="margin-top: 15px;">
        <strong style="color: #9b59b6;">Influenced:</strong>
        <div style="margin-top: 8px; display: grid; grid-template-columns: repeat(2, 1fr); gap: 5px;">
          ${influences.map(g => `
            <div style="font-size: 11px; padding: 5px 8px; background: rgba(155, 89, 182, 0.1);
              border: 1px solid rgba(155, 89, 182, 0.3); border-radius: 4px; color: #ddd;">
              ${g}
            </div>
          `).join('')}
        </div>
      </div>`;
  }

  detailsPanel.innerHTML = `
    <div style="display: flex; flex-direction: column; gap: 15px;">
      <!-- Game Info -->
      <div>
        <h3 style="margin: 0 0 10px 0; color: #ff9800;">${game.name}</h3>
        <div style="color: #aaa; font-size: 13px; line-height: 1.6;">
          <div><strong>Release Year:</strong> ${game.year || '—'}</div>
          <div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;">
            <strong>Type:</strong>
            ${game.type ? `<span style="font-size:11px;font-weight:bold;padding:2px 8px;border-radius:10px;background:rgba(255,152,0,0.18);border:1px solid rgba(255,152,0,0.45);color:#ff9800;cursor:pointer;"
              onclick="window.gamesTypeFilter=${JSON.stringify(game.type)}; switchCollectionTab('games');"
              title="Filter by ${game.type}">${game.type}</span>` : '—'}
          </div>
        </div>
      </div>

      <!-- Tags -->
      ${game.tags && game.tags.length > 0 ? `
        <div style="padding:10px 12px;background:rgba(155,89,182,0.08);border:1px solid rgba(155,89,182,0.25);border-radius:8px;">
          <div style="font-size:11px;font-weight:bold;color:#9b59b6;margin-bottom:8px;">🏷 Tags</div>
          <div style="display:flex;flex-wrap:wrap;gap:6px;">
            ${game.tags.map(tag => `
              <span style="font-size:11px;padding:3px 10px;border-radius:12px;background:rgba(155,89,182,0.18);border:1px solid rgba(155,89,182,0.4);color:#ba68c8;cursor:pointer;font-weight:bold;"
                onclick="window.gamesTagFilter=${JSON.stringify(tag)}; switchCollectionTab('games');"
                title="Filter by tag: ${tag}">${tag}</span>
            `).join('')}
          </div>
        </div>
      ` : ''}

      <!-- Tracked Stats -->
      <div style="padding: 12px; background: rgba(255, 152, 0, 0.1); border: 1px solid rgba(255, 152, 0, 0.3); border-radius: 6px;">
        <h4 style="margin: 0 0 8px 0; color: #ff9800; font-size: 14px;">📊 Tracked Stats</h4>
        <div style="font-size: 13px; color: #ddd; line-height: 1.8;">
          <div><strong>Beaten:</strong> ${gameStats.beaten}</div>
          ${gameStats.amulets > 0 ? `<div><strong>Amulets Collected:</strong> ${gameStats.amulets}</div>` : ''}
        </div>
      </div>

      <!-- Connections -->
      ${connectionsHTML}
    </div>
  `;

  // Highlight the selected card in the grid
  document.querySelectorAll('.collection-game-card').forEach(card => {
    const isSel = card.dataset.gameName === gameName;
    card.classList.toggle('game-selected', isSel);
    card.style.borderColor = isSel ? '#ff9800' : '#444';
    card.style.background  = isSel ? 'rgba(255,152,0,0.1)' : 'rgba(0,0,0,0.3)';
  });
}

function showEnemyDetails(enemyName) {
  const enemy = enemies.find(e => e.name === enemyName);
  if (!enemy) return;

  const enemyStats = getEnemyStats(enemyName);
  const variants = enemies.filter(e => e.variantOf === enemyName);

  const getDifficultyColor = (d) => {
    switch((d||'').toLowerCase()) {
      case 'low': return '#4CAF50'; case 'medium': return '#ff9800';
      case 'high': return '#f44336'; case 'boss': return '#9b59b6';
      default: return '#888';
    }
  };
  const getTypeColor = (t) => {
    switch((t||'').toLowerCase()) {
      case 'strength': return '#f44336'; case 'dexterity': return '#4CAF50';
      case 'intelligence': return '#2196F3'; case 'charisma': return '#ff9800';
      default: return '#888';
    }
  };

  const diffColor = getDifficultyColor(enemy.difficulty);
  const typeColor = getTypeColor(enemy.type);

  const detailsPanel = document.getElementById('enemy-details');
  if (!detailsPanel) return;

  // Build variant forms HTML
  let variantHTML = '';
  if (variants.length > 0) {
    const allForms = [enemy, ...variants];
    variantHTML = '<div style="margin-top:15px;"><strong style="color:#9b59b6;">Forms:</strong><div style="display:flex;gap:8px;margin-top:8px;flex-wrap:wrap;">' +
      allForms.map((form, idx) =>
        '<div onclick="switchEnemyForm(\'' + form.name.replace(/'/g, "\\'") + '\')" style="cursor:pointer;padding:5px;border:2px solid ' + (idx===0?'#9b59b6':'#444') + ';border-radius:6px;background:rgba(0,0,0,0.3);transition:border-color 0.2s;" onmouseover="this.style.borderColor=\'#9b59b6\'" onmouseout="this.style.borderColor=\'' + (idx===0?'#9b59b6':'#444') + '\'">' +
          '<img src="' + (form.imageUrl || getEnemyImagePath(form.name)) + '" alt="' + form.name + '" style="width:50px;height:50px;object-fit:contain;" onerror="this.style.opacity=\'0.3\'"/>' +
          '<div style="font-size:9px;text-align:center;color:#aaa;margin-top:3px;">' + form.name + '</div></div>'
      ).join('') +
    '</div></div>';
  }

  // Build pattern HTML — parse "Turn X: A | Turn Y: B | Next: C" or "Always: A / B"
  let patternHTML = '';
  if (enemy.pattern) {
    const renderPatternStep = (step) => {
      // Determine intent icon based on keywords
      const s = step.toLowerCase();
      let icon = '?', color = '#888';
      if (s.includes('dmg') || s.includes('pain') || s.includes('assassinate')) { icon = '⚔'; color = '#f44336'; }
      else if (s.includes('block')) { icon = '🛡'; color = '#5b9bd5'; }
      else if (s.includes('heal') || s.includes('regenerat')) { icon = '💚'; color = '#4CAF50'; }
      else if (s.includes('ritual') || s.includes('power') || s.includes('get ') || s.includes('inflict') || s.includes('burn') || s.includes('poison') || s.includes('vulnerable') || s.includes('weak') || s.includes('stun') || s.includes('confused') || s.includes('ruptured')) { icon = '✦'; color = '#ff9800'; }
      else if (s.includes('spawn') || s.includes('alter') || s.includes('consume') || s.includes('steal') || s.includes('add ')) { icon = '◈'; color = '#9b59b6'; }
      else if (s.includes('unknown') || s.includes('charging') || s.includes('wandering')) { icon = '?'; color = '#888'; }
      return '<div style="display:flex;align-items:flex-start;gap:8px;padding:6px 8px;background:rgba(0,0,0,0.2);border-left:3px solid ' + color + ';border-radius:0 5px 5px 0;margin-bottom:4px;">' +
        '<span style="font-size:14px;flex-shrink:0;">' + icon + '</span>' +
        '<span style="font-size:11px;color:#ddd;line-height:1.5;">' + step.trim() + '</span></div>';
    };

    // Split on " | " for turn-based or use "/" for probability within a phase
    const phases = enemy.pattern.split(' | ');
    patternHTML = '<div id="enemy-pattern-section" style="margin-top:12px;"><strong style="color:#f44336;font-size:13px;">Pattern:</strong>' +
      '<div style="margin-top:8px;font-size:11px;color:#bbb;font-style:italic;margin-bottom:6px;">' + enemy.pattern + '</div>';

    if (phases.length > 1) {
      // Turn-based: render each phase
      patternHTML += '<div style="display:flex;flex-direction:column;gap:4px;">';
      phases.forEach(phase => {
        const colonIdx = phase.indexOf(':');
        if (colonIdx !== -1) {
          const label = phase.slice(0, colonIdx).trim();
          const actions = phase.slice(colonIdx + 1).trim();
          patternHTML += '<div style="margin-bottom:4px;"><span style="color:#ff9800;font-size:10px;font-weight:bold;text-transform:uppercase;">' + label + ':</span>';
          actions.split('/').forEach(act => { patternHTML += renderPatternStep(act.trim()); });
          patternHTML += '</div>';
        } else {
          phase.split('/').forEach(act => { patternHTML += renderPatternStep(act.trim()); });
        }
      });
      patternHTML += '</div>';
    } else {
      // Single phase (Always: ... / ...)
      const colonIdx = enemy.pattern.indexOf(':');
      const actions = colonIdx !== -1 ? enemy.pattern.slice(colonIdx + 1) : enemy.pattern;
      patternHTML += '<div style="display:flex;flex-direction:column;gap:4px;">';
      actions.split('/').forEach(act => { patternHTML += renderPatternStep(act.trim()); });
      patternHTML += '</div>';
    }
    patternHTML += '</div>';
  }

  detailsPanel.innerHTML = `
    <div style="display:flex;flex-direction:column;gap:12px;">
      <!-- Header -->
      <div style="display:flex;gap:12px;align-items:flex-start;">
        <img id="enemy-detail-image"
          src="${enemy.imageUrl || getEnemyImagePath(enemy.name)}"
          alt="${enemy.name}"
          style="width:110px;height:110px;object-fit:contain;border-radius:8px;background:rgba(0,0,0,0.3);border:2px solid ${diffColor};image-rendering:pixelated;"
          onerror="this.style.opacity='0.3'"
        />
        <div style="flex:1;">
          <h3 style="margin:0 0 8px 0;color:#f44336;">${enemy.name}</h3>
          <div style="font-size:12px;color:#aaa;line-height:1.9;">
            <div><strong>Type:</strong> <span style="color:${typeColor};">${enemy.type || '—'}</span></div>
            <div><strong>Difficulty:</strong> <span style="color:${diffColor};">${enemy.difficulty || '—'}</span></div>
            <div><strong>HP:</strong> ${enemy.hpMin != null ? (enemy.hpMin === enemy.hpMax ? enemy.hpMin : enemy.hpMin + '–' + enemy.hpMax) : (enemy.hp || '—')}</div>
            <div><strong>Game:</strong> ${enemy.game || '—'}</div>
            <div><strong>Location:</strong> ${enemy.location || '—'}</div>
            ${enemy.tag ? `<div style="margin-top:4px;"><span style="font-size:11px;font-weight:bold;padding:2px 8px;border-radius:10px;background:rgba(155,89,182,0.18);border:1px solid rgba(155,89,182,0.4);color:#ba68c8;cursor:pointer;"
              onclick="window.enemyTagFilter=${JSON.stringify(enemy.tag)}; switchCollectionTab('enemies');"
              title="Filter by tag: ${enemy.tag}">${enemy.tag}</span></div>` : ''}
          </div>
        </div>
      </div>

      <!-- Ability -->
      ${enemy.ability && enemy.ability !== 'N/A' ? `
        <div style="padding:10px 12px;background:rgba(155,89,182,0.1);border:1px solid rgba(155,89,182,0.3);border-radius:6px;">
          <div style="font-size:12px;font-weight:bold;color:#9b59b6;margin-bottom:4px;">⚡ Ability</div>
          <div style="font-size:12px;color:#ddd;">${enemy.ability}</div>
        </div>
      ` : ''}

      <!-- Pattern -->
      ${patternHTML}

      <!-- Combat Stats -->
      <div style="padding:10px 12px;background:rgba(244,67,54,0.08);border:1px solid rgba(244,67,54,0.2);border-radius:6px;">
        <div style="font-size:12px;font-weight:bold;color:#f44336;margin-bottom:4px;">📊 Combat Record</div>
        <div style="font-size:12px;color:#ddd;line-height:1.8;">
          <div>Defeated: ${enemyStats.timesBeaten || 0}x</div>
          <div>Killed Player: ${enemyStats.timesKilledPlayer || 0}x</div>
        </div>
      </div>

      <!-- Variants -->
      ${variantHTML}
    </div>
  `;
}

// Switch enemy form in details panel (for variants) — updates image and pattern
function switchEnemyForm(enemyName) {
  const enemy = enemies.find(e => e.name === enemyName);
  if (!enemy) return;

  const img = document.getElementById('enemy-detail-image');
  if (img) img.src = enemy.imageUrl || getEnemyImagePath(enemy.name);

  const patternContainer = document.getElementById('enemy-pattern-section');
  if (patternContainer && enemy.pattern) {
    patternContainer.querySelector('div:nth-child(2)').textContent = enemy.pattern;
  }
}

/**
 * Show item details in the collection panel
 * @param {string} itemName - Name of the item to show details for
 */
function showItemDetails(itemName) {
  const item = items.find(i => i.name === itemName);
  if (!item) return;

  const detailsPanel = document.getElementById('item-details');
  if (!detailsPanel) return;

  // Get rarity color
  const getRarityColor = (rarity) => {
    const rarityLower = (rarity || '').toLowerCase();
    switch(rarityLower) {
      case 'legendary': return '#ff6b00';
      case 'rare': return '#9b59b6';
      case 'uncommon': return '#4CAF50';
      case 'common': return '#aaa';
      default: return '#888';
    }
  };

  // Get type color
  const getTypeColor = (type) => {
    const typeLower = (type || '').toLowerCase();
    switch(typeLower) {
      case 'weapon': return '#f44336';
      case 'passive': return '#4CAF50';
      case 'consumable': return '#2196F3';
      case 'active': return '#ff9800';
      case 'boon': return '#9b59b6';
      default: return '#888';
    }
  };

  const rarityColor = getRarityColor(item.rarity);
  const typeColor = getTypeColor(item.type);

  // Build tags HTML
  const tagsHTML = item.tags && item.tags.length > 0 ? `
    <div style="margin-top: 15px;">
      <strong style="color: #9b59b6;">Tags:</strong>
      <div style="display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px;">
        ${item.tags.map(tag => `
          <span style="
            font-size: 11px;
            padding: 4px 10px;
            background: rgba(155, 89, 182, 0.15);
            border: 1px solid rgba(155, 89, 182, 0.4);
            border-radius: 12px;
            color: #ba68c8;
          ">${tag}</span>
        `).join('')}
      </div>
    </div>
  ` : '';

  // Look up weapon dice from WEAPONS_DATA if this is a weapon
  let weaponDice = null;
  if (item.type === 'Weapon' && typeof WEAPONS_DATA !== 'undefined') {
    const weaponData = WEAPONS_DATA.find(w => w.name === item.name);
    if (weaponData && weaponData.dice) {
      weaponDice = weaponData.dice;
    }
  }

  // Build dice HTML for weapons
  const diceHTML = weaponDice && weaponDice.length > 0 ? `
    <div style="margin-top: 15px;">
      <strong style="color: #f44336;">Weapon Dice:</strong>
      <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-top: 8px;">
        ${weaponDice.map((face, idx) => {
          if (face.isBlank) {
            return `
              <div style="
                background: rgba(0,0,0,0.4);
                border: 1px solid #333;
                border-radius: 6px;
                padding: 8px;
                text-align: center;
                font-size: 11px;
                color: #666;
              ">
                <div style="font-weight: bold; color: #444;">Face ${idx + 1}</div>
                <div>Blank</div>
              </div>
            `;
          }
          return `
            <div style="
              background: rgba(244, 67, 54, 0.1);
              border: 1px solid rgba(244, 67, 54, 0.3);
              border-radius: 6px;
              padding: 8px;
              text-align: center;
              font-size: 11px;
              color: #ddd;
            ">
              <div style="font-weight: bold; color: #f44336; margin-bottom: 4px;">Face ${idx + 1}</div>
              <div>${face.raw || face.effects?.map(e => e.raw).join(', ') || '—'}</div>
            </div>
          `;
        }).join('')}
      </div>
    </div>
  ` : '';

  detailsPanel.innerHTML = `
    <div style="display: flex; flex-direction: column; gap: 15px;">
      <!-- Item Header -->
      <div style="display: flex; gap: 15px; align-items: flex-start;">
        <img
          src="${item.image || 'images/items/no-item.svg'}"
          alt="${item.name}"
          style="width: 120px; height: 120px; object-fit: contain; border-radius: 8px; background: rgba(0,0,0,0.3); border: 2px solid ${rarityColor}; image-rendering: pixelated;"
          onerror="this.style.opacity='0.3'"
        />
        <div style="flex: 1;">
          <h3 style="margin: 0 0 10px 0; color: ${rarityColor};">${item.name}</h3>
          <div style="color: #aaa; font-size: 13px; line-height: 1.8;">
            <div><strong>Rarity:</strong> <span style="color: ${rarityColor}; text-transform: uppercase; font-weight: bold;">${item.rarity || '—'}</span></div>
            <div><strong>Type:</strong> <span style="color: ${typeColor};">${item.type || '—'}</span></div>
            <div><strong>Game:</strong> ${item.game || '—'}</div>
          </div>
        </div>
      </div>

      <!-- Description -->
      <div style="padding: 12px; background: rgba(${rarityColor === '#ff6b00' ? '255,107,0' : rarityColor === '#9b59b6' ? '155,89,182' : rarityColor === '#4CAF50' ? '76,175,80' : '170,170,170'}, 0.1); border: 1px solid ${rarityColor}40; border-radius: 6px;">
        <h4 style="margin: 0 0 8px 0; color: ${rarityColor}; font-size: 14px;">📜 Description</h4>
        <div style="font-size: 13px; color: #ddd; line-height: 1.6;">${item.description || 'No description available.'}</div>
      </div>

      <!-- Unlock Condition -->
      ${item.unlockCondition && item.unlockCondition !== 'N/A' ? `
        <div style="padding: 12px; background: rgba(255, 152, 0, 0.1); border: 1px solid rgba(255, 152, 0, 0.3); border-radius: 6px;">
          <h4 style="margin: 0 0 8px 0; color: #ff9800; font-size: 14px;">🔓 Unlock Condition</h4>
          <div style="font-size: 13px; color: #ddd;">${item.unlockCondition}</div>
        </div>
      ` : ''}

      <!-- Tags -->
      ${tagsHTML}

      <!-- Dice (for weapons) -->
      ${diceHTML}

      <!-- Weapon Card (for weapons, show card render from CARDS_DATA) -->
      ${(() => {
        if ((item.type || '').toLowerCase() !== 'weapon') return '';
        const allCards = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA : [];
        const card = allCards.find(c => c.name === item.name && c.tags && c.tags.includes('weapon'));
        if (!card) return '';
        const getRarityColorC = (r) => {
          switch((r||'').toLowerCase()) {
            case 'legendary': return '#ff6b00'; case 'rare': return '#9b59b6';
            case 'uncommon': return '#4CAF50'; case 'common': return '#aaa';
            case 'starter': return '#2196F3'; default: return '#666';
          }
        };
        const rc = getRarityColorC(card.rarity);
        const tc = typeColor; // reuse weapon red
        return `
          <div style="margin-top:5px;">
            <div style="font-size:12px;font-weight:bold;color:#f44336;margin-bottom:8px;">🃏 Weapon Card</div>
            <div style="border:2px solid ${rc};border-radius:12px;background:rgba(10,10,15,0.9);box-shadow:0 0 12px ${rc}55;overflow:hidden;max-width:220px;margin:0 auto;position:relative;">
              <div style="position:absolute;top:8px;left:8px;width:26px;height:26px;border-radius:50%;background:${tc};border:2px solid rgba(255,255,255,0.35);display:flex;align-items:center;justify-content:center;font-size:13px;font-weight:bold;color:white;z-index:2;">
                ${card.cost !== null && card.cost !== undefined ? card.cost : '?'}
              </div>
              ${card.imageUrl
                ? '<img src="' + card.imageUrl + '" alt="' + card.name + '" style="width:100%;height:160px;object-fit:contain;background:rgba(0,0,0,0.3);display:block;" onerror="this.style.display=\'none\'"/>'
                : '<div style="width:100%;height:160px;background:rgba(244,67,54,0.15);display:flex;align-items:center;justify-content:center;font-size:48px;color:#f4433688;">⚔</div>'
              }
              <div style="padding:10px;">
                <div style="font-size:14px;font-weight:bold;color:#eee;margin-bottom:4px;">${card.name}</div>
                <div style="display:flex;gap:8px;margin-bottom:8px;">
                  <span style="font-size:10px;color:${tc};text-transform:uppercase;font-weight:bold;">${card.type||''}</span>
                  <span style="font-size:10px;color:${rc};text-transform:uppercase;">${card.rarity||''}</span>
                </div>
                <div style="font-size:12px;color:#ddd;line-height:1.5;">${card.description||'No description.'}</div>
              </div>
            </div>
            ${card.canUpgrade && card.upgradedDescription ? `
              <div style="margin-top:8px;padding:10px 12px;background:rgba(255,152,0,0.1);border:1px solid rgba(255,152,0,0.3);border-radius:8px;max-width:220px;margin-left:auto;margin-right:auto;">
                <div style="font-size:11px;font-weight:bold;color:#ff9800;margin-bottom:6px;">✦ Upgraded</div>
                <div style="font-size:11px;color:#ccc;line-height:1.5;">${card.upgradedDescription}</div>
              </div>` : ''}
          </div>`;
      })()}

      <!-- Keywords -->
      ${(() => {
        const allText = (item.description || '').toLowerCase();
        const statusData = typeof STATUSES_DATA !== 'undefined' ? STATUSES_DATA : {};
        const addonData  = typeof ADDONS_DATA  !== 'undefined' ? ADDONS_DATA  : {};
        const matchedStatuses = Object.values(statusData).filter(s =>
          new RegExp(`\\b${s.name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')}\\b`, 'i').test(allText)
        );
        const matchedAddons = Object.values(addonData).filter(a =>
          new RegExp(`\\b${a.name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')}\\b`, 'i').test(allText)
        );
        if (matchedStatuses.length === 0 && matchedAddons.length === 0) return '';
        const statusColor = s => s.preference === 'Positive' ? '#4CAF50' : s.preference === 'Negative' ? '#e74c3c' : '#888';
        const statusBadge = s => `
          <div style="display:flex;align-items:flex-start;gap:8px;padding:7px 9px;background:rgba(0,0,0,0.35);border:1px solid ${statusColor(s)}44;border-radius:7px;">
            ${s.imageUrl ? `<img src="${s.imageUrl}" style="width:22px;height:22px;object-fit:contain;flex-shrink:0;border-radius:3px;" onerror="this.style.display='none'">` : `<span style="font-size:16px;line-height:1;flex-shrink:0;">${s.preference==='Positive'?'🟢':s.preference==='Negative'?'🔴':'⚪'}</span>`}
            <div>
              <div style="font-size:11px;font-weight:bold;color:${statusColor(s)};">${s.name}</div>
              <div style="font-size:10px;color:#aaa;line-height:1.35;">${s.description}</div>
            </div>
          </div>`;
        const addonBadge = a => `
          <div style="display:flex;align-items:flex-start;gap:8px;padding:7px 9px;background:rgba(0,0,0,0.35);border:1px solid #9b59b644;border-radius:7px;">
            <span style="font-size:16px;line-height:1;flex-shrink:0;">🔷</span>
            <div>
              <div style="font-size:11px;font-weight:bold;color:#9b59b6;">${a.name}</div>
              <div style="font-size:10px;color:#aaa;line-height:1.35;">${a.description}</div>
            </div>
          </div>`;
        return `
          <div style="display:flex;flex-direction:column;gap:5px;">
            <div style="font-size:11px;font-weight:bold;color:#aaa;margin-bottom:2px;">Keywords</div>
            ${matchedStatuses.map(statusBadge).join('')}
            ${matchedAddons.map(addonBadge).join('')}
          </div>`;
      })()}
    </div>
  `;
}

function showSpellDetails(spellName) {
  const spellsData = typeof SPELLS_DATA !== 'undefined' ? SPELLS_DATA : [];
  const spell = spellsData.find(s => s.name === spellName);
  if (!spell) return;

  const detailsPanel = document.getElementById('spell-details');
  if (!detailsPanel) return;

  // Get rarity color
  const getRarityColor = (rarity) => {
    const rarityLower = (rarity || '').toLowerCase();
    switch(rarityLower) {
      case 'rare': return '#9b59b6';
      case 'uncommon': return '#4CAF50';
      case 'common': return '#aaa';
      default: return '#888';
    }
  };

  // Get element color
  const getElementColor = (element) => {
    switch((element || '').toLowerCase()) {
      case 'fire': return '#ff4444';
      case 'water': return '#4488ff';
      case 'earth': return '#88aa44';
      case 'dark': return '#8844aa';
      case 'blood': return '#cc2222';
      case 'poison': return '#44aa44';
      case 'electric': return '#ffcc00';
      default: return '#888';
    }
  };

  const rarityColor = getRarityColor(spell.rarity);
  const elementColor = getElementColor(spell.element);

  // Build keywords HTML
  const keywordsHTML = spell.keywords && spell.keywords.length > 0 ? `
    <div style="margin-top: 15px;">
      <strong style="color: #9b59b6;">Keywords:</strong>
      <div style="display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px;">
        ${spell.keywords.map(keyword => `
          <span style="
            font-size: 11px;
            padding: 4px 10px;
            background: rgba(155, 89, 182, 0.15);
            border: 1px solid rgba(155, 89, 182, 0.4);
            border-radius: 12px;
            color: #ba68c8;
          ">${keyword}</span>
        `).join('')}
      </div>
    </div>
  ` : '';

  detailsPanel.innerHTML = `
    <div style="display: flex; flex-direction: column; gap: 15px;">
      <!-- Spell Header -->
      <div style="display: flex; gap: 15px; align-items: flex-start;">
        <img
          src="${spell.imageUrl || spell.image || 'images/spells/no-spell.svg'}"
          alt="${spell.name}"
          style="width: 120px; height: 120px; object-fit: contain; border-radius: 8px; background: rgba(0,0,0,0.3); border: 2px solid ${rarityColor}; image-rendering: pixelated;"
          onerror="this.style.opacity='0.3'"
        />
        <div style="flex: 1;">
          <h3 style="margin: 0 0 10px 0; color: ${rarityColor};">${spell.name}</h3>
          <div style="color: #aaa; font-size: 13px; line-height: 1.8;">
            <div><strong>Rarity:</strong> <span style="color: ${rarityColor}; text-transform: uppercase; font-weight: bold;">${spell.rarity || '—'}</span></div>
            <div><strong>Cost:</strong> <span style="color: #66b3ff; font-weight: bold;">${spell.cost} Mana</span></div>
            <div><strong>Game:</strong> ${spell.game || '—'}</div>
            <div><strong>Element:</strong> <span style="color: ${elementColor}; font-weight: bold;">${spell.element && spell.element !== 'N/A' ? spell.element : 'None'}</span></div>
          </div>
        </div>
      </div>

      <!-- Description -->
      <div style="padding: 12px; background: rgba(${rarityColor === '#9b59b6' ? '155,89,182' : rarityColor === '#4CAF50' ? '76,175,80' : '170,170,170'}, 0.1); border: 1px solid ${rarityColor}40; border-radius: 6px;">
        <h4 style="margin: 0 0 8px 0; color: ${rarityColor}; font-size: 14px;">Effect</h4>
        <div style="font-size: 13px; color: #ddd; line-height: 1.6;">${spell.description || 'No description available.'}</div>
      </div>

      <!-- Bonus Indicator -->
      <div style="padding: 12px; background: rgba(${spell.hasBonus ? '76, 175, 80' : '136, 136, 136'}, 0.1); border: 1px solid ${spell.hasBonus ? '#4CAF5040' : '#88888840'}; border-radius: 6px;">
        <div style="display: flex; align-items: center; gap: 8px;">
          <span style="font-size: 18px;">${spell.hasBonus ? '✓' : '✗'}</span>
          <div>
            <div style="font-weight: bold; color: ${spell.hasBonus ? '#4CAF50' : '#888'};">
              ${spell.hasBonus ? 'Has Bonus Effect' : 'No Bonus Effect'}
            </div>
            <div style="font-size: 11px; color: #888;">
              ${spell.hasBonus ? 'This spell can be enhanced with bonuses' : 'This spell cannot be enhanced'}
            </div>
          </div>
        </div>
      </div>

      <!-- Keywords -->
      ${keywordsHTML}
    </div>
  `;
}

function showCardDetails(cardName) {
  const allCards = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA : [];
  const card = allCards.find(c => c.name === cardName);
  if (!card) return;

  const detailsPanel = document.getElementById('card-details');
  if (!detailsPanel) return;

  const getRarityColor = (r) => {
    switch((r||'').toLowerCase()) {
      case 'legendary': return '#ff6b00';
      case 'rare': return '#9b59b6';
      case 'uncommon': return '#4CAF50';
      case 'common': return '#aaa';
      case 'starter': return '#2196F3';
      default: return '#666';
    }
  };
  const getTypeColor = (t) => {
    switch((t||'').toLowerCase()) {
      case 'attack': return '#e74c3c';
      case 'skill': return '#2980b9';
      case 'power': return '#8e44ad';
      case 'training': return '#27ae60';
      case 'dice': return '#d35400';
      default: return '#888';
    }
  };

  const rc = getRarityColor(card.rarity);
  const tc = getTypeColor(card.type);
  const isDice = (card.type||'').toLowerCase() === 'dice';
  const typeEmoji = {attack:'⚔',skill:'🛡',power:'✨',dice:'🎲',training:'📖'}[(card.type||'').toLowerCase()] || '🃏';

  // Build dice face grid for dice-type cards
  const diceData = isDice && typeof DICE_DATA !== 'undefined'
    ? DICE_DATA.find(d => d.name === card.name)
    : null;
  const diceFacesHTML = diceData ? `
    <div style="margin-top:4px;">
      <div style="font-size:11px;font-weight:bold;color:${tc};margin-bottom:6px;">🎲 Die Faces</div>
      <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:4px;">
        ${diceData.faces.map((f,i) => `
          <div style="background:rgba(0,0,0,0.5);border:1px solid ${tc}66;border-radius:5px;padding:4px 3px;text-align:center;">
            <div style="font-size:9px;color:#888;">Face ${i+1}</div>
            <div style="font-size:10px;color:${tc};font-weight:bold;line-height:1.3;">${f.text || f.face || '?'}</div>
          </div>`).join('')}
      </div>
    </div>` : '';

  detailsPanel.innerHTML = `
    <div style="display:flex;flex-direction:column;gap:14px;">
      <!-- Card render -->
      <div style="border:2px solid ${rc};border-radius:12px;background:rgba(10,10,15,0.9);box-shadow:0 0 12px ${rc}55;overflow:hidden;max-width:220px;margin:0 auto;position:relative;">
        <div style="position:absolute;top:8px;left:8px;width:26px;height:26px;border-radius:50%;background:${tc};border:2px solid rgba(255,255,255,0.35);display:flex;align-items:center;justify-content:center;font-size:13px;font-weight:bold;color:white;z-index:2;">
          ${card.cost !== null && card.cost !== undefined ? card.cost : '?'}
        </div>
        ${card.imageUrl
          ? '<img src="' + card.imageUrl + '" alt="' + card.name + '" style="width:100%;height:160px;object-fit:contain;background:rgba(0,0,0,0.3);display:block;" onerror="this.style.display=\'none\'"/>'
          : '<div style="width:100%;height:160px;background:linear-gradient(135deg,' + tc + '33,' + rc + '22);display:flex;align-items:center;justify-content:center;font-size:48px;color:' + tc + '88;">' + typeEmoji + '</div>'
        }
        <div style="padding:10px;">
          <div style="font-size:14px;font-weight:bold;color:#eee;margin-bottom:4px;">${card.name}</div>
          <div style="display:flex;gap:8px;margin-bottom:8px;">
            <span style="font-size:10px;color:${tc};text-transform:uppercase;font-weight:bold;">${card.type||''}</span>
            <span style="font-size:10px;color:${rc};text-transform:uppercase;">${card.rarity||''}</span>
          </div>
          <div style="font-size:12px;color:#ddd;line-height:1.5;">${card.description||'No description.'}</div>
          ${diceFacesHTML}
        </div>
      </div>

      ${card.canUpgrade && card.upgradedDescription ? `
        <div style="padding:10px 12px;background:rgba(255,152,0,0.1);border:1px solid rgba(255,152,0,0.3);border-radius:8px;">
          <div style="font-size:11px;font-weight:bold;color:#ff9800;margin-bottom:6px;">✦ Upgraded</div>
          <div style="font-size:11px;color:#ccc;line-height:1.5;">${card.upgradedDescription}</div>
          ${card.upgradedCost !== card.cost ? '<div style="font-size:10px;color:#888;margin-top:4px;">Cost: ' + card.upgradedCost + '</div>' : ''}
        </div>
      ` : (card.upgradedDescription ? `
        <div style="padding:10px 12px;background:rgba(150,150,150,0.08);border:1px solid rgba(150,150,150,0.2);border-radius:8px;">
          <div style="font-size:11px;font-weight:bold;color:#aaa;margin-bottom:6px;">Upgraded</div>
          <div style="font-size:11px;color:#bbb;line-height:1.5;">${card.upgradedDescription}</div>
        </div>
      ` : '')}

      ${card.game ? `<div style="font-size:11px;color:#666;">From: <span style="color:#888;">${card.game}</span></div>` : ''}

      ${(() => {
        // Scan description + upgraded description for known status and addon keywords
        const allText = ((card.description || '') + ' ' + (card.upgradedDescription || '')).toLowerCase();
        const statusData = typeof STATUSES_DATA !== 'undefined' ? STATUSES_DATA : {};
        const addonData  = typeof ADDONS_DATA  !== 'undefined' ? ADDONS_DATA  : {};
        const isPower    = (card.type || '').toLowerCase() === 'power';

        // For Power cards, only show statuses the card explicitly grants/inflicts
        // (matches "Gain N StatusName" or "Inflict N StatusName" patterns)
        const statusGrantPattern = /(?:gain|inflict|apply)\s+(?:\+?\d+\s+)?(\w[\w\s]*)/gi;
        const explicitlyGranted = new Set();
        if (isPower) {
          let m;
          while ((m = statusGrantPattern.exec(allText)) !== null) {
            explicitlyGranted.add(m[1].trim().toLowerCase());
          }
        }

        const matchedStatuses = Object.values(statusData).filter(s => {
          const nameRe = new RegExp(`\\b${s.name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')}\\b`, 'i');
          if (!nameRe.test(allText)) return false;
          if (isPower) {
            // Only include if the status name appears in an explicit grant/inflict context
            return [...explicitlyGranted].some(g => g.includes(s.name.toLowerCase()) || s.name.toLowerCase().includes(g.split(' ')[0]));
          }
          return true;
        });
        const matchedAddons = Object.values(addonData).filter(a =>
          new RegExp(`\\b${a.name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')}\\b`, 'i').test(allText)
        );

        if (matchedStatuses.length === 0 && matchedAddons.length === 0) return '';

        const statusColor = s => s.preference === 'Positive' ? '#4CAF50' : s.preference === 'Negative' ? '#e74c3c' : '#888';
        const statusBadge = s => `
          <div style="display:flex;align-items:flex-start;gap:8px;padding:7px 9px;background:rgba(0,0,0,0.35);border:1px solid ${statusColor(s)}44;border-radius:7px;">
            ${s.imageUrl ? `<img src="${s.imageUrl}" style="width:22px;height:22px;object-fit:contain;flex-shrink:0;border-radius:3px;" onerror="this.style.display='none'">` : `<span style="font-size:16px;line-height:1;flex-shrink:0;">${s.preference==='Positive'?'🟢':s.preference==='Negative'?'🔴':'⚪'}</span>`}
            <div>
              <div style="font-size:11px;font-weight:bold;color:${statusColor(s)};">${s.name}</div>
              <div style="font-size:10px;color:#aaa;line-height:1.35;">${s.description}</div>
            </div>
          </div>`;
        const addonBadge = a => `
          <div style="display:flex;align-items:flex-start;gap:8px;padding:7px 9px;background:rgba(0,0,0,0.35);border:1px solid #9b59b644;border-radius:7px;">
            <span style="font-size:16px;line-height:1;flex-shrink:0;">🔷</span>
            <div>
              <div style="font-size:11px;font-weight:bold;color:#9b59b6;">${a.name}</div>
              <div style="font-size:10px;color:#aaa;line-height:1.35;">${a.description}</div>
            </div>
          </div>`;

        return `
          <div style="display:flex;flex-direction:column;gap:5px;">
            <div style="font-size:11px;font-weight:bold;color:#aaa;margin-bottom:2px;">Keywords</div>
            ${matchedStatuses.map(statusBadge).join('')}
            ${matchedAddons.map(addonBadge).join('')}
          </div>`;
      })()}
    </div>
  `;
}

function formatLevelUpReward(reward) {
  if (!reward || reward.type === 'none' || !reward.type) return null;
  switch (reward.type) {
    case 'gold':  return `💰 +${reward.amount} Gold`;
    case 'item':  return `📦 Choose an Item`;
    case 'card':  return reward.tag
      ? `🃏 1 ${reward.tag.charAt(0).toUpperCase() + reward.tag.slice(1)} Card Reward`
      : '🃏 Choose a Card';
    case 'spell': return `✨ Choose a Spell`;
    default:      return null;
  }
}

function showCharacterDetails(charName) {
  const allChars = typeof CHARACTERS_DATA !== 'undefined' ? Object.values(CHARACTERS_DATA) : [];
  const char = allChars.find(c => c.name === charName);
  if (!char) return;

  const detailsPanel = document.getElementById('character-details');
  if (!detailsPanel) return;

  const charIcon = `images/characters/Full/${char.name}.png`;

  // Build level up bonuses list — read from levelUpStats object
  const levelUpBonuses = [];
  const lus = char.levelUpStats || {};
  if (lus.strength > 0) levelUpBonuses.push({ stat: 'Strength', value: lus.strength, color: '#f44336' });
  if (lus.dexterity > 0) levelUpBonuses.push({ stat: 'Dexterity', value: lus.dexterity, color: '#4CAF50' });
  if (lus.intelligence > 0) levelUpBonuses.push({ stat: 'Intelligence', value: lus.intelligence, color: '#2196F3' });
  if (lus.charisma > 0) levelUpBonuses.push({ stat: 'Charisma', value: lus.charisma, color: '#9b59b6' });
  if (lus.luck > 0) levelUpBonuses.push({ stat: 'Luck', value: lus.luck, color: '#ff9800' });
  if (lus.reroll > 0) levelUpBonuses.push({ stat: 'Reroll', value: lus.reroll, color: '#888' });
  if (lus.dash > 0) levelUpBonuses.push({ stat: 'Dash', value: lus.dash, color: '#888' });
  if (lus.skip > 0) levelUpBonuses.push({ stat: 'Skip', value: lus.skip, color: '#888' });
  if (lus.discovery > 0) levelUpBonuses.push({ stat: 'Discovery', value: lus.discovery, color: '#888' });
  if (lus.fov > 0) levelUpBonuses.push({ stat: 'FoV', value: lus.fov, color: '#888' });
  if (lus.random > 0) levelUpBonuses.push({ stat: 'Random (any stat)', value: lus.random, color: '#aaa' });

  const levelUpBonusesHTML = levelUpBonuses.length > 0
    ? levelUpBonuses.map(b => `<span style="color: ${b.color}; font-weight: bold;">+${b.value} ${b.stat}</span>`).join(', ')
    : '<span style="color: #888;">None</span>';

  // Build starting cards HTML
  const startingEntries = (char.startingDeck) ? char.startingDeck : [];
  const startingDeckHTML = startingEntries.length > 0 ? `
    <div style="margin-top: 15px;">
      <strong style="color: #4CAF50;">Starting Cards:</strong>
      <div style="margin-top: 8px; display: flex; flex-direction: column; gap: 5px;">
        ${startingEntries.map(entry => {
          const template = typeof CARDS_DATA !== 'undefined'
            ? CARDS_DATA.find(c => c.name === entry.cardName || c.name.toLowerCase() === entry.cardName.toLowerCase())
            : null;
          const color = template ? (template.rarity === 'Rare' ? '#9b59b6' : template.rarity === 'Uncommon' ? '#4CAF50' : '#888') : '#888';
          return `<div style="display:flex;align-items:center;gap:8px;background:rgba(0,0,0,0.3);border:1px solid ${color};border-radius:6px;padding:5px 8px;cursor:default;"
            onmouseenter="showCardNameTooltip('${entry.cardName.replace(/'/g,"\\'")}', event)"
            onmouseleave="hideCardNameTooltip()">
            <span style="color:${color};font-weight:bold;font-size:14px;min-width:24px;">×${entry.count}</span>
            <div>
              <div style="font-size:12px;color:white;font-weight:bold;">${entry.cardName}</div>
              ${template ? `<div style="font-size:10px;color:#aaa;">${template.type || ''} · Cost ${template.cost !== undefined ? template.cost : '?'}</div>` : ''}
            </div>
          </div>`;
        }).join('')}
      </div>
    </div>
  ` : '';

  const combatStartHTML = char.combatStyle ? `
    <div style="margin-top: 10px; padding: 8px; background: rgba(255,152,0,0.1); border: 1px solid rgba(255,152,0,0.4); border-radius: 6px;">
      <div style="color: #ff9800; font-size: 12px; font-weight: bold; margin-bottom: 3px;">⚡ Combat Style</div>
      <div style="color: #ddd; font-size: 12px;">${char.combatStyle}</div>
    </div>
  ` : '';

  const startingItemsList = char.startingItems || [];
  const startingItemsHTML = startingItemsList.length > 0 ? `
    <div style="margin-top: 15px;">
      <strong style="color: #cc6600;">Starting Item${startingItemsList.length > 1 ? 's' : ''}:</strong>
      <div style="margin-top: 8px; display: flex; flex-direction: column; gap: 8px;">
        ${startingItemsList.map(itemName => {
          const itemData = typeof items !== 'undefined' ? items.find(i => i.name === itemName) : null;
          const rarityColor = itemData ? (itemData.rarity === 'Rare' ? '#9b59b6' : itemData.rarity === 'Uncommon' ? '#4CAF50' : itemData.rarity === 'Common' ? '#aaa' : '#888') : '#cc6600';
          const imgSrc = itemData && itemData.image ? itemData.image : '';
          const safeDesc = itemData && itemData.description ? itemData.description.replace(/"/g, '&quot;') : '';
          const safeType = itemData && itemData.type ? itemData.type.replace(/"/g, '&quot;') : '';
          const safeRef  = itemData && (itemData.reference || itemData.game) ? (itemData.reference || itemData.game).replace(/"/g, '&quot;') : '';
          const safeItemName = itemName.replace(/"/g, '&quot;');
          return `<div class="collection-starting-item"
            data-item-name="${safeItemName}"
            data-item-img="${imgSrc}"
            data-item-desc="${safeDesc}"
            data-item-type="${safeType}"
            data-item-ref="${safeRef}"
            data-item-color="${rarityColor}"
            style="display:flex;align-items:center;gap:12px;background:rgba(0,0,0,0.3);border:1px solid ${rarityColor};border-radius:8px;padding:8px 10px;cursor:default;"
            onmouseenter="showStartingItemTip(this, event)"
            onmouseleave="hideStartingItemTip()">
            ${imgSrc
              ? `<img src="${imgSrc}" alt="${safeItemName}" style="width:52px;height:52px;object-fit:contain;border-radius:6px;border:1px solid ${rarityColor}40;image-rendering:pixelated;flex-shrink:0;" onerror="this.style.display='none'">`
              : `<div style="width:52px;height:52px;display:flex;align-items:center;justify-content:center;font-size:28px;flex-shrink:0;">📦</div>`
            }
            <div>
              <div style="font-size:13px;color:white;font-weight:bold;">${itemName}</div>
              ${itemData ? `<div style="font-size:11px;color:${rarityColor};font-weight:bold;text-transform:uppercase;">${itemData.rarity || ''}</div>` : ''}
              ${itemData && itemData.type ? `<div style="font-size:10px;color:#aaa;">${itemData.type}</div>` : ''}
            </div>
          </div>`;
        }).join('')}
      </div>
    </div>
  ` : '';

  detailsPanel.innerHTML = `
    <div style="display: flex; flex-direction: column; gap: 15px;">
      <!-- Character Image - Centered -->
      <img
        src="${charIcon}"
        alt="${char.name}"
        style="width: 280px; height: 280px; object-fit: contain; border-radius: 8px; background: #1a1a1a; border: 3px solid #4CAF50; display: block; margin: 0 auto;"
        onerror="this.style.opacity='0.3'"
      />

      <!-- Character Name & Info -->
      <div style="text-align: center;">
        <h3 style="margin: 0 0 5px 0; color: #4CAF50; font-size: 22px;">${char.name}</h3>
        <div style="color: #aaa; font-size: 13px;">From: ${char.game || 'Unknown'}</div>
      </div>

      <!-- Description -->
      <div style="padding: 12px; background: rgba(76, 175, 80, 0.1); border: 1px solid rgba(76, 175, 80, 0.3); border-radius: 6px;">
        <div style="font-size: 13px; color: #ddd; line-height: 1.6; font-style: italic;">"${char.description || 'No description available.'}"</div>
      </div>

      <!-- Starting Resources -->
      <div>
        <strong style="color: #4CAF50;">Starting Resources:</strong>
        <div style="display: flex; gap: 15px; margin-top: 8px; justify-content: center;">
          <div style="background: rgba(255,204,0,0.15); border: 1px solid rgba(255,204,0,0.4); border-radius: 6px; padding: 10px 20px; text-align: center;">
            <div style="font-size: 11px; color: #ffcc00; text-transform: uppercase;">Energy</div>
            <div style="font-size: 24px; font-weight: bold; color: #ffcc00;">${char.energy || 0}</div>
          </div>
          <div style="background: rgba(102,179,255,0.15); border: 1px solid rgba(102,179,255,0.4); border-radius: 6px; padding: 10px 20px; text-align: center;">
            <div style="font-size: 11px; color: #66b3ff; text-transform: uppercase;">Mana</div>
            <div style="font-size: 24px; font-weight: bold; color: #66b3ff;">${char.mana || 0}</div>
          </div>
        </div>
      </div>

      <!-- Level Up -->
      <div style="padding: 12px; background: rgba(255, 152, 0, 0.1); border: 1px solid rgba(255, 152, 0, 0.3); border-radius: 6px;">
        <h4 style="margin: 0 0 8px 0; color: #ff9800; font-size: 14px;">⬆️ Level Up Condition</h4>
        <div style="font-size: 13px; color: #ddd; margin-bottom: 8px;">${char.levelUpCondition || char.levelUp || 'None'}</div>
        <div style="font-size: 12px; color: #aaa;">
          <strong>Rewards:</strong> ${levelUpBonusesHTML}
        </div>
        ${(() => {
          const rewardText = formatLevelUpReward(char.levelUpReward);
          return rewardText
            ? `<div style="font-size:12px;color:#ccc;margin-top:5px;"><strong>Bonus:</strong> ${rewardText}</div>`
            : '';
        })()}
      </div>

      <!-- Starting Deck -->
      ${startingDeckHTML}
      ${combatStartHTML}
      ${startingItemsHTML}

      <!-- Deck Beaten Checklist -->
      ${(() => {
        if (typeof AVAILABLE_DECKS === 'undefined' || !AVAILABLE_DECKS.length) return '';
        const dw = (typeof getDeckWinsForCharacter === 'function') ? getDeckWinsForCharacter(charName) : [];
        const rows = AVAILABLE_DECKS.map(d => {
          const beaten = dw.includes(d.id);
          return `<div style="display:flex;align-items:center;gap:8px;padding:4px 0;">
            <span style="font-size:14px;">${beaten ? '✅' : '⬜'}</span>
            <span style="font-size:12px;color:${beaten ? '#4CAF50' : '#888'};">${d.name} Deck</span>
          </div>`;
        }).join('');
        return `<div style="margin-top:15px;padding:12px;background:rgba(0,0,0,0.3);border:1px solid #333;border-radius:8px;">
          <div style="font-size:12px;font-weight:bold;color:#aaa;margin-bottom:8px;">🏆 Beaten With Deck</div>
          ${rows}
        </div>`;
      })()}
    </div>
  `;
}

function showAllyDetails(allyName) {
  const alliesData = typeof ALLIES_DATA !== 'undefined' ? ALLIES_DATA : [];
  const ally = alliesData.find(a => a.name === allyName);
  if (!ally) return;

  const detailsPanel = document.getElementById('ally-details');
  if (!detailsPanel) return;

  const allyIcon = ally.image || `images/allies/${ally.name}.png`;

  // Get rarity color
  const getRarityColor = (rarity) => {
    switch((rarity || '').toLowerCase()) {
      case 'high': return '#9b59b6';
      case 'medium': return '#ff9800';
      case 'low': return '#4CAF50';
      default: return '#888';
    }
  };

  const rarityColor = getRarityColor(ally.rarity);

  // Build dice HTML
  const diceHTML = ally.dice && ally.dice.length > 0 ? `
    <div style="margin-top: 15px;">
      <strong style="color: #2196F3;">Ally Dice:</strong>
      <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-top: 8px;">
        ${ally.dice.map((face, idx) => {
          if (face.isBlank || face.raw === 'X') {
            return `<div style="background: rgba(0,0,0,0.4); border: 1px solid #333; border-radius: 6px; padding: 8px; text-align: center; font-size: 11px; color: #666;">
              <div style="font-weight: bold; color: #444;">Face ${idx + 1}</div>
              <div>${face.raw === 'X' ? 'X' : 'Blank'}</div>
            </div>`;
          }
          return `<div style="background: rgba(33, 150, 243, 0.1); border: 1px solid rgba(33, 150, 243, 0.3); border-radius: 6px; padding: 8px; text-align: center; font-size: 11px; color: #ddd;">
            <div style="font-weight: bold; color: #2196F3; margin-bottom: 4px;">Face ${idx + 1}</div>
            <div>${face.raw || '—'}</div>
          </div>`;
        }).join('')}
      </div>
    </div>
  ` : '';

  detailsPanel.innerHTML = `
    <div style="display: flex; flex-direction: column; gap: 15px;">
      <!-- Ally Header -->
      <div style="display: flex; gap: 15px; align-items: flex-start;">
        <img
          src="${allyIcon}"
          alt="${ally.name}"
          style="width: 100px; height: 100px; object-fit: contain; border-radius: 8px; background: rgba(0,0,0,0.3); border: 2px solid ${rarityColor}; image-rendering: pixelated;"
          onerror="this.style.opacity='0.3'"
        />
        <div style="flex: 1;">
          <h3 style="margin: 0 0 10px 0; color: ${rarityColor};">${ally.name}</h3>
          <div style="color: #aaa; font-size: 13px; line-height: 1.8;">
            <div><strong>Type:</strong> ${ally.type || 'Ally'}</div>
            <div><strong>Rarity:</strong> <span style="color: ${rarityColor}; text-transform: uppercase; font-weight: bold;">${ally.rarity || '—'}</span></div>
            <div><strong>HP:</strong> <span style="color: #ff4444; font-weight: bold;">${ally.hp || '?'}</span></div>
            <div><strong>Game:</strong> ${ally.game || '—'}</div>
          </div>
        </div>
      </div>

      <!-- Ability -->
      ${ally.ability ? `
        <div style="padding: 12px; background: rgba(33, 150, 243, 0.1); border: 1px solid rgba(33, 150, 243, 0.3); border-radius: 6px;">
          <h4 style="margin: 0 0 8px 0; color: #2196F3; font-size: 14px;">✨ Special Ability</h4>
          <div style="font-size: 13px; color: #ddd; line-height: 1.6;">${ally.ability}</div>
        </div>
      ` : `
        <div style="padding: 12px; background: rgba(0,0,0,0.2); border: 1px solid #444; border-radius: 6px;">
          <div style="font-size: 13px; color: #888; text-align: center;">No special ability</div>
        </div>
      `}

      <!-- Dice -->
      ${diceHTML}
    </div>
  `;
}

// Get enemy stats from gameState
function getEnemyStats(enemyName) {
  if (!gameState.enemyStats) {
    gameState.enemyStats = {};
  }

  // Find base enemy name (for variants)
  const enemy = enemies.find(e => e.name === enemyName);
  const baseName = enemy?.variantOf || enemyName;

  return gameState.enemyStats[baseName] || { timesBeaten: 0, timesKilledPlayer: 0 };
}

// Record enemy defeat
function recordEnemyDefeated(enemyName) {
  if (!gameState.enemyStats) {
    gameState.enemyStats = {};
  }

  // Find base enemy name (for variants)
  const enemy = enemies.find(e => e.name === enemyName);
  const baseName = enemy?.variantOf || enemyName;

  if (!gameState.enemyStats[baseName]) {
    gameState.enemyStats[baseName] = { timesBeaten: 0, timesKilledPlayer: 0 };
  }

  gameState.enemyStats[baseName].timesBeaten++;
  saveCurrentGame();
}

// Record player death to enemy
function recordPlayerKilledBy(enemyName) {
  if (!gameState.enemyStats) {
    gameState.enemyStats = {};
  }

  // Find base enemy name (for variants)
  const enemy = enemies.find(e => e.name === enemyName);
  const baseName = enemy?.variantOf || enemyName;

  if (!gameState.enemyStats[baseName]) {
    gameState.enemyStats[baseName] = { timesBeaten: 0, timesKilledPlayer: 0 };
  }

  gameState.enemyStats[baseName].timesKilledPlayer++;
  saveCurrentGame();
}

// ===== COLLECTION WINDOW EXPORTS =====
window.showCollection = showCollection;
window.switchCollectionTab = switchCollectionTab;
window.sortCollectionSpells = sortCollectionSpells;
window.switchLootSubTab = switchLootSubTab;
window.sortCollectionItems = sortCollectionItems;
window.toggleItemsNA = toggleItemsNA;
window.sortEnemies = sortEnemies;
window.switchCurseTier = switchCurseTier;
window.showGameDetails = showGameDetails;
window.showEnemyDetails = showEnemyDetails;
window.switchEnemyForm = switchEnemyForm;
window.showItemDetails = showItemDetails;
window.showSpellDetails = showSpellDetails;
window.showCardDetails = showCardDetails;
window.formatLevelUpReward = formatLevelUpReward;
window.showCharacterDetails = showCharacterDetails;
window.showAllyDetails = showAllyDetails;
window.getGameStats = getGameStats;
window.saveGameStats = saveGameStats;
window.incrementGameBeaten = incrementGameBeaten;
window.getFishStats = getFishStats;
window.saveFishStats = saveFishStats;
window.incrementFishCaught = incrementFishCaught;
window.getEnemyStats = getEnemyStats;
window.recordEnemyDefeated = recordEnemyDefeated;
window.recordPlayerKilledBy = recordPlayerKilledBy;
