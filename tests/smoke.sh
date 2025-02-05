#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/minitalk-smoke.XXXXXX")
OUT="$TEST_TMP/server.out"
EXPECTED="$TEST_TMP/expected.out"
SERVER_ERR="$TEST_TMP/server.err"
CLIENT_ERR="$TEST_TMP/client.err"
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

"$ROOT/server" >"$OUT" 2>"$SERVER_ERR" &
SERVER_PID=$!

tries=0
while [ "$tries" -lt 50 ]; do
	if [ -s "$OUT" ] && [ "$(sed -n '1p' "$OUT")" = "$SERVER_PID" ]; then
		break
	fi
	tries=$((tries + 1))
	sleep 0.1
done

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
	printf 'server exited before smoke test\n' >&2
	exit 1
fi
if [ ! -s "$OUT" ] || [ "$(sed -n '1p' "$OUT")" != "$SERVER_PID" ]; then
	printf 'server did not publish its complete pid line\n' >&2
	exit 1
fi
if ! "$ROOT/client" "$SERVER_PID" "hello" 2>"$CLIENT_ERR"; then
	printf 'client failed to deliver hello\n' >&2
	exit 1
fi
if [ -s "$CLIENT_ERR" ] || [ -s "$SERVER_ERR" ]; then
	printf 'smoke test wrote unexpected diagnostics\n' >&2
	exit 1
fi

{
	printf '%s\n' "$SERVER_PID"
	printf 'hello\n'
} >"$EXPECTED"

diff -u "$EXPECTED" "$OUT"
