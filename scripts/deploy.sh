#!/bin/bash
# Deploy Stealth Address Contracts to Starknet Sepolia
#
# Prerequisites:
# 1. Create account: sncast account create --name stealth-deployer
# 2. Fund account with Sepolia ETH from faucet
# 3. Deploy account: sncast account deploy --name stealth-deployer
#
# Usage: ./scripts/deploy.sh
# Optional: export REGISTRY_OWNER (defaults to ACCOUNT_ADDRESS)

set -e

# Configuration
ACCOUNT_NAME="${ACCOUNT_NAME:-stealth-deployer}"
RPC_URL="${RPC_URL:-https://api.zan.top/public/starknet-sepolia}"
NETWORK="sepolia"
ACCOUNT_ADDRESS="${ACCOUNT_ADDRESS:-}"
REGISTRY_OWNER="${REGISTRY_OWNER:-$ACCOUNT_ADDRESS}"

echo "[*] Deploying Stealth Address Contracts to Starknet $NETWORK"
echo "    Account: $ACCOUNT_NAME"
echo "    RPC: $RPC_URL"
echo "    Registry owner: ${REGISTRY_OWNER:-<unset>}"
echo ""

if [ -z "$REGISTRY_OWNER" ]; then
    echo "[X] REGISTRY_OWNER is required (or set ACCOUNT_ADDRESS)"
    exit 1
fi

# Build contracts
echo "[*] Building contracts..."
cd "$(dirname "$0")/.."
scarb build

# Contract artifacts
REGISTRY_CLASS="target/dev/starknet_stealth_addresses_StealthRegistry.contract_class.json"
ACCOUNT_CLASS="target/dev/starknet_stealth_addresses_StealthAccount.contract_class.json"
FACTORY_CLASS="target/dev/starknet_stealth_addresses_StealthAccountFactory.contract_class.json"

# Step 1: Declare StealthRegistry
echo ""
echo "[*] Step 1/4: Declaring StealthRegistry..."
REGISTRY_DECLARE=$(sncast --account $ACCOUNT_NAME --url $RPC_URL \
    declare --contract-name StealthRegistry --fee-token strk 2>&1) || true

if echo "$REGISTRY_DECLARE" | grep -q "class_hash:"; then
    REGISTRY_CLASS_HASH=$(echo "$REGISTRY_DECLARE" | grep "class_hash:" | awk '{print $2}')
    echo "    [OK] Registry class hash: $REGISTRY_CLASS_HASH"
elif echo "$REGISTRY_DECLARE" | grep -q "already declared"; then
    REGISTRY_CLASS_HASH=$(echo "$REGISTRY_DECLARE" | grep -oE "0x[a-fA-F0-9]+")
    echo "    [i] Registry already declared: $REGISTRY_CLASS_HASH"
else
    echo "    [X] Failed to declare Registry"
    echo "$REGISTRY_DECLARE"
    exit 1
fi

# Step 2: Declare StealthAccount
echo ""
echo "[*] Step 2/4: Declaring StealthAccount..."
ACCOUNT_DECLARE=$(sncast --account $ACCOUNT_NAME --url $RPC_URL \
    declare --contract-name StealthAccount 2>&1) || true

if echo "$ACCOUNT_DECLARE" | grep -q "class_hash:"; then
    ACCOUNT_CLASS_HASH=$(echo "$ACCOUNT_DECLARE" | grep "class_hash:" | awk '{print $2}')
    echo "    [OK] Account class hash: $ACCOUNT_CLASS_HASH"
elif echo "$ACCOUNT_DECLARE" | grep -q "already declared"; then
    ACCOUNT_CLASS_HASH=$(echo "$ACCOUNT_DECLARE" | grep -oE "0x[a-fA-F0-9]+")
    echo "    [i] Account already declared: $ACCOUNT_CLASS_HASH"
else
    echo "    [X] Failed to declare Account"
    echo "$ACCOUNT_DECLARE"
    exit 1
fi

# Step 3: Declare StealthAccountFactory
echo ""
echo "[*] Step 3/4: Declaring StealthAccountFactory..."
FACTORY_DECLARE=$(sncast --account $ACCOUNT_NAME --url $RPC_URL \
    declare --contract-name StealthAccountFactory 2>&1) || true

if echo "$FACTORY_DECLARE" | grep -q "class_hash:"; then
    FACTORY_CLASS_HASH=$(echo "$FACTORY_DECLARE" | grep "class_hash:" | awk '{print $2}')
    echo "    [OK] Factory class hash: $FACTORY_CLASS_HASH"
elif echo "$FACTORY_DECLARE" | grep -q "already declared"; then
    FACTORY_CLASS_HASH=$(echo "$FACTORY_DECLARE" | grep -oE "0x[a-fA-F0-9]+")
    echo "    [i] Factory already declared: $FACTORY_CLASS_HASH"
else
    echo "    [X] Failed to declare Factory"
    echo "$FACTORY_DECLARE"
    exit 1
fi

# Step 4: Deploy contracts
echo ""
echo "[*] Step 4/4: Deploying contracts..."

# Deploy Registry (constructor arg: owner)
echo "    Deploying StealthRegistry..."
REGISTRY_DEPLOY=$(sncast --account $ACCOUNT_NAME --url $RPC_URL \
    deploy --class-hash $REGISTRY_CLASS_HASH \
    --constructor-calldata $REGISTRY_OWNER 2>&1)

if echo "$REGISTRY_DEPLOY" | grep -q "contract_address:"; then
    REGISTRY_ADDRESS=$(echo "$REGISTRY_DEPLOY" | grep "contract_address:" | awk '{print $2}')
    echo "    [OK] Registry deployed: $REGISTRY_ADDRESS"
else
    echo "    [X] Failed to deploy Registry"
    echo "$REGISTRY_DEPLOY"
    exit 1
fi

# Deploy Factory (constructor arg: account_class_hash)
echo "    Deploying StealthAccountFactory..."
FACTORY_DEPLOY=$(sncast --account $ACCOUNT_NAME --url $RPC_URL \
    deploy --class-hash $FACTORY_CLASS_HASH \
    --constructor-calldata $ACCOUNT_CLASS_HASH 2>&1)

if echo "$FACTORY_DEPLOY" | grep -q "contract_address:"; then
    FACTORY_ADDRESS=$(echo "$FACTORY_DEPLOY" | grep "contract_address:" | awk '{print $2}')
    echo "    [OK] Factory deployed: $FACTORY_ADDRESS"
else
    echo "    [X] Failed to deploy Factory"
    echo "$FACTORY_DEPLOY"
    exit 1
fi

# Summary
echo ""
echo "==================================================================="
echo "                    DEPLOYMENT COMPLETE"
echo "==================================================================="
echo ""
echo "Network: Starknet $NETWORK"
echo ""
echo "Class Hashes:"
echo "  StealthRegistry:       $REGISTRY_CLASS_HASH"
echo "  StealthAccount:        $ACCOUNT_CLASS_HASH"
echo "  StealthAccountFactory: $FACTORY_CLASS_HASH"
echo ""
echo "Contract Addresses:"
echo "  StealthRegistry:       $REGISTRY_ADDRESS"
echo "  StealthAccountFactory: $FACTORY_ADDRESS"
echo ""
echo "Explorer Links:"
echo "  Registry: https://sepolia.starkscan.co/contract/$REGISTRY_ADDRESS"
echo "  Factory:  https://sepolia.starkscan.co/contract/$FACTORY_ADDRESS"
echo ""

# Save deployment info
DEPLOYMENT_FILE="deployments/$NETWORK.json"
mkdir -p deployments
cat > $DEPLOYMENT_FILE << EOF
{
  "network": "$NETWORK",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "classHashes": {
    "StealthRegistry": "$REGISTRY_CLASS_HASH",
    "StealthAccount": "$ACCOUNT_CLASS_HASH",
    "StealthAccountFactory": "$FACTORY_CLASS_HASH"
  },
  "contracts": {
    "StealthRegistry": "$REGISTRY_ADDRESS",
    "StealthAccountFactory": "$FACTORY_ADDRESS"
  }
}
EOF

echo "[*] Deployment info saved to: $DEPLOYMENT_FILE"
