#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/minitalk-inherited-mask.XXXXXX")
OUT="$TEST_TMP/server.out"
EXPECTED="$TEST_TMP/expected.out"
SERVER_ERR="$TEST_TMP/server.err"
CLIENT_ERR="$TEST_TMP/client.err"
WRAPPER_PID=
SERVER_PID=
SERVER_PATH=

cleanup()
{
	if [ -n "$SERVER_PID" ]; then
		kill -TERM "$SERVER_PID" 2>/dev/null || true
	fi
	if [ -n "$WRAPPER_PID" ]; then
		wait "$WRAPPER_PID" 2>/dev/null || true
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

"$ROOT/tests/masked_exec" "$ROOT/server" >"$OUT" 2>"$SERVER_ERR" &
WRAPPER_PID=$!
tries=0
while [ "$tries" -lt 50 ]; do
	SERVER_PID=$(sed -n '1p' "$OUT" 2>/dev/null || true)
	if [ -n "$SERVER_PID" ]; then
		break
	fi
	if ! kill -0 "$WRAPPER_PID" 2>/dev/null; then
		printf 'masked server wrapper exited before readiness\n' >&2
		exit 1
	fi
	tries=$((tries + 1))
	sleep 0.1
done
case "$SERVER_PID" in
	''|*[!0-9]*)
		printf 'masked server did not publish a pid\n' >&2
		exit 1
		;;
esac
SERVER_PATH="/tmp/signal-message-bus-$(id -u)/server-$SERVER_PID.sock"

"$ROOT/client" "$SERVER_PID" "inherited mask" 2>"$CLIENT_ERR"
[ ! -s "$CLIENT_ERR" ]
[ ! -s "$SERVER_ERR" ]
{
	printf '%s\n' "$SERVER_PID"
	printf 'inherited mask\n'
} >"$EXPECTED"
diff -u "$EXPECTED" "$OUT"

kill -TERM "$SERVER_PID"
server_status=0
wait "$WRAPPER_PID" || server_status=$?
WRAPPER_PID=
SERVER_PID=
[ "$server_status" -eq 143 ]
[ ! -e "$SERVER_PATH" ]
SERVER_PATH=
[ ! -s "$SERVER_ERR" ]
