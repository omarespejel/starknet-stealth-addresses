#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/devnet.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "No devnet PID file found."
  exit 0
fi

PID="$(cat "$PID_FILE")"
if ps -p "$PID" > /dev/null 2>&1; then
  echo "Stopping devnet (PID $PID)..."
  kill "$PID"
else
  echo "Devnet PID $PID not running."
fi

rm -f "$PID_FILE"
