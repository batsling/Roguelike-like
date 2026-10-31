# Test flakes that were fixed, and how each was found

Moved out of `CLAUDE.md` (19 Oct 2026), word for word, because it is history
rather than a rule: it was 9 KB of a file loaded into every session. **Read it
when a test starts failing only sometimes**, before blaming a random seed — every
one of these was an assertion that was only *usually* true, and the diagnostics
that found them (a stress loop of one test run 40-50 times, printing the board on
failure; diffing a passing and failing run's Control tree) are the reusable part.

- **The same goes for a FAILURE that comes and goes.** `test_atlas.gd::test_the_route_set_is_rebuilt_when_the_run_moves`
  failed on roughly one run in four, on any tree, because it asserted that
  `AtlasView.route_stars()` DIFFERS after the run moves. It doesn't always:
  that set is the union of the road ahead and the road walked, so stepping along
  the optimal path moves the game you left from one half into the other and
  leaves the union identical — a correct rebuild that reads exactly like a stale
  cache. It now checks the cache against a fresh build instead, which is what
  "rebuilt" meant and is true either way. Before blaming a random graph for a
  varying failure, work out which assertion is only *usually* true.
- **The varying failures that used to live here are FIXED.** All were
  assertions that were only *usually* true, and they are worth reading before
  blaming a seed for a new one.
  - `test_title_letters.gd`'s portal and vortex tests (31 Oct 2026) passed or
    failed with the machine's speed. They waited `wait_frames(3)`, which GUT
    counts in `_physics_process`, but the portal only fits itself in `_process`
    (`MenuPortal._process`). On a slow first frame several physics ticks run
    before one process frame, so the test read an unfitted oval (size 0, the
    shader's parameters null). Adding the heading-font rule made the menu's
    first frame slightly heavier and the failure regular. A debug print of
    `portal._last` per frame showed it fitting on the fifth wait. The file now
    waits `wait_process_frames`, the clock the portal and layout run on.
    **`wait_frames` is deprecated in this GUT and means physics frames**: use
    `wait_process_frames` for anything that waits for layout, drawing or `_process`.
  - `test_card_system.gd::test_simple_cards_of_the_set` (27 Oct 2026) got 2
    shields from Shrug it Off about one run in 400. The card it deals is random
    and reaches the pack before `card_used` fires for Shrug it Off, so a dealt
    After Image shields on the way in. A 400-play stress loop showed the 2 every
    time After Image was dealt and never otherwise; the test now adds whatever
    the dealt card's `card_used` triggers grant.
  - `test_statuses.gd`'s Speed and Marked tests (20 Oct 2026) failed only in
    FULL runs, a different one each time, and never alone or across 80 seeds of
    `seed()`, because the offering's random enemy is not drawn off the global
    seed. They stood a random body and assumed its turn was a step and its
    Health one goal's worth. Forcing each of the 25 ability-carrying enemies'
    abilities onto the body in turn found it: a Host or a Mysterious Tree spends its turn
    without walking. They now call the file's own `_disarm_board()` (and the
    shield test sets the body's Health to 2, as its sibling does), the fix
    CLAUDE.md already names for this.
  - `test_overworld2.gd::test_leaving_the_haul_screen_lands_the_shelf_under_the_board`
    failed roughly one full-suite run in six, and only in a FULL run, which is
    what made it look like cross-file leakage. It isn't: `before_each` →
    `_open_at_first_offering` takes `choose_start(0)`, the first of a **random**
    offering, and once in a while that opening game was one of the ten hubs
    (which sold until §19.7) — at which point walking off its haul screen
    mounted that hub's shelf, exactly as it should. The test then asserted `_shop_panel` was null "while the haul is
    up" and found the OPENING game's shop sitting there. The behaviour was never
    wrong; the test now calls `_ui._clear_shop()` first so it starts from the
    state it is actually about, whatever the opening rolled.
  - `test_overworld2.gd::test_the_page_still_fits_the_window_with_machines_standing_on_it`
    was a **real thin margin, not a bad assertion**: the page with three machines
    under the board measured 616px of the 625px a 720p window leaves, and the
    left column's height rides on the run's random offering and checklist, whose
    goal text wraps differently game to game — so one extra wrapped line
    overflowed it. The page got 26px back out of its own CHROME (both left
    panels' content margin 12->8, the gap between them 10->8, the four gaps
    inside the select panel 8->6), which also widens their text so fewer lines
    wrap at all. The left column now measures 590 and the binding column is the
    RIGHT one at 594 — the board and the pack, which do not wrap.
  - `test_overworld2.gd::test_the_checklist_follows_a_reroll_of_the_board`
    failed about one run in twelve and outlived three attempts to explain it —
    including two confident wrong ones (a mid-test tier crossing, and a
    board-bounds leak), both ruled out by probing the board rather than by
    argument. **`reroll_enemies` rolls each body independently, so two bodies can
    swap enemies WITH EACH OTHER**: a real re-roll, two swaps reported, and the
    board carrying the pair it started with. The checklist GROUPS by when a goal
    settles (`ReportChecklist._bodies_settled_at_the_end` / `_bodies_settled_now`)
    rather than listing the stack in order, so the same two goals in the other
    order render byte for byte the same. Caught by printing the swap count and
    the before/after names: `2 swapped; ["Monkey", "Floating Eye"] -> ["Floating
    Eye", "Monkey"]`. The test stands ONE body now, where the exclusion
    guarantees a different enemy and a reported swap has to change the list.
    **The lesson is the diagnostic, not the fix**: three runs were spent guessing
    because the assertion printed two identical blocks of text and nothing else.
  - `test_enemy_abilities.gd` dropped **one test, and which one depended on the
    seed** — the spawner, the illusionist and the summoned-body payout.
    **The cause was the FOOTPRINT, not the board being full.** All three authored
    their ability as `tier:low`, so `GameLoop2.roll_ability_enemy` drew a RANDOM
    low-tier body — and `_brood_cell` asks `fits_at`, which is about the body's
    footprint (§7.3). A rolled body wider than one cell does not fit the single
    square in front of the spawner, `_brood_cell` answers OFF_FIELD, and nothing
    is laid: correct behaviour ("a spawner with no space simply does not spawn
    this turn"). Those three now name a one-cell body through `_one_cell_selector()`
    (`enemy:<id>`, picked out of the roster by shape rather than hardcoded), and
    `test_a_spawner_with_nowhere_to_lay_a_body_lays_nothing` asserts the other
    half on purpose. If a spawner test starts varying again, look at what the
    selector rolls before anything else.
  - **Eight more in `test_overworld2`, and the same two causes six times over.**
    Found with a stress loop — the one test run 40-50 times in a single process,
    with `before_each`/`after_each` between — which turned "one full run in
    several" into a rate, and then a print of the board on each failure. Before
    blaming a seed, check these two: **the random offering stands a BOSS** about
    one run in seven (a boss is bomb-immune, survives a goal hit, and pays a
    chest of its own on top of the win's), and **the road stands bodies up at the
    end of ANY game** (`pressure()`, §19.5, counted in `last_result["end_spawns"]`),
    so a head count after a report is not a fact about the body you acted on.
    Follow THAT body by instance (`GameLoop2.entry_for`), and stand a known one
    with `_make_front_body(&"monkey")` when the test needs a plain one-hit body.
    A third (until §19.10 retired them): node kinds were dealt per run, so a
    helper that picked "the first game in the catalog" was sometimes standing
    on a Shop, which paid no event.
    **Never run two GUT processes at once**: they share `user://`, race on
    `slot_0.json`, and produce a spray of failures that are not flakes at all.
  - **Two goal-tick tests** (`test_confirming_a_goal_kills_the_enemy_there_and_then`,
    `test_fulfilling_a_follower_goal_defeats_and_drops_it`) failed about one run
    in sixty: a ticked goal is ONE hit, and the offering now and then rolls an
    enemy authored with more Health (a Mysterious Tree has 3), which took the hit,
    stood, and dropped nothing. A stress loop printing the body on failure named
    it. Tests that expect the kill now call `_one_hit(instance)` on the body they
    tick, and so does `_solo_with_bonus` (a bonus pays with its body).
  - `test_items2.gd::test_lords_parasol_takes_the_whole_shelf_for_nothing` counted
    the pack after the sweep and failed when the rolled shelf held an **Ultra
    Duplicator**, which copies the relic swept after it (one more than the shelf).
    It now checks each shelf relic is owned, by id.
  - `test_overworld2.gd::test_bash_refills_the_slot_from_a_connected_game` failed
    when the run laid a **rift** beside the hub it stands at: `_first_bashable`
    took the first non-Amulet card, and bashing a rift card keeps the slot and
    brings another game through it (`bash_rift`), so no slot was "bashed" and no
    new game appeared. Confirmed by bashing rift cards on purpose in a stress
    loop. Both bash helpers now skip rift and Rift Key cards.
  - `test_overworld2.gd::test_the_page_still_fits_the_window_with_a_shop_on_it`
    failed about one run in three at "needs 642 of 625", and **the random part
    was the CHARACTER**, not the map. With a shop under it the board's width is
    the hero's shield row; three shields made it narrow enough that the pressure
    strip's small print wrapped to a second row (+20px). Found by dumping the
    page's Control tree with sizes on a passing and a failing run and diffing the
    two: same text, same grid, board 406 vs 369px. A layout test that varies is
    usually a WIDTH that varies upstream of a wrap; look for the wrap first.
  - `test_overworld2.gd::test_report_goal_met_defeats_and_drops` failed once in a
    full suite run ("[3] expected to equal [2]") and passed six reruns in a row.
    The random offering had stood **Mysterious Tree**, the one enemy authored at
    **Health 3**: a met goal deals one hit, so the tree took it, survived stunned
    (§7.2), and the body count came out one over. Confirmed by giving the arrived
    bodies 3 Health on purpose, which failed the same way every time.
    `_disarm_board` now sets every non-boss body to Health 1, beside the
    abilities and goal modes it already strips. Bosses keep theirs, since their
    phases are what a boss is.
