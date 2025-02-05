#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/minitalk-smoke.XXXXXX")
OUT="$TEST_TMP/server.out"
EXPECTED="$TEST_TMP/expected.out"
SERVER_ERR="$TEST_TMP/server.err"
CLIENT_ERR="$TEST_TMP/client.err"
SERVER_PID=

send_checked()
{
	label=$1
	message=$2
	if ! "$ROOT/client" "$SERVER_PID" "$message" 2>"$CLIENT_ERR"; then
		printf 'client failed during %s\n' "$label" >&2
		exit 1
	fi
	if [ -s "$CLIENT_ERR" ]; then
		printf 'client wrote to stderr during %s\n' "$label" >&2
		exit 1
	fi
}

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
send_checked hello "hello"
send_checked empty ""
send_checked utf8 "안녕하세요"
LONG_MESSAGE=$(awk 'BEGIN { for (i = 0; i < 1024; i++) printf "x" }')
send_checked long "$LONG_MESSAGE"
send_checked final "last message"

if [ -s "$SERVER_ERR" ]; then
	printf 'server wrote unexpected diagnostics\n' >&2
	exit 1
fi

{
	printf '%s\n' "$SERVER_PID"
	printf 'hello\n'
	printf '\n'
	printf '안녕하세요\n'
	printf '%s\n' "$LONG_MESSAGE"
	printf 'last message\n'
} >"$EXPECTED"

diff -u "$EXPECTED" "$OUT"
