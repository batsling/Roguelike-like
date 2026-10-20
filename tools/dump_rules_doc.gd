extends GutTest

# WRITE `docs/rules.md` — the in-game manual as a page (scripts/ui/HowToPlayMarkdown.gd).
#
#     godot --headless -s addons/gut/gut_cmdln.gd \
#         -gdir=res://tools -gprefix=dump_ -gselect=dump_rules_doc.gd -gexit
#
# A GutTest for the reason `dump_map_health.gd` is one: `-s` boots without the
# autoloads, and the manual quotes constants that live on them. It lives in
# `tools/`, so the suite never runs it; `test/test_rules_doc.gd` is the check.

const HowToPlayMarkdown := preload("res://scripts/ui/HowToPlayMarkdown.gd")

func test_dump_rules_doc() -> void:
	var path: String = ProjectSettings.globalize_path(HowToPlayMarkdown.PATH)
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(f, "can write %s" % path)
	if f == null:
		return
	f.store_string(HowToPlayMarkdown.render())
	f.close()
	print("wrote ", path)
