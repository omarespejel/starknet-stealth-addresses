#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/devnet.log"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NVMRC_PATH="$REPO_ROOT/.nvmrc"

RPC_URL="${DEVNET_RPC_URL:-http://127.0.0.1:5050/rpc}"
ACCOUNT_ADDRESS="${DEVNET_ACCOUNT_ADDRESS:-}"
PRIVATE_KEY="${DEVNET_ACCOUNT_PRIVATE_KEY:-}"

cleanup() {
  "$SCRIPT_DIR/stop-devnet.sh" >/dev/null 2>&1 || true
}
trap cleanup EXIT

"$SCRIPT_DIR/start-devnet.sh"

if [ -z "$ACCOUNT_ADDRESS" ] || [ -z "$PRIVATE_KEY" ]; then
  echo "Waiting for devnet logs to extract account..."
  for _ in $(seq 1 30); do
    if [ -s "$LOG_FILE" ]; then
      break
    fi
    sleep 1
  done

  if [ ! -s "$LOG_FILE" ]; then
    echo "Devnet log is empty. Cannot extract account."
    exit 1
  fi

  ACCOUNT_LINE=""
  for _ in $(seq 1 30); do
    ACCOUNT_LINE="$(python3 - "$LOG_FILE" <<'PY' 2>/dev/null || true
import re
import sys
from pathlib import Path

if len(sys.argv) < 2:
    raise SystemExit(1)

log_path = Path(sys.argv[1])
text = log_path.read_text(errors="ignore")
lines = text.splitlines()

hex_re = re.compile(r'0x[0-9a-fA-F]+')

for i, line in enumerate(lines):
    if "Account address" in line:
        addr_match = hex_re.search(line)
        if not addr_match:
            continue
        addr = addr_match.group(0)
        for j in range(i + 1, min(i + 4, len(lines))):
            if "Private key" in lines[j]:
                key_match = hex_re.search(lines[j])
                if key_match:
                    print(addr, key_match.group(0))
                    raise SystemExit(0)

raise SystemExit(1)
PY
)"
    if [ -n "$ACCOUNT_LINE" ]; then
      read -r ACCOUNT_ADDRESS PRIVATE_KEY <<<"$ACCOUNT_LINE"
      break
    fi
    sleep 1
  done

  if [ -z "${ACCOUNT_ADDRESS:-}" ] || [ -z "${PRIVATE_KEY:-}" ]; then
    echo "Failed to extract predeployed account from devnet logs."
    echo "Open $LOG_FILE and set DEVNET_ACCOUNT_ADDRESS / DEVNET_ACCOUNT_PRIVATE_KEY."
    exit 1
  fi
fi

export DEVNET_RPC_URL="$RPC_URL"
export DEVNET_ACCOUNT_ADDRESS="$ACCOUNT_ADDRESS"
export DEVNET_ACCOUNT_PRIVATE_KEY="$PRIVATE_KEY"

echo "Using account: $DEVNET_ACCOUNT_ADDRESS"

nvm_use_if_available() {
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  if [ -s "$nvm_dir/nvm.sh" ]; then
    # shellcheck source=/dev/null
    . "$nvm_dir/nvm.sh"
    if [ -f "$NVMRC_PATH" ]; then
      nvm install >/dev/null
      nvm use >/dev/null
    else
      nvm install 22 >/dev/null
      nvm use 22 >/dev/null
    fi
  fi
}

nvm_use_if_available

npm install
npm run e2e
