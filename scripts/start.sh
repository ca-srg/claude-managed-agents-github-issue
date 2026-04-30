#!/usr/bin/env bash
set -euo pipefail

# Persist runtime state (proper-lockfile, state.json, run-*.json) on the
# mounted Fly volume. STATE_FILE / RUN_LOCK in src/shared/constants.ts are
# resolved against process.cwd() (= /app), so we redirect that subdirectory
# to /data via a symlink instead of editing the constants.
mkdir -p /data/agent-state
if [ ! -L /app/.github-issue-agent ] \
  || [ "$(readlink /app/.github-issue-agent)" != "/data/agent-state" ]; then
  rm -rf /app/.github-issue-agent
  ln -sfn /data/agent-state /app/.github-issue-agent
fi

bun /app/index.ts &
APP_PID=$!
echo "[start.sh] bun server started (pid=$APP_PID)" >&2

shutdown() {
  echo "[start.sh] received signal, shutting down" >&2
  kill -TERM "$APP_PID" 2>/dev/null || true
  wait
}

trap shutdown TERM INT

set +e
wait "$APP_PID"
EXIT_CODE=$?
set -e

echo "[start.sh] child exited with code=$EXIT_CODE; tearing down" >&2
shutdown
exit "$EXIT_CODE"
