# Starknet Stealth Addresses

Privacy-preserving payments on Starknet using stealth addresses. Recipients can receive funds at unique, one-time addresses that cannot be linked to their public identity.

> **Live Demo**: [Try it on Sepolia](https://omarespejel.github.io/starknet-stealth-addresses/)

## Deployed Contracts (Sepolia)

| Contract | Address | Explorer |
|----------|---------|----------|
| **StealthRegistry** | `0x0638f00436e34e4d932b2f173eabcfb20e9173585ae5862bc1778fb645e0991c` | [View](https://sepolia.starkscan.co/contract/0x0638f00436e34e4d932b2f173eabcfb20e9173585ae5862bc1778fb645e0991c) |
| **StealthAccountFactory** | `0x06a715a0a2147db921bb25f4ed880cc4dba2a434851b8b32e6b1ca9ac31aa7cb` | [View](https://sepolia.starkscan.co/contract/0x06a715a0a2147db921bb25f4ed880cc4dba2a434851b8b32e6b1ca9ac31aa7cb) |
| **StealthAccount** (class) | `0xfe0c0abc68d8c9e9e5dd708e49d4a8547a16c1449c5f16af881c2c98e8bcdd` | - |

## Features

- **Recipient Unlinkability**: Each payment goes to a unique address
- **SNIP-6 Compatible**: Stealth accounts are full Starknet accounts
- **Efficient Scanning**: View tags provide ~256x speedup for recipients
- **Deterministic Addresses**: Senders can pre-compute addresses before deployment
- **Production-Grade Security**: Defense-in-depth validation using native Starknet ECDSA
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

Registries may enable a **per-caller minimum block gap** between announcements to reduce spam. The default is disabled to keep the registry permissionless.

### Known Limitations

This protocol provides **recipient unlinkability** but shares limitations with other stealth address implementations (ERC-5564, Umbra):

- Transaction amounts remain visible
- Sender addresses are exposed in announcements
- Timing correlation attacks are possible

See the [Security Analysis](./docs/PRIVACY_AUDIT.md) for detailed analysis and the [Tongo Integration](#privacy-stack-integration-with-tongo) section for achieving full privacy.

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
