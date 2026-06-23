class_name Backpack
extends Control

# Global backpack popup. Mounted once on a high CanvasLayer by Main and
# toggled with Tab from anywhere in a run. An always-visible Stats hub fills
# the left column (vitals, attributes + their derived combat stats, and the
# combat / exploration stats), with tabbed content on the right:
#   Items — every ItemData in GameState.inventory. USABLE consumables (pills)
#           get a Use button, enabled only when GameState.can_use_items()
#           (i.e. in combat or while an event roll is open). Sortable by
#           pickup order, rarity, or name.
#   Loot  — the run-scope loot counters (potions / scrolls / keys / fish …).
#   Gear  — the action-combat loadout (doubles as the equipment screen).
#   Deck  — every card in the run deck, deduped with copy counts.
#
# Built entirely in code so it has no scene-file node dependencies. Runs with
# PROCESS_MODE_ALWAYS and pauses the tree while open so real-time action
# combat freezes behind it.

enum Tab { ITEMS, LOOT, GEAR, DECK, HISTORY }
enum SortMode { PICKUP, RARITY, NAME }

# Card-type labels for the Deck tab.
const CARD_TYPE_LABELS := ["Attack", "Skill", "Power", "Dice", "Status", "Curse", "Training"]

# Base overworld portal count (mirrors Overworld.BASE_PORTAL_COUNT); the FoV
# stat shown in the hub is this plus GameState.fov_bonus.
const BASE_FOV := 3

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS := [
	Color(0.78, 0.78, 0.78), Color(0.45, 0.85, 0.5),
	Color(0.4, 0.6, 1.0), Color(0.75, 0.45, 1.0), Color(1.0, 0.8, 0.3),
]
# Starter items (Burning Blood, Ring of the Snake) carry a character's opening
# loadout and never roll in random pools, so they read as "Starter" rather than
# a rolled rarity. Cyan keeps them visually distinct from Common.
const STARTER_NAME := "Starter"
const STARTER_COLOR := Color(0.4, 0.85, 0.95)
# Friendly labels for known loot kinds; unknown kinds fall back to capitalize.
const LOOT_LABELS := {
	"potion": "Potions", "scroll": "Scrolls", "key": "Keys", "fish": "Fish",
}

var _tab: Tab = Tab.ITEMS
var _sort: SortMode = SortMode.PICKUP

var _panel: PanelContainer
var _tab_items_btn: Button
var _tab_loot_btn: Button
var _tab_gear_btn: Button
var _tab_deck_btn: Button
var _tab_history_btn: Button
var _sort_bar: HBoxContainer
var _list_vbox: VBoxContainer
var _hint_label: Label
var _stats_vbox: VBoxContainer
var _card_preview: CanvasLayer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_ui()
	GameState.inventory_changed.connect(_on_state_changed)
	GameState.stats_changed.connect(_on_state_changed)
	GameState.deck_changed.connect(_on_state_changed)
	Notifications.notified.connect(_on_notified)

# Tab toggles the backpack from anywhere in a run. Handled here (rather than
# in Main) because the backpack runs PROCESS_MODE_ALWAYS, so it keeps working
# while the tree is paused (i.e. so Tab also closes it once it's open).
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("backpack"):
		toggle()
		get_viewport().set_input_as_handled()
	# Esc closes the bag when it's open (and is consumed here so it doesn't also
	# pop the pause menu underneath). Runs in _input, before PauseMenu's handler.
	elif visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _on_state_changed() -> void:
	if visible:
		_refresh()

func _on_notified(_text: String, _color: Color) -> void:
	# Keep the History tab live while it's open; other tabs don't care.
	if visible and _tab == Tab.HISTORY:
		_refresh()

# ------------------------------------------------------------------
# Open / close
# ------------------------------------------------------------------

func is_open() -> bool:
	return visible

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	# In action mode the backpack doubles as the equipment screen, but gear is
	# only meant to change between rooms — refuse to open over a live fight.
	var scene = GameState.combat_scene
	if scene != null and scene.has_method("has_live_enemies") and scene.has_live_enemies():
		GameLog.add("Clear the room before opening your backpack.", Color(0.85, 0.7, 0.4))
		return
	visible = true
	get_tree().paused = true
	_refresh()

func close() -> void:
	visible = false
	get_tree().paused = false
	# Re-apply the action loadout so any gear swap made here takes effect
	# immediately (recharges cooldowns too). No-op outside action combat.
	var scene = GameState.combat_scene
	if scene != null and scene.has_method("reload_loadout"):
		scene.reload_loadout()

# ------------------------------------------------------------------
# UI construction
# ------------------------------------------------------------------

func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.size = Vector2(1060, 600)
	_panel.position = (get_viewport_rect().size - _panel.size) / 2.0
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_panel.add_child(root)

	# Header row: title + close button.
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Backpack"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var collection_btn := Button.new()
	collection_btn.text = "📚 Collection"
	collection_btn.pressed.connect(_open_collection)
	header.add_child(collection_btn)
	var close_btn := Button.new()
	close_btn.text = "Close (Tab)"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# Body: always-visible player-stats hub on the left, tabbed content right.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# --- Left column: live stats hub ---
	var stats_col := VBoxContainer.new()
	stats_col.custom_minimum_size = Vector2(310, 0)
	stats_col.add_theme_constant_override("separation", 4)
	body.add_child(stats_col)
	var stats_title := Label.new()
	stats_title.text = "Stats"
	stats_title.add_theme_font_size_override("font_size", 18)
	stats_title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	stats_col.add_child(stats_title)
	var stats_scroll := ScrollContainer.new()
	stats_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_scroll.custom_minimum_size = Vector2(310, 500)
	stats_col.add_child(stats_scroll)
	_stats_vbox = VBoxContainer.new()
	_stats_vbox.add_theme_constant_override("separation", 8)
	_stats_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_scroll.add_child(_stats_vbox)

	body.add_child(VSeparator.new())

	# --- Right column: the existing tabbed content ---
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(main)

	# Tab buttons.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	main.add_child(tabs)
	_tab_items_btn = Button.new()
	_tab_items_btn.text = "Items"
	_tab_items_btn.toggle_mode = true
	_tab_items_btn.pressed.connect(func(): _set_tab(Tab.ITEMS))
	tabs.add_child(_tab_items_btn)
	_tab_loot_btn = Button.new()
	_tab_loot_btn.text = "Loot"
	_tab_loot_btn.toggle_mode = true
	_tab_loot_btn.pressed.connect(func(): _set_tab(Tab.LOOT))
	tabs.add_child(_tab_loot_btn)
	_tab_gear_btn = Button.new()
	_tab_gear_btn.text = "Gear"
	_tab_gear_btn.toggle_mode = true
	_tab_gear_btn.pressed.connect(func(): _set_tab(Tab.GEAR))
	tabs.add_child(_tab_gear_btn)
	_tab_deck_btn = Button.new()
	_tab_deck_btn.text = "Deck"
	_tab_deck_btn.toggle_mode = true
	_tab_deck_btn.pressed.connect(func(): _set_tab(Tab.DECK))
	tabs.add_child(_tab_deck_btn)
	_tab_history_btn = Button.new()
	_tab_history_btn.text = "History"
	_tab_history_btn.toggle_mode = true
	_tab_history_btn.pressed.connect(func(): _set_tab(Tab.HISTORY))
	tabs.add_child(_tab_history_btn)

	# Sort bar (Items tab only).
	_sort_bar = HBoxContainer.new()
	_sort_bar.add_theme_constant_override("separation", 6)
	main.add_child(_sort_bar)
	var sort_lbl := Label.new()
	sort_lbl.text = "Sort:"
	_sort_bar.add_child(sort_lbl)
	_add_sort_button("Pickup", SortMode.PICKUP)
	_add_sort_button("Rarity", SortMode.RARITY)
	_add_sort_button("Name", SortMode.NAME)

	# Scrollable list.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(700, 440)
	main.add_child(scroll)
	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 6)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_vbox)

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	main.add_child(_hint_label)

# Opens the Collection compendium on top of the backpack. Added as a child of
# the backpack (which runs PROCESS_MODE_ALWAYS and stays visible underneath) so
# closing the collection returns here without un-pausing the run.
func _open_collection() -> void:
	Collection.open(self)

func _add_sort_button(text: String, mode: SortMode) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func(): _set_sort(mode))
	b.set_meta("sort_mode", int(mode))
	_sort_bar.add_child(b)

func _set_tab(t: Tab) -> void:
	_tab = t
	_refresh()

func _set_sort(mode: SortMode) -> void:
	_sort = mode
	_refresh()

# ------------------------------------------------------------------
# Render
# ------------------------------------------------------------------

func _refresh() -> void:
	_refresh_stats()
	_tab_items_btn.button_pressed = _tab == Tab.ITEMS
	_tab_loot_btn.button_pressed = _tab == Tab.LOOT
	_tab_gear_btn.button_pressed = _tab == Tab.GEAR
	_tab_deck_btn.button_pressed = _tab == Tab.DECK
	_tab_history_btn.button_pressed = _tab == Tab.HISTORY
	_sort_bar.visible = _tab == Tab.ITEMS
	for b in _sort_bar.get_children():
		if b is Button and b.has_meta("sort_mode"):
			b.modulate = Color(1, 1, 0.6) if int(b.get_meta("sort_mode")) == int(_sort) else Color.WHITE
	for child in _list_vbox.get_children():
		child.queue_free()
	match _tab:
		Tab.ITEMS:
			_render_items()
		Tab.LOOT:
			_render_loot()
		Tab.GEAR:
			_render_gear()
		Tab.DECK:
			_render_deck()
		Tab.HISTORY:
			_render_history()

# ------------------------------------------------------------------
# Stats hub — always-visible left column. Mirrors the old HTML sidebar:
# vitals, attributes paired with their derived combat stats, then the
# combat and exploration stats this project adds on top. Values show the
# total with the item/temp-bonus breakdown when there is one.
# ------------------------------------------------------------------

const STAT_ICON_SIZE := 22

func _refresh_stats() -> void:
	if _stats_vbox == null:
		return
	for c in _stats_vbox.get_children():
		c.queue_free()

	var vitals := _stat_section("Vitals")
	vitals.add_child(_stat_widget("Health", "%d / %d" % [GameState.hp, GameState.max_hp],
		Color(0.95, 0.5, 0.5), "Your current and maximum hit points. Reach 0 and the run ends."))
	var energy_def: StatDefinition = Stats.get_definition(&"max_energy")
	vitals.add_child(_stat_widget("Energy", str(GameState.max_energy), Color(0.6, 0.85, 1.0),
		energy_def.description if energy_def != null else "Energy spent to play cards each combat turn."))
	vitals.add_child(_stat_widget("Hand Size", str(GameState.hand_size), Color(0.8, 0.85, 0.95),
		"Cards drawn at the start of each of your combat turns."))
	vitals.add_child(_stat_widget("Gold", str(GameState.gold), Color(1.0, 0.85, 0.35),
		"Currency spent in shops on cards, items, and removals."))

	var attrs := _stat_section("Attributes")
	_add_attribute(attrs, &"strength", Color(0.95, 0.55, 0.45))
	_add_attribute(attrs, &"dexterity", Color(0.55, 0.85, 0.55))
	_add_attribute(attrs, &"intelligence", Color(0.6, 0.7, 1.0))
	_add_attribute(attrs, &"charisma", Color(0.9, 0.6, 0.95))
	_add_attribute(attrs, &"constitution", Color(0.85, 0.7, 0.5))

	var combat := _stat_section("Combat")
	_add_attribute(combat, &"crit_chance", Color(1.0, 0.8, 0.4), "%")
	# Crit Chance Up = the effective per-hit crit chance (folds Luck in).
	combat.add_child(_stat_widget("Crit Chance Up", "%d%%" % Stats.crit_chance_percent(),
		Color(1.0, 0.85, 0.55),
		"Effective per-hit crit chance: max(0, 2 x Luck) + Crit Chance, capped at 100%.", true))
	_add_attribute(combat, &"crit_damage", Color(1.0, 0.7, 0.4), "%")
	_add_attribute(combat, &"luck", Color(0.7, 1.0, 0.7))
	_add_attribute(combat, &"speed", Color(0.6, 0.9, 1.0))
	_add_attribute(combat, &"range", Color(0.95, 0.75, 0.55))
	_add_attribute(combat, &"harvesting", Color(1.0, 0.85, 0.4))
	_add_attribute(combat, &"regeneration", Color(0.55, 0.95, 0.7))

	var explore := _stat_section("Exploration")
	explore.add_child(_stat_widget("FoV", str(BASE_FOV + Stats.get_value(&"fov_bonus")), Color(0.7, 0.85, 1.0),
		"Number of game portals shown on the overworld."))
	explore.add_child(_stat_widget("Discovery", str(GameState.discovery), Color(0.8, 0.8, 1.0),
		"Extra choices when collecting item and card rewards."))
	explore.add_child(_stat_widget("Dash", str(GameState.dash_charges), Color(0.85, 0.9, 1.0),
		"Charges to dash to any connected game node."))
	explore.add_child(_stat_widget("Reroll", str(GameState.reroll_charges), Color(0.85, 0.9, 1.0),
		"Charges to re-roll the overworld portal choices."))

# A titled, rounded "stat card" panel. Adds it to the hub and returns the
# inner VBox so the caller can append its rows.
func _stat_section(title: String) -> VBoxContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.16, 0.85)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.06)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(body)
	var head := Label.new()
	head.text = title.to_upper()
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", Color(1.0, 0.78, 0.4))
	body.add_child(head)
	body.add_child(HSeparator.new())
	_stats_vbox.add_child(card)
	return body

# Adds a base-stat row (value with item/temp breakdown + a tooltip from its
# StatDefinition), then an indented derived-status row if the stat has one
# (e.g. Strength -> Power). `suffix` appends a unit like "%".
func _add_attribute(body: VBoxContainer, stat_id: StringName, color: Color, suffix: String = "") -> void:
	var def: StatDefinition = Stats.get_definition(stat_id)
	var label: String = def.display_name if def != null and def.display_name != "" else String(stat_id).capitalize()
	var tip: String = def.description if def != null else ""
	body.add_child(_stat_widget(label, _stat_value_text(stat_id, suffix), color, tip))
	if def != null and def.derived_status != &"":
		var dname: String = String(def.derived_status).capitalize()
		# Skip the indented derived row when it would just repeat the stat
		# (e.g. the Regeneration stat derives the Regeneration status 1:1).
		if dname != label:
			var per: int = maxi(1, def.derived_per)
			var stacks: int = int(floor(float(Stats.get_value(stat_id)) / float(per)))
			var ddesc := "Granted by %s at combat start: 1 stack per %d point%s." % [
				label, per, "s" if per != 1 else ""]
			body.add_child(_stat_widget(dname, str(stacks), Color(0.6, 0.8, 0.95), ddesc, true))

# Builds one stat row: icon (or a colour dot) + label + value chip, wrapped in
# a StatRow that owns the hover highlight and the themed description tooltip.
# `derived` indents/dims the row (e.g. Strength's Power) and drops the icon.
func _stat_widget(label: String, value: String, color: Color, desc: String = "", derived: bool = false) -> StatRow:
	var row := StatRow.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.stat_title = label
	row.stat_desc = desc
	# A non-empty tooltip_text is what makes Godot call our _make_custom_tooltip.
	row.tooltip_text = desc if desc != "" else label

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hb)

	hb.add_child(_icon_or_dot(label, color, derived))

	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_color",
		color if not derived else color.lerp(Color(0.6, 0.6, 0.6), 0.4))
	if derived:
		lbl.add_theme_font_size_override("font_size", 12)
	hb.add_child(lbl)

	hb.add_child(_value_chip(value, derived))
	return row

# Stat icon from the old HTML set (res://images/Stats/<Name>.png), or null when
# the stat doesn't have one yet — callers fall back to a colour dot.
func _stat_icon(icon_name: String) -> Texture2D:
	if icon_name == "":
		return null
	var path := "res://images/Stats/%s.png" % icon_name
	return load(path) if ResourceLoader.exists(path) else null

# A fixed-size leading cell: the stat's icon if one exists, otherwise a small
# colour dot tinted to the stat. Derived rows get a blank spacer so their
# label still lines up under the parent stat.
func _icon_or_dot(label: String, color: Color, derived: bool) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(STAT_ICON_SIZE, STAT_ICON_SIZE)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if derived:
		return box
	var tex := _stat_icon(label.replace(" ", ""))
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tr)
	else:
		var dot := Panel.new()
		var ds := StyleBoxFlat.new()
		ds.bg_color = color
		ds.set_corner_radius_all(6)
		dot.add_theme_stylebox_override("panel", ds)
		dot.size = Vector2(12, 12)
		dot.position = Vector2((STAT_ICON_SIZE - 12) / 2.0, (STAT_ICON_SIZE - 12) / 2.0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(dot)
	return box

# Right-aligned value in a subtle dark rounded chip.
func _value_chip(text: String, derived: bool) -> Control:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.32)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", Color(0.97, 0.97, 0.97))
	if derived:
		l.add_theme_font_size_override("font_size", 12)
	chip.add_child(l)
	return chip

# "total" or "total  (base +bonus)" when item/temp bonuses are present.
func _stat_value_text(stat_id: StringName, suffix: String = "") -> String:
	var field := String(stat_id)
	var base: int = int(GameState.get(field))
	# Route the total through Stats so derived contributions show too — most
	# notably Paper Bag, which mirrors Charisma onto the highest core stat
	# without ever landing in item_stat_bonus. For every other stat this equals
	# base + item/temp bonus, so the breakdown below is unchanged.
	var total: int = Stats.get_value(stat_id)
	var bonus: int = total - base
	if bonus == 0:
		return "%d%s" % [total, suffix]
	return "%d%s  (%d %+d)" % [total, suffix, base, bonus]

# ------------------------------------------------------------------
# History tab — the Notifications channel log (item procs, pickups, run
# milestones), newest first. Text + color, mirroring the entry's toast.
# ------------------------------------------------------------------

func _render_history() -> void:
	var entries: Array = Notifications.history
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "No notifications yet."
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_list_vbox.add_child(empty)
		_hint_label.text = "Important events show here as they happen."
		return
	# Newest first.
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.12, 0.16, 0.6)
		sb.border_color = e.get("color", Color(0.5, 0.5, 0.5))
		sb.border_width_left = 3
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		row.add_theme_stylebox_override("panel", sb)
		var lbl := Label.new()
		lbl.text = String(e.get("text", ""))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(640, 0)
		lbl.add_theme_color_override("font_color", e.get("color", Color.WHITE))
		row.add_child(lbl)
		_list_vbox.add_child(row)
	_hint_label.text = "%d notifications this run (newest first)." % entries.size()

func _render_items() -> void:
	var items: Array = _sorted_items()
	if items.is_empty():
		var empty := Label.new()
		empty.text = "Your backpack is empty."
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_list_vbox.add_child(empty)
	else:
		for it in items:
			_list_vbox.add_child(_build_item_row(it))
	var can_use: bool = GameState.can_use_items()
	_hint_label.text = "Click Use to consume a pill." if can_use \
		else "Pills can only be used in combat or during an event."

func _sorted_items() -> Array:
	var items: Array = GameState.inventory.duplicate()
	match _sort:
		SortMode.PICKUP:
			items.sort_custom(_cmp_pickup)
		SortMode.NAME:
			items.sort_custom(_cmp_name)
		SortMode.RARITY:
			items.sort_custom(_cmp_rarity)
	return items

func _cmp_pickup(a: ItemData, b: ItemData) -> bool:
	# instance_id is minted monotonically by GameState.add_item, so it doubles
	# as pickup order.
	return a.instance_id < b.instance_id

func _cmp_name(a: ItemData, b: ItemData) -> bool:
	return a.display_name.naturalnocasecmp_to(b.display_name) < 0

func _cmp_rarity(a: ItemData, b: ItemData) -> bool:
	# Highest rarity first; ties broken by name.
	if int(a.rarity) != int(b.rarity):
		return int(a.rarity) > int(b.rarity)
	return a.display_name.naturalnocasecmp_to(b.display_name) < 0

func _build_item_row(item: ItemData) -> Control:
	var row := PanelContainer.new()
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	if item.image != null:
		var icon := TextureRect.new()
		icon.texture = item.image
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(icon)

	# Charged actives get an Isaac-style charge bar beside the icon.
	if item.is_charged():
		var bar := ChargeBar.new()
		bar.custom_minimum_size = Vector2(7, 48)
		bar.setup(item.max_charge(), item.current_charge)
		hbox.add_child(bar)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var name_lbl := Label.new()
	var rarity_idx: int = clampi(int(item.rarity), 0, RARITY_NAMES.size() - 1)
	var rarity_text: String = RARITY_NAMES[rarity_idx]
	var rarity_color: Color = RARITY_COLORS[rarity_idx]
	if item.starter:
		rarity_text = STARTER_NAME
		rarity_color = STARTER_COLOR
	name_lbl.text = "%s   [%s]" % [item.display_name, rarity_text]
	name_lbl.add_theme_color_override("font_color", rarity_color)
	info.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = item.description
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(520, 0)
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82))
	info.add_child(desc_lbl)

	# Incremental progress badge — shows how close an "every Nth …" item is to
	# its next proc (e.g. 7/10), and Dead Eye's live streak bonus (+3 Dmg).
	var badge: String = _incremental_badge(item)
	if badge != "":
		var badge_lbl := Label.new()
		badge_lbl.text = badge
		badge_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badge_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.27))
		badge_lbl.add_theme_font_size_override("font_size", 16)
		hbox.add_child(badge_lbl)

	if item.is_charged():
		# Charged actives can be fired from any screen once their bar is full.
		var charge_lbl := Label.new()
		charge_lbl.text = "%d/%d" % [item.current_charge, item.max_charge()]
		charge_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		charge_lbl.add_theme_font_size_override("font_size", 14)
		charge_lbl.add_theme_color_override("font_color",
			Color(0.5, 1.0, 0.6) if item.is_fully_charged() else Color(0.8, 0.8, 0.5))
		hbox.add_child(charge_lbl)
		var use_btn := Button.new()
		use_btn.text = "Use" if item.is_fully_charged() else "Charging"
		use_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		use_btn.disabled = not GameState.can_fire_item(item)
		use_btn.pressed.connect(func(): _on_use_pressed(item))
		hbox.add_child(use_btn)
	elif item.kind == ItemData.ItemKind.USABLE:
		var use_btn := Button.new()
		use_btn.text = "Use"
		if item.max_uses > 1:
			use_btn.text = "Use (%d)" % item.max_uses
		use_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Item-aware so overworld actives (Winged Boots) enable on the map too.
		use_btn.disabled = not GameState.can_fire_item(item)
		use_btn.pressed.connect(func(): _on_use_pressed(item))
		hbox.add_child(use_btn)

	return row

# Progress text for incremental items. Counter items (Happy Flower, Nunchaku,
# Ornamental Fan, Shuriken, Pen Nib) advertise their counter via a `counter`
# effect in their triggers, so the badge is derived from the item data rather
# than a hard-coded name list. Dead Eye is a streak, not a counter, so it shows
# its current bonus instead. Returns "" for non-incremental items.
func _incremental_badge(item: ItemData) -> String:
	if item == null:
		return ""
	if String(item.id) == "dead_eye":
		var n: int = GameState.dead_eye_streak
		return "+%d Dmg" % n if n > 0 else "+0 Dmg"
	for trig in item.triggers:
		for eff in trig.get("effects", []):
			if typeof(eff) == TYPE_DICTIONARY and String(eff.get("type", "")) == "counter":
				var every: int = maxi(1, int(eff.get("every", 1)))
				var cur: int = GameState.incremental_value(String(eff.get("key", ""))) % every
				return "%d/%d" % [cur, every]
	return ""

func _on_use_pressed(item: ItemData) -> void:
	# An overworld active opens a picker on the map underneath — close the backpack
	# so it's visible (the use is only spent once the player commits there).
	var overworld_active: bool = item != null and item.overworld_usable \
		and GameState.combat_scene == null
	if GameState.use_item(item):
		GameLog.add("Used %s." % item.display_name, Color(0.8, 0.9, 1.0))
		if overworld_active:
			close()
			return
	_refresh()

func _render_loot() -> void:
	var any := false
	for kind in GameState.loot.keys():
		var count: int = int(GameState.loot[kind])
		if count <= 0:
			continue
		any = true
		var row := PanelContainer.new()
		var hbox := HBoxContainer.new()
		row.add_child(hbox)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = String(LOOT_LABELS.get(kind, String(kind).capitalize()))
		hbox.add_child(label)
		var count_lbl := Label.new()
		count_lbl.text = "x%d" % count
		count_lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
		hbox.add_child(count_lbl)
		_list_vbox.add_child(row)
	if not any:
		var empty := Label.new()
		empty.text = "No loot collected yet."
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_list_vbox.add_child(empty)
	_hint_label.text = "Potions, scrolls, keys and other findings."

# ------------------------------------------------------------------
# Deck tab — every card the player currently owns, deduped by card id
# with a count, shown as a grid of the real in-game card visuals
# (CardView) so the deck reads the same way it does in a fight.
# ------------------------------------------------------------------

func _render_deck() -> void:
	# Group the deck by (card id + upgraded), preserving first-seen order, and
	# count copies. Keying on the upgrade flag too means an upgraded copy shows
	# as its own "Whetstone+"-style cell instead of collapsing into the base
	# card — so the deck reflects which cards have actually been upgraded.
	var counts: Dictionary = {}
	var order: Array = []          # Array of CardInstance (one representative per key)
	var total := 0
	for c in GameState.deck:
		if not (c is CardInstance) or c.data == null:
			continue
		total += 1
		var key: String = "%s|%s" % [c.data.id, "+" if c.upgraded else ""]
		if counts.has(key):
			counts[key] += 1
		else:
			counts[key] = 1
			order.append(c)
	if order.is_empty():
		var empty := Label.new()
		empty.text = "Your deck is empty."
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_list_vbox.add_child(empty)
		_hint_label.text = "Every card in your run deck."
		return
	# A wrapping grid of card visuals rather than a vertical list of rows.
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_child(grid)
	for inst in order:
		var key: String = "%s|%s" % [inst.data.id, "+" if inst.upgraded else ""]
		grid.add_child(_build_card_cell(inst, int(counts[key])))
	_hint_label.text = "%d cards across %d unique." % [total, order.size()]

# A single deck-grid cell: the actual in-game CardView for this card, with a
# small "xN" badge in the corner when the deck holds more than one copy. Built
# from a representative CardInstance so the upgrade state (name "+", upgraded
# numbers) carries through to the rendered card.
func _build_card_cell(inst: CardInstance, count: int) -> Control:
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(CardView.CARD_W, CardView.CARD_H)

	var view := CardView.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.setup(CardInstance.from_data(inst.data, inst.upgraded))
	wrapper.add_child(view)

	# Upgraded cards get a green glowing outline + an "UPGRADED" tab so it's
	# obvious at a glance (the card name already carries the "+").
	if inst.upgraded:
		var outline := Panel.new()
		outline.set_anchors_preset(Control.PRESET_FULL_RECT)
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ob := StyleBoxFlat.new()
		ob.bg_color = Color(0, 0, 0, 0)
		ob.set_corner_radius_all(4)
		ob.set_border_width_all(3)
		ob.border_color = Color(0.45, 0.95, 0.55, 0.95)
		outline.add_theme_stylebox_override("panel", ob)
		wrapper.add_child(outline)

		var ub := StyleBoxFlat.new()
		ub.bg_color = Color(0.16, 0.45, 0.22, 0.95)
		ub.set_corner_radius_all(6)
		ub.set_content_margin_all(3)
		var ulbl := Label.new()
		ulbl.text = "▲ UPGRADED"
		ulbl.add_theme_font_size_override("font_size", 10)
		ulbl.add_theme_color_override("font_color", Color(0.8, 1.0, 0.85))
		ulbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var upanel := PanelContainer.new()
		upanel.add_theme_stylebox_override("panel", ub)
		upanel.add_child(ulbl)
		upanel.position = Vector2(6, CardView.CARD_H - 24)
		upanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(upanel)

	if count > 1:
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.1, 0.1, 0.14, 0.92)
		bg.set_corner_radius_all(10)
		bg.set_border_width_all(1)
		bg.border_color = Color(1.0, 0.85, 0.4, 0.9)
		bg.set_content_margin_all(4)
		var lbl := Label.new()
		lbl.text = "x%d" % count
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", bg)
		panel.add_child(lbl)
		panel.position = Vector2(CardView.CARD_W - 44, 6)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(panel)

	# Click anywhere on the cell to open the close-up preview. A transparent
	# button on top captures the click (the CardView and badges below ignore
	# mouse), so the preview opens regardless of where in the cell you click.
	var click := Button.new()
	click.flat = true
	click.set_anchors_preset(Control.PRESET_FULL_RECT)
	click.tooltip_text = "Click to view this card up close"
	click.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var data: CardData = inst.data
	var up: bool = inst.upgraded
	click.pressed.connect(func(): _show_card_preview(data, up))
	wrapper.add_child(click)

	return wrapper

# Full-screen close-up of a deck card with a toggle to preview its upgraded
# form. Rebuilds itself when the toggle flips so the card art, cost and text
# all reflect the chosen state.
func _show_card_preview(card_data: CardData, upgraded: bool) -> void:
	if card_data == null:
		return
	_close_card_preview()

	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	_card_preview = layer

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.8)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close_card_preview())
	layer.add_child(dim)

	var inst := CardInstance.from_data(card_data, upgraded)

	# Card panel on the left; a "keywords" tooltip column on the right explaining
	# every Element / Addon / Status the card carries (so a zoomed card teaches
	# the player what Fire / Finesse / Burn actually do).
	var lore: Array = CardLore.entries_for(card_data)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var psize := Vector2(380, 600)
	var lore_w: float = 300.0 if not lore.is_empty() else 0.0
	row.position = (get_viewport_rect().size - Vector2(psize.x + (lore_w + 14.0 if lore_w > 0.0 else 0.0), psize.y)) / 2.0
	layer.add_child(row)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = psize
	row.add_child(panel)
	if not lore.is_empty():
		row.add_child(_build_lore_panel(lore, psize.y))

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	# Scaled-up card visual.
	var card_scale: float = 1.7
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(CardView.CARD_W, CardView.CARD_H) * card_scale
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var view := CardView.new()
	view.setup(inst)
	view.scale = Vector2(card_scale, card_scale)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(view)
	vb.add_child(holder)

	# Type • rarity • cost line.
	var card_rarities := ["Starter", "Common", "Uncommon", "Rare", "Legendary"]
	var type_idx: int = clampi(int(card_data.type), 0, CARD_TYPE_LABELS.size() - 1)
	var rar_idx: int = clampi(int(card_data.rarity), 0, card_rarities.size() - 1)
	var info := Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.text = "%s  •  %s  •  Cost %d" % [
		CARD_TYPE_LABELS[type_idx], card_rarities[rar_idx], inst.get_cost()]
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	vb.add_child(info)

	# Full description text.
	var desc := RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.custom_minimum_size = Vector2(psize.x - 48, 0)
	desc.add_theme_font_size_override("normal_font_size", 13)
	desc.text = "[center]%s[/center]" % inst.get_description()
	vb.add_child(desc)

	# Upgrade preview toggle (or a note when the card can't upgrade).
	if card_data.can_upgrade:
		var toggle := CheckButton.new()
		toggle.text = "Preview upgraded"
		toggle.button_pressed = upgraded
		toggle.toggled.connect(func(on: bool): _show_card_preview(card_data, on))
		vb.add_child(toggle)
	else:
		var note := Label.new()
		note.text = "This card can't be upgraded."
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		vb.add_child(note)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close_card_preview)
	vb.add_child(close)

func _close_card_preview() -> void:
	if _card_preview != null:
		_card_preview.queue_free()
		_card_preview = null

# Tooltip-style sidebar for the card zoom: one panel per Element / Addon / Status
# the card carries, each with its name (tinted) and an explanation. Mirrors how
# the in-game hover card reads, so the player can learn keywords up close.
func _build_lore_panel(lore: Array, height: float) -> Control:
	var outer := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.1, 0.97)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_content_margin_all(12)
	outer.add_theme_stylebox_override("panel", sb)
	outer.custom_minimum_size = Vector2(300, height)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.custom_minimum_size = Vector2(276, 0)
	scroll.add_child(vb)

	var title := Label.new()
	title.text = "Keywords"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	vb.add_child(title)
	vb.add_child(HSeparator.new())

	for entry in lore:
		vb.add_child(_lore_entry_row(entry))
	return outer

func _lore_entry_row(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.16, 0.9)
	sb.set_corner_radius_all(8)
	sb.border_width_left = 3
	sb.border_color = entry.get("color", Color(0.6, 0.6, 0.6))
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	card.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	vb.add_child(head)
	var nm := Label.new()
	nm.text = String(entry.get("name", ""))
	nm.add_theme_font_size_override("font_size", 13)
	nm.add_theme_color_override("font_color", entry.get("color", Color.WHITE))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var kind := Label.new()
	kind.text = String(entry.get("kind", "")).to_upper()
	kind.add_theme_font_size_override("font_size", 9)
	kind.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66))
	head.add_child(kind)
	var desc := Label.new()
	desc.text = String(entry.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(258, 0)
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.84, 0.84, 0.87))
	vb.add_child(desc)
	return card

# ------------------------------------------------------------------
# Gear tab — action-combat loadout (doubles as the equipment screen).
# Equipment can't be changed mid-combat (the action rule); the rows go
# read-only whenever a combat is live.
# ------------------------------------------------------------------

func _render_gear() -> void:
	# Action combat exposes reload_loadout(); the backpack only opens there
	# between rooms, so gear stays editable. Turn-based card combats keep the
	# action loadout locked while a fight is live.
	var scene = GameState.combat_scene
	var locked: bool = scene != null and not scene.has_method("reload_loadout")
	if locked:
		var note := Label.new()
		note.text = "You can't change equipment during combat."
		note.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
		_list_vbox.add_child(note)
	_list_vbox.add_child(_gear_card_slot("Left click", "LMB", 0, locked))
	_list_vbox.add_child(_gear_card_slot("Right click", "RMB", 1, locked))
	_list_vbox.add_child(_gear_item_slot("Usable item", "Q", locked))
	_list_vbox.add_child(_gear_charged_item_slot("Charged item", "Space", locked))
	_hint_label.text = "Locked while fighting." if locked \
		else "Pick the card fired by each mouse button, the pill you pop with Q, and the charged active you fire with Space. Only Strikes and weapons fit the click slots."

# Shared frame for a gear slot: an icon preview, the slot's name + binding key,
# and a dropdown to pick what's slotted. Returns {row, preview, opt}.
func _gear_slot_frame(title: String, key: String) -> Dictionary:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.17, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_content_margin_all(8)
	row.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	var preview := Control.new()
	preview.custom_minimum_size = Vector2(48, 64)
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(preview)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 5)
	hbox.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	head.add_child(lbl)
	var keycap := Label.new()
	keycap.text = "[%s]" % key
	keycap.add_theme_font_size_override("font_size", 12)
	keycap.add_theme_color_override("font_color", Color(0.7, 0.78, 0.95))
	head.add_child(keycap)

	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(opt)

	return {"row": row, "preview": preview, "opt": opt}

# A click-slot (LMB / RMB) row: dropdown of every eligible Strike/weapon in the
# deck plus "(empty)", with the card art previewed alongside.
func _gear_card_slot(title: String, key: String, slot: int, locked: bool) -> Control:
	var f: Dictionary = _gear_slot_frame(title, key)
	var opt: OptionButton = f.opt
	opt.disabled = locked
	var cur: StringName = GameState.action_left_card_id if slot == 0 else GameState.action_right_card_id
	opt.add_item("(empty)")
	opt.set_item_metadata(0, &"")
	var sel := 0
	for id in _eligible_click_ids():
		var cd: CardData = Data.get_card(id)
		opt.add_item(cd.display_name if cd != null else String(id))
		var idx: int = opt.item_count - 1
		opt.set_item_metadata(idx, id)
		if id == cur:
			sel = idx
	opt.select(sel)
	opt.item_selected.connect(func(_i): _on_click_slot_selected(slot, opt))
	_fill_card_preview(f.preview, cur)
	return f.row

# The active-item (Q) row: dropdown of every usable consumable in the inventory
# plus "(empty)", with the item icon previewed alongside.
func _gear_item_slot(title: String, key: String, locked: bool) -> Control:
	var f: Dictionary = _gear_slot_frame(title, key)
	var opt: OptionButton = f.opt
	opt.disabled = locked
	var cur: StringName = GameState.action_active_item_id
	opt.add_item("(empty)")
	opt.set_item_metadata(0, &"")
	var sel := 0
	for id in _usable_item_ids():
		var it: ItemData = Data.get_item(id)
		opt.add_item(it.display_name if it != null else String(id))
		var idx: int = opt.item_count - 1
		opt.set_item_metadata(idx, id)
		if id == cur:
			sel = idx
	opt.select(sel)
	opt.item_selected.connect(func(_i): _on_item_slot_selected(opt))
	_fill_item_preview(f.preview, cur)
	return f.row

func _on_click_slot_selected(slot: int, opt: OptionButton) -> void:
	var id: StringName = StringName(opt.get_selected_metadata())
	if slot == 0:
		GameState.action_left_card_id = id
	else:
		GameState.action_right_card_id = id
	# Only one Strike across the two click slots: if this pick duplicates a
	# Strike already in the other slot, clear that other slot.
	if id != &"":
		var cd: CardData = Data.get_card(id)
		if cd != null and cd.tags.has("strike"):
			if slot == 0:
				var oc: CardData = Data.get_card(GameState.action_right_card_id)
				if oc != null and oc.tags.has("strike"):
					GameState.action_right_card_id = &""
					GameLog.add("Only one Strike fits the click slots — cleared Right click.", Color(0.85, 0.7, 0.4))
			else:
				var oc2: CardData = Data.get_card(GameState.action_left_card_id)
				if oc2 != null and oc2.tags.has("strike"):
					GameState.action_left_card_id = &""
					GameLog.add("Only one Strike fits the click slots — cleared Left click.", Color(0.85, 0.7, 0.4))
	_refresh()

func _on_item_slot_selected(opt: OptionButton) -> void:
	GameState.action_active_item_id = StringName(opt.get_selected_metadata())
	_refresh()

# The charged-item (E) row: dropdown of every charged active in the inventory
# plus "(empty)". The slotted item is the one that charges per turn in action.
func _gear_charged_item_slot(title: String, key: String, locked: bool) -> Control:
	var f: Dictionary = _gear_slot_frame(title, key)
	var opt: OptionButton = f.opt
	opt.disabled = locked
	var cur: StringName = GameState.action_charged_item_id
	opt.add_item("(empty)")
	opt.set_item_metadata(0, &"")
	var sel := 0
	for id in _charged_item_ids():
		var it: ItemData = Data.get_item(id)
		opt.add_item(it.display_name if it != null else String(id))
		var idx: int = opt.item_count - 1
		opt.set_item_metadata(idx, id)
		if id == cur:
			sel = idx
	opt.select(sel)
	opt.item_selected.connect(func(_i): _on_charged_item_slot_selected(opt))
	_fill_item_preview(f.preview, cur)
	return f.row

func _on_charged_item_slot_selected(opt: OptionButton) -> void:
	GameState.action_charged_item_id = StringName(opt.get_selected_metadata())
	_refresh()

# Fills a slot's preview box with the card art (or an "empty" placeholder).
func _fill_card_preview(preview: Control, id: StringName) -> void:
	if id == &"":
		_fill_empty_preview(preview)
		return
	var cd: CardData = Data.get_card(id)
	if cd != null and cd.image != null:
		_add_preview_texture(preview, cd.image)
	else:
		_fill_empty_preview(preview)

func _fill_item_preview(preview: Control, id: StringName) -> void:
	if id == &"":
		_fill_empty_preview(preview)
		return
	var it: ItemData = Data.get_item(id)
	if it != null and it.image != null:
		_add_preview_texture(preview, it.image)
	else:
		_fill_empty_preview(preview)

func _add_preview_texture(preview: Control, tex: Texture2D) -> void:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(tr)

func _fill_empty_preview(preview: Control) -> void:
	var p := Panel.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.11, 0.8)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.08)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(p)
	var l := Label.new()
	l.text = "—"
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(l)

func _usable_item_ids() -> Array:
	var out: Array = []
	for it in GameState.inventory:
		if it is ItemData and it.kind == ItemData.ItemKind.USABLE and not out.has(it.id):
			out.append(it.id)
	return out

func _charged_item_ids() -> Array:
	var out: Array = []
	for it in GameState.inventory:
		if it is ItemData and it.is_charged() and not out.has(it.id):
			out.append(it.id)
	return out

func _eligible_click_ids() -> Array:
	var out: Array = []
	for c in GameState.deck:
		if c is CardInstance and c.data != null:
			var id: StringName = c.data.id
			if not out.has(id) and GameState.is_click_eligible(id):
				out.append(id)
	return out

