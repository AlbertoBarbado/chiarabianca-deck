#!/usr/bin/env bash
# Runs every automated suite and prints one summary line per suite.
#   GODOT=/path/to/godot bash tests/run_all_tests.sh [headless|windowed|all] [name_filter]
# Headless suites are the logic tests (tests/**/run_*.gd, run_tests.gd, balance_simulation.gd and the
# scene-based tests/**/*_logic_test.tscn, which need the autoloads).
# Windowed suites are the scene walkthroughs (tests/**/*.tscn) and need a display.
# Not run here: tests/art/check_release_art.gd (release gate, lists unlicensed art) and the
# long balance simulation tests/combat/run_simulation.tscn.
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
MODE="${1:-all}"
FILTER="${2:-}"
FAILED=0

summary() {
	# The last "N checks, M failures" style line, or the last failure count line a suite prints.
	grep -E "checks?, [0-9]+ failures?|[0-9]+ failures?$|FAIL" "$1" | grep -v "^\s*ok" | tail -6
}

run_suite() {
	local label="$1"; shift
	[[ -n "$FILTER" && "$label" != *"$FILTER"* ]] && return
	local log
	log="$(mktemp)"
	timeout 900 "$GODOT" "$@" >"$log" 2>&1
	local code=$?
	echo "$label :: exit $code :: $(summary "$log" | tr '\n' ' ')"
	[[ $code -ne 0 ]] && FAILED=$((FAILED + 1))
	rm -f "$log"
}

if [[ "$MODE" != "windowed" ]]; then
	for f in tests/combat/balance_simulation.gd $(find tests -name "run_*.gd" | sort); do
		case "$f" in
			*run_menu_ui_tests.gd|*run_simulation.gd|*run_all_tests*) continue ;;
		esac
		run_suite "$f" --headless --path . --script "res://$f"
	done
	# Logic suites that need the autoloads run as scenes, still headless.
	for f in $(find tests -name "*_logic_test.tscn" | sort); do
		run_suite "$f" --headless --path . "res://$f"
	done
fi
if [[ "$MODE" != "headless" ]]; then
	for f in $(find tests -name "*.tscn" | sort); do
		[[ "$f" == *run_simulation.tscn || "$f" == *_logic_test.tscn ]] && continue
		run_suite "$f" --path . "res://$f"
	done
fi
echo "suites failed: $FAILED"
exit $((FAILED > 0))
