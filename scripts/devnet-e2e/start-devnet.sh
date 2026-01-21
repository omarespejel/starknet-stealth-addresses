#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/devnet.pid"
LOG_FILE="$SCRIPT_DIR/devnet.log"

if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE")"
  if ps -p "$PID" > /dev/null 2>&1; then
    echo "Devnet already running (PID $PID)."
    echo "Logs: $LOG_FILE"
    exit 0
  fi
fi

if ! command -v starknet-devnet >/dev/null 2>&1; then
  echo "starknet-devnet not found in PATH."
  echo "Install it and retry."
  exit 1
fi

echo "Starting starknet-devnet..."
nohup starknet-devnet > "$LOG_FILE" 2>&1 &
PID="$!"
echo "$PID" > "$PID_FILE"

echo "Devnet started (PID $PID)."
echo "RPC: http://127.0.0.1:5050/rpc"
echo "Logs: $LOG_FILE"
echo "Copy a predeployed account address + private key from the log."
