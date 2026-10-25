# Archived design docs

These specs describe the **simulated-combat build that the games-first cut
removed** (`docs/games-first-redesign.md` §11). The deckbuilder / action /
strategy scenes, combat cards, statuses, potions and combat enemy stat blocks are
all gone from the build, and so are the resources and folders these docs
reference — `CardData`, `ActionEnemyData`, `data/cards/`, `data/action_enemies/`,
`data/enemies/`.

They are kept because the design reasoning in them is still worth reading, and
because some of it will be mined again. **Nothing here describes how the current
build works.** Treat every path, class and sheet name in these files as historical.

| doc | described |
|---|---|
| `card_authoring.md` | the `cardsnew` sheet ↔ `data/cards/` mapping |
| `action-attack-translation.md` | attack archetypes for the Action arena |
| `action-enemy-authoring.md` | the `enemiesA` sheet ↔ `data/action_enemies/` |
| `enemy-plan.md` | deckbuilder enemy system (never implemented) |
| `fear-status-design.md` | the Fear status across all three combat modes |
| `gaper-plan.md` | the Gaper action enemy (never implemented) |
| `addon-sheet-authoring-handoff.md` | sheet-authoring the **addon** catalog (never implemented) |
| `addon-translation-dsl.md` | the DSL that handoff was to translate into |

**Finished plans and superseded designs from the games-first build** (moved here
on 25 Oct 2026). These describe the current build's history, not the combat era,
but every one of them is done or replaced, and the paths in them (`data/items/`,
`generate_item_tres.py`, `legacy-web/`, `ReferenceCatalog.gd`) have since been
deleted:

| doc | described | now |
|---|---|---|
| `games-first-redesign-implementation-plan.md` | Phase 1 of the games-first cut: the data foundation and the decisions locked in discovery | built; the spec is `../games-first-redesign.md` |
| `sheet-authoring-handoff.md` | sheet-authoring items, events and addons | items and events built (`../item-sheet-authoring.md`, `../event-sheet-authoring.md`), addons never |
| `potions-handoff.md` | the session handoff while potions were being built | built; `../potions-design.md` |
| `stat-dispatcher.md` | the per-combat-mode stat dispatcher | the `Stats` autoload kept the run stats and Luck (`../architecture.md`) |
| `locations-and-events-design.md` | the brainstorm that gave every location a goal and a choice | replaced by `../locations-design.md`; `../event-sheet-authoring.md` still argues from its §1 and §6 |

**The two addon docs were in the live `docs/` folder until they were moved here**,
which is worth recording because it is the failure this README exists to prevent:
they name `scripts/action/ActionCombat.gd`,
`scripts/deckbuilder/DeckbuilderCombat.gd`, `scripts/strategy/combat/BattleView.gd`
and `scripts/runtime/AddonSystem.gd` — four paths that have not existed for a long
time — and nothing live linked to either of them, so nothing ever contradicted
them. A reader following `CLAUDE.md`'s reading order would have found them sitting
beside the current specs with no warning attached. The addon system they plan was
never built at all; the sheet-authoring pass they were part of shipped for items
and events only (`docs/sheet-authoring-handoff.md`, which carries a status banner
saying so).

For the current build, start at [`../games-first-redesign.md`](../games-first-redesign.md).
