#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/minitalk-protocol.XXXXXX")
OUT="$TEST_TMP/server.out"
ERR="$TEST_TMP/server.err"
SERVER_PID=
SERVER_PATH=
UNRELATED_PID=

cleanup()
{
	if [ -n "$UNRELATED_PID" ]; then
		kill "$UNRELATED_PID" 2>/dev/null || true
		wait "$UNRELATED_PID" 2>/dev/null || true
	fi
	if [ -n "$SERVER_PID" ]; then
		kill "$SERVER_PID" 2>/dev/null || true
		wait "$SERVER_PID" 2>/dev/null || true
	fi
	if [ -n "$SERVER_PATH" ]; then
		rm -f "$SERVER_PATH"
	fi
	rm -rf "$TEST_TMP"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

wait_ready()
{
	file=$1
	tries=0
	while [ "$tries" -lt 50 ] && ! grep -qx "$SERVER_PID" "$file" 2>/dev/null; do
		if ! kill -0 "$SERVER_PID" 2>/dev/null; then
			printf 'server exited before becoming ready\n' >&2
			exit 1
		fi
		tries=$((tries + 1))
		sleep 0.1
	done
	grep -qx "$SERVER_PID" "$file"
}

UNRELATED_ERR="$TEST_TMP/unrelated.err"
sleep 30 &
UNRELATED_PID=$!
if "$ROOT/client" "$UNRELATED_PID" unrelated 2>"$UNRELATED_ERR"; then
	printf 'client accepted a process without an active server\n' >&2
	exit 1
fi
grep -qx 'client: invalid server pid' "$UNRELATED_ERR"
kill -0 "$UNRELATED_PID"
kill "$UNRELATED_PID"
wait "$UNRELATED_PID" 2>/dev/null || true
UNRELATED_PID=

STALE_UNRELATED_ERR="$TEST_TMP/stale-unrelated.err"
"$ROOT/tests/stale_server_exec" "$ROOT/client" unrelated \
	2>"$STALE_UNRELATED_ERR"
grep -qx 'client: failed to send signal' "$STALE_UNRELATED_ERR"

STALE_SERVER_OUT="$TEST_TMP/stale-server.out"
STALE_SERVER_ERR="$TEST_TMP/stale-server.err"
"$ROOT/tests/stale_server_exec" "$ROOT/server" \
	>"$STALE_SERVER_OUT" 2>"$STALE_SERVER_ERR"
[ ! -s "$STALE_SERVER_OUT" ]
grep -qx 'server: failed to create response channel' "$STALE_SERVER_ERR"

RUNTIME_DIR="/tmp/signal-message-bus-$(id -u)"
"$ROOT/server" >"$OUT" 2>"$ERR" &
SERVER_PID=$!
SERVER_PATH="$RUNTIME_DIR/server-$SERVER_PID.sock"
wait_ready "$OUT"
if [ "$(uname -s)" = Darwin ]; then
	runtime_mode=$(stat -f '%Lp' "$RUNTIME_DIR")
else
	runtime_mode=$(stat -c '%a' "$RUNTIME_DIR")
fi
[ "$runtime_mode" = 700 ]

"$ROOT/tests/stale_exec" "$ROOT/client" "$SERVER_PID" stale socket \
	2>"$TEST_TMP/stale.err"
[ ! -s "$TEST_TMP/stale.err" ]
"$ROOT/tests/stale_exec" "$ROOT/client" "$SERVER_PID" blocked file \
	2>"$TEST_TMP/file.err"
grep -qx 'client: failed to create response channel' "$TEST_TMP/file.err"
[ ! -s "$ERR" ]
{
	sed -n '1p' "$OUT"
	printf 'stale\n'
} >"$TEST_TMP/expected"
diff -u "$TEST_TMP/expected" "$OUT"

kill "$SERVER_PID"
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=
rm -f "$SERVER_PATH"
SERVER_PATH=
