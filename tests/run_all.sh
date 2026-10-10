#!/bin/bash
# Runs every headless check: the offline match check and all online
# scenarios against a freshly built Go server. Works on a copy of the
# project so the real .godot/ cache is never touched.
#   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 WORK=/some/scratch/dir tests/run_all.sh
# BACKEND is the uma-go checkout (default: ../uma-go next to this project).
# Prints each test's output; every PASS line is one passing check (11 total).
set -u
GODOT=${GODOT:?set GODOT to a Godot 4.7 binary}
WORK=${WORK:?set WORK to a scratch directory}
PROJECT=$(cd "$(dirname "$0")/.." && pwd)
BACKEND=${BACKEND:-$PROJECT/../uma-go}
PORT=${PORT:-18080}

mkdir -p "$WORK"
(cd "$BACKEND" && go build -o "$WORK/server" ./cmd/server) || exit 1
rm -rf "$WORK/proj" && cp -r "$PROJECT" "$WORK/proj" && rm -rf "$WORK/proj/.godot"
timeout 60 "$GODOT" --headless --path "$WORK/proj" --editor --quit 2>&1 | grep -iE 'error|warn|parse'

for test in match_check menu_check run_check; do
	echo "== $test"
	timeout 90 "$GODOT" --headless --path "$WORK/proj" -s res://tests/run.gd -- $test 2>&1 | grep -E 'PASS|FAIL|ERROR'
done

"$WORK/server" -addr "127.0.0.1:$PORT" -min-version 0.1.0 -latest-version 0.2.0 \
	-android-url https://example.test/android > "$WORK/server.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
export SERVER_URL=ws://127.0.0.1:$PORT/ws
sleep 0.5

echo "== version_check"
timeout 60 "$GODOT" --headless --path "$WORK/proj" -s res://tests/run.gd -- version_check 2>&1 | grep -E 'PASS|FAIL|ERROR'

run_scenario() {
	local scenario=$1
	shift
	echo "== online_check $scenario"
	export SCENARIO=$scenario CODE_FILE=$WORK/code_$scenario.txt
	rm -f "$CODE_FILE" "$CODE_FILE.result"
	local pids=()
	for role in "$@"; do
		ROLE=$role timeout 90 "$GODOT" --headless --path "$WORK/proj" -s res://tests/run.gd -- online_check \
			> "$WORK/$scenario.$role.log" 2>&1 &
		pids+=($!)
	done
	for pid in "${pids[@]}"; do wait "$pid"; done
	for role in "$@"; do grep -hvE '^\s*$|Godot Engine' "$WORK/$scenario.$role.log"; done
}

run_scenario basic host guest late
run_scenario guest_leaves host guest
run_scenario host_leaves host guest
