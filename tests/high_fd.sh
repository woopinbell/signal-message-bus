#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/minitalk-high-fd.XXXXXX")
OUT="$TEST_TMP/server.out"
ERR="$TEST_TMP/server.err"
CLIENT_ERR="$TEST_TMP/client.err"
HIGH_SERVER_OUT="$TEST_TMP/high-server.out"
HIGH_SERVER_ERR="$TEST_TMP/high-server.err"
SERVER_PID=

cleanup()
{
	if [ -n "$SERVER_PID" ]; then
		kill "$SERVER_PID" 2>/dev/null || true
		wait "$SERVER_PID" 2>/dev/null || true
	fi
	rm -rf "$TEST_TMP"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

"$ROOT/server" >"$OUT" 2>"$ERR" &
SERVER_PID=$!
tries=0
while [ "$tries" -lt 50 ] && ! grep -qx "$SERVER_PID" "$OUT" 2>/dev/null; do
	if ! kill -0 "$SERVER_PID" 2>/dev/null; then
		printf 'server exited before high descriptor test\n' >&2
		exit 1
	fi
	tries=$((tries + 1))
	sleep 0.1
done
grep -qx "$SERVER_PID" "$OUT"

client_status=0
"$ROOT/tests/high_fd_exec" "$ROOT/client" "$SERVER_PID" high-fd \
	2>"$CLIENT_ERR" || client_status=$?
[ "$client_status" -eq 1 ]
grep -qx 'client: failed to create response channel' "$CLIENT_ERR"
kill -0 "$SERVER_PID"
[ ! -s "$ERR" ]

server_status=0
"$ROOT/tests/high_fd_exec" "$ROOT/server" \
	>"$HIGH_SERVER_OUT" 2>"$HIGH_SERVER_ERR" || server_status=$?
[ "$server_status" -eq 1 ]
[ ! -s "$HIGH_SERVER_OUT" ]
grep -qx 'server: failed to create response channel' "$HIGH_SERVER_ERR"
