extends GutTest

# FloatingNumbers.spawn attaches a short-lived Label to the given parent showing
# the (absolute) amount. The drift/fade tween and self-free are time-based, so
# these tests only assert the spawn contract: a labelled child appears, and the
# no-op guards hold.

func test_spawn_adds_label_with_amount() -> void:
	var host := Control.new()
	add_child_autofree(host)
	FloatingNumbers.spawn(host, Vector2(20, 20), 7)
	assert_eq(host.get_child_count(), 1, "one floating label spawned")
	var lbl := host.get_child(0) as Label
	assert_not_null(lbl, "spawned node is a Label")
	assert_eq(lbl.text, "7", "shows the amount")

func test_spawn_shows_absolute_value() -> void:
	var host := Control.new()
	add_child_autofree(host)
	FloatingNumbers.spawn(host, Vector2.ZERO, -12)
	assert_eq((host.get_child(0) as Label).text, "12", "negative input shown as a bare number")

func test_zero_amount_is_a_noop() -> void:
	var host := Control.new()
	add_child_autofree(host)
	FloatingNumbers.spawn(host, Vector2.ZERO, 0)
	assert_eq(host.get_child_count(), 0, "zero never spawns a label")

func test_spawn_uses_given_color() -> void:
	var host := Control.new()
	add_child_autofree(host)
	FloatingNumbers.spawn(host, Vector2.ZERO, 4, FloatingNumbers.HEAL_COLOR)
	var lbl := host.get_child(0) as Label
	assert_eq(lbl.get_theme_color("font_color"), FloatingNumbers.HEAL_COLOR,
		"heal numbers use the green heal colour")

func test_null_parent_is_safe() -> void:
	# Must not crash.
	FloatingNumbers.spawn(null, Vector2.ZERO, 5)
	assert_true(true, "null parent is a safe no-op")
