class_name EncounterModal
extends Control

# The interaction popup for an overworld ENCOUNTER. Given an EncounterData, it
# renders a shared header (sprite + name + reference + description) and a body
# that branches on the encounter's Type, resolving the parsed `effects` ops:
#
#   Deal      — offer N items from a tag pool; "any" lets you take multiple,
#               each costing %HP (by item rarity) + a random curse; "one" is a
#               free single pick (Angel Room).
#   Shop      — buy items rolled from a tag pool, priced by rarity, with an
#               optional discount.
#   Movement  — engage: fight an elite first (delegated to the Overworld, which
#               launches the combat), then teleport on return.
#   Challenge — honour-system: play a random unconnected game of the named
#               engine, self-reporting up to N attempts; win/lose buckets apply.
#
# World-mutating actions the Overworld owns (teleport, launching the elite
# combat) are emitted as signals; everything self-contained (gold, curses, item
# grants, banked chests) is applied here against GameState.

signal closed
# Movement: the player chose to engage. `resume` carries the teleport tail to
# apply when the fight is won (the overworld stashes it across the scene-swap).
signal elite_combat_requested(engine: String, resume: Dictionary)
# Movement (no preceding combat, unused today) / generic teleport request.
signal teleport_requested(spec: Dictionary)

const PRICE_BY_RARITY := [50, 80, 120, 175, 250]
const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]

var _enc: EncounterData = null
var _rng := RandomNumberGenerator.new()
var _body: VBoxContainer = null
var _gold_label: Label = null
# Challenge state.
var _attempts_left: int = 0
var _challenge_game: GameData = null
# Whether anything banked a chest (redeemed by the overworld on close).
var minted_chest: bool = false

func setup(enc: EncounterData) -> void:
	_enc = enc
	_rng.randomize()
	_build()

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(640, 540)
	panel.size = Vector2(640, 540)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	add_child(panel)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 20
	root.offset_top = 16
	root.offset_right = -20
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	root.add_child(_header())

	var sep := HSeparator.new()
	root.add_child(sep)

	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	root.add_child(_body)

	match _enc.type.to_lower():
		"deal":
			_build_deal()
		"shop":
			_build_shop()
		"movement":
			_build_movement()
		"challenge":
			_build_challenge()
		_:
			_body.add_child(_label("This encounter has nothing for you.", 16))
			_add_leave_button("Leave")

func _header() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)

	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(96, 96)
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if _enc.image != null:
		art.texture = _enc.image
	box.add_child(art)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label(_enc.display_name, 22)
	text.add_child(title)
	var sub := "%s   ·   %s" % [_enc.type, _enc.reference]
	if _enc.is_animate():
		sub = "%s the %s   ·   %s" % [_enc.npc, _enc.type, _enc.reference]
	text.add_child(_label(sub, 12, Color(0.7, 0.72, 0.8)))
	var desc := _label(_enc.description, 14, Color(0.85, 0.87, 0.95))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(460, 0)
	text.add_child(desc)
	box.add_child(text)
	return box

# --------------------------------------------------------------------------
# Deal — offer items from a tag pool (Devil = take any @ cost, Angel = pick one)
# --------------------------------------------------------------------------

func _build_deal() -> void:
	var offer := _find_op("offer_items")
	if offer.is_empty():
		_add_leave_button("Leave")
		return
	var pick: String = String(offer.get("pick", "one"))
	var items: Array = _roll_pool_items(String(offer.get("tag", "")), int(offer.get("count", 3)))
	if items.is_empty():
		_body.add_child(_label("Nothing on offer.", 16))
		_add_leave_button("Leave")
		return

	var per_item: Array = _per_item_effects()
	var cost_text := _deal_cost_text(per_item)
	if cost_text != "":
		_body.add_child(_label(cost_text, 13, Color(1.0, 0.7, 0.7)))

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 12)
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(grid)
	for it in items:
		grid.add_child(_deal_tile(it, pick, per_item))

	_add_leave_button("Leave" if pick == "any" else "Decline")

func _deal_tile(item: ItemData, pick: String, per_item: Array) -> Control:
	var ridx: int = clampi(int(item.rarity), 0, RARITY_NAMES.size() - 1)
	var tile := Panel.new()
	tile.custom_minimum_size = Vector2(160, 200)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 8
	col.offset_top = 8
	col.offset_right = -8
	col.offset_bottom = -8
	col.add_theme_constant_override("separation", 6)
	tile.add_child(col)

	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(0, 96)
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if item.image != null:
		art.texture = item.image
	col.add_child(art)
	col.add_child(_label("%s\n[%s]" % [item.display_name, RARITY_NAMES[ridx]], 12))

	var take := Button.new()
	take.text = "Take"
	take.pressed.connect(func() -> void:
		GameState.add_item(item)
		Notifications.notify("Gained %s" % item.display_name, Color(0.8, 0.9, 1.0))
		# Devil-style per-item price: %HP by this item's rarity + curses.
		for eff in per_item:
			_apply_per_item(eff, ridx)
		take.disabled = true
		take.text = "Taken"
		if pick == "one":
			_finish()
	)
	col.add_child(take)
	return tile

func _apply_per_item(eff: Dictionary, rarity_idx: int) -> void:
	match String(eff.get("op", "")):
		"lose_hp_pct":
			var pct: int
			if eff.has("by_rarity"):
				var arr: Array = eff["by_rarity"]
				pct = int(arr[clampi(rarity_idx, 0, arr.size() - 1)])
			else:
				pct = int(eff.get("value", 0))
			var dmg: int = int(ceil(GameState.max_hp * pct / 100.0))
			GameState.set_hp(maxi(1, GameState.hp - dmg))
			Notifications.notify("Paid %d HP" % dmg, Color(1.0, 0.6, 0.6))
		"add_curse":
			_grant_random_curses(int(eff.get("count", 1)))
		_:
			_apply_leaf(eff)

# --------------------------------------------------------------------------
# Shop — buy items rolled from a tag pool, priced by rarity, optional discount
# --------------------------------------------------------------------------

func _build_shop() -> void:
	var shop := _find_op("shop")
	var pools: Array = shop.get("pools", [])
	var discount: int = int(shop.get("discount", 0))
	var items: Array = _roll_pool_items_multi(pools, 4)
	if items.is_empty():
		_body.add_child(_label("The shelves are bare.", 16))
		_add_leave_button("Leave")
		return

	_gold_label = _label("Gold: %d" % GameState.gold, 14, Color(1.0, 0.85, 0.4))
	_body.add_child(_gold_label)

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 12)
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(grid)
	for it in items:
		grid.add_child(_shop_tile(it, discount))
	_add_leave_button("Leave")

func _shop_tile(item: ItemData, discount: int) -> Control:
	var ridx: int = clampi(int(item.rarity), 0, RARITY_NAMES.size() - 1)
	var base: int = PRICE_BY_RARITY[ridx]
	var price: int = int(round(base * (100 - discount) / 100.0))
	var tile := Panel.new()
	tile.custom_minimum_size = Vector2(150, 210)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 8
	col.offset_top = 8
	col.offset_right = -8
	col.offset_bottom = -8
	col.add_theme_constant_override("separation", 6)
	tile.add_child(col)

	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(0, 90)
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if item.image != null:
		art.texture = item.image
	col.add_child(art)
	col.add_child(_label("%s\n[%s]" % [item.display_name, RARITY_NAMES[ridx]], 12))

	var buy := Button.new()
	buy.text = "Buy (%dg)" % price
	buy.pressed.connect(func() -> void:
		if GameState.gold < price:
			Notifications.notify("Not enough gold.", Color(1.0, 0.6, 0.5))
			return
		GameState.change_gold(-price)
		GameState.add_item(item)
		Notifications.notify("Bought %s" % item.display_name, Color(0.8, 0.95, 0.8))
		buy.disabled = true
		buy.text = "Sold"
		if _gold_label != null:
			_gold_label.text = "Gold: %d" % GameState.gold
	)
	col.add_child(buy)
	return tile

# --------------------------------------------------------------------------
# Movement — fight an elite first, then teleport (delegated to the overworld)
# --------------------------------------------------------------------------

func _build_movement() -> void:
	var combat := _find_op("combat")
	var teleport := _find_op("teleport")
	var engine: String = String(combat.get("engine", "action"))

	if combat.is_empty():
		# Pure teleporter (no gate fight): apply immediately.
		var go := Button.new()
		go.text = "Step through"
		go.pressed.connect(func() -> void:
			emit_signal("teleport_requested", teleport)
			_finish()
		)
		_body.add_child(go)
	else:
		_body.add_child(_label("An elite blocks the way. Defeat it to use the portal.", 14))
		var engage := Button.new()
		engage.text = "Fight the elite, then teleport"
		engage.pressed.connect(func() -> void:
			# The overworld takes over (stashes the teleport tail + launches the
			# combat). Don't emit `closed` — that runs the redeem/save cleanup, and
			# we're about to be freed by the scene-swap anyway.
			emit_signal("elite_combat_requested", engine, {"teleport": teleport})
			queue_free()
		)
		_body.add_child(engage)
	_add_leave_button("Leave")

# --------------------------------------------------------------------------
# Challenge — honour-system: play a random unconnected game, self-report
# --------------------------------------------------------------------------

func _build_challenge() -> void:
	var ch := _find_op("challenge")
	var engine: String = String(ch.get("engine", "action"))
	_attempts_left = int(ch.get("attempts", 3))
	_challenge_game = _pick_unconnected_game(engine)
	if _challenge_game == null:
		_body.add_child(_label("No unconnected %s game to challenge right now." % engine, 15))
		_add_leave_button("Leave")
		return

	_body.add_child(_label("Go play a run of %s (%s)." % [_challenge_game.display_name, engine], 16))
	var status := _label("", 14, Color(0.9, 0.85, 0.6))
	_body.add_child(status)
	_refresh_challenge_status(status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(row)

	var won := Button.new()
	won.text = "I beat it"
	won.pressed.connect(func() -> void: _challenge_win())
	row.add_child(won)

	var failed := Button.new()
	failed.text = "Failed an attempt"
	failed.pressed.connect(func() -> void: _challenge_fail(status, won, failed))
	row.add_child(failed)

func _refresh_challenge_status(status: Label) -> void:
	status.text = "Attempts remaining: %d" % _attempts_left

func _challenge_win() -> void:
	for eff in _outcome_effects("win"):
		_apply_leaf(eff)
	Notifications.notify("Challenge cleared!", Color(0.7, 1.0, 0.7))
	_finish()

func _challenge_fail(status: Label, won: Button, failed: Button) -> void:
	_attempts_left -= 1
	_refresh_challenge_status(status)
	if _attempts_left <= 0:
		for eff in _outcome_effects("lose"):
			_apply_leaf(eff)
		Notifications.notify("Challenge failed.", Color(1.0, 0.6, 0.6))
		won.disabled = true
		failed.disabled = true
		_finish()

# --------------------------------------------------------------------------
# Effect leaves + helpers
# --------------------------------------------------------------------------

func _apply_leaf(eff: Dictionary) -> void:
	match String(eff.get("op", "")):
		"gain_gold":
			GameState.change_gold(int(eff.get("value", 0)))
			Notifications.notify("+%d gold" % int(eff.get("value", 0)), Color(1.0, 0.85, 0.4))
		"gain_chest":
			GameState.pending_chests += 1
			minted_chest = true
			Notifications.notify("Item chest earned!", Color(0.8, 0.95, 1.0))
		"add_curse":
			_grant_random_curses(int(eff.get("count", 1)))
		"lose_hp_pct":
			_apply_per_item(eff, 0)
		_:
			push_warning("[EncounterModal] unhandled effect op: %s" % eff)

func _grant_random_curses(n: int) -> void:
	for _i in range(n):
		var curse: CurseData = GameState.random_curse()
		if curse != null:
			GameState.add_active_curse(curse)
			Notifications.notify("Cursed: %s" % curse.display_name, Color(0.85, 0.6, 0.85))

func _find_op(op: String) -> Dictionary:
	for e in _enc.effects:
		if e is Dictionary and String(e.get("op", "")) == op:
			return e
	return {}

func _per_item_effects() -> Array:
	var out: Array = []
	for e in _enc.effects:
		if e is Dictionary and String(e.get("op", "")) == "per_item" and e.get("effect") is Dictionary:
			out.append(e["effect"])
	return out

func _outcome_effects(bucket: String) -> Array:
	var out: Array = []
	for e in _enc.effects:
		if e is Dictionary and String(e.get("op", "")) == bucket and e.get("effect") is Dictionary:
			out.append(e["effect"])
	return out

func _deal_cost_text(per_item: Array) -> String:
	var parts: Array = []
	for eff in per_item:
		match String(eff.get("op", "")):
			"lose_hp_pct":
				if eff.has("by_rarity"):
					parts.append("%% of max HP by item rarity")
				else:
					parts.append("%d HP" % int(eff.get("value", 0)))
			"add_curse":
				var c: int = int(eff.get("count", 1))
				parts.append("%d curse%s" % [c, "" if c == 1 else "s"])
	if parts.is_empty():
		return ""
	return "Each item taken costs: " + ", ".join(PackedStringArray(parts))

func _roll_pool_items(tag: String, count: int) -> Array:
	return _roll_pool_items_multi([tag], count)

func _roll_pool_items_multi(tags: Array, count: int) -> Array:
	var pool: Array = []
	for it in Data.all_items():
		if it is ItemData and not it.starter:
			for t in tags:
				if it.tags.has(String(t)):
					pool.append(it)
					break
	# Shuffle then take up to count distinct.
	for i in range(pool.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp = pool[i]; pool[i] = pool[j]; pool[j] = tmp
	return pool.slice(0, mini(count, pool.size()))

func _pick_unconnected_game(engine: String) -> GameData:
	var etype: int = _engine_to_type(engine)
	var current: StringName = GameState.current_game_id
	var nbrs: Array = RunGraph.neighbors(current)
	var pool: Array = []
	var fallback: Array = []
	for g in Data.all_games():
		if not (g is GameData) or g.type != etype or g.id == current:
			continue
		if GameState.beaten_games.has(g.id):
			continue
		fallback.append(g)
		if not nbrs.has(g.id):
			pool.append(g)
	var pick_from: Array = pool if not pool.is_empty() else fallback
	if pick_from.is_empty():
		return null
	return pick_from[_rng.randi_range(0, pick_from.size() - 1)]

func _engine_to_type(engine: String) -> int:
	match engine:
		"action": return GameData.GameType.ACTION
		"strategy": return GameData.GameType.STRATEGY
		"deckbuilder": return GameData.GameType.DECKBUILDER
		_: return GameData.GameType.ACTION

# --------------------------------------------------------------------------
# UI scaffolding
# --------------------------------------------------------------------------

func _label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if color != Color.WHITE:
		l.add_theme_color_override("font_color", color)
	return l

func _add_leave_button(text: String) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(spacer)
	var leave := Button.new()
	leave.text = text
	leave.custom_minimum_size = Vector2(160, 40)
	leave.pressed.connect(func() -> void: _finish())
	var wrap := HBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(leave)
	_body.add_child(wrap)

func _finish() -> void:
	emit_signal("closed")
	queue_free()
