#!/bin/bash
# Run ONE test file, or one test in it, in seconds rather than the whole suite.
#
#   tools/gut.sh test_gameloop2                 # one file
#   tools/gut.sh test_overworld2 crash          # the tests in it whose name contains "crash"
#   tools/gut.sh                                # the whole suite (~25 min)
#   tools/gut.sh --parallel [N]                 # the whole suite in N processes at
#                                               # once (default: one per core)
#
# WHY `-gconfig=`: .gutconfig.json names `res://test/` as a directory to run, and
# GUT adds a `-gtest` file ON TOP of it rather than instead of it — so
# `-gtest=res://test/test_x.gd` alone silently runs all ~3,100 tests. Emptying the
# config drops the directory; the pre-run hook (starting gear off) is passed back
# by hand, since it lived in the same file.
#
# Prints the totals and every failure; the full log is in $GUT_LOG (default under
# /tmp). Never run two at once: they share user:// and race on the save slots —
# except as --parallel, which gives each process its own (see below).
set -u
cd "$(dirname "$0")/.."
LOG="${GUT_LOG:-/tmp/gut_last.log}"

# --PARALLEL: the whole suite as N shards running side by side. Each process keeps
# every N-th test of every file (GUT_SHARD, read by test/pre_run_hook.gd) and gets
# its own user:// through XDG_DATA_HOME, which is where Godot keeps it on Linux,
# so no two of them touch the same save slot. The logs are concatenated into $LOG
# and the totals summed; the run fails if any shard does.
if [ "${1:-}" = "--parallel" ]; then
	N="${2:-$(nproc)}"
	WORK="$(mktemp -d "${TMPDIR:-/tmp}/gut_parallel.XXXXXX")"
	PIDS=()
	for ((k = 0; k < N; k++)); do
		mkdir -p "$WORK/data$k"
		XDG_DATA_HOME="$WORK/data$k" GUT_SHARD="$k/$N" \
			godot --headless -s addons/gut/gut_cmdln.gd > "$WORK/shard$k.log" 2>&1 &
		PIDS+=($!)
	done
	STATUS=0
	for pid in "${PIDS[@]}"; do
		wait "$pid" || STATUS=1
	done
	: > "$LOG"
	for ((k = 0; k < N; k++)); do
		echo "===== shard $k/$N =====" >> "$LOG"
		cat "$WORK/shard$k.log" >> "$LOG"
	done
	# Totals, summed over the shards' own "Totals" blocks.
	awk '/^Totals/{t=1} t && /^Tests /{a+=$2} t && /^Passing Tests/{p+=$3} \
		t && /^Failing Tests/{f+=$3} t && /^(Risky|Pending)/{r+=$NF} \
		END{printf "Tests %d  Passing %d  Failing %d  Risky/Pending %d  (%d shards)\n", a, p, f, r, '"$N"'}' \
		"$WORK"/shard*.log
	grep -hE "SCRIPT ERROR|Parse Error|\[Failed\]|at line" "$WORK"/shard*.log | head -60
	rm -rf "$WORK"
	echo "(exit $STATUS, full log: $LOG)"
	exit $STATUS
fi

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
