# Starknet Stealth Addresses

Privacy-preserving payments on Starknet using stealth addresses. Recipients can receive funds at unique, one-time addresses that cannot be linked to their public identity.

> **Live Demo**: [Try it on Sepolia](https://omarespejel.github.io/starknet-stealth-addresses/)

## Deployed Contracts (Sepolia)

| Contract | Address | Explorer |
|----------|---------|----------|
| **StealthRegistry** | `0x30e391e0fb3020ccdf4d087ef3b9ac43dae293fe77c96897ced8cc86a92c1f0` | [View](https://sepolia.starkscan.co/contract/0x30e391e0fb3020ccdf4d087ef3b9ac43dae293fe77c96897ced8cc86a92c1f0) |
| **StealthAccountFactory** | `0x2175848fdac537a13a84aa16b5c1d7cdd4ea063cd7ed344266b99ccc4395085` | [View](https://sepolia.starkscan.co/contract/0x2175848fdac537a13a84aa16b5c1d7cdd4ea063cd7ed344266b99ccc4395085) |
| **StealthAccount** (class) | `0x30d37d3acccb722a61acb177f6a5c197adb26c6ef09cb9ba55d426ebf07a427` | - |

### Sepolia Cost Report (2026-01-22)

Measured on Sepolia using `scripts/demo/costs.ts`. Full raw data in `deployments/sepolia_costs.json`.

| Step | Transaction | Fee (STRK) | L2 gas | L1 data gas |
|------|-------------|------------|--------|-------------|
| Register meta-address | [0x4369...b2e](https://sepolia.starkscan.co/tx/0x4369df0e44f5ae6c54c3ea02a354f4f0fa0c598927ba19a80627e92cfb05b2e) | 0.010747415167060608 | 1302400 | 672 |
| Deploy stealth account | [0x64ff...595](https://sepolia.starkscan.co/tx/0x64ff72456d2e41d3634765f37d5319874a8fc54868f0834ac30267d119a7595) | 0.012016945763760096 | 1452160 | 864 |
| Announce payment | [0x76c4...f88](https://sepolia.starkscan.co/tx/0x76c476c1233d219ed586de96109a65a5f470d51ed0f5a52d1b42537dabe0f88) | 0.009026894378373952 | 1117760 | 288 |
| Fund stealth address | [0x264f...b7a](https://sepolia.starkscan.co/tx/0x264f38f887ea924417653fa46b27420d98551871112701a24a6aa12e4a4ab7a) | 0.009111974835850144 | 1116800 | 224 |
| Spend from stealth account | [0x5cd1...c5f](https://sepolia.starkscan.co/tx/0x5cd1be542cbbe214c227469ea577bb206993a9aca85214e1a55403fcb3e7c5f) | 0.007832112901324608 | 971955 | 192 |

### Mainnet Cost Estimate (2026-01-22)

Estimated using Sepolia resource usage and mainnet gas prices from
`scripts/demo/estimate-mainnet.ts`. Full output in `deployments/mainnet_estimate.json`.

| Step | Estimated fee (STRK) |
|------|----------------------|
| Register meta-address | 0.010426505462009216 |
| Deploy stealth account | 0.011626672736868992 |
| Announce payment | 0.008945210912289664 |
| Fund stealth address | 0.008936835154003072 |
| Spend from stealth account | 0.007777727274859776 |
| **Total** | **0.04771295154003072** |

## Audits

- **Nethermind AuditAgent (2026-01-21)**: [Summary](./audits/README.md) · [PDF](./audits/raw/audit_agent_report_1_d530a46b-4d72-43b4-b64b-0db3bffb285c.pdf)

## Features

- **Recipient Unlinkability**: Each payment goes to a unique address
- **SNIP-6 Compatible**: Stealth accounts are full Starknet accounts
- **Efficient Scanning**: View tags provide ~256x speedup for recipients
- **Deterministic Addresses**: Senders can pre-compute addresses before deployment
- **Production-Grade Security**: Defense-in-depth validation using native Starknet ECDSA
- **Dual-Key Support**: Separate viewing keys for delegated scanning
- **87 Tests Passing**: Unit, security, integration, E2E, fuzz, stress, and gas benchmarks

## How It Works

1. **Recipient** publishes a meta-address (public key) to the registry
2. **Sender** fetches meta-address and generates a one-time stealth address using ECDH
3. **Sender** deploys stealth account and announces the payment
4. **Recipient** scans announcements, finds their payments, and derives spending keys

### Why Not Just Create a New Account?

A common question: "Can't Alice just create a fresh account and share it with Bob?"

**Without Stealth Addresses:**
```
Alice creates Account A1 → tells Bob "send to A1" → Bob sends
Problem: The email/chat links Alice to A1. If Bob is hacked, attacker knows Alice owns A1.
```

**With Stealth Addresses:**
```
Alice publishes meta-address once (can be public!)
Bob computes unique stealth address S1 → sends
Carol computes different stealth address S2 → sends
Only Alice can identify S1 and S2 as hers
```

| Comparison | New Account | Stealth Address |
|------------|-------------|-----------------|
| Alice online for each payment? | Yes | No |
| Communication channel exposed? | Yes | No (meta-address is public) |
| Payments linkable? | Yes | No |
| Can sender prove recipient? | Yes | No |

**Key insight**: Stealth addresses separate identity from receiving addresses. Your meta-address can be on Twitter, your website, anywhere - but each payment goes to a unique address only you can claim.

## Quick Start

### Run Demo Locally

```bash
# Clone the repo
git clone https://github.com/omarespejel/starknet-stealth-addresses
cd starknet-stealth-addresses

# Start demo server
cd demo && python3 -m http.server 8080

# Open http://localhost:8080
```

### Build & Test

```bash
# Build Cairo contracts
scarb build

# Run tests (56 tests)
snforge test

# Format code
scarb fmt
```

## Project Structure

```
starknet-stealth-addresses/
├── src/                              # Cairo contracts
│   ├── contracts/
│   │   ├── stealth_registry.cairo    # Meta-address storage + announcements
│   │   ├── stealth_account.cairo     # SNIP-6 compliant stealth account
│   │   └── stealth_account_factory.cairo # Deterministic deployment
│   ├── crypto/                       # View tags, constants
│   └── interfaces/                   # Contract interfaces
├── tests/                            # 56 comprehensive tests
├── sdk/                              # TypeScript SDK
├── demo/                             # Interactive demo frontend
├── scripts/                          # Deployment scripts
├── SNIP.md                           # SNIP specification
└── deployments/                      # Deployed contract addresses
```

## Security

### Production-Grade Validation

Public key validation uses the same approach as **OpenZeppelin Cairo contracts**:

| Layer | Protection | Implementation |
|-------|------------|----------------|
| **Registration** | Reject zero coordinates | `is_valid_public_key()` |
| **ECDH (SDK)** | Validate curve points | `@scure/starknet` library |
| **Spending** | Full key validation | Native `check_ecdsa_signature` builtin |

This defense-in-depth approach relies on Starknet's audited native ECDSA implementation rather than custom curve checks.
Implementations can optionally enable full on-curve checks during registration/announcement at a higher gas cost.

### X-Only Signature Binding

Starknet ECDSA verification binds only to the **public key X coordinate**. The stealth account address is derived from `(x, y)`, but signature validation uses `x` only. Implementations must treat `y` as address-bound metadata and rely on off-chain curve validation.

### Optional Announcement Rate Limiting

Registries may enable a **per-caller minimum block gap** between announcements to reduce spam. The default is disabled (gap = 0) to keep the registry permissionless; an owner can raise the gap up to a capped maximum, and changes apply only to new announcements.

### Known Limitations

This protocol provides **recipient unlinkability** but shares limitations with other stealth address implementations (ERC-5564, Umbra):

- Transaction amounts remain visible
- Sender addresses are exposed in announcements
- Timing correlation attacks are possible
- Announcements can be spammed (permissionless announce; per-caller limits are sybil-bypassable)

See the [Audit Summary](./audits/README.md) for detailed analysis and the [Tongo Integration](#privacy-stack-integration-with-tongo) section for achieving full privacy.

### Stronger Privacy: Paymasters + Tongo

Stealth addresses solve **recipient unlinkability**, but stronger privacy requires **amount hiding** and **fee unlinkability**:

- **Tongo** can add amount privacy so observers cannot link deposits/withdrawals by value.
- **Paymasters** can sponsor fees so the payer address is not linked to the recipient’s announce/spend flow.
- Starknet’s **native account abstraction** (accounts are contracts) makes paymaster-style flows cleaner than ERC‑4337 on Ethereum, while Solana’s fee‑payer model is flexible but does not offer programmable account validation in the same way. Today, paymasters are implemented via standards/services (SNIP‑9 / SNIP‑29), with protocol-level support on the V3 roadmap.

Together, stealth + Tongo + paymasters can move closer to Monero‑grade privacy in a smart‑contract setting.

### Security Assumptions

- Meta-addresses and announcements are public on-chain data.
- RPC providers can observe queries and timing; avoid leaking metadata.
- Private keys are generated and stored securely by the client.
- The SDK relies on `@scure/starknet` and Starknet standard cryptography.
- Registry and factory contracts are immutable; upgrades require redeploy/migration.

## Privacy Best Practices

- Register meta-addresses from a different address than your spending accounts.
- Avoid consolidating multiple stealth withdrawals into a single collector address.
- Use varied funding sources or relayers for gas to reduce linkage.
- Consider delayed withdrawals and amount splitting for timing correlation resistance.
- Never reuse ephemeral keys; the SDK generates fresh randomness per payment.

## Privacy Rationale (Concise)

Starknet’s pre‑computable addresses and native account abstraction reduce (but do not eliminate) common stealth‑address leakage:

- **Pre‑computation** lets senders fund a stealth address without deploying it, and recipients can deploy later to break timing correlation.
- **Atomic send + announce** is possible with multicall, which reduces timing‑based linkage but does not hide the sender.
- **Native account abstraction** reduces the “gas funding” leak by letting stealth accounts pay fees with received tokens or via paymasters.
- **Important caveat**: Ethereum ERC‑5564 implementations vary; not all flows require contract deployment, and transaction counts can differ.

## Documentation

- [SNIP Specification](./SNIP.md) - Full protocol specification
- [SDK Documentation](./sdk/README.md) - TypeScript SDK usage
- [Security Analysis](./docs/PRIVACY_AUDIT.md) - Internal security analysis and known limitations

## Local Devnet E2E

Run the full flow locally: deploy contracts, register a meta-address, announce, and scan via the SDK.

1. Start a local devnet using `starknet-devnet`:
   - https://github.com/0xSpaceShard/starknet-devnet
   - `make devnet-up` (helper)
2. Build contracts:
   - `scarb build`
3. Run the E2E script (automated):
   - `make devnet-e2e`
4. Stop devnet:
   - `make devnet-down`

## Privacy Stack: Integration with Tongo

Stealth addresses and [Tongo](https://github.com/tongonetwork/tongo) are **complementary** technologies that together create a complete privacy solution for Starknet.

### What Each Provides

| Component | Privacy Property | What's Hidden |
|-----------|------------------|---------------|
| **Stealth Addresses** | Recipient unlinkability | Who receives funds |
| **Tongo** | Amount privacy | How much is transferred |
| **Combined** | Full transaction privacy | Sender, recipient, and amount |

### Privacy Comparison

```
Without privacy:
  "Alice (0x123) sent 5000 STRK to Bob (0x456)"

With Stealth Addresses only:
  "Alice (0x123) sent 5000 STRK to [unlinkable address]"

With Tongo only:
  "Alice (0x123) sent [hidden amount] to Bob (0x456)"

With BOTH (Aztec-level privacy):
  "[anonymous] sent [hidden amount] to [unlinkable address]"
```

### Why Not Just Use Aztec?

| Feature | Aztec | Starknet + Stealth + Tongo |
|---------|-------|----------------------------|
| Privacy level | Full | Full (when combined) |
| Execution model | UTXO-like notes | Account abstraction |
| Composability | Aztec-only contracts | Any Starknet dApp |
| Adoption | Requires migration | Incremental opt-in |
| Wallet support | Custom wallets | Existing wallets (SNIP-6) |

### Roadmap to Full Privacy

1. **Phase 1** (Complete): Stealth addresses for recipient privacy
2. **Phase 2**: Integration with Tongo for amount privacy  
3. **Phase 3**: Relayer network for sender privacy
4. **Phase 4**: SNIP-42/43 for user-friendly addresses

## Roadmap to Production

### Current Status
- SNIP specification complete
- 56 tests passing (unit, security, integration, E2E)
- Deployed on Sepolia testnet

### Before Mainnet (Recommended)

**Option A: Professional Audit**
- Trail of Bits, OpenZeppelin, Consensys Diligence
- Cost: $10k-50k+

**Option B: Community Audit**
- Code4rena contest
- Sherlock contest

**Option C: Bug Bounty**
- Immunefi program

### After Mainnet
- Relayer network for sender privacy
- Tongo integration for amount privacy
- SNIP-42/43 integration for user-friendly addresses

## Related Work

- [ERC-5564](https://eips.ethereum.org/EIPS/eip-5564) - Ethereum's stealth address standard (inspiration)
- [SNIP-6](https://community.starknet.io/t/snip-6-standard-account-interface) - Starknet Standard Account Interface
- [Tongo](https://github.com/tongonetwork/tongo) - Amount privacy (complementary)
- [Aztec Network](https://aztec.network/) - Full privacy L2 (comparable end-state)

## Contact

- Telegram: [@espejelomar](https://t.me/espejelomar)
- X/Twitter: [@omarespejel](https://x.com/omarespejel)
- GitHub: [@omarespejel](https://github.com/omarespejel)
- Email: omar@starknet.org

## License

MIT
