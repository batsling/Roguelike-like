extends GutTest

# NO LAMBDA ON THE DEFERRED QUEUE FROM AN OBJECT THAT CAN BE FREED.
#
# CI's GUT job crashed with signal 11 on main (19 Nov 2026) and on PR #366 (20
# Nov), each time right after "Trying to call a lambda with an invalid
# instance" / "Error calling deferred method: '…<anonymous lambda>': Instance
# is null". A lambda written inside an instance method belongs to that object;
# deferred, it outlives a screen freed in the same frame (which every headless
# test that opens and leaves a screen does), and Godot 4.6 can then read freed
# memory naming it — the "TextParagraph::" in the message is whatever reused
# the slot. A deferred METHOD call is checked by ObjectID and dropped quietly.
#
# So: `(func …).call_deferred()` and `some_lambda.call_deferred()` are refused
# in instance code. A lambda in a STATIC function has no object to outlive, and
# is allowed.

func _scan(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(path.path_join(f))
	for d in dir.get_directories():
		_scan(path.path_join(d), out)

func test_no_instance_lambda_is_deferred() -> void:
	var files: Array = []
	_scan("res://scripts", files)
	var bad: Array = []
	var lam_var := RegEx.create_from_string("var\\s+(\\w+)\\s*(?::\\s*Callable)?\\s*:?=\\s*func")
	for path in files:
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		var in_static: bool = false
		var lambdas: Dictionary = {}
		var open_inline: int = -1       # line of the last "(func" seen in this function
		for i in range(lines.size()):
			var line: String = lines[i]
			var t: String = line.strip_edges()
			if t.begins_with("#"):
				continue
			if line.begins_with("func ") or line.begins_with("static func "):
				in_static = line.begins_with("static func ")
				lambdas.clear()
				open_inline = -1
			if in_static:
				continue
			var m := lam_var.search(t)
			if m != null:
				lambdas[m.get_string(1)] = true
			if t.contains("(func"):
				open_inline = i
			if t.contains(".call_deferred("):
				if open_inline >= 0 and i - open_inline <= 14 and t.contains(").call_deferred("):
					bad.append("%s:%d" % [path.get_file(), i + 1])
				for name in lambdas:
					if t.contains("%s.call_deferred(" % name):
						bad.append("%s:%d" % [path.get_file(), i + 1])
	assert_eq(bad, [], "defer a method, not a lambda (see the top of this file)")
