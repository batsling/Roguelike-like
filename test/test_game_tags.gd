extends GutTest

# GameTags — tags the player adds to or takes off a game in game, laid over the
# sheet's baked GameData.tags, and exported for tools/apply_tag_edits.py.
#
# What is worth defending: the baked tags are never written to; an edit counts
# at once (an event can route to a game tagged a moment ago); an edit is
# undoable from either direction; the pending list empties itself once the
# sheet has caught up; and the export carries exactly what the script needs.
# The real profile's edits are put aside for the file and restored after, so a
# test run never costs the player their pending tags.

var _saved_added: Dictionary
var _saved_removed: Dictionary

func before_all() -> void:
	_saved_added = GameTags._added.duplicate(true)
	_saved_removed = GameTags._removed.duplicate(true)

func after_all() -> void:
	GameTags._added = _saved_added
	GameTags._removed = _saved_removed
	GameTags._changed(&"")

func before_each() -> void:
	GameTags.clear_all()

func after_each() -> void:
	GameTags.clear_all()

# A game the sheet tags, and one it doesn't.
func _tagged() -> GameData:
	for g in Data.all_games():
		if g is GameData and (g as GameData).tags.size() >= 1:
			return g
	return null

func _untagged() -> GameData:
	for g in Data.all_games():
		if g is GameData and (g as GameData).tags.is_empty():
			return g
	return null

# --- reading ---------------------------------------------------------------

func test_with_no_edits_a_game_reads_as_the_sheet_says() -> void:
	for g in Data.all_games():
		if g is GameData:
			var want := PackedStringArray()
			for t in (g as GameData).tags:
				want.append(GameTags.normalize(t))
			assert_eq(GameTags.tags_of(g), want, "%s reads its baked tags" % g.display_name)

func test_a_tag_is_kept_in_one_spelling() -> void:
	assert_eq(GameTags.normalize("  Tower   Defense "), "tower defense")
	assert_eq(GameTags.normalize("crab, maritime"), "crab maritime",
		"a comma would split the sheet's cell, so it is refused")
	assert_eq(GameTags.normalize("   "), "")

# --- writing ---------------------------------------------------------------

func test_adding_a_tag_counts_at_once_and_leaves_the_sheet_alone() -> void:
	var g: GameData = _untagged()
	var baked: PackedStringArray = g.tags.duplicate()
	assert_true(GameTags.add_tag(g, "Lighthouse"))
	assert_true(GameTags.has_tag(g, "lighthouse"))
	assert_true(GameTags.is_added(g, "lighthouse"), "and it reads as not in the sheet yet")
	assert_eq(g.tags, baked, "the baked tags are never written to")
	assert_false(GameTags.add_tag(g, "LIGHTHOUSE"), "the same tag twice is one tag")

func test_removing_a_sheet_tag_hides_it_and_adding_it_back_restores_it() -> void:
	var g: GameData = _tagged()
	var t: String = GameTags.normalize(g.tags[0])
	assert_true(GameTags.remove_tag(g, t))
	assert_false(GameTags.has_tag(g, t))
	assert_eq(GameTags.removed_of(g), PackedStringArray([t]))
	assert_true(GameTags.add_tag(g, t), "putting it back")
	assert_true(GameTags.has_tag(g, t))
	assert_eq(GameTags.pending_count(), 0, "a removal taken back is no edit at all")

func test_taking_off_a_tag_added_here_leaves_no_edit() -> void:
	var g: GameData = _untagged()
	GameTags.add_tag(g, "lighthouse")
	GameTags.remove_tag(g, "lighthouse")
	assert_eq(GameTags.pending_count(), 0)
	assert_eq(GameTags.removed_of(g).size(), 0, "a tag the sheet never had is not a removal")

func test_the_vocabulary_offers_every_tag_once_including_new_ones() -> void:
	var voc: PackedStringArray = GameTags.vocabulary()
	assert_true(voc.has("space") and voc.has("dice"), "the sheet's own tags are on offer")
	GameTags.add_tag(_untagged(), "lighthouse")
	assert_true(GameTags.vocabulary().has("lighthouse"), "and a new one joins as soon as it is used")
	var sorted: PackedStringArray = GameTags.vocabulary().duplicate()
	sorted.sort()
	assert_eq(GameTags.vocabulary(), sorted)

# --- gameplay --------------------------------------------------------------

func test_an_event_can_send_the_run_to_a_game_tagged_in_game() -> void:
	var before: int = Settings.game_filter
	Settings.game_filter = Settings.GameFilter.ALL
	var g: GameData = _untagged()
	assert_false(EventSystem.games_with_tag(&"lighthouse").has(g.id))
	GameTags.add_tag(g, "lighthouse")
	assert_true(EventSystem.games_with_tag(&"lighthouse").has(g.id),
		"the detour pool reads the live tags, not the baked ones")
	var t: GameData = _tagged()
	var sheet_tag: String = GameTags.normalize(t.tags[0])
	GameTags.remove_tag(t, sheet_tag)
	assert_false(EventSystem.games_with_tag(StringName(sheet_tag)).has(t.id),
		"and a tag taken off stops routing there")
	Settings.game_filter = before

# --- persistence -------------------------------------------------------------

func test_edits_survive_a_reload() -> void:
	var g: GameData = _untagged()
	var t: GameData = _tagged()
	GameTags.add_tag(g, "lighthouse")
	GameTags.remove_tag(t, t.tags[0])
	GameTags.load_tags()
	assert_true(GameTags.is_added(g, "lighthouse"))
	assert_false(GameTags.has_tag(t, t.tags[0]))

func test_edits_the_sheet_has_caught_up_with_drop_off_on_load() -> void:
	# Stand in for apply_tag_edits.py + a re-import: write the edit into the
	# baked tags, then reload.
	var g: GameData = _untagged()
	GameTags.add_tag(g, "lighthouse")
	var keep: PackedStringArray = g.tags.duplicate()
	g.tags = PackedStringArray(["lighthouse"])
	GameTags.load_tags()
	assert_eq(GameTags.pending_count(), 0, "the sheet has it, so it is no longer pending")
	assert_true(GameTags.has_tag(g, "lighthouse"))
	g.tags = keep

# --- export ------------------------------------------------------------------

func test_the_export_covers_every_game_with_its_tags_and_its_edits() -> void:
	var g: GameData = _untagged()
	var t: GameData = _tagged()
	GameTags.add_tag(g, "Lighthouse")
	GameTags.remove_tag(t, t.tags[0])
	var path: String = GameTags.export_edits("user://test_tag_edits.json")
	assert_ne(path, "")
	var data = JSON.parse_string(FileAccess.get_file_as_string("user://test_tag_edits.json"))
	DirAccess.remove_absolute(path)
	assert_true(data is Dictionary)
	var by_id: Dictionary = {}
	for row in data["games"]:
		by_id[row["id"]] = row
	assert_eq(by_id.size(), Data.all_games().size(), "every game in the catalog, edited or not")
	assert_eq(int(data["edited"]), 2)
	assert_eq(by_id[String(g.id)]["name"], g.display_name, "the sheet is keyed by name")
	assert_eq(by_id[String(g.id)]["add"], ["lighthouse"])
	assert_eq(by_id[String(g.id)]["tags"], Array(GameTags.tags_of(g)), "with the tags the game has")
	assert_eq(by_id[String(t.id)]["remove"], [GameTags.normalize(t.tags[0])])
	var other: GameData = null
	for x in Data.all_games():
		if x is GameData and x.id != g.id and x.id != t.id and (x as GameData).tags.size() > 0:
			other = x
			break
	assert_eq(by_id[String(other.id)]["tags"], Array(GameTags.tags_of(other)),
		"an unedited game carries its sheet tags")
	assert_eq(by_id[String(other.id)]["add"], [], "and no edit for the script to write")
	assert_eq(GameTags.pending_count(), 2, "exporting leaves the edits live until the sheet has them")

func test_settings_exports_every_games_tags() -> void:
	GameTags.add_tag(_untagged(), "lighthouse")
	var modal := SettingsModal.new()
	add_child_autofree(modal)
	var btn := modal.find_child("ExportTagsBtn", true, false) as Button
	assert_not_null(btn, "Settings has the one Export")
	var hint := modal.find_child("TagsHint", true, false) as Label
	assert_string_contains(hint.text, "1 game has tag edits")
	btn.pressed.emit()
	var path: String = GameTags.export_path()
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_true(data is Dictionary, "the button wrote the file")
	assert_eq((data["games"] as Array).size(), Data.all_games().size())
	assert_string_contains(hint.text, "Exported all %d games" % Data.all_games().size())

func test_from_the_project_folder_the_export_lands_beside_the_workbook() -> void:
	# Tests run from the project, never from an exported pack.
	assert_eq(GameTags.export_path(), GameTags.PROJECT_EXPORT)

# --- the editor ---------------------------------------------------------------

func _editor(g: GameData) -> TagEditor:
	var ed := TagEditor.make(g)
	add_child_autofree(ed)
	return ed

func _button(ed: Node, node_name: String) -> Button:
	return ed.find_child(node_name, true, false) as Button

func test_the_editor_shows_the_games_tags_and_takes_one_off_with_a_click() -> void:
	var g: GameData = _tagged()
	var t: String = GameTags.normalize(g.tags[0])
	var ed := _editor(g)
	var chip := _button(ed, "Tag_" + t)
	assert_not_null(chip, "each tag is a chip")
	chip.pressed.emit()
	assert_false(GameTags.has_tag(g, t))
	assert_not_null(_button(ed, "Removed_" + t), "the removed tag stays on view to put back")
	var note := ed.find_child("Pending", true, false) as Label
	assert_not_null(note, "and the footer counts the pending edits")
	assert_string_contains(note.text, "Settings", "pointing at the one Export, in Settings")

func test_the_editor_adds_from_the_vocabulary_and_from_the_box() -> void:
	var g: GameData = _untagged()
	var ed := _editor(g)
	assert_null(ed.find_child("Adder", true, false), "the list stays shut until asked for")
	_button(ed, "AddTag").pressed.emit()
	var offer := _button(ed, "Offer_space")
	assert_not_null(offer, "the sheet's tags are one click away")
	offer.pressed.emit()
	assert_true(GameTags.has_tag(g, "space"))
	var field := ed.find_child("NewTag", true, false) as LineEdit
	field.text = "Lighthouse"
	_button(ed, "AddNew").pressed.emit()
	assert_true(GameTags.has_tag(g, "lighthouse"), "and a brand-new one from the box")
	assert_not_null(_button(ed, "Tag_lighthouse"), "drawn as a chip straight away")

func test_an_edit_on_one_screen_shows_on_the_other() -> void:
	var g: GameData = _untagged()
	var a := _editor(g)
	var b := _editor(g)
	_button(a, "AddTag").pressed.emit()
	_button(a, "Offer_space").pressed.emit()
	assert_not_null(_button(b, "Tag_space"), "both editors read GameTags, so both redraw")

func test_the_collection_page_and_the_run_card_both_carry_the_editor() -> void:
	var g: GameData = _tagged()
	var col := Collection.new()
	add_child_autofree(col)
	col._show_game_detail(g)
	assert_eq(col._detail_box.find_children("*", "TagEditor", true, false).size(), 1,
		"the Collection's game page")
	var box: VBoxContainer = RouteLadder.node_card_body({"id": g.id})
	assert_eq(box.find_children("*", "TagEditor", true, false).size(), 1,
		"and the run map's game card")
	box.free()
