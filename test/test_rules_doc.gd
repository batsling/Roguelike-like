extends GutTest

# `docs/rules.md` is the in-game manual rendered as a page, and it is generated,
# never hand-edited (scripts/ui/HowToPlayMarkdown.gd). The manual's numbers move
# with the code; this fails the moment the checked-in page no longer says what the
# game does. To fix it, regenerate:
#
#     godot --headless -s addons/gut/gut_cmdln.gd \
#         -gdir=res://tools -gprefix=dump_ -gselect=dump_rules_doc.gd -gexit

const HowToPlayMarkdown := preload("res://scripts/ui/HowToPlayMarkdown.gd")
const HowToPlayText := preload("res://scripts/ui/HowToPlayText.gd")

func test_the_rules_page_is_the_manual_as_it_stands() -> void:
	var f := FileAccess.open(HowToPlayMarkdown.PATH, FileAccess.READ)
	assert_not_null(f, "docs/rules.md exists")
	if f == null:
		return
	var on_disk: String = f.get_as_text()
	var want: String = HowToPlayMarkdown.render()
	if on_disk == want:
		assert_true(true, "docs/rules.md is current")
		return
	# Name the first line that differs, so the failure says what moved.
	var a: PackedStringArray = on_disk.split("\n")
	var b: PackedStringArray = want.split("\n")
	var i: int = 0
	while i < mini(a.size(), b.size()) and a[i] == b[i]:
		i += 1
	fail_test("docs/rules.md is stale — regenerate it (tools/dump_rules_doc.gd). "
		+ "First difference at line %d:\n  on disk: %s\n  manual:  %s" % [i + 1,
		a[i] if i < a.size() else "<end>", b[i] if i < b.size() else "<end>"])

func test_every_chapter_is_on_the_page() -> void:
	var page: String = HowToPlayMarkdown.render()
	for ch in HowToPlayText.chapters():
		assert_string_contains(page, "## %s %s" % [ch["icon"], ch["title"]])

func test_a_table_gets_a_header_rule_once() -> void:
	var out: PackedStringArray = []
	HowToPlayMarkdown._blocks([
		{"k": "row", "c": ["a", "b"], "head": true},
		{"k": "row", "c": ["1", "2|3"]},
	], out)
	assert_eq(Array(out), ["| a | b |", "| --- | --- |", "| 1 | 2\\|3 |"])
