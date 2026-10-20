extends RefCounted

# The written manual as Markdown — `docs/rules.md`, "the rules as the player sees
# them". `HowToPlayText` holds every word and `HowToPlayScreen` draws it in game;
# this draws the same chapters as a page, so the rules can be read, linked and
# shared without opening the game.
#
# THE PAGE IS GENERATED, NEVER EDITED. The manual's numbers are read off the
# constants that govern them, so a balance change moves the in-game manual by
# itself — and a hand-kept copy would be the one place it did not. Regenerate with
#
#     godot --headless -s addons/gut/gut_cmdln.gd \
#         -gdir=res://tools -gprefix=dump_ -gselect=dump_rules_doc.gd -gexit
#
# and `test_rules_doc.gd` fails while the checked-in page differs from this.
#
# No `class_name`, so nothing needs an editor rescan to see it: preload it.

const HowToPlayText := preload("res://scripts/ui/HowToPlayText.gd")

const PATH := "res://docs/rules.md"

static func render() -> String:
	var chapters: Array = HowToPlayText.chapters()
	var out: PackedStringArray = []
	out.append("# Rules — as the player sees them")
	out.append("")
	out.append("> **Generated** from the in-game manual (📖 How to Play, "
		+ "`scripts/ui/HowToPlayText.gd`) by `tools/dump_rules_doc.gd` — edit the "
		+ "manual, not this page. Every number here is read off the constant the "
		+ "game itself uses, so this page and the game cannot disagree. The design "
		+ "reasoning behind the rules is in "
		+ "[`games-first-redesign.md`](games-first-redesign.md).")
	out.append("")
	out.append("## Contents")
	out.append("")
	for i in range(chapters.size()):
		var ch: Dictionary = chapters[i]
		out.append("%d. [%s](#%s) — %s" % [i + 1, String(ch["title"]),
			_anchor(_heading(ch)), String(ch.get("blurb", ""))])
	for ch in chapters:
		out.append("")
		out.append("## " + _heading(ch))
		out.append("")
		var blurb: String = String(ch.get("blurb", ""))
		if blurb != "":
			out.append("*%s*" % blurb)
			out.append("")
		_blocks(ch.get("blocks", []), out)
	return "\n".join(out).strip_edges() + "\n"

static func _heading(ch: Dictionary) -> String:
	return "%s %s" % [String(ch.get("icon", "")), String(ch["title"])]

# GitHub's anchor rule: lowercase, drop everything that is not a letter, digit,
# space, hyphen or underscore, spaces to hyphens. An icon leaves a leading hyphen
# behind, which is what GitHub produces too.
static func _anchor(heading: String) -> String:
	var a: String = ""
	for c in heading.to_lower():
		if c == " ":
			a += "-"
		elif c == "-" or c == "_" or (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			a += c
	return a

# Lists and table rows run together; everything else is its own paragraph.
static func _blocks(blocks: Array, out: PackedStringArray) -> void:
	var prev: String = ""
	var table_open: bool = false
	for block in blocks:
		var k: String = String(block.get("k", "p"))
		var listy: bool = k in ["b", "kv", "step"]
		var joins: bool = (listy and prev in ["b", "kv", "step"]) or (k == "row" and prev == "row")
		if prev != "" and not joins:
			out.append("")
		if k != "row":
			table_open = false
		match k:
			"h":
				out.append("### " + _text(block["t"]))
			"b":
				out.append("- " + _text(block["t"]))
			"kv":
				out.append("- **%s** — %s" % [_text(block["t"]), _text(block.get("v", ""))])
			"step":
				out.append("%d. %s" % [int(block.get("n", 1)), _text(block["t"])])
			"note":
				out.append("> " + _text(block["t"]))
			"row":
				var cells: Array = []
				for c in block.get("c", []):
					cells.append(_text(c).replace("|", "\\|"))
				out.append("| " + " | ".join(cells) + " |")
				# A Markdown table needs a header: the first row is it, marked or not.
				if not table_open:
					var rule: Array = []
					for _c in cells:
						rule.append("---")
					out.append("| " + " | ".join(rule) + " |")
					table_open = true
			_:
				out.append(_text(block["t"]))
		prev = k

static func _text(t) -> String:
	return String(t).strip_edges().replace("\n", " ")
