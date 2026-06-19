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
`free_random_hand_card`, `attack_double`, `+Replay N`,
`reduce_card_cost N [tag=X type=Y count=N]` (Empty Tome: at combat start, shave
N off the cost of `count` random cards matching the tag/type filter for the rest
of the fight — and since action cooldown is `2*cost + rarity`, the same discount
shortens that card's cooldown there too).

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

**Status: items are fully sheet-authored.** All 89 `data/items/*.tres` are
generated from the `items` sheet by `generate_item_tres.py`, including the
`Description` text (authored in the sheet's `Description` column). Re-run the
generator after any sheet edit; effects round-trip with 0 gameplay-critical
diffs (verified by `_item_parity.py`).

## DSL-portability cells in `tools/Roguelikes.xlsx`

These `Effect` cells were tuned so the cell fully describes the `.tres`. Keep
them across re-uploads or the parser falls back to wrong/old behavior:
- **Dead Eye** → `attack_landed: +1 dead_eye streak (same target); attack_missed: reset dead_eye`
- **Death Orb** → `dmg all_enemies value_from=curses x2 type=true (...)`
- **Du-Vu Doll** → `+X power (self) stacks_from=curses` (space, not comma)
- **Leech Brood** → `lose_hp 10 (non_lethal, self)`

## Sheet-driven values to keep an eye on

`kind` comes from the `Type` column (first word; `Incremental` = TRIGGERED) and
`rarity` from `Rating`. A multi-value `Type` like `Pickup, Scaling` resolves to
its first word (→ PICKUP), so set the cell to the single intended value. Item
`tags` and `Description` are taken verbatim from the sheet — an empty `tags`
cell yields no tags.
