extends GutTest

# WHAT THE RUN'S PAGE COMPILES BEFORE IT CAN APPEAR (docs/performance-backlog.md
# §6). Loading Overworld2.gd compiles every class it NAMES and every script it
# PRELOADS — and every one those name in turn — before the page exists. It was
# 49 scripts and ~1.4 s between Start Run and the page; the screens a run may
# never open are now reached by path at the moment they open, and it is 33 and
# ~0.9 s.
#
# A cold compile cannot be timed inside a GUT run (by the time a test runs,
# everything is loaded), so this guards the CAUSE instead: none of these files
# may name, or preload, a screen that is only opened on demand. Naming one again
# does not break anything a test can see — it just quietly puts a few hundred
# milliseconds back on every run's start, which is how it got to 1.4 s.

# The screens the page opens on demand, and what they drag in with them.
const ON_DEMAND := [
	"AtlasView", "Collection", "HowToPlayScreen", "SettingsModal",
	"TierListScreen", "RunHistoryScreen", "RunLogScreen", "RunOverScreen",
	"EventModal2", "RewardScreen", "GraveyardPanel", "CompletedGoalsPanel",
	"RunMapModal",
]

# The page, and the pieces it builds on its first frame. A screen named from
# ANY of these is compiled with the page.
const EAGER_FILES := [
	"res://scripts/redesign2/Overworld2.gd",
	"res://scripts/redesign2/PostCombatScreen.gd",
	"res://scripts/redesign2/RouteLadder.gd",
	"res://scripts/redesign2/GameChoiceModal.gd",
	"res://scripts/redesign2/BattlefieldView.gd",
	"res://scripts/redesign2/OfferingCards.gd",
	"res://scripts/redesign2/DropQueue.gd",
	"res://scripts/redesign2/PackStrip.gd",
	"res://scripts/redesign2/ShopPanel2.gd",
]

# The code on a line: comments dropped, string contents blanked, so a class
# mentioned in prose or inside a load("…") path does not count.
func _code_of(line: String) -> String:
	var out: String = ""
	var in_str: bool = false
	for i in range(line.length()):
		var ch: String = line[i]
		if ch == "\"":
			in_str = not in_str
			out += ch
		elif in_str:
			out += " "
		elif ch == "#":
			break
		else:
			out += ch
	return out

func test_the_page_names_no_screen_it_only_opens_on_demand() -> void:
	var found: Array = []
	for path in EAGER_FILES:
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for i in range(lines.size()):
			var code: String = _code_of(lines[i])
			for cls in ON_DEMAND:
				var re := RegEx.create_from_string("\\b%s\\b" % cls)
				if re.search(code) != null:
					found.append("%s:%d names %s" % [path.get_file(), i + 1, cls])
	assert_eq(found, [], "reach these by path at the moment they open (load(X_SCRIPT)), "
		+ "or they are compiled into every run's page load: %s" % str(found))

func test_the_page_preloads_no_screen_it_only_opens_on_demand() -> void:
	var found: Array = []
	for path in EAGER_FILES:
		var text: String = FileAccess.get_file_as_string(path)
		for cls in ON_DEMAND:
			if text.contains('preload("res://scripts/ui/%s.gd")' % cls) \
					or text.contains('preload("res://scripts/redesign2/%s.gd")' % cls):
				found.append("%s preloads %s" % [path.get_file(), cls])
	assert_eq(found, [], "a preload is as eager as a class name: %s" % str(found))

# The paths the page loads by must point at real files, or the screen simply
# fails to open the first time someone presses its button.
func test_every_on_demand_path_the_page_loads_exists() -> void:
	var script: Script = load("res://scripts/redesign2/Overworld2.gd")
	var consts: Dictionary = script.get_script_constant_map()
	var checked: int = 0
	for key in consts:
		if String(key).ends_with("_SCRIPT") and consts[key] is String:
			assert_true(ResourceLoader.exists(consts[key]), "%s -> %s exists" % [key, consts[key]])
			checked += 1
	assert_gt(checked, 10, "the page lists its on-demand screens")
