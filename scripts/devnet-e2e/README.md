## Devnet E2E (Local)

This script deploys the contracts to a local Starknet devnet, registers a meta-address, announces a payment, and scans via the SDK using a real RPC.

### 1) Start Devnet

Use the official Rust devnet:
https://github.com/0xSpaceShard/starknet-devnet

Option A (manual):
- Start devnet in a terminal and copy a predeployed account address + private key.

Option B (helper):
```
make devnet-up
```
Then open `scripts/devnet-e2e/devnet.log` and copy a predeployed account address + private key.

### 2) Build Contracts

```
scarb build
```

### 3) Run E2E (automated)

```
make devnet-e2e
```

This will:
- start devnet (if not running)
- read a predeployed account from `devnet.log`
- run the full deploy → announce → scan flow

### 4) Stop Devnet

```
make devnet-down
```
