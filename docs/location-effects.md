# Location effects — ideas to match to locations

106 things a location could DO, each built from content the game already has.
They are the `location_effects` sheet of `tools/Research.xlsx` (write `yes` /
`no` in its Owner column, and which location each one goes on in Owner Notes);
this page is the same list grouped, to read. The source of truth is
`research/location_effects.csv` ([research.md](research.md) §6.7).

**Ready** means its Effect is valid location grammar today: paste it into the
`locations` sheet's Effect column. The rest name the one piece of code they wait
for; [locations-design.md](locations-design.md) §9 groups those.

`<tag>` rows are templates: write the location's own tag in.

An effect marked *on the sheet already* is one a location on the `locations`
sheet already does all of; `research.py build` sets its Status to `on sheet` by
itself (§6.7 of research.md), so it drops out of what is left to review.

## When entered (51)

| effect | tier | what it does | lean | ready? |
|---|---|---|---|---|
| **Scorched Floor** *(on the sheet already: Burning Basement does it)* | Low | When entered, 2 random tiles catch Fire. | fire +20% | ✓ `arrive: place_tile fire 2` |
| **Wall of Flame** | High | When entered, the whole back column catches Fire — everything that walks on starts burning. | fire +30% | needs a place_tile target of a whole column (`back`) |
| **Burning Approach** | Medium | When entered, the front column catches Fire, as a Scroll of Fire would — and you with it. | fire +20% | needs Scroll of Fire's effect as a location verb (`read_scroll scroll_of_fire`) |
| **Cobwebs** *(on the sheet already: Caves does it)* | Low | When entered, 3 random tiles are covered in Web. | spider +20% | ✓ `arrive: place_tile web 3` |
| **Frozen Floor** | Medium | When entered, 4 random tiles freeze into Web: whatever walks in loses its next step. | ice +30% | ✓ `arrive: place_tile web 4` |
| **Minefield** | Low | When entered, place 2 Landmines on random tiles. | bomb +20% | ✓ `arrive: apply_unit landmine random_empty; apply_unit landmine random_empty` |
| **Poop Room** | Low | When entered, place 3 random poop tagged objects on random tiles. | poop +20% | ✓ `arrive: place_unit poop 3` |
| **Golden Cache** | Medium | When entered, place 2 Golden Poops on random tiles. Break them for gold before the enemies do. | gold +30% | ✓ `arrive: apply_unit golden_poop random_empty; apply_unit golden_poop random_empty` |
| **Field Hospital** | Medium | When entered, place 2 Rainbow Poops on random tiles. Each heals you for 3 when it breaks. | heart +20% | ✓ `arrive: apply_unit rainbow_poop random_empty; apply_unit rainbow_poop random_empty` |
| **Barricades** | High | When entered, a Poop stands in front of you in every lane — walls the stack must chew through. | poop +20% | needs place_unit on a whole column (`front`) |
| **Hostages** | Medium | When entered, place a Golden Poop and a Rainbow Poop on random tiles — they pay whoever breaks them, you or the enemies. |  | ✓ `arrive: apply_unit golden_poop random_empty; apply_unit rainbow_poop random_empty` |
| **Ambush** | Medium | When entered, spawn 2 random Enemies at the run's tier. |  | ✓ `arrive: spawn_enemy; spawn_enemy` |
| **Nest** | Low | When entered, spawn 1 random Enemy of the location's tag. | <tag> +20% | ✓ once its tag is written in |
| **Swarm** | High | When entered, spawn 3 random Enemies of the location's tag. | <tag> +30% | ✓ once its tag is written in |
| **Lair** | High | When entered, a random boss walks on. |  | ✓ `arrive: spawn_boss` |
| **Twin Thrones** | Insane | When entered, 2 random bosses walk on. |  | ✓ `arrive: spawn_boss; spawn_boss` |
| **Sleeping Monsters** | Medium | When entered, spawn 3 random Enemies, each Stunned for 2 turns. |  | needs stunning the bodies an arrive spawns (`stunned=2` on spawn_enemy) |
| **Sanctuary** | Low | When entered, heal to full. | holy +30% | ✓ `arrive: heal_full` |
| **Spring** | Low | When entered, Gain +3 Health. |  | ✓ `arrive: gain_hp 3` |
| **Fortified** | Medium | When entered, Gain +2 Shields that stay. |  | ✓ `arrive: gain_stat bonus_shields 2` |
| **Heart Container** | High | When entered, Gain +1 Max Health. | heart +30% | ✓ `arrive: gain_max_hp 1` |
| **Empty Vessel** | Medium | When entered, Gain +2 Max Health, empty. | heart +20% | ✓ `arrive: gain_empty_max_hp 2` |
| **Marked Ground** | Medium | When entered, you are Marked: each game, get an achievement in the game you are playing or take 3 damage. |  | ✓ `arrive: apply_status marked 1` |
| **Smouldering** | Medium | When entered, you catch +1 Burn. | fire +20% | ✓ `arrive: apply_status burn 1` |
| **Blessing** | Low | When entered, Gain a random Buff. | holy +20% | ✓ `arrive: gain_random_buff` |
| **Cleansing Waters** | Low | When entered, lose a random Debuff. |  | ✓ `arrive: remove_random_debuff` |
| **The Bell Tolls** | High | When entered, take on the Curse of the Bell. |  | ✓ `arrive: add_curse curse_of_the_bell` |
| **Rough Night** | Medium | When entered, take on Poor Sleep. |  | ✓ `arrive: add_curse poor_sleep` |
| **Old Wounds** | Medium | When entered, take on an Injury. |  | ✓ `arrive: add_curse injury` |
| **Armoury** | Low | When entered, Gain +2 Bombs. | bomb +30% | ✓ `arrive: gain_stat bombs 2` |
| **Keyring** | Medium | When entered, Gain +2 Keys. | key +30% | ✓ `arrive: gain_stat keys 2` |
| **Shortcut** | Low | When entered, Gain +2 Dash. |  | ✓ `arrive: gain_stat dash 2` |
| **Rubble** | Low | When entered, Gain +2 Bash. |  | ✓ `arrive: gain_stat bash 2` |
| **Alchemist's Den** | Medium | When entered, Gain +2 Transmute. | pot +30% | ✓ `arrive: gain_stat transmute 2` |
| **Shifting Maze** | Medium | When entered, Gain +2 Scramble. | dice +30% | ✓ `arrive: gain_stat scramble 2` |
| **Boulder Hall** | Low | When entered, Gain +3 Push. | rock +30% | ✓ `arrive: gain_stat push 3` |
| **Lucky Floor** | Medium | When entered, Gain +1 Luck. | dice +30% | ✓ `arrive: gain_stat luck 1` |
| **Library** | Medium | When entered, Gain 2 random Scrolls. | book +30% | ✓ `arrive: gain_scroll 2` |
| **Apothecary** | Medium | When entered, Gain 2 random Potions. | pot +30% | ✓ `arrive: gain_potion 2` |
| **Pill Bottle** | Low | When entered, Gain 2 random Pills. | pills +30% | ✓ `arrive: gain_pill 2` |
| **Card Table** | Medium | When entered, Gain 2 random Cards. |  | ✓ `arrive: gain_card 2` |
| **Scavenger's Haul** | Low | When entered, Gain 2 random Loot. |  | ✓ `arrive: gain_loot 2` |
| **Relic Shrine** | High | When entered, Gain a random Item. |  | ✓ `arrive: gain_random_item` |
| **Recharge Station** | Medium | When entered, 2 charges go into something you carry. | wire +30% | ✓ `arrive: charge_random 2` |
| **Fool's Gold** | Low | When entered, Gain +5 Gold. | coin +30% | ✓ `arrive: gain_gold 5` |
| **City of Gold** | High | When entered, Gain +10 Gold. | gold, coin +50% | ✓ `arrive: gain_gold 10` |
| **Donation Box** | Low | When entered, a Donation Machine stands under the board for the stay. |  | needs spawn_object naming its object (`spawn_object donation_machine` reads as no object today) |
| **Blood Bank** | Medium | When entered, a Blood Donation Machine stands under the board for the stay. | blood +20% | needs spawn_object naming its object |
| **Revelation** | Medium | When entered, every piece of loot you carry is identified. | book +20% | needs an identify-all verb |
| **Reshuffled Foes** | Medium | When entered, every enemy on the board is rerolled into another of its tier. |  | ✓ `arrive: reroll_enemies` |
| **Weapon Rack** | Low | When entered, Gain a random Weapon. |  | needs a grant of one loot kind |

## While you are there (47)

| effect | tier | what it does | lean | ready? |
|---|---|---|---|---|
| **Embers That Linger** | Medium | Fire lit here burns for 1 more game. | fire +20% | needs a location-scoped tile decay bonus |
| **Damp Ground** | Low | Fire goes out the moment it is lit here: no Fire tile can be laid. | fish +20% | needs a location-scoped refusal of one tile |
| **Every Step Burns** | High | At the end of every game here, 1 random empty tile catches Fire. | fire +30% | needs an effect at the end of every game (`game_ended:` header) |
| **Laid Charges** | Medium | At the end of every game here, a Landmine is laid on a random empty tile — the Landmines relic, for the stay. | bomb +20% | needs an effect at the end of every game (`game_ended:` header) |
| **Haunted** | Medium | Every body that walks on here arrives Invisible until it first strikes. | undead +30% | needs granting an ability to bodies while here |
| **Trampling Herd** | High | Every enemy here Tramples — it shoves whatever is in its way aside. |  | needs granting an ability to bodies while here |
| **Restless Dead** | High | Every body that dies here leaves Restless Remains that stand back up. | undead +30% | needs granting an ability to bodies while here |
| **Agile Foes** | Medium | Every enemy here is Agile: blocked, it slips diagonally into the next lane. |  | needs granting an ability to bodies while here |
| **Bolstered Ranks** | High | Enemies here arrive with +1 Strength. |  | needs a location-scoped `spawn_status strength 1` |
| **Swift Ground** | Medium | Enemies here arrive with +1 Speed — they close an extra column a turn. |  | needs a location-scoped `spawn_status speed 1` |
| **Armoured** | High | Enemies here arrive with +1 Dexterity — a Shield each. | robot +20% | needs a location-scoped `spawn_status dexterity 1` |
| **Bloodied Arena** | Medium | Enemies here arrive Bleeding. | blood +30% | needs a location-scoped `spawn_status bleed 1` |
| **Hunting Ground** | High | Every enemy here has Predatory Scent: it hunts the wounded. | dog +30% | needs granting an ability to bodies while here |
| **Tanky Brutes** | Insane | Every enemy that walks on here is Tanky: one more Health. |  | needs granting an ability to bodies while here |
| **Clear Air** | Low | Nothing walks on when a game here ends. |  | needs a location-scoped override of the end-of-game spawn |
| **Hold the Line** | Medium | Every game that ends here stands up 1 more body, and every game you beat here pays +1 Small Chest. |  | needs end-of-game spawn bonus and a `game_won:` payout on a location |
| **Thin Air** | High | Every game here grants 1 fewer Temporary Shield (never below 1). |  | needs a location-scoped Fracture rule |
| **Glass Floor** *(on the sheet already: Dark Room, The Chest does it)* | High | Damage taken here is doubled. |  | ✓ `while: damage_taken_mult 2` |
| **Soft Ground** | Low | Damage taken here is halved, rounded down. |  | ✓ `while: damage_taken_mult 0.5` |
| **No Healing** | Medium | Healing does nothing here. |  | needs a location-scoped `heal_multiplier 0` |
| **Double Healing** | Medium | Healing here heals twice as much. | heart +20% | needs a location-scoped `heal_multiplier 2` |
| **Dud Powder** | Medium | Bombs can't be used here. |  | needs a location-scoped verb lock |
| **Locked Doors** | Medium | Dash can't be used here — every road out is the offering's. |  | needs a location-scoped verb lock |
| **Free Passage** *(on the sheet already: The Void does it)* | Insane | One game on every offering is a free rift. |  | ✓ `while: offering_rift 1` |
| **Unstable Ground** | High | Two games on every offering are free rifts. |  | ✓ `while: offering_rift 2` |
| **Bombardier** | Medium | Bombs thrown here blast a cross, as if you held Brimstone. | bomb +30% | needs a location-scoped bomb modifier |
| **Heavy Push** | Medium | A Push here shoves a body two cells. |  | needs a location-scoped push distance |
| **Black Market** | Medium | Every game you beat here opens a shop shelf, but everything on it costs +2 Gold. |  | needs a shelf off any beaten game; a location-scoped price |
| **Rich Veins** | Medium | Every enemy defeated here pays +1 Gold. | coin +30% | needs a location-scoped `gold_per_enemy` |
| **Double Loot** | High | Every enemy defeated here drops 2 pieces of loot. |  | needs a location-scoped `loot_multiplier 2` |
| **Bigger Chests** | High | Every chest here is one size bigger. |  | needs a location-scoped `base_chest_bonus 1` |
| **Bosses Pay More** | High | Bosses defeated here drop +1 more chest. |  | needs a location-scoped `boss_chest_bonus` |
| **Market Day** | Low | Every game you beat here opens a shop shelf, as a full shop bar does. |  | needs a shelf off any game beaten while here |
| **Ferryman's Toll** | High | Every shelf here is Charon's: it takes Health, not Gold. |  | needs forcing a shopkeeper while here |
| **Jimbo's Stall** | Medium | Every shelf here is Jimbo's: cards and jokers. | joker +30% | needs forcing a shopkeeper while here |
| **Busy Roads** | Medium | Every game here pays a second event. |  | needs a location-scoped extra event roll |
| **Quiet Roads** | Low | No event fires after a game here. |  | needs a location-scoped event skip |
| **No Rest** | Medium | You cannot make camp here. |  | needs Camp refusing while here |
| **Campfire** | Low | Making camp here offers a third card. |  | needs a location-scoped Camp option |
| **Relentless** | High | Enemies take an extra turn after every game beaten or escaped here. |  | needs a location-scoped Fracture rule |
| **Tight Quarters** | Medium | The board here is one row shorter. |  | needs a location-scoped grid size |
| **Open Plain** | Medium | The board here is one row taller: more enemies abreast. |  | needs a location-scoped grid size |
| **Long Corridor** | Low | The board here is one column longer: further to walk. |  | needs a location-scoped `grid_length 1` |
| **Fog** | Medium | You cannot see what an offering's enemy is until you pick it. |  | needs a location-scoped `hide_spawns` |
| **Easy Exits** | Low | Escape opens after 1 lost run here, whatever the game. |  | needs a location-scoped escape threshold |
| **Unidentified** | Medium | Nothing can be identified here: scrolls, pills and potions stay unknown. |  | needs a location-scoped identify lock |
| **Weapon Forge** | High | Weapons charge twice as fast here. |  | needs a location-scoped weapon charge rate |

## Trades (a button, a few times) (8)

| effect | tier | what it does | lean | ready? |
|---|---|---|---|---|
| **Blood Price** | Medium | Take 2 Damage to Gain +1 Small Chest, up to 3 times. | blood +20% | needs an action cost of Health (`lose_hp`) |
| **Devil's Deal** *(on the sheet already: Dark Room does it)* | High | Lose 2 Max Health to Gain +1 Devilish Small Chest, up to 4 times. | devilish +20% | ✓ `action 4: lose_max_hp 2 => gain_chest small devilish` |
| **Treasure Vault** | Medium | Spend a Key to Gain +1 Large Chest, once. | key +30% | ✓ `action 1: spend keys 1 => gain_chest large` |
| **Secret Walls** | Low | Spend a Bomb to Gain +1 Small Chest, up to 3 times. | bomb +20% | ✓ `action 3: spend bombs 1 => gain_chest small` |
| **Toll Gate** | Medium | Pay 5 Gold, once, to Gain +1 Large Chest. |  | ✓ `action 1: spend gold 5 => gain_chest large` |
| **Armour for Riches** | Medium | Spend a Shield that stays to Gain +1 Medium Chest, up to 2 times. |  | ✓ `action 2: spend bonus_shields 1 => gain_chest medium` |
| **Sacrifice Altar** | High | Lose 3 Max Health to Gain +1 Huge Chest, once. |  | ✓ `action 1: lose_max_hp 3 => gain_chest huge` |
| **Dig Site** | Low | Spend a Bash to Gain 1 random Loot, up to 3 times. | tool +30% | ✓ `action 3: spend bash 1 => gain_loot 1` |
