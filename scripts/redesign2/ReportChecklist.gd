class_name ReportChecklist
extends RefCounted

# The checklist half of the overworld's stage — the left column, in both of its
# states.
#
# WHILE CHOOSING it is the STANDING list (populate_standing): the goals already
# on you, read-only, because there is nothing to report until a game is in play.
# WHILE PLAYING it is the REPORT step (populate_play_panel): the same list grown
# tick boxes, plus the launch and rate buttons, which is what the honour system
# is actually made of.
#
# It also owns the pairing between a checklist row and a body on the board —
# they are the same fact written twice, and lighting one lights the other
# (bind_row_to_body / light_bodies / on_enemy_hovered).
#
# Split out of Overworld2 (docs/performance-backlog.md §1), the largest of the
# seams that file measures. The page still owns the two containers this fills
# (`_verify_box` and `_launch_row`, built in Overworld2._build_ui) and still
# decides when to rebuild; everything this needs of the run it reads through the
# page or asks GameLoop2 / GameState for directly, exactly as it did inline.
#
# `_page` is the Overworld2 that owns this checklist, typed loosely because
# Overworld2 names ReportChecklist and two class_names that name each other are a
# cyclic reference Godot resolves badly.
var _page: Node = null
var _box: VBoxContainer = null       # the page's _verify_box
var _launch: HBoxContainer = null    # the page's _launch_row

# The per-game tick state, PUBLIC because it is this class's whole output and the
# page publishes read-only views of it under the names the tests already use.
# Five parallel arrays that must be cleared as one (reset_state).
var fulfil_checks: Array = []        # [{check: CheckBox, instance: int}]
# Statuses 2.0 (§13) on the report checklist. `status_goal_checks` are the
# player's own BUFF goals — extra rows that pay when ticked, plus the `demand` rows
# that BITE when they are not; `bonus_checks` are the OPTIONAL bonus objectives an
# enemy's `bonus` side hangs off it; `instead_checks` are the "or instead" rows a
# burned enemy grows, each a second way to clear that body. All three are read into
# beat_game's `claims` on report; the required clauses (enemy buffs, player
# clauses) need no boxes of their own because they are folded into the goal line.
# `status` here is an OBJECTIVE KEY, not a bare status id: a status held both for
# good and on loan has one row per instance (GameState.status_objectives), and the
# key is what tells the claim which of them was ticked. For the permanent bucket
# the key IS the bare id, so the name still reads true for the common case.
var status_goal_checks: Array = []   # [{check: CheckBox, status: String}]
var bonus_checks: Array = []         # [{check: CheckBox, instance: int, status: StringName}]
var instead_checks: Array = []       # [{check: CheckBox, instance: int, status: StringName}]
# Bindings for the two event-borne sections, cleared with the rest in reset_state.
# Each entry is {check, index into GameState's array}.
var event_goal_checks: Array = []
var curse_goal_checks: Array = []
var levelup_check: CheckBox = null   # null when the character has no level-up
# Checklist row -> board body (see bind_row_to_body). `row_paints` is instance ->
# the paint callables of every row written about that body; `lit_instances` is
# what is lit right now, from whichever end the mouse is on.
var row_paints: Dictionary = {}
var lit_instances: Dictionary = {}

# This half's repaint guard — the standing list's signature. See the
# "repaint guards" block in Overworld2, which explains all three of them.
var _sig: String = ""

# The REPORT step's own signature: what the tick-box list was built to say about
# the board. The standing list's guard above stops it repainting when nothing
# changed; this one does the opposite job — it is how the page notices that
# something DID, while a game is in play (see play_panel_stale).
var _play_sig: String = ""

func _init(page: Node, box: VBoxContainer, launch: HBoxContainer) -> void:
	_page = page
	_box = box
	_launch = launch

# Build the self-report panel for the chosen game: a launch button (when the
# game can be launched) and a fulfilment checkbox per following enemy so old
# goals can be cleared this game (§2).
func populate_play_panel() -> void:
	# The report step and the standing checklist share _box, so taking it
	# over here has to drop the standing list's signature — otherwise the next
	# return to the offering would match a signature describing rows this panel
	# replaced, and leave the report step's checklist on screen. Not guarded
	# itself: it holds the player's TICKS, and rebuilding it is what the tick
	# handlers rely on.
	# NOTHING TO BUILD ON. This is reachable a frame late (_rebuild_soon), by which
	# time the page may have been torn down — a test that freed the overworld, a
	# run that ended — and the containers below belong to it.
	if _page == null or not is_instance_valid(_page) \
			or _box == null or not is_instance_valid(_box) \
			or _launch == null or not is_instance_valid(_launch):
		return
	# …or the run may simply have moved on to the next screen while the rebuild was
	# in the queue. Asked BEFORE the clears, not after: emptying the box and then
	# returning is how the standing checklist gets wiped by a game that is over.
	if _page._chosen.is_empty():
		return
	_sig = ""
	_play_sig = _play_panel_sig()
	_page._clear(_launch)
	_page._clear(_box)
	reset_state()
	var game: GameData = _page._chosen["game"]
	# "Open the real game" — launches the executable/shortcut in the game's
	# file_location column (falling back to its store page). Only games with a
	# launch target get the button.
	if game.has_launch_target():
		var play_btn := Button.new()
		play_btn.text = "▶  Play %s" % game.display_name
		play_btn.custom_minimum_size = Vector2(0, 38)
		play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play_btn.add_theme_stylebox_override("normal", UITheme.flat(Color(0.10, 0.22, 0.16, 0.9), 8, 8, 1, Color(0.4, 0.9, 0.6)))
		play_btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
		play_btn.pressed.connect(func(): game.launch())
		_launch.add_child(play_btn)
	# NO ★ RATE BUTTON HERE ANY MORE. It sat under the Play button, which offered
	# the score while the game was still in front of the player — the one moment
	# they have not finished forming the opinion it is asking for. It lives on the
	# haul screen now (PostCombatScreen._rate_button), beside the cover of the game
	# that just ended, which is where there is finally something to say.

	# One clean checklist of everything to verify this game. Tick what you actually
	# did, then press "Completed Game" once (§2 / §3.1):
	#   • EVERY ENEMY on the board, in one list — the ones that walked on when you
	#     took this game and the ones that have been following you for ten;
	#   • the character LEVEL-UP challenge;
	#   • the event and curse goals.
	#
	# THERE IS NO "GOAL" BOX. The enemy the card advertised used to get an
	# emphasised row of its own at the top, because it was the game's own enemy and
	# beating the game was what cleared it. Nothing is a game's own enemy any more
	# (GameLoop2.arrivals): a body that walked on this game and a body you have
	# owed since three games ago are the same kind of debt, and asking about them
	# in two different places said they were not.
	_box.add_child(_verify_head("Tick what you did this game:"))

	# On the Amulet, playing the game is the win — not any goal on this list (see
	# report()). Said at the top, because a checklist is otherwise exactly where a
	# player would look for the win condition and not find it.
	if bool(_page._chosen.get("amulet", false)):
		var win_note := Label.new()
		win_note.text = "🏆  Completing this game wins the run — everything below is a bonus."
		win_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		win_note.add_theme_font_size_override("font_size", 12)
		win_note.add_theme_color_override("font_color", UITheme.GOLD)
		_box.add_child(win_note)

	# The player's own standing rows (§13): challenges that pay out every game you
	# satisfy them, and the `demand` rows that CHARGE for every game you don't — so
	# they are on the report step of EVERY game rather than belonging to any one
	# enemy. A demand is tinted like the threat it is: on this list an unticked box
	# usually means a prize forgone, and on that one row it means a bill.
	for row in GameState.status_objectives():
		var sd: StatusData = row["status"]
		var stacks: int = int(row["stacks"])
		# A BORROWED goal says so on the row itself, not only in its hover
		# (docs/potions-design.md §5.3): this is the line the player reads to decide
		# what to chase, and one that expires tonight is a different offer.
		var games: int = int(row.get("games", 0))
		# ONE ROW PER INSTANCE (§5.4): the stacks the run owns and every borrowed
		# application beside them, each with its own clock, its own tick and its own
		# payout. `key` is what holds two rows of the same status apart everywhere
		# downstream — the tick, the claim, the demand's bill.
		var key: String = String(row["key"])
		var srow := verify_row(
			"%s %s%s" % [_status_prefix(sd, stacks),
				sd.objective_text(StatusData.PLAYER, stacks),
				StatusData.clock_suffix(games)],
			_status_row_tint(sd), false, null, null, 0,
			_status_mark(sd, stacks, StatusData.PLAYER, false, games))
		_box.add_child(srow["row"])
		status_goal_checks.append({"check": srow["check"], "status": key})
		# A `demand` is the one row where confirming buys something other than a
		# reward: it is what stops the bill at the end of the game (§13), and it
		# stops it whether it was answered now or at the report.
		_arm_row(srow["check"], "status:%s" % key,
			"You met %s." % sd.display_name,
			func() -> void:
				if GameLoop2.claim_player_objective(key):
					_announce("%s paid out." % sd.display_name, UITheme.GOLD)
				else:
					_announce("%s is answered for this game." % sd.display_name,
						UITheme.TEXT_DIM))

	# Level-up challenge (§3.1): a per-game Yes/No for the character's condition,
	# with its reward shown inline so the payoff reads at a glance. It carries its
	# own Notes button for the same reason the goal rows do — the condition is a
	# standing one, and how you satisfied it is a fact about THIS game.
	var ch: CharacterData = Data.get_character2(GameState.character_id)
	if ch != null and ch.level_up_condition != "":
		var lu_text: String = "Leveled up — %s" % ch.level_up_condition
		if ch.level_up_reward != "" and ch.level_up_reward.to_upper() != "N/A":
			lu_text += "   → %s" % ch.level_up_reward
		var lu_row := verify_row(lu_text, UITheme.GOLD, false, null, ch)
		levelup_check = lu_row["check"]
		_box.add_child(lu_row["row"])
		var game_now: GameData = _page._chosen.get("game")
		_arm_row(lu_row["check"], LEVELUP_KEY,
			"You met %s's level-up condition." % ch.display_name,
			func() -> void:
				GameLoop2.mark_row_answered(LEVELUP_KEY)
				_page._apply_level_up()
				if game_now != null:
					GameStats.record_level_up(game_now.id, GameState.character_id)
				_announce("Levelled up — %s." % ch.level_up_condition, UITheme.GOLD))

	# EVENT GOALS and CURSE GOALS (docs/event-sheet-authoring.md §5). Their own
	# sections, deliberately: the checklist now carries three kinds of objective
	# and they bite in three different ways. An enemy goal is a DEBT — miss it and
	# it follows you and hits. An event goal is a BONUS — miss it and it merely
	# expires. A curse is a BILL, and the only row here you tick to say you did
	# something WRONG. Rendering all three alike would misrepresent which one
	# hurts, so the curse rows are purple and sit apart.
	_add_event_goal_rows()

	# GOAL FIRST, then whose it is. The checklist is scanned for "what did I
	# actually do", and the goal is the part being answered — the enemy's name is
	# the label on it. Leading with the name made every row start with a proper
	# noun the player has to read past to reach the thing they're ticking.
	#
	# EVERY body on the board, on the same terms and in board order. The ones that
	# walked on when this game was taken are simply the last ones in the list.
	for entry in GameLoop2.stack:
		var inst: int = int(entry["instance"])
		var e: GoalEnemyData = entry["enemy"]
		var row := verify_row("Cleared: %s — %s" % [
			GameLoop2.goal_text_for(entry), e.display_name], UITheme.TEXT, false, e, null, inst)
		_box.add_child(row["row"])
		fulfil_checks.append({"check": row["check"], "instance": inst})
		_arm_goal_row(row["check"], inst, e)
		_add_instead_rows(entry)
		_add_bonus_rows(entry)
	# A BODY YOU ALREADY KILLED THIS GAME still has a line on this list, and its
	# bonus is still claimable off it (§2.1). Without this the row for a cleared
	# enemy vanished on the next repaint and took the optional objective you had
	# earned with it — silently, and only for the players who ticked in the
	# "wrong" order.
	for inst in GameLoop2.cleared_this_game.keys():
		if GameLoop2.entry_for(int(inst)).is_empty():
			_add_ghost_rows(int(inst))

# The rows a body defeated MID-GAME leaves behind: its own, ticked and locked, and
# whatever bonus objectives it was carrying, still open.
func _add_ghost_rows(instance: int) -> void:
	var entry: Dictionary = GameLoop2.ghost_for(instance)
	if entry.is_empty():
		return
	var e: GoalEnemyData = entry.get("enemy")
	if e == null:
		return
	var row := verify_row("Cleared: %s — %s" % [
		GameLoop2.goal_text_for(entry), e.display_name],
		UITheme.TEXT, false, e, null, 0)
	_box.add_child(row["row"])
	_lock_row(row["check"])
	_add_bonus_rows(entry)

# One enemy's goal row. Confirming it deals the goal's hit THERE AND THEN — the
# body dies if that is enough, and its loot lands on the square it fell in (§8.2)
# for you to go and pick up while the game is still on.
func _arm_goal_row(cb: CheckBox, instance: int, enemy: GoalEnemyData) -> void:
	var name_of: String = enemy.display_name if enemy != null else "it"
	_arm_row(cb, "goal:%d" % instance,
		"You cleared %s's goal." % name_of,
		func() -> void:
			var standing: int = GameLoop2.stack.size()
			var at_game: GameData = _page._chosen.get("game")
			GameLoop2.fulfill(instance, true)
			var gone: bool = GameLoop2.entry_for(instance).is_empty()
			# Banked here rather than at the report, because the report can no
			# longer see it: the body it would have looked up is already off the
			# board. Against the GAME it happened at and the CHARACTER who did it,
			# exactly as report() banks the ones it resolves itself.
			if gone and at_game != null and enemy != null:
				_page._record_defeat(at_game, enemy)
			_announce(
				("%s is down — its loot is on the board." % name_of if gone
					else "%s took the hit, and is holding its fire." % name_of),
				UITheme.SUCCESS if gone else UITheme.GOLD)
			# The list itself changes shape when a body leaves it, so it is rebuilt
			# — safely, because every answered row is remembered by the loop, and
			# DEFERRED, because the box being locked a line above is one of the
			# children the rebuild frees.
			if gone and standing > GameLoop2.stack.size():
				_rebuild_soon())

# The two event-borne sections of the checklist. Both count down in games, and
# both show how long is left — an objective with a clock on it is a different
# decision on its last game than on its first, and the player cannot see the
# clock anywhere else.
func _add_event_goal_rows() -> void:
	for i in range(GameState.event_goals.size()):
		var goal: Dictionary = GameState.event_goals[i]
		var left: int = int(goal.get("games_left", 0))
		var text: String = "Event goal — %s   → %s   (%d %s left)" % [
			goal.get("condition", ""), goal.get("effects_text", ""),
			left, "game" if left == 1 else "games"]
		var row := verify_row(text, UITheme.ACCENT, false)
		_box.add_child(row["row"])
		event_goal_checks.append({"check": row["check"], "index": i})
		# CLAIMED ON THE SPOT, and claiming it takes it off GameState's list — which
		# is why there is no row key for it: the row is simply not built again. The
		# goal is looked up by IDENTITY rather than by the index captured here,
		# because an earlier claim in the same game has already shifted the indices
		# under it.
		var goal_row: Dictionary = goal
		_arm_row(row["check"], "event:%d:%s" % [i, goal.get("condition", "")],
			"You met the event goal: %s." % goal.get("condition", ""),
			func() -> void:
				var at: int = GameState.event_goals.find(goal_row)
				if at < 0:
					return
				var claimed: Dictionary = GameState.claim_event_goal(at)
				if claimed.is_empty():
					return
				var src: EventData2 = Data.get_event2(StringName(claimed.get("event", &"")))
				var line: String = src.goal_met if src != null and src.goal_met != "" \
					else "Event goal met — %s." % claimed.get("effects_text", "")
				_announce(line, UITheme.ACCENT)
				_rebuild_soon())

	for i in range(GameState.curse_goals.size()):
		var entry: Dictionary = GameState.curse_goals[i]
		var cd: CurseData2 = Data.get_curse2(StringName(entry.get("curse", &"")))
		if cd == null:
			continue
		var left: int = int(entry.get("games_left", 0))
		# A CURSE IS A ROW LIKE ANY OTHER: an instruction, ticked if you followed
		# it, with what it costs you written after it. It used to be phrased as the
		# rule instead — "If you use a rest site to replenish health, spawn a random
		# enemy when you report the game" — with a box that fired the penalty when
		# you CHECKED it. That made it the one row on this list whose tick meant the
		# opposite of every other row's, and it read as a confession rather than as
		# something to go and do. Unticked is the failure here exactly as it is on
		# the goal above it; the difference is only what failing costs.
		var text: String = "%s — %s   if failed, %s   (%s)" % [
			cd.display_name, cd.goal_text(), cd.penalty_text,
			CurseData2.window_text(left)]
		var row := verify_row(text, UITheme.CURSE, false)
		_box.add_child(row["row"])
		curse_goal_checks.append({"check": row["check"], "index": i})
		# THE ONE ROW WITH NOTHING TO RESOLVE. A curse pays no reward for being
		# followed; what ticking it buys is the penalty NOT firing at the end of the
		# game, and that is settled at the report either way (resolve_event_goals).
		# It still confirms and still locks, because it is still a claim about what
		# you did, and this list does not take those back.
		var curse_key: String = "curse:%d:%s" % [i, cd.id]
		_arm_row(row["check"], curse_key,
			"You followed %s: %s." % [cd.display_name, cd.goal_text()],
			func() -> void:
				GameLoop2.mark_row_answered(curse_key)
				_announce("%s followed — it will not bite this game." % cd.display_name,
					UITheme.CURSE))


# Pay out whatever the player ticked in those two sections. Claims are resolved
# HIGHEST INDEX FIRST because claiming an event goal removes it from the array,
# and a low-index removal would shift every index recorded after it.
func resolve_event_goals() -> void:
	var claimed: Array = []
	for entry in event_goal_checks:
		# Skipping the ones already claimed mid-game (§2.1) — and skipping them
		# MATTERS here rather than merely being tidy: claiming an event goal removes
		# it from GameState's list, so the index this row recorded now points at a
		# different goal entirely.
		if _open_claim(entry.get("check")):
			claimed.append(int(entry.get("index", -1)))
	claimed.sort()
	claimed.reverse()
	for idx in claimed:
		var goal: Dictionary = GameState.claim_event_goal(idx)
		if goal.is_empty():
			continue
		var src: EventData2 = Data.get_event2(StringName(goal.get("event", &"")))
		var line: String = src.goal_met if src != null and src.goal_met != "" else \
			"Event goal met — %s." % goal.get("effects_text", "")
		Notifications.notify(line, UITheme.ACCENT)
		GameLog.add(line, UITheme.ACCENT)

	# A curse fires but does NOT clear — that is what separates it from a goal.
	# Breaking it twice across two games costs twice; only the timer removes it.
	#
	# UNTICKED is what fires it. The row is an instruction (see
	# _add_event_goal_rows), so a box left empty says the player did not follow it
	# — the same thing an empty box says on every other row of the checklist.
	var triggered: Array = []
	for entry in curse_goal_checks:
		var check: CheckBox = entry.get("check")
		if check != null and is_instance_valid(check) and not check.button_pressed:
			triggered.append(int(entry.get("index", -1)))
	for idx in triggered:
		var fired: Dictionary = GameState.trigger_curse_goal(idx)
		if fired.is_empty():
			continue
		var cd: CurseData2 = Data.get_curse2(StringName(fired.get("curse", &"")))
		if cd != null:
			var line: String = "%s bites — %s." % [cd.display_name, cd.penalty_text]
			Notifications.notify(line, UITheme.CURSE)
			GameLog.add(line, UITheme.CURSE)


# Every `demand` the report left unanswered, and what it cost (§13). Says what the
# hit was for AND what stopped it: a burn the tries absorbed whole took no Health,
# and a line that only quoted the 3 would read as a lie next to an unmoved bar.
func announce_status_penalties(res: Dictionary) -> void:
	for raw in res.get("status_penalties", []):
		if not (raw is Dictionary):
			continue
		var bite: Dictionary = raw
		var sd: StatusData = Data.get_status(StringName(bite.get("status", &"")))
		if sd == null:
			continue
		var dealt: int = int(bite.get("damage", 0))
		var blocked: int = int(bite.get("blocked", 0))
		var line: String = "%s bites — %d damage" % [sd.display_name, dealt]
		if blocked > 0:
			line += ", %d absorbed by the tries" % blocked
		line += "."
		Notifications.notify(line, UITheme.DANGER)
		GameLog.add(line, UITheme.DANGER)

# The OPTIONAL bonus rows an enemy's `bonus` sides hang off it (§13) — "and if you get 3
# achievements, gain +3 Small Chests". A row of its own rather than part of the
# goal line, because claiming it is a separate decision from meeting the goal: an
# enemy you failed can still pay its bonus, and one you beat need not have.
# The "or instead" rows a burned enemy grows (§13) — the SECOND WAY to clear this
# body, ticked when the player did the alternative rather than the goal.
#
# A row of its own and not a second reading of the goal row, because the two answer
# different questions and the run records them differently: ticking the goal says
# the enemy's condition was met, and this one says it never was. So this row
# deliberately carries NO Notes button — `verify_row` only grows one when it is
# handed the enemy — since a note here would be a note about how you beat a goal you
# didn't do. Same reason `ticked_status_claims` keeps these out of the fulfilments
# the report records defeats from.
func _add_instead_rows(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var instance: int = int(entry.get("instance", 0))
	for row in GameLoop2.alternatives_for(entry):
		var sd: StatusData = row["status"]
		var stacks: int = int(row["stacks"])
		var games: int = int(row.get("games", 0))
		var irow := verify_row("%s or instead: %s%s" % [
			_status_prefix(sd, stacks), sd.alternative_text(StatusData.ENEMY, stacks),
			StatusData.clock_suffix(games)],
			UITheme.GOLD.lerp(UITheme.TEXT, 0.3), false, null, null, instance,
			_status_mark(sd, stacks, StatusData.ENEMY, false, games))
		_box.add_child(irow["row"])
		instead_checks.append({"check": irow["check"], "instance": instance,
			"status": sd.id})
		# CLEARS THE BODY, so it resolves like the goal row it stands in for — the
		# hit, the drop, the lot. Keyed on the INSTANCE and not on the status:
		# clearing a body is clearing a body, so a second `instead` on the same one
		# has nothing left to do and locks with it.
		var alt_name: String = enemy_name_of(instance)
		_arm_row(irow["check"], "instead:%d" % instance,
			"You cleared %s the other way." % alt_name,
			func() -> void:
				var standing: int = GameLoop2.stack.size()
				GameLoop2.fulfill_instead(instance, sd.id)
				GameLoop2.mark_row_answered("instead:%d" % instance)
				var gone: bool = GameLoop2.entry_for(instance).is_empty()
				_announce(
					("%s is down the other way — its loot is on the board." % alt_name
						if gone else "%s took the hit, and is holding its fire." % alt_name),
					UITheme.SUCCESS if gone else UITheme.GOLD)
				if gone and standing > GameLoop2.stack.size():
					_rebuild_soon())
	# A BOSS CARRYING ONE SAYS SO (§7.1). The way out is void on a boss — its goal
	# is the only thing that takes it off the board — and until now that was said
	# by drawing nothing at all, which is indistinguishable from the burn having
	# failed to apply. A row with no tick box on it, in the dimmed colour the rest
	# of the read-only lines use.
	for row in GameLoop2.nullified_alternatives_for(entry):
		_box.add_child(_nullified_row(row))

func _add_bonus_rows(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var instance: int = int(entry.get("instance", 0))
	for row in GameLoop2.bonus_objectives_for(entry):
		var sd: StatusData = row["status"]
		var stacks: int = int(row["stacks"])
		var games: int = int(row.get("games", 0))
		var brow := verify_row(
			"%s %s%s" % [_status_prefix(sd, stacks),
				sd.objective_text(StatusData.ENEMY, stacks),
				StatusData.clock_suffix(games)],
			UITheme.GOLD.lerp(UITheme.TEXT, 0.3), false, null, null, instance,
			_status_mark(sd, stacks, StatusData.ENEMY, false, games))
		_box.add_child(brow["row"])
		bonus_checks.append({"check": brow["check"], "instance": instance, "status": sd.id})
		var key: String = "bonus:%d:%s" % [instance, sd.id]
		_arm_row(brow["check"], key,
			"You did %s's bonus objective." % enemy_name_of(instance),
			func() -> void:
				if GameLoop2.claim_enemy_bonus(instance, sd.id):
					GameLoop2.mark_row_answered(key)
					_announce("%s paid out." % sd.display_name, UITheme.GOLD))

# What colour a player-side status row reads in. GOLD is the checklist's colour
# for "something you can earn"; a `demand` is the one row where leaving the box
# empty COSTS something, so it takes the danger tint the curse rows established.
func _status_row_tint(status: StatusData) -> Color:
	return UITheme.DANGER if status.is_demand(StatusData.PLAYER) else UITheme.GOLD

# How a status announces itself on a checklist row: its SYMBOL — the same art the
# board draws as a pip — and the stack count. "×3 —" carries the X the rest of the
# line was written against, which is the number the player has to hold in their
# head while they play; the art carries which status is asking, in the one form
# the player is already reading it in everywhere else (the hero strip, an enemy's
# pips, its card). The name is what the symbol is FOR, so spelling it out beside
# the icon is the row saying the same thing twice, on a list that has to stay
# glanceable.
#
# The name comes back when a status has no art (`_status_mark` returns no icon):
# an unlabelled row for a status with nothing to show would be a row that never
# says what it is.
func _status_prefix(status: StatusData, stacks: int) -> String:
	if status.image != null:
		return "×%d —" % stacks
	return "%s %d —" % [status.display_name, stacks]

const STATUS_ICON_SIZE := 22

# The symbol itself, as a row-leading chip — or null for a status with no art, in
# which case `_status_prefix` has already fallen back to the name. Carries the
# status's OWN hover card (the one the board's pips use), so the icon is not a
# symbol the player has to have memorised: it answers what it is, at what stack,
# and what that side does, in the same words the pip would.
func _status_mark(status: StatusData, stacks: int, which: StringName,
		nullified: bool = false, games: int = 0) -> Control:
	if status == null or status.image == null:
		return null
	var frame := PanelContainer.new()
	var tint: Color = _status_row_tint(status) if which == StatusData.PLAYER else UITheme.GOLD
	frame.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG, 4, 2, 1, tint.lerp(UITheme.BORDER, 0.35)))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.add_child(UITheme.crisp_tex(status.image, STATUS_ICON_SIZE))
	HoverCard.attach(frame, status.hover_card(which, stacks, nullified, games))
	return frame

# Every per-game checklist binding, dropped together. Five parallel arrays that
# must be cleared as one — a stale CheckBox left in any of them is a claim read
# off a freed node on the next report.
# --- a tick is a confirm, and a confirm resolves NOW (§2.1) ------------------
#
# The report used to be the only moment anything on this list could happen. That
# was fine while a game was one long wait for a single point; it is wrong now that
# the board moves whenever you fail and a kill is something you can go and make.
# So every box here asks once — "did you really?" — and on Yes the row RESOLVES on
# the spot: the enemy takes its hit and drops its loot on the board (§8.2), the
# reward is paid, the level is taken. Mid-game, while you are still playing.
#
# THERE ARE NO TAKE-BACKS. The confirm is the safeguard, and once past it the row
# locks: an enemy that is already dead cannot be un-killed, and a reward already
# in the pack cannot be handed back. (The Undo beside the lost-run tracker is a
# different thing — it takes back a TURN, which is the board's, not yours.)
#
# What a row has been answered for is remembered by GameLoop2, not by these
# boxes: the page rebuilds this list on every repaint, and a tick you cannot take
# back must not be something a repaint can lose.

# Lock a row that has been answered — visibly done rather than merely disabled,
# because a greyed-out box reads as "you can't" and this one means "you did".
func _lock_row(cb: CheckBox) -> void:
	if cb == null or not is_instance_valid(cb):
		return
	# `button_pressed`, not the no-signal setter: the row's green wash hangs off
	# `toggled` (see verify_row), and a rebuilt list has to repaint it.
	cb.button_pressed = true
	cb.disabled = true
	cb.add_theme_color_override("font_disabled_color",
		UITheme.SUCCESS.lerp(Color.WHITE, 0.55))
	cb.tooltip_text = "Done this game — it resolved when you confirmed it."

# Wire one row's box to the confirm. `key` is what GameLoop2 remembers it by (see
# row_answered); `what` is the sentence the confirm asks about; `on_yes` is what
# resolving it actually does, and runs exactly once.
func _arm_row(cb: CheckBox, key: String, what: String, on_yes: Callable) -> void:
	if cb == null:
		return
	if GameLoop2.row_answered(key):
		_lock_row(cb)
		return
	cb.toggled.connect(func(on: bool) -> void:
		if not on or cb.disabled:
			return
		ConfirmPanel.ask(_page, "Confirm this", CONFIRM_BODY % what, "Yes, I did it",
			func() -> void:
				if not is_instance_valid(cb) or cb.disabled:
					return
				on_yes.call()
				_lock_row(cb),
			func() -> void:
				if is_instance_valid(cb) and not cb.disabled:
					cb.button_pressed = false))

# One wording for all of them, because it is one promise. Says what is about to
# happen AND that it is final — a player who has to guess which half of that is
# true will tick nothing until the end of the game, which is the behaviour this
# whole change exists to stop.
const CONFIRM_BODY := ("%s\n\nThis resolves right now, while you are still "
	+ "playing — and it cannot be taken back.")

# The level-up's row key. One row, one character, one game — so it needs nothing
# in it to tell it apart from anything else.
const LEVELUP_KEY := "levelup"

# Whose body an instance is, for a confirm that has to name it. Reads the ghost
# too, so a row about an enemy you already killed still says who it was.
func enemy_name_of(instance: int) -> String:
	var entry: Dictionary = GameLoop2.entry_for(instance)
	if entry.is_empty():
		entry = GameLoop2.ghost_for(instance)
	var e: GoalEnemyData = entry.get("enemy")
	return e.display_name if e != null else "it"

# Rebuild the list once the frame that changed it is over. THROUGH THE PAGE, not
# through this object: a deferred call carries only an object id, Godot drops one
# whose object has gone, and the page is a Node whose lifetime the engine tracks —
# while this is a RefCounted the page holds, which can be released between the
# call being queued and the frame ending. That is what the crash was.
func _rebuild_soon() -> void:
	if _page != null and is_instance_valid(_page):
		_page.call_deferred("_populate_play_panel")

# Everything a resolved row has in common on the page: say what happened, and
# repaint the board, which may have just lost a body and gained a piece of loot.
func _announce(line: String, color: Color) -> void:
	GameLog.add(line, color)
	Notifications.notify(line, color)
	if _page == null or not is_instance_valid(_page):
		return
	if _page._board != null:
		_page._board.refresh()
	_page._refresh_stats()

func reset_state() -> void:
	# The rows are about to be freed, and with them every paint bound to a body.
	# Nothing is lit on a list that no longer exists, so the board is told too.
	row_paints.clear()
	if not lit_instances.is_empty():
		lit_instances = {}
		if _page != null and is_instance_valid(_page) and _page._board != null:
			_page._board.highlight([])
	fulfil_checks.clear()
	status_goal_checks.clear()
	bonus_checks.clear()
	instead_checks.clear()
	event_goal_checks.clear()
	curse_goal_checks.clear()
	levelup_check = null

# The checklist while you're CHOOSING: the goals already on you — the character's
# level-up challenge, and every follower's outstanding goal (any of which you may
# clear during whatever game you pick next, §2). Answering "what do I need to do?"
# belongs BEFORE you commit to a game, not only after, so the panel keeps its place
# beside the board instead of appearing out of nowhere on pick.
#
# Read-only by design: there is nothing to report until a game is in play, so these
# are rows rather than tick boxes.
func populate_standing() -> void:
	var sig: String = _standing_checklist_sig()
	if sig == _sig and _box.get_child_count() > 0:
		return
	_sig = sig
	_page._clear(_launch)
	_page._clear(_box)
	reset_state()
	_box.add_child(_verify_head("What you need to do:"))

	var ch: CharacterData = Data.get_character2(GameState.character_id)
	if ch != null and ch.level_up_condition != "":
		var lu_text: String = "Level up — %s" % ch.level_up_condition
		if ch.level_up_reward != "" and ch.level_up_reward.to_upper() != "N/A":
			lu_text += "   → %s" % ch.level_up_reward
		_box.add_child(_objective_row(lu_text, UITheme.GOLD))

	# Event goals and curses, read-only (docs/event-sheet-authoring.md §5). These
	# have to be here and not only on the report step: an event fires the moment a
	# game is beaten, and the goal it hands over lands while the player is still
	# looking at the OFFERING. Listing it only once a game is picked meant taking
	# on "beat a game in 1 attempt" and then being shown nothing about it until
	# after the decision it was supposed to inform.
	for goal in GameState.event_goals:
		var left: int = int(goal.get("games_left", 0))
		_box.add_child(_objective_row("Event goal — %s   → %s   (%d %s left)" % [
			goal.get("condition", ""), goal.get("effects_text", ""),
			left, "game" if left == 1 else "games"], UITheme.ACCENT))
	for entry in GameState.curse_goals:
		var cd: CurseData2 = Data.get_curse2(StringName(entry.get("curse", &"")))
		if cd == null:
			continue
		var left: int = int(entry.get("games_left", 0))
		# The same instruction the report step will ask about, because this list is
		# headed "What you need to do" and the answer for a curse is the thing to
		# do, not the rule it is derived from.
		_box.add_child(_objective_row("%s — %s   if failed, %s   (%s)" % [
			cd.display_name, cd.goal_text(), cd.penalty_text,
			CurseData2.window_text(left)], UITheme.CURSE))

	# The player's standing status buffs (§13) — goals that belong to no enemy and
	# are available at whatever game gets picked next.
	for row in GameState.status_objectives():
		var sd: StatusData = row["status"]
		var stacks: int = int(row["stacks"])
		var pgames: int = int(row.get("games", 0))
		_box.add_child(_objective_row(
			"%s %s%s" % [_status_prefix(sd, stacks),
				sd.objective_text(StatusData.PLAYER, stacks),
				StatusData.clock_suffix(pgames)],
			_status_row_tint(sd), null, 0,
			_status_mark(sd, stacks, StatusData.PLAYER, false, pgames)))

	# Followers, tinted the way the board tints them: the ones in the front column
	# are the goals worth clearing first, because they hit next game.
	for entry in GameLoop2.stack:
		var e: GoalEnemyData = entry["enemy"]
		var urgent: bool = GameLoop2.in_front(entry)
		var tint: Color = UITheme.DANGER if urgent else UITheme.GOLD.lerp(UITheme.TEXT, 0.4)
		# Goal first, then whose it is — same order as the report step, since these
		# are the same list in two states and the goal is what's being read for.
		# "dmg N" in words: the board's ⚔ badge is a fine-detail glyph that reads as
		# an ✕ at list-row sizes.
		var inst: int = int(entry.get("instance", 0))
		_box.add_child(_objective_row(
			"%s — %s   (dmg %d)" % [GameLoop2.goal_text_for(entry), e.display_name, e.damage],
			tint, _enemy_icon_rect(e, tint), inst))
		# The way out of that goal, if something burned this body (§13) — read here
		# rather than only on the report step, because it is a reason to play the
		# next game differently and this list is what is read before choosing one.
		for alt in GameLoop2.alternatives_for(entry):
			var asd: StatusData = alt["status"]
			var astacks: int = int(alt["stacks"])
			var agames: int = int(alt.get("games", 0))
			_box.add_child(_objective_row("%s or instead: %s%s" % [
				_status_prefix(asd, astacks),
				asd.alternative_text(StatusData.ENEMY, astacks),
				StatusData.clock_suffix(agames)],
				UITheme.GOLD.lerp(UITheme.TEXT, 0.3), null, inst,
				_status_mark(asd, astacks, StatusData.ENEMY, false, agames)))
		# …and the ones a boss is ignoring, said rather than left out (see
		# _add_instead_rows, which draws the same line on the report step).
		for dead in GameLoop2.nullified_alternatives_for(entry):
			_box.add_child(_nullified_row(dead, inst))
		for bonus in GameLoop2.bonus_objectives_for(entry):
			var sd: StatusData = bonus["status"]
			var stacks: int = int(bonus["stacks"])
			var bgames: int = int(bonus.get("games", 0))
			_box.add_child(_objective_row(
				"%s %s%s" % [_status_prefix(sd, stacks),
					sd.objective_text(StatusData.ENEMY, stacks),
					StatusData.clock_suffix(bgames)],
				UITheme.GOLD.lerp(UITheme.TEXT, 0.3), null, inst,
				_status_mark(sd, stacks, StatusData.ENEMY, false, bgames)))

	if GameLoop2.stack.is_empty() and GameState.status_objectives().is_empty():
		var none := _verify_head("Nothing is following you — pick a game and take on its goal.")
		_box.add_child(none)

# Everything the standing checklist draws, as one string — the guard for the
# rebuild above (see the repaint-guard block near the top of the file).
#
# It quotes the SAME calls the rebuild does rather than a summary of them
# (`goal_text_for` is the row's actual text, `in_front` is its tint), so a row
# whose wording changes for any reason at all changes the signature with it. That
# costs those calls twice on a rebuild, which is fine: they are string work, and
# what a rebuild actually pays for is the Labels.
#
# `_launch` is not represented because this function always leaves it empty —
# only the report step (populate_play_panel) puts anything in it.
# --- the report step going stale under the player -------------------------
#
# THE CHECKLIST IS A LIST OF GOALS, AND THE GOALS CAN CHANGE MID-GAME. A D10
# re-rolls every non-boss body where it stands (GameLoop2.reroll_enemies), a
# Scroll of Create Monster conjures one onto the stack, a bomb takes one off — and
# the report step was built once, when the game was taken, and never looked again.
# So a player who spent a die to escape a goal they could not do went on being
# asked about that goal by a list describing a board that no longer existed.
#
# It was not an oversight so much as a deliberate omission grown stale:
# `Overworld2._refresh` skips this panel on purpose, because it holds the player's
# TICKS and a repaint that dropped them would be worse than a list a step behind.
# That reasoning stopped applying when the rows learned to RESOLVE THEMSELVES —
# a confirmed row is recorded in `GameLoop2.answered_rows`, not in its checkbox
# (see the block above _lock_row), so a rebuild re-locks everything that was
# answered and loses only ticks that never existed. Rebuilding is safe now; what
# was missing was a way to know when it is warranted.
#
# Hence a signature of WHAT THE ROWS SAY. Deliberately not `_standing_checklist_sig`
# itself, close as the two are: that one includes `in_front`, which changes every
# time the board advances, so a lost run would rebuild the panel under the player
# once a turn for a list whose words had not changed at all.
func _play_panel_sig() -> String:
	var parts: PackedStringArray = PackedStringArray()
	var ch: CharacterData = Data.get_character2(GameState.character_id)
	if ch != null:
		parts.append("%s/%s" % [ch.level_up_condition, ch.level_up_reward])
	parts.append(str(GameState.event_goals))
	parts.append(str(GameState.curse_goals))
	for row in GameState.status_objectives():
		# The KEY, not the id: two rows of the same status differ only by instance,
		# and a signature that could not see the difference would leave the panel
		# showing one of them after the other expired.
		parts.append("%s:%d" % [String(row["key"]), int(row["stacks"])])
	for entry in GameLoop2.stack:
		var e: GoalEnemyData = entry["enemy"]
		# The enemy's ID, not only its name: a re-roll that landed on a different
		# body with the same name is still a different goal, and the id is the only
		# thing that cannot collide.
		parts.append("%d:%s:%s" % [int(entry.get("instance", 0)),
			String(e.id) if e != null else "", GameLoop2.goal_text_for(entry)])
		for alt in GameLoop2.alternatives_for(entry):
			parts.append("/%s:%d" % [String((alt["status"] as StatusData).id),
				int(alt["stacks"])])
		for bonus in GameLoop2.bonus_objectives_for(entry):
			parts.append("+%s:%d" % [String((bonus["status"] as StatusData).id),
				int(bonus["stacks"])])
	return "|".join(parts)

# Does the report step describe a board that has since changed? False when there
# is no report step up — the standing list has its own guard and this must not
# speak for it.
func play_panel_stale() -> bool:
	if _page == null or not is_instance_valid(_page) or _page._chosen.is_empty():
		return false
	return _play_sig != _play_panel_sig()

func _standing_checklist_sig() -> String:
	var parts: PackedStringArray = PackedStringArray()
	var ch: CharacterData = Data.get_character2(GameState.character_id)
	if ch != null:
		parts.append("%s/%s" % [ch.level_up_condition, ch.level_up_reward])
	parts.append(str(GameState.event_goals))
	parts.append(str(GameState.curse_goals))
	for row in GameState.status_objectives():
		# The KEY, not the id: two rows of the same status differ only by instance,
		# and a signature that could not see the difference would leave the panel
		# showing one of them after the other expired.
		parts.append("%s:%d" % [String(row["key"]), int(row["stacks"])])
	for entry in GameLoop2.stack:
		var e: GoalEnemyData = entry["enemy"]
		parts.append("%d:%s:%s:%d:%s" % [int(entry.get("instance", 0)),
			GameLoop2.goal_text_for(entry), e.display_name, e.damage,
			str(GameLoop2.in_front(entry))])
		for alt in GameLoop2.alternatives_for(entry):
			parts.append("/%s:%d" % [String((alt["status"] as StatusData).id),
				int(alt["stacks"])])
		for bonus in GameLoop2.bonus_objectives_for(entry):
			parts.append("+%s:%d" % [String((bonus["status"] as StatusData).id),
				int(bonus["stacks"])])
	return "|".join(parts)

# --- the checklist and the board, pointing at each other -------------------
#
# A goal on the checklist and a body on the board are the same fact written
# twice, and until now nothing said which line went with which enemy: a list of
# four goals beside a board of four bodies left the player matching them up by
# name. So the pair is LIT FROM EITHER END. Hovering a goal row brightens the
# enemies it belongs to; hovering an enemy brightens its row. One binding does
# both directions, because they are the same relation read from opposite sides.
#
# `instance` 0 means the row belongs to no body (the level-up challenge, an event
# goal, a player status): those rows bind nothing and stay inert.

# Bind one checklist row to one body. `paint` is called with whether the row
# should read as lit; it is kept per instance so the board's hover can find it.
#
# Call this once the row is FULLY BUILT: the whole row is the hover target, and
# what makes that work is walking what is actually in it.
func bind_row_to_body(row: Control, instance: int, paint: Callable) -> void:
	if instance <= 0:
		return
	var rows: Array = row_paints.get(instance, [])
	rows.append(paint)
	row_paints[instance] = rows
	# The frame passes its clicks on, as it always has — it is a highlight, not a
	# button, and the page under it scrolls.
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	_bind_hover(row, func(): light_bodies([instance]), func(): light_bodies([]))


# Hover on a ROW, not on the sliver of it nothing else claimed.
#
# Godot sends mouse_entered to the ONE control under the cursor — a MOUSE_FILTER
# PASS ancestor hears nothing while a STOP child has the pointer. A checklist row
# is a frame containing a full-width CheckBox and a Notes button, both STOP, so
# binding the frame alone left the goal lighting its enemy only from the two or
# three pixels of padding around the box: hover the row anywhere a player would
# actually aim and nothing happened. So every descendant carries the same pair.
#
# The exit is positional rather than a plain "leave one of them": crossing from
# the checkbox to the Notes button fires an exit and an enter in the same frame,
# and treating that as a departure made the highlight flicker along the row. If
# the pointer is still inside the frame, the row was never left.
func _bind_hover(frame: Control, on_enter: Callable, on_exit: Callable) -> void:
	var leave := func() -> void:
		if not is_instance_valid(frame) or not frame.get_global_rect().has_point(
				frame.get_global_mouse_position()):
			on_exit.call()
	for node in hover_targets(frame):
		if node.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			# A Label is IGNORE by default and never reports anything; it is also
			# most of a checklist row's width. PASS lets it report the hover while
			# still handing the click to whatever is underneath.
			node.mouse_filter = Control.MOUSE_FILTER_PASS
		node.mouse_entered.connect(on_enter)
		node.mouse_exited.connect(leave)


# `frame` and every Control under it.
func hover_targets(frame: Control) -> Array:
	var out: Array = [frame]
	for child in frame.get_children():
		if child is Control:
			out.append_array(hover_targets(child))
	return out

# Light `instances` on the BOARD (and, so the two halves never disagree, the rows
# that belong to them). Passing [] clears.
func light_bodies(instances: Array) -> void:
	var want: Dictionary = {}
	for inst in instances:
		want[int(inst)] = true
	if want == lit_instances:
		return
	var touched: Dictionary = lit_instances.duplicate()
	for inst in want:
		touched[inst] = true
	lit_instances = want
	for inst in touched:
		for paint in row_paints.get(inst, []):
			if (paint as Callable).is_valid():
				(paint as Callable).call(lit_instances.has(inst))
	if _page._board != null:
		_page._board.highlight(lit_instances.keys())

# The other direction: the mouse crossed a body on the board.
func on_enemy_hovered(instance: int, hovered: bool) -> void:
	light_bodies([instance] if hovered else [])

# One read-only checklist row: the same frame the tick-box rows use, without the
# box, so the standing list and the report step read as the same list in two
# states. `icon` is the enemy's portrait, when the row belongs to a body
# (_enemy_icon_rect); `instance` is that body on the board, which is what pairs the
# row with the enemy in both directions (bind_row_to_body).
# The line a burned BOSS gets where an ordinary body would get a tick box: what
# the status promises, and the one sentence saying why it is not on offer here.
# Read-only on purpose — there is nothing to claim, and a box that could be ticked
# and did nothing would be a worse lie than the silence this replaces.
func _nullified_row(row: Dictionary, instance: int = 0) -> Control:
	var sd: StatusData = row["status"]
	var stacks: int = int(row["stacks"])
	return _objective_row("%s or instead: %s  —  nullified: a boss comes off the board on its goal alone" % [
		_status_prefix(sd, stacks), sd.alternative_text(StatusData.ENEMY, stacks)],
		UITheme.TEXT_FAINT, null, instance,
		_status_mark(sd, stacks, StatusData.ENEMY, true))

# `icon` is the enemy's portrait chip when the row belongs to a body, built by the
# caller (_enemy_icon_rect) rather than passed as a texture, because what it
# carries — its frame colour, whether it says "Boss" — is a fact about the enemy
# and not about the row.
func _objective_row(text: String, color: Color, icon: Control = null,
		instance: int = 0, mark: Control = null) -> Control:
	var wrap := PanelContainer.new()
	var idle: StyleBox = UITheme.flat(Color(0.10, 0.10, 0.13, 0.6), 5, 4, 1,
		color.lerp(UITheme.BORDER, 0.35))
	var lit: StyleBox = UITheme.flat(color.lerp(UITheme.BG, 0.78), 5, 4, 2,
		color.lerp(Color.WHITE, 0.35))
	wrap.add_theme_stylebox_override("panel", idle)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	wrap.add_child(line)
	if icon != null:
		line.add_child(icon)
	if mark != null:
		line.add_child(mark)
	var l := Label.new()
	l.text = "•  " + text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(l)
	# Bound last: the hover covers what is IN the row, so the row has to be in it.
	bind_row_to_body(wrap, instance, func(is_lit: bool) -> void:
		if is_instance_valid(wrap):
			wrap.add_theme_stylebox_override("panel", lit if is_lit else idle))
	return wrap

# EVERY BODY'S PORTRAIT RIDES ITS ROW, not just a boss's.
#
# Only bosses used to get one, on the reasoning that a boss is the one thing on
# this list that isn't just another line of text. True of a boss, and it turned
# out to be the wrong conclusion: the board beside this list draws every enemy as
# a PICTURE, and the list drew every enemy as a NAME, so pairing a row with the
# body it belongs to meant reading a proper noun off one and matching it to art on
# the other. The lit-pair highlight (bind_row_to_body) papered over that for the
# one row the mouse is on; the other four were still a name-matching exercise. Now
# the two halves say the same thing in the same way, and the boss keeps what was
# actually its own — the orange frame and the "Boss" label on it.
const PORTRAIT_SIZE := 26

# The portrait chip for one enemy, or null when there is no art to show (and the
# row then reads exactly as it did before). A boss is framed in the board's own
# boss orange and says so; everything else takes the row's tint, dimmed, so a
# checklist of five bodies doesn't read as five alarms.
func _enemy_icon_rect(enemy: GoalEnemyData, tint: Color = UITheme.TEXT) -> Control:
	if enemy == null or enemy.image == null:
		return null
	var boss: bool = enemy.is_boss()
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG, 4, 2, 1,
			Color(0.95, 0.55, 0.2) if boss else tint.lerp(UITheme.BORDER, 0.45)))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.tooltip_text = ("Boss — %s" % enemy.display_name) if boss else enemy.display_name
	frame.add_child(UITheme.crisp_tex(enemy.image, PORTRAIT_SIZE))
	return frame

# One checklist row: a bordered CheckBox tinted `color`; `emphasise` gives the
# main-goal row a heavier border so it reads as the primary question. Kept to a
# single tight line each — the stage above it is the board, and the checklist has
# to stay a glanceable list rather than a stack of cards.
# One checklist line. When `enemy` is given the row also carries a Notes button
# on the right, for writing down how this enemy was actually beaten AT this game
# — the note belongs to the pair, and the Atlas surfaces it on the game later.
# `mark` is a chip the row leads with instead of a word — today the status symbol
# (_status_mark), handed in built rather than as a texture because what it carries
# (its frame, its hover card) is the caller's fact, not the row's.
func verify_row(text: String, color: Color, emphasise: bool,
		enemy: GoalEnemyData = null, character: CharacterData = null,
		instance: int = 0, mark: Control = null) -> Dictionary:
	var wrap := PanelContainer.new()
	var border: Color = color.lerp(UITheme.BORDER, 0.35)
	var width: int = 2 if emphasise else 1
	var idle: StyleBox = UITheme.flat(Color(0.10, 0.10, 0.13, 0.6), 5, 4, width, border)
	# The WHOLE ROW answers, not just the box: a ticked row goes green-washed and
	# green-rimmed, so a filled checklist reads at a glance from the board beside
	# it rather than needing each little box squinted at in turn.
	var ticked_box: StyleBox = UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.80), 5, 4,
		maxi(width, 2), UITheme.SUCCESS.lerp(UITheme.BORDER, 0.15))
	# …and a LIT row is the third state: the board beside this list is pointing at
	# the body this goal belongs to (see bind_row_to_body).
	var lit: StyleBox = UITheme.flat(color.lerp(UITheme.BG, 0.78), 5, 4,
		maxi(width, 2), color.lerp(Color.WHITE, 0.35))
	var ticked := {"on": false}
	var paint := func(is_lit: bool) -> void:
		if not is_instance_valid(wrap):
			return
		if bool(ticked["on"]):
			wrap.add_theme_stylebox_override("panel", ticked_box)
		else:
			wrap.add_theme_stylebox_override("panel", lit if is_lit else idle)
	wrap.add_theme_stylebox_override("panel", idle)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	wrap.add_child(line)
	# The body's own portrait, right where its name is about to be read.
	var portrait: Control = _enemy_icon_rect(enemy, color)
	if portrait != null:
		line.add_child(portrait)
	if mark != null:
		line.add_child(mark)
	var cb := CheckBox.new()
	cb.text = text
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A level-up clause reads "Use sorrow or self-inflicted pain as a weapon →
	# Gain +1 Small Chest and +1 Scramble", and an unwrapped CheckBox claims every
	# pixel of that as its minimum width — which is what pushed the left column to
	# 772px and put a horizontal scrollbar under the whole page. Wrapped, the row
	# is as tall as it needs and as wide as it is given.
	cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cb.add_theme_font_size_override("font_size", 13)
	cb.add_theme_color_override("font_color", color)
	cb.add_theme_color_override("font_pressed_color", color)
	cb.add_theme_color_override("font_hover_color", UITheme.GOLD)
	cb.toggled.connect(func(on: bool):
		ticked["on"] = on
		paint.call(lit_instances.has(instance))
		cb.add_theme_color_override("font_color",
			UITheme.SUCCESS.lerp(Color.WHITE, 0.55) if on else color))
	line.add_child(cb)
	var game: GameData = _page._chosen.get("game")
	if game != null:
		if enemy != null:
			line.add_child(_notes_button(game, enemy))
		elif character != null:
			line.add_child(_levelup_notes_button(game, character))
	# Bound last: the hover covers what is IN the row, so the row has to be in it.
	bind_row_to_body(wrap, instance, paint)
	return {"row": wrap, "check": cb}

# The per-row Notes button. Shows a filled glyph once something is written, so a
# game you've already annotated reads at a glance.
func _notes_button(game: GameData, enemy: GoalEnemyData) -> Button:
	return _note_button_for(
		"Write down how you beat %s here" % enemy.display_name,
		func(): return GameStats.enemy_note(game.id, enemy.id),
		func(refresh): EnemyNoteModal.open(_page, game, enemy, refresh))

# The same button for the level-up row, writing the (game, character) note.
func _levelup_notes_button(game: GameData, character: CharacterData) -> Button:
	return _note_button_for(
		"Write down how you hit %s's level-up here" % character.display_name,
		func(): return GameStats.level_up_note(game.id, character.id),
		func(refresh): EnemyNoteModal.open_level_up(_page, game, character, refresh))

# Shared shape for both: `read` answers the current text (so the glyph can say
# whether there is one) and `open` is handed the refresh to call on save.
func _note_button_for(tip: String, read: Callable, open: Callable) -> Button:
	var b := Button.new()
	b.add_theme_font_size_override("font_size", 11)
	b.tooltip_text = tip
	var refresh := func():
		var has: bool = String(read.call()).strip_edges() != ""
		b.text = "🗒 Notes ✎" if has else "🗒 Notes"
		b.add_theme_color_override("font_color", UITheme.GOLD if has else UITheme.TEXT_DIM)
	refresh.call()
	b.pressed.connect(func(): open.call(refresh))
	return b

func _verify_head(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	return l

# A ROW ALREADY RESOLVED IS NOT A CLAIM (§2.1). Every box on this list is a
# confirm, and confirming one resolves and LOCKS it, so a pressed-and-locked row
# has already had its effect — handing it to the report would deal a second hit
# for a goal that was met once. `disabled` is the whole test: nothing on this list
# is disabled except by _lock_row, and nothing can be pressed without going
# through it.
func _open_claim(check) -> bool:
	return check != null and is_instance_valid(check) \
		and check.button_pressed and not check.disabled

# The instances the player ticked as fulfilled this game and has NOT already
# resolved. In practice this is empty — the checklist resolves everything it is
# handed the moment it is confirmed — and it stays here because "the report deals
# the hit for anything still outstanding" is the rule, not "the report never
# deals one".
func ticked_fulfilments() -> Array:
	var out: Array = []
	for f in fulfil_checks:
		if _open_claim(f["check"]):
			out.append(f["instance"])
	return out

# The ticked STATUS rows, in the shape beat_game's `claims` wants (§13): the
# player-side rows met this game (the buff goals, and the `demand` rows whose price
# is dodged by answering them), the enemy bonus objectives claimed, and the goals
# cleared the OTHER way.
#
# The `instead` ticks are a separate list all the way through — never folded into
# `ticked_fulfilments` — because the report records a defeat for every fulfilment
# it is handed, and these are exactly the clears that must leave no record.
#
# Returned even when nothing at all is ticked, unlike before: an EMPTY report is
# the answer a missed `demand` is billed for, and a caller handed {} could not tell
# "nothing was ticked" from "no checklist asked".
func ticked_status_claims() -> Dictionary:
	var goals: Array = []
	for s in status_goal_checks:
		if _open_claim(s["check"]):
			goals.append(s["status"])
	var bonuses: Array = []
	for b in bonus_checks:
		if _open_claim(b["check"]):
			bonuses.append({"instance": b["instance"], "status": b["status"]})
	var instead: Array = []
	for i in instead_checks:
		if _open_claim(i["check"]):
			instead.append({"instance": i["instance"], "status": i["status"]})
	return {"status_goals": goals, "bonuses": bonuses, "instead": instead}
