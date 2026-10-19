#!/bin/bash
# Run ONE test file, or one test in it, in seconds rather than the whole suite.
#
#   tools/gut.sh test_gameloop2                 # one file
#   tools/gut.sh test_overworld2 crash          # the tests in it whose name contains "crash"
#   tools/gut.sh                                # the whole suite (~25 min)
#
# WHY `-gconfig=`: .gutconfig.json names `res://test/` as a directory to run, and
# GUT adds a `-gtest` file ON TOP of it rather than instead of it — so
# `-gtest=res://test/test_x.gd` alone silently runs all ~3,100 tests. Emptying the
# config drops the directory; the pre-run hook (starting gear off) is passed back
# by hand, since it lived in the same file.
#
# Prints the totals and every failure; the full log is in $GUT_LOG (default under
# /tmp). Never run two at once: they share user:// and race on the save slots.
set -u
cd "$(dirname "$0")/.."
LOG="${GUT_LOG:-/tmp/gut_last.log}"
if [ $# -eq 0 ]; then
	godot --headless -s addons/gut/gut_cmdln.gd > "$LOG" 2>&1
else
	FILE="$1"
	FILE="${FILE#res://}"; FILE="${FILE#test/}"; FILE="${FILE%.gd}"
	ARGS=(-gconfig= "-gtest=res://test/$FILE.gd" -gpre_run_script=res://test/pre_run_hook.gd -gexit)
	[ $# -ge 2 ] && ARGS+=("-gunit_test_name=$2")
	godot --headless -s addons/gut/gut_cmdln.gd "${ARGS[@]}" > "$LOG" 2>&1
fi
STATUS=$?
grep -E "Scripts  |^Tests  |Passing Tests|Failing Tests|Risky|Pending|SCRIPT ERROR|Parse Error|\[Failed\]|at line" "$LOG" | head -60
echo "(exit $STATUS, full log: $LOG)"
exit $STATUS
