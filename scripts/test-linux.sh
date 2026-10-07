#!/usr/bin/env bash
# Exercises the Linux command with a stand-in for systemd-inhibit.
# On a machine where logind grants the lock, also runs one real on/off.
# PATH and the pid file are exported inside subshells on purpose, so each
# invocation gets a clean environment without changing this script's own.
# shellcheck disable=SC2030,SC2031
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/scripts/lidawake"
REAL_PATH="$PATH"

work="$(mktemp -d "${TMPDIR:-/tmp}/lidawake-linux.XXXXXX")"
pidfile="$work/pid"
fake_log="$work/inhibit.log"
on_log="$work/on.log"

cleanup() {
  if [[ -x "$BIN" ]]; then
    LIDAWAKE_PID_FILE="$pidfile" "$BIN" off >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

cat >"$work/systemd-inhibit" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${LIDAWAKE_FAKE_LOG:?}"
while true; do
  sleep 1
done
EOF
cat >"$work/gnome-session-inhibit" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'gnome %s\n' "$*" >>"${LIDAWAKE_FAKE_LOG:?}"
while true; do
  sleep 1
done
EOF
chmod +x "$work/systemd-inhibit" "$work/gnome-session-inhibit" "$BIN"

run_bin() {
  (
    unset XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION
    export PATH="$work:$REAL_PATH"
    export LIDAWAKE_PID_FILE="$pidfile"
    export LIDAWAKE_FAKE_LOG="$fake_log"
    exec "$BIN" "$@"
  )
}

echo "usage rejects unknown commands"
set +e
run_bin no-such >"$work/usage.out" 2>"$work/usage.err"
code=$?
set -e
[[ "$code" -eq 2 ]]
grep -q "usage:" "$work/usage.err"

echo "status is stopped before start"
[[ "$(run_bin status)" == "stopped" ]]

echo "off is safe when nothing is running"
run_bin off >/dev/null

echo "on asks logind to ignore the lid and idle sleep"
: >"$fake_log"
(
  unset XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION
  export PATH="$work:$REAL_PATH"
  export LIDAWAKE_PID_FILE="$pidfile"
  export LIDAWAKE_FAKE_LOG="$fake_log"
  exec "$BIN" on
) >"$on_log" 2>&1 &
holder=$!
ready=0
for _ in $(seq 1 50); do
  if [[ "$(run_bin status)" == "running $holder" ]] && grep -q "lid override on" "$on_log"; then
    ready=1
    break
  fi
  sleep 0.1
done
[[ "$ready" -eq 1 ]]
logged=0
for _ in $(seq 1 50); do
  if grep -q -- "--what=handle-lid-switch:idle" "$fake_log"; then
    logged=1
    break
  fi
  sleep 0.1
done
[[ "$logged" -eq 1 ]]
grep -q -- "--who=lidawake" "$fake_log"
grep -q -- "--mode=block" "$fake_log"
if grep -q "gnome-session-inhibit" "$fake_log"; then
  echo "gnome inhibitor was used outside a GNOME session" >&2
  exit 1
fi

echo "a second on is refused"
set +e
run_bin on >"$work/second.out" 2>"$work/second.err"
code=$?
set -e
[[ "$code" -eq 1 ]]
grep -q "already running" "$work/second.err"

echo "off releases the lock"
run_bin off >"$work/off.log"
grep -q "normal lid sleep restored" "$on_log"
[[ "$(run_bin status)" == "stopped" ]]
if kill -0 "$holder" 2>/dev/null; then
  echo "holder pid $holder still alive" >&2
  exit 1
fi

echo "a GNOME session also inhibits gnome-session suspend and idle"
: >"$fake_log"
(
  unset XDG_SESSION_DESKTOP DESKTOP_SESSION
  export XDG_CURRENT_DESKTOP=GNOME
  export PATH="$work:$REAL_PATH"
  export LIDAWAKE_PID_FILE="$pidfile"
  export LIDAWAKE_FAKE_LOG="$fake_log"
  exec "$BIN" on
) >"$work/gnome-on.log" 2>&1 &
gnome_holder=$!
ready=0
for _ in $(seq 1 50); do
  if [[ "$(run_bin status)" == "running $gnome_holder" ]] && grep -q -- "--inhibit suspend" "$fake_log"; then
    ready=1
    break
  fi
  sleep 0.1
done
[[ "$ready" -eq 1 ]]
grep -q -- "--inhibit suspend" "$fake_log"
grep -q -- "--inhibit idle" "$fake_log"
run_bin off >/dev/null

if [[ "$(uname -s)" == "Linux" ]] && command -v systemd-inhibit >/dev/null 2>&1; then
  if PATH="$REAL_PATH" systemd-inhibit --what=handle-lid-switch:idle --who=lidawake-probe --why=probe --mode=block true >/dev/null 2>&1; then
    echo "live logind lock"
    : >"$fake_log"
    (
      unset XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION
      export PATH="$REAL_PATH"
      export LIDAWAKE_PID_FILE="$pidfile"
      exec "$BIN" on
    ) >"$work/live-on.log" 2>&1 &
    live=$!
    ready=0
    for _ in $(seq 1 50); do
      if [[ "$(PATH="$REAL_PATH" LIDAWAKE_PID_FILE="$pidfile" "$BIN" status)" == "running $live" ]]; then
        ready=1
        break
      fi
      sleep 0.1
    done
    [[ "$ready" -eq 1 ]]
    PATH="$REAL_PATH" systemd-inhibit --list | grep -F "lidawake" >/dev/null
    PATH="$REAL_PATH" LIDAWAKE_PID_FILE="$pidfile" "$BIN" off >/dev/null
    if PATH="$REAL_PATH" systemd-inhibit --list | grep -F "Keep the machine awake with the lid closed" >/dev/null; then
      echo "live lock still held after off" >&2
      exit 1
    fi
  else
    echo "logind did not grant a lid lock here; the stand-in tests already ran"
  fi
fi

echo "ok"
