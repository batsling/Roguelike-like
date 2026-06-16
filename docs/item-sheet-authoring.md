# Item sheet-authoring

Items are generated from the `items` sheet of `tools/Roguelikes.xlsx` by
`tools/generate_item_tres.py`, the same way the card catalog is generated from
`cardsnew`. The structured behavior lives in the sheet's **`Effect`** column, a
colon/semicolon DSL that parses into the `ItemData` fields Godot consumes.

```
python3 tools/generate_item_tres.py          # regenerate every item that has a .tres
python3 tools/generate_item_tres.py --all    # also emit sheet rows with no .tres yet
python3 tools/generate_item_tres.py --list    # print parses without writing
python3 tools/_item_parity.py                 # parity check vs the hand-authored .tres
```

## Effect DSL

One item = `clause; clause; ...` (paren/bracket aware — a `;` inside `()`,
`[]`, or `{}` does not split). Each clause is `<prefix>: <payload>`.

| Prefix | Maps to | Example |
| --- | --- | --- |
| `passive` | `stat_bonuses` | `passive: +3 strength, -2 discovery` |
| `combat_start[ed]` / `combat_end[ed]` | `triggers[{on}]` | `combat_start: +10 block (self)` |
| `<signal>` | `triggers[{on}]` | `enemy_killed: 50% chance +2 hp` |
| `<signal> if_turn=N` / `if_type=X` | trigger + gate | `turn_started if_turn=3: +18 block (self)` |
| `card_played if_type=X` | `triggers[{on:card_played, if_card_type}]` | `card_played if_type=attack: counter key=attacks_total every=10 -> gain_energy 1` |
| `card_grant if_tag=X [if_type=Y]` | `card_grants` | `card_grant if_tag=strike: +1 bruise (enemy)` |
| `scaling` | `scaling` | `scaling: +1 strength per 20 max_hp` |
| `weapon` / `verify` | `weapon_card_id` + `verification_*` | `weapon: barrel; verify: <q> => 1/2 random fish` |
| `perfect` | `perfect_effects` / `perfect_save_chance` | `perfect: gain_hp 5` |
| `status_amplify`, `attack_damage_bonus`, `upgrade_card_types`, `stat_mirror`, `stat_floor`, `stat_gain_bonus`, `negate_lethal`, `reroll_low_rarity`, `carries_leftover_energy`, `lower_hp_damage_mult`, `gold_spend_stat_per=N`, `level_up`, `charged (charge_cost N)` | the matching one-off `ItemData` field | — |

**Payload effects** (comma-separated within a clause):
`+N <status>` / `-N <stat>` (target from a trailing `(self)`/`(enemy)`/
`(all_enemies)`/`(random_enemies count=2)`; bare `(prose)` is ignored),
`dmg N|all_enemies [value_from=.. xN type=..]`, `block/heal/draw/gain_energy/
gain_gold/gain_hp/gain_max_hp/gain_chest/lose_hp N`, `gain_stat <s> N`,
`temp_stat <s> +N`, `N% chance <effect>`, `counter key=K every=N -> <effect>`,
`if_hp above|below F -> <effect>`, `roll_block sides=N`, `roll_gold [a,b,c]`,
`upgrade_random_cards card_type=X count=N`, `+N <name> streak` / `reset <name>`,
`free_random_hand_card`, `attack_double`, `+Replay N`.

### Conventions the generator applies (so the sheet stays terse)
- High-frequency hooks (`attack_landed`, `attack_missed`, `turn_tick`,
  `damage_taken`, and any counter/streak) get `silent: true`.
- A counter / streak effect's `label` is the item's display name.
- `block`/`heal`/buff effects under a self-facing trigger (`combat_started`,
  `turn_started/ended`, `item_acquired`) default to `target: self`; a bare
  `enemy` target stays implicit (it is the EffectSystem default).
- USABLE (pill) items default to `max_uses: 1`; everything else `-1`.

## Parity

`tools/_item_parity.py` parses each hand-authored `data/items/*.tres` and diffs
it field-by-field against the in-memory parse, normalizing away cosmetic noise
(field order, implicit `enemy` target, log-only `label`/`notify`/`silent`).

**Status: items are flipped — all 89 `data/items/*.tres` are generated from the
sheet, with 0 gameplay-critical diffs** (verified by parsing the pre-flip files
and semantically diffing them against the regenerated output: descriptions,
tags, `source_game`, effects, and charge/use fields all preserved). The only
change in the files is formatting (multi-line arrays collapse to single-line
JSON). Re-run `generate_item_tres.py` after any sheet edit.

## Cell changes applied to `tools/Roguelikes.xlsx`

`items` sheet (so the user can replicate after a re-upload):

DSL portability (made the `Effect` cell fully describe the `.tres`):
- **Dead Eye** `Effect` → `attack_landed: +1 dead_eye streak (same target); attack_missed: reset dead_eye` (was a trailing prose note + bare `reset`).
- **Death Orb** `Effect` → added `type=true` to the `dmg` clause.
- **Du-Vu Doll** `Effect` → `+X power (self) stacks_from=curses` (space, not comma, so `stacks_from` attaches to the effect).
- **Leech Brood** `Effect` → `lose_hp 10 (non_lethal, self)` (was `(self)`; the hit must be non-lethal).

Value disagreements — **set the sheet to match the code (ground truth)**; review
whether the sheet's old value was actually intended:
- **Alien Baby** `Type` `Pickup, Scaling` → `Passive` (code kind = PASSIVE).
- **Horn Cleat** `Type` `Passive` → `Triggered` (code kind = TRIGGERED).
- **Ballistic Boots** `Rating` `Rare` → `Common`.
- **Hollow Heart** `Rating` `Common` → `Uncommon`.
- **Mango** `Rating` `Rare` → `Uncommon`.

Prose backport (so the sheet is the single source and the flip kept the
polished text): the 89 `.tres` descriptions were copied into the `Description`
column (87 changed), and 6 `tags` cells were reconciled to the `.tres` values
(`bear_trap_mask` mask,trap; `beefy_ring` ring,scaling; `bird_head` head,bird;
`blood_magic` magic,blood; `brain_candy` drug,pill,devilish; `brass_knuckles`
offense).
