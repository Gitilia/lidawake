#!/usr/bin/env bash
# Build is a separate make step. This script checks on/off against the live Mac.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${LIDAWAKE_BIN:-$ROOT/lidawake}"
PIDFILE="$(mktemp "${TMPDIR:-/tmp}/lidawake-test.XXXXXX")"
export LIDAWAKE_PID_FILE="$PIDFILE"

cleanup() {
  "$BIN" off >/dev/null 2>&1 || true
  rm -f "$PIDFILE"
}
trap cleanup EXIT

if [[ ! -x "$BIN" ]]; then
  echo "missing binary: $BIN" >&2
  exit 1
fi

echo "usage rejects unknown commands"
set +e
"$BIN" no-such >/tmp/lidawake-usage.out 2>/tmp/lidawake-usage.err
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q "usage:" /tmp/lidawake-usage.err

echo "status is stopped before start"
[[ "$("$BIN" status)" == "stopped" ]]

echo "off is safe when nothing is running"
"$BIN" off >/dev/null

echo "on holds an idle-sleep assertion"
"$BIN" on >/tmp/lidawake-on.log 2>&1 &
holder=$!
ready=0
for _ in $(seq 1 50); do
  if [[ "$("$BIN" status)" == "running $holder" ]] && grep -q "clamshell override on" /tmp/lidawake-on.log; then
    ready=1
    break
  fi
  sleep 0.1
done
[[ "$ready" -eq 1 ]]

asserted=0
for _ in $(seq 1 50); do
  if pmset -g assertions | grep -F 'named: "lidawake"' >/tmp/lidawake-assert.txt; then
    asserted=1
    break
  fi
  sleep 0.1
done
[[ "$asserted" -eq 1 ]]

echo "a second on is refused"
set +e
"$BIN" on >/tmp/lidawake-second.out 2>/tmp/lidawake-second.err
code=$?
set -e
[[ "$code" -eq 1 ]]
grep -q "already running" /tmp/lidawake-second.err

echo "off releases the assertion and the pid"
"$BIN" off >/tmp/lidawake-off.log
grep -q "normal lid sleep restored" /tmp/lidawake-on.log
[[ "$("$BIN" status)" == "stopped" ]]
if pmset -g assertions | grep -F 'named: "lidawake"' >/dev/null; then
  echo "assertion still held after off" >&2
  exit 1
fi

# The holder must be gone. kill -0 returns non-zero when it is.
if kill -0 "$holder" 2>/dev/null; then
  echo "holder pid $holder still alive" >&2
  exit 1
fi

echo "ok"
