---
snip: TBD
title: Stealth Address Protocol for Starknet
author: Omar Espejel <omar@starknet.org>
discussions-to: https://community.starknet.io/t/XXXXXX
status: Draft
type: Standards Track
category: Interface
created: 2026-01-19
requires: SNIP-5, SNIP-6
---

## Abstract

This SNIP defines a standard for stealth addresses on Starknet, enabling privacy-preserving payments where the recipient's address cannot be linked to their public identity. The protocol uses Elliptic Curve Diffie-Hellman (ECDH) key exchange on the STARK curve to generate one-time addresses that only the intended recipient can spend from.

## Prior Art & Inspiration

This specification draws from established stealth address research and implementations:

- **ERC-5564 (Ethereum)**: The primary inspiration for this SNIP. Defines stealth address mechanics for EVM chains, including the announcement pattern and view tags for efficient scanning. We adapt these concepts for Starknet's account abstraction model and STARK curve.

- **Dual-Key Stealth Address Protocol (DKSAP)**: Academic foundation for stealth addresses, originally proposed for Bitcoin. This SNIP supports dual-key mode with a single-key compatibility option.

- **Umbra Protocol**: Production deployment of ERC-5564 on Ethereum. Demonstrates viability of stealth addresses at scale and informs our UX considerations.

- **Monero**: Pioneered stealth addresses in production since 2014. View tags concept adapted from Monero's approach to efficient scanning.

### Starknet-Specific Adaptations

Unlike Ethereum implementations, this protocol:

1. **Leverages native account abstraction**: Stealth accounts are full SNIP-6 accounts, not just EOAs
2. **Uses STARK curve**: All cryptographic operations use Starknet's native curve
3. **Poseidon hashing**: Uses Starknet's native hash function for shared secret derivation
4. **Factory pattern**: Deterministic deployment via `deploy_syscall` for address pre-computation

## Motivation

Current Starknet transactions are fully transparent - sender, recipient, and amount are visible to all observers. While this transparency is valuable for auditability, it creates privacy concerns:

1. **Address Correlation**: Once an address is known to belong to a person, all their transactions become traceable
2. **Payment Linking**: Multiple payments to the same recipient reveal patterns
3. **Business Privacy**: Companies cannot receive payments without exposing their customer relationships

Stealth addresses solve recipient unlinkability by generating a fresh, unique address for each payment. The recipient can claim funds using their private key, but observers cannot determine which addresses belong to the same recipient.

### Why Not Just Create a New Account?

A common question is: "Why not just have Alice create a fresh account and share that address with Bob?"

**Scenario A: Alice Creates New Account (No Stealth Addresses)**

```
1. Alice creates Account A1
2. Alice tells Bob via email/chat: "Send to A1"
3. Bob sends to A1
```

Problems with this approach:

| Issue | Description |
|-------|-------------|
| **Communication link** | Anyone monitoring the communication channel knows Alice owns A1 |
| **Sender knowledge** | Bob (and anyone who compromises Bob) knows Alice owns A1 |
| **No reusability** | If Alice gives A1 to Carol too, both can see she received from the other |
| **Requires coordination** | Alice must be online to generate and share each new address |
| **Scaling** | Alice needs N addresses for N senders, each requiring secure communication |

**Scenario B: Stealth Addresses**

```
1. Alice publishes ONE meta-address to the registry (once)
2. Bob computes a unique stealth address S1 for Alice
3. Carol computes a DIFFERENT stealth address S2 for Alice
4. Alice scans blockchain, finds both payments with her private key
```

Benefits:

| Feature | New Account | Stealth Address |
|---------|-------------|-----------------|
| Alice needs to be online? | Yes, for each payment | No - publish once |
| Addresses reusable? | No (privacy leak) | One meta-address, unlimited stealth addresses |
| Payments linkable by observers? | Yes, if address reused | No, each address is unique |
| Sender can prove recipient? | Yes | No (only Alice can identify her payments) |
| Communication channel exposed? | Yes | No (meta-address is public) |

**The Key Insight**: Stealth addresses separate identity from receiving addresses. Alice's meta-address can be completely public (on her website, social media, etc.), but each payment she receives goes to a fresh address that only she can link to herself.

### Use Cases

- **Private donations**: Receive funds without revealing your main address
- **Payroll**: Pay employees without exposing all salaries on-chain
- **B2B payments**: Transact without revealing business relationships
- **Personal privacy**: Receive payments without creating a traceable payment history

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this
document are to be interpreted as described in RFC 2119.

### Overview

The protocol consists of three components:

1. **StealthRegistry**: Stores recipient meta-addresses and emits payment announcements
2. **StealthAccountFactory**: Deploys stealth accounts at deterministic addresses
3. **StealthAccount**: SNIP-6 compliant account controlled by derived stealth key

### Key Definitions

| Term | Definition |
|------|------------|
| **Meta-address** | A public key pair (K, V) that recipients publish to receive stealth payments |
| **Ephemeral key** | A one-time key pair (r, R) generated by sender for each payment |
| **Shared secret** | The ECDH shared point S = r*V = v*R |
| **Stealth public key** | P = K + hash(S)*G, the public key for the one-time address |
| **Stealth private key** | p = k + hash(S) mod n, derived by recipient to spend |
| **View tag** | First byte of hash(S), used for efficient scanning |

### Cryptographic Scheme

The protocol implements Dual-Key Stealth Address Protocol (DKSAP) on the STARK curve,
with optional single-key mode (viewing key = spending key).

#### Parameters

- **Curve**: STARK curve (y² = x³ + α*x + β over F_p)
- **Field prime (p)**: 0x800000000000011000000000000000000000000000000000000000000000001
- **Curve order (n)**: 0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f
- **Generator (G)**: Standard STARK curve generator point
- **Hash function**: Poseidon hash

#### Protocol Flow

**1. Recipient Setup**

Recipient generates spending and viewing key pairs:
```
k ← random ∈ [1, n-1]
K = k * G
v ← random ∈ [1, n-1]
V = v * G
```

Recipient publishes (K, V) as their meta-address via
`register_stealth_meta_address(K.x, K.y, V.x, V.y, scheme_id)`.
For single-key mode, set `V = K` and `scheme_id = 0`. For dual-key, use `scheme_id = 1`.

**2. Sender Generates Stealth Address**

Sender fetches recipient's meta-address (K, V), then:
```
r ← random ∈ [1, n-1]        // ephemeral private key
R = r * G                      // ephemeral public key
S = r * V                      // shared secret (ECDH)
h = poseidon(S.x, S.y) mod n   // hash of shared secret
P = K + h * G                  // stealth public key
view_tag = h mod 256           // for efficient scanning
```

Sender deploys stealth account with public key P, then announces:
```
announce(scheme_id, R.x, R.y, stealth_address, view_tag, metadata)
```

Senders MUST use the `scheme_id` from the recipient's meta-address when announcing.

**3. Recipient Scans and Recovers**

Recipient scans `Announcement` events. For each announcement with ephemeral key R:
```
S' = v * R                     // same shared secret
h' = poseidon(S'.x, S'.y) mod n
view_tag' = h' mod 256

if view_tag' == announced_view_tag:
    p = k + h' mod n           // stealth private key
    // Verify: p * G == P (optional)
    // Use p to control stealth account
```

### Contract Interfaces

#### StealthMetaAddress ABI

The meta-address ABI is a fixed field order:

```
StealthMetaAddress {
  scheme_id: u8,
  spending_pubkey_x: felt252,
  spending_pubkey_y: felt252,
  viewing_pubkey_x: felt252,
  viewing_pubkey_y: felt252
}
```

Serialization order (felt252 sequence):

```
[scheme_id, spending_pubkey_x, spending_pubkey_y, viewing_pubkey_x, viewing_pubkey_y]
```

Note: `u8` fields are encoded as felt252 values in the ABI.

#### IStealthRegistry

```cairo
#[starknet::interface]
trait IStealthRegistry<TContractState> {
    /// Register caller's stealth meta-address
    fn register_stealth_meta_address(
        ref self: TContractState,
        spending_pubkey_x: felt252,
        spending_pubkey_y: felt252,
        viewing_pubkey_x: felt252,
        viewing_pubkey_y: felt252,
        scheme_id: u8
    );

    /// Emit announcement for a stealth payment
    fn announce(
        ref self: TContractState,
        scheme_id: u8,
        ephemeral_pubkey_x: felt252,
        ephemeral_pubkey_y: felt252,
        stealth_address: ContractAddress,
        view_tag: u8,
        metadata: felt252
    );

    /// Get user's registered meta-address
    fn get_stealth_meta_address(
        self: @TContractState,
        user: ContractAddress
    ) -> StealthMetaAddress;

    /// Check if user has registered a meta-address
    fn has_meta_address(
        self: @TContractState,
        user: ContractAddress
    ) -> bool;
}
```

#### StealthRegistry Constructor

```
constructor(owner: ContractAddress)
```

- `owner` MUST be non-zero.
- The registry uses `owner` for optional admin controls (rate limiting, ownership transfer).

#### IStealthRegistryAdmin

```cairo
#[starknet::interface]
trait IStealthRegistryAdmin<TContractState> {
    /// Set minimum block gap between announcements (0 = disabled)
    fn set_min_announce_block_gap(ref self: TContractState, min_gap: u64);

    /// Get minimum block gap between announcements
    fn get_min_announce_block_gap(self: @TContractState) -> u64;

    /// Get registry owner
    fn get_owner(self: @TContractState) -> ContractAddress;

    /// Get pending owner (two-step transfer)
    fn get_pending_owner(self: @TContractState) -> ContractAddress;

    /// Begin ownership transfer (two-step)
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);

    /// Accept ownership transfer
    fn accept_ownership(ref self: TContractState);

    /// Cancel pending ownership transfer
    fn cancel_ownership_transfer(ref self: TContractState);
}
```

#### IStealthAccountFactory

```cairo
#[starknet::interface]
trait IStealthAccountFactory<TContractState> {
    /// Deploy a stealth account with given public key
    fn deploy_stealth_account(
        ref self: TContractState,
        stealth_pubkey_x: felt252,
        stealth_pubkey_y: felt252,
        salt: felt252
    ) -> ContractAddress;

    /// Compute stealth account address without deploying
    fn compute_stealth_address(
        self: @TContractState,
        stealth_pubkey_x: felt252,
        stealth_pubkey_y: felt252,
        salt: felt252
    ) -> ContractAddress;

    /// Get the account class hash used for deployment
    fn get_account_class_hash(self: @TContractState) -> ClassHash;
}
```

#### IStealthAccount

```cairo
#[starknet::interface]
trait IStealthAccount<TContractState> {
    /// Get the stealth public key controlling this account
    fn get_stealth_pubkey(self: @TContractState) -> (felt252, felt252);
}
```

The StealthAccount MUST also implement SNIP-6 (Standard Account Interface).

### Events

#### MetaAddressRegistered

Emitted when a user registers their stealth meta-address.

```cairo
#[derive(Drop, starknet::Event)]
struct MetaAddressRegistered {
    #[key]
    user: ContractAddress,
    scheme_id: u8,
    spending_pubkey_x: felt252,
    spending_pubkey_y: felt252,
    viewing_pubkey_x: felt252,
    viewing_pubkey_y: felt252,
}
```

#### Announcement

Emitted by sender to announce a stealth payment.

```cairo
#[derive(Drop, starknet::Event)]
struct Announcement {
    #[key]
    scheme_id: u8,
    #[key]
    view_tag: u8,
    ephemeral_pubkey_x: felt252,
    ephemeral_pubkey_y: felt252,
    stealth_address: ContractAddress,
    metadata: felt252,
    index: u64,
}
```

**Event layout for interoperability**:

- `keys`: `[selector, scheme_id, view_tag]`
- `data`: `[ephemeral_pubkey_x, ephemeral_pubkey_y, stealth_address, metadata, index]`

### Interoperability Notes

- Clients MUST treat `scheme_id` and `view_tag` as 8-bit values encoded as felts.
- Scanners SHOULD filter by `scheme_id` and `view_tag` before full ECDH.
- Recipients MUST reject non-canonical or off-curve public keys.

### Scheme Identifiers

| scheme_id | Description |
|-----------|-------------|
| 0 | STARK curve ECDH (single-key) |
| 1 | STARK curve ECDH (dual-key) |
| 2 | Reserved for secp256k1 schemes |
| 255 | Reserved for post-quantum schemes |

Contracts and SDKs MUST reject unknown `scheme_id` values.

Scheme IDs serve as versioning: any incompatible change in hashing, encoding,
or validation MUST use a new `scheme_id`.

### View Tags

View tags enable efficient scanning by allowing recipients to quickly filter announcements:

- **Without view tags**: Recipient must compute full ECDH for every announcement (~1ms each)
- **With view tags**: Recipient compares single byte first (~0.004ms), only does full ECDH on match

Expected false positive rate: 1/256 ≈ 0.39%

For a recipient scanning 10,000 announcements:
- Without view tags: ~10 seconds
- With view tags: ~0.04 seconds + ~39 full ECDH computations ≈ 0.08 seconds

### Address Computation

Stealth account addresses are computed using Starknet's standard contract address formula:

```
address = pedersen(
    pedersen(
        pedersen(
            pedersen(CONTRACT_ADDRESS_PREFIX, deployer),
            salt
        ),
        class_hash
    ),
    constructor_calldata_hash
) mod 2^251
```

Where:
- `CONTRACT_ADDRESS_PREFIX` = `0x535441524b4e45545f434f4e54524143545f41444452455353` ("STARKNET_CONTRACT_ADDRESS")
- `deployer` = factory contract address
- `salt` = user-provided salt (typically derived from ephemeral key)
- `class_hash` = StealthAccount class hash
- `constructor_calldata_hash` = `pedersen(pedersen(0, pubkey_x), pubkey_y)`

Senders SHOULD set `salt = poseidon(R.x, R.y)` for deterministic pre-computation.

### Test Vectors

All values are hex. `scheme_id` is an 8-bit value encoded as felt252.

**Vector A (single-key, scheme_id = 0)**:

- Spending priv key `k = 0x1`
- Viewing priv key `v = 0x1`
- Ephemeral priv key `r = 0x2`
- `K = (0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca,
        0x5668060aa49730b7be4801df46ec62de53ecd11abe43a32873000c36e8dc1f)`
- `V = K`
- `R = (0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5,
        0x10adb5cbff189082a3fe5d7a6752d8d18baa55778874e606c4a9d28569b93c0)`
- `S = r * V`
- `h = poseidon(S.x, S.y) mod n = 0x3a92647e1f06f120e786c2a58c7a5fe21a30aeb33d84e4dac94eea10550150c`
- `view_tag = h mod 256 = 0x0c`
- `P = (0x6f13d02826597fdcc7b05df3e77a5d0bdb7676e7166206218e96825f9f94531,
        0x31741467d1f817e49b90c7f9490fa61ff47ce12e2ae07f62535b5cc159923cc)`
- `p = k + h mod n = 0x3a92647e1f06f120e786c2a58c7a5fe21a30aeb33d84e4dac94eea10550150d`
- Example address computation:
  - `factory = 0x5678`
  - `class_hash = 0x1234`
  - `salt = poseidon(R.x, R.y) = 0x3a92647e1f06f120e786c2a58c7a5fe21a30aeb33d84e4dac94eea10550150c`
  - `address = 0x2e3de8ec295c883b011e3249e74c0bfb4011458ecaa945f8011e1abb75a2833`

**Vector B (dual-key, scheme_id = 1)**:

- Spending priv key `k = 0x1`
- Viewing priv key `v = 0x2`
- Ephemeral priv key `r = 0x3`
- `K = (0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca,
        0x5668060aa49730b7be4801df46ec62de53ecd11abe43a32873000c36e8dc1f)`
- `V = (0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5,
        0x10adb5cbff189082a3fe5d7a6752d8d18baa55778874e606c4a9d28569b93c0)`
- `R = (0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20,
        0x1e4c1453f76dc3d3d90bf6ab6e6e0306b0c4090cfe12caac1dd2047fd0f97b)`
- `h = 0x3ae520b1330d6c941ba044136e0b4ef63b4c8636234b354740b5f0ea2c184a6`
- `view_tag = 0xa6`
- `P = (0x2c8d43da90a22a11adb3ae45954994c13cd6c59bca77a10f3c061db367c710f,
        0x3b7177ca1e67d94cc23e0358187b30bab20b7044f772877c84a3ceccca23a6b)`
- `p = 0x3ae520b1330d6c941ba044136e0b4ef63b4c8636234b354740b5f0ea2c184a7`
- Example address computation:
  - `factory = 0x5678`
  - `class_hash = 0x1234`
- `salt = 0x3ae520b1330d6c941ba044136e0b4ef63b4c8636234b354740b5f0ea2c184a6`
  - `address = 0x31436de7715354e07f55e134d358d2dbd719e8c68effc2e336691dd264777`

## Rationale

### Single Key vs Dual Key

This specification supports both single-key and dual-key schemes:
- Single-key mode (`scheme_id = 0`) sets `V = K` for simplicity.
- Dual-key mode (`scheme_id = 1`) separates viewing from spending to support
  delegated scanning and watch-only wallets.

### Poseidon Hash

Poseidon is chosen over Pedersen for hashing the shared secret because:
1. It's the standard hash for Starknet operations
2. Better performance for the specific use case
3. Consistent with Cairo ecosystem conventions

### Factory Pattern

The factory pattern is used instead of direct deployment because:
1. Enables pre-computation of stealth addresses before funding
2. Provides consistent deployment behavior
3. Simplifies sender's workflow

### SNIP-6 Compliance

StealthAccount implements SNIP-6 to ensure compatibility with existing Starknet infrastructure (wallets, SDKs, explorers).

## Backwards Compatibility

This SNIP introduces new contracts and does not modify existing protocol behavior. Existing accounts and contracts are unaffected.

Wallets implementing stealth address support should:
1. Display stealth payments separately from regular transactions
2. Allow users to export stealth private keys
3. Implement efficient scanning with view tag filtering

## Security Considerations

### Audits

- **Nethermind AuditAgent (2026-01-21)**: See `audits/README.md` and `audits/raw/audit_agent_report_1_d530a46b-4d72-43b4-b64b-0db3bffb285c.pdf`.

### Private Key Security

- **Spending key (k)**: MUST be kept secret. Exposure allows spending from all stealth addresses
- **Stealth key (p)**: Derived per-payment. Exposure only affects one stealth account
- **Ephemeral key (r)**: Generated fresh per payment. No long-term security impact

### Shared Secret Uniqueness

Each payment MUST use a fresh ephemeral key (r). Reusing r across payments to different recipients would allow those recipients to compute each other's shared secrets.

### View Tag Privacy

View tags reveal 8 bits of information about the shared secret. This is acceptable because:
1. Observers cannot determine which view tags correspond to which recipient
2. The full shared secret remains computationally infeasible to derive

### Timing Attacks

Implementations SHOULD use constant-time operations for:
- Private key generation
- ECDH computation
- Hash comparisons (view tag matching)

### Front-Running

The `announce` function does not require the stealth account to exist. Senders should:
1. Deploy the stealth account first
2. Then call announce
3. Or use multicall to do both atomically

### Public Key Validation

Public key validation uses a defense-in-depth approach:

**On-chain (contracts)**:
- Reject zero coordinates (point at infinity)
- Rely on `check_ecdsa_signature` builtin for full validation at spend time

**Off-chain (SDK)**:
- MUST use audited EC libraries (e.g., `@scure/starknet`) for ECDH
- These libraries validate that points lie on the STARK curve

This approach is used by OpenZeppelin Cairo contracts and relies on Starknet's native, audited ECDSA implementation rather than custom curve checks.

Implementations MAY optionally enable full on-curve checks during registration/announcement at the cost of higher gas.

### X-Only Signature Binding

Starknet ECDSA verification binds only to the **public key X coordinate**. This protocol stores both `(x, y)` on-chain and derives the stealth account address from `(x, y)`, but signature validation uses `x` only. Implementations MUST:

- Treat `y` as part of address derivation (not signature binding).
- Validate public keys off-chain (SDK) to avoid invalid-curve inputs.
- Avoid assuming the signature uniquely binds `(x, y)`.

### Announcement Rate Limiting (Optional)

To mitigate announcement spam/DoS, registries MAY implement **per-caller rate limits** (e.g., minimum block gap between announcements). This is optional and should be configurable (default disabled) to preserve open access; an owner can raise the gap up to a capped maximum, and changes apply only to new announcements.

### Immutability

StealthRegistry and StealthAccountFactory are intentionally immutable; if a critical issue is discovered, a new deployment and migration are required.

### Paymasters and Amount Privacy (Tongo)

Stealth addresses provide **recipient unlinkability**, but stronger privacy requires **amount privacy** and **fee unlinkability**. Implementations SHOULD consider:

- **Tongo** (or similar) for amount hiding so deposits/withdrawals are not linkable by value. Tongo is a confidential payments protocol on Starknet (see [tongo.cash](https://www.tongo.cash/)).
- **Paymasters** to sponsor fees or accept non‑native fee payments, reducing links between the payer and the stealth recipient (availability depends on paymaster infrastructure).

Starknet’s **native account abstraction** (all accounts are contracts) makes paymaster-style flows cleaner than ERC‑4337 on Ethereum, which relies on an `EntryPoint` contract and bundlers. Solana’s fee‑payer model allows sponsored fees but does not offer programmable account‑level validation in the same way.

### Known Privacy Limitations

Based on research from the [Umbra Anonymity Study](https://arxiv.org/abs/2308.01703), stealth addresses alone do NOT provide complete privacy. The following information remains visible:

| Data | Visibility | Mitigation |
|------|------------|------------|
| **Transaction amounts** | Fully visible | Integrate with amount‑hiding protocols (e.g., Tongo) |
| **Sender address** | Visible in announce tx | Use relayers |
| **Timing** | Block timestamps visible | Recommend withdrawal delays |
| **View tag** | 8 bits of shared secret | Accepted trade-off |
| **Announcement spam** | Permissionless announce can be spammed | Documented trade-off; indexers should expect noise |

### Deanonymization Heuristics

Adversaries may use the following techniques to correlate stealth payments:

1. **Amount matching**: Unique amounts link sender to recipient
2. **Timing correlation**: Quick withdrawals after announcements
3. **Behavioral patterns**: Consistent gas usage, interaction patterns
4. **Graph analysis**: Linking withdrawal destinations

**Recommendation**: For strong privacy, combine stealth addresses with:
- Amount hiding (Tongo)
- Relayers for announcement submission
- Randomized withdrawal timing
- Fresh addresses for withdrawals

## Limitations

This protocol provides recipient unlinkability but shares the same limitations as other stealth address implementations (ERC-5564, Umbra):

- **Transaction amounts remain visible**: Observers can see how much is sent to each stealth address
- **Sender addresses are exposed in announcements**: The sender's address is visible in the `announce` transaction
- **Timing correlation attacks are possible**: If recipients withdraw funds shortly after receiving, observers can correlate deposits and withdrawals
- **Announcements can be spammed**: `announce` is permissionless; rate limits are per-caller and sybil-bypassable

The [Umbra Anonymity Study](https://arxiv.org/abs/2308.01703) found that 25-65% of stealth payments could be deanonymized using behavioral heuristics, not cryptographic weaknesses. This protocol has the same attack surface.

For stronger privacy, integrate with amount-hiding protocols like [Tongo](https://www.tongo.cash/). See the "Future Work: Complete Privacy Stack" section for the integration roadmap.

## Reference Implementation

A complete reference implementation is available, including Cairo smart contracts and a TypeScript SDK.

**GitHub**: [https://github.com/omarespejel/starknet-stealth-addresses](https://github.com/omarespejel/starknet-stealth-addresses)

### Components

| Component | Location | Description |
|-----------|----------|-------------|
| Cairo Contracts | `src/contracts/` | Registry, Factory, Account |
| TypeScript SDK | `sdk/` | ECDH, scanning, address generation |
| Cairo Test Suite | `tests/` | 96 comprehensive tests |
| SDK Tests | `sdk/tests/` | 17 unit tests (vitest) |
| Interactive Demo | `demo/index.html` | Browser-based demo |

### TypeScript SDK

**npm**: [`@starknet-stealth/sdk`](https://www.npmjs.com/package/@starknet-stealth/sdk)

```bash
npm install @starknet-stealth/sdk
```

The SDK provides:
- ECDH key exchange on STARK curve
- Stealth address generation and scanning
- View tag computation for efficient scanning (~256x speedup)
- Contract address pre-computation
- Full TypeScript type definitions

### Test Coverage

| Category | Description |
|----------|-------------|
| Unit tests | Registry, Account, Factory, View Tag |
| Security tests | Zero rejection, isolation, boundaries |
| Integration tests | Cross-component flows |
| E2E tests | Complete user workflows |
| Fuzz tests | Random inputs (100+ runs each) |
| Invariant tests | Properties that must always hold |
| Gas benchmarks | Performance baselines |
| Stress tests | High-load scenarios (50+ users, 100+ ops) |

SDK tests are run with `cd sdk && npm test` (17 tests).

Run test categories:
```bash
snforge test --filter "unit_"      # Unit tests
snforge test --filter "security_"  # Security tests
snforge test --filter "fuzz_"      # Fuzz tests
snforge test --filter "stress_"    # Stress tests
snforge test --filter "gas_"       # Gas benchmarks
```

Key invariants tested:
- `compute_stealth_address` MUST match actual deployed address
- Registered users MUST be able to retrieve their meta-address
- Announcement count MUST always increase

### Development Status

| Milestone | Status |
|-----------|--------|
| SNIP specification | Complete |
| Cairo contracts | Complete |
| TypeScript SDK | Complete |
| Test suite (96 Cairo tests + 17 SDK tests) | Complete |
| Fuzz testing | Complete |
| Stress testing | Complete |
| Sepolia deployment | Complete |
| Internal security analysis | Complete |
| External audit | Pending |
| Mainnet deployment | Pending audit |


### Deployed Contracts (Sepolia Testnet)

| Contract | Address |
|----------|---------|
| StealthRegistry | `0x30e391e0fb3020ccdf4d087ef3b9ac43dae293fe77c96897ced8cc86a92c1f0` |
| StealthAccountFactory | `0x2175848fdac537a13a84aa16b5c1d7cdd4ea063cd7ed344266b99ccc4395085` |
| StealthAccount (class) | `0x30d37d3acccb722a61acb177f6a5c197adb26c6ef09cb9ba55d426ebf07a427` |

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

## Future Work: Complete Privacy Stack

### Current State

This SNIP provides **recipient unlinkability** - observers cannot determine which addresses belong to the same recipient. However, transaction amounts and sender addresses remain visible.

### Integration with Tongo (Amount Privacy)

[Tongo](https://www.tongo.cash/) is a confidential payments protocol for Starknet focused on **amount privacy** (encrypted balances + ZK proofs). It does not provide recipient unlinkability by itself; stealth addresses cover that. Sender privacy depends on pool usage and relayers.

| Privacy Property | Stealth Addresses | Tongo | Combined |
|------------------|-------------------|-------|----------|
| Recipient unlinkability | Yes | No | Yes |
| Amount hiding | No | Yes | Yes |
| Sender privacy | No | Pool/relayer-dependent | Pool/relayer-dependent |

**Note:** Combining stealth addresses with Tongo yields recipient + amount privacy. Sender privacy requires relayers or other anonymity infrastructure and is out of scope for this SNIP.

### Technical Integration Pattern

The following pattern enables recipient + amount privacy by combining stealth addresses with Tongo (sender privacy depends on relayers/pool usage):

```
┌──────────────────────────────────────────────────────────────────┐
│                AMOUNT-PRIVATE STEALTH FLOW                         │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  SETUP (one-time):                                                │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ Alice generates spending/viewing keypairs (k, K) and (v, V)  │ │
│  │ Alice calls registry.register_stealth_meta_address(K.x, K.y, V.x, V.y, scheme_id) │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  PAYMENT (per transaction):                                       │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ 1. Bob fetches Alice's meta-address (K, V) from registry     │ │
│  │                                                               │ │
│  │ 2. Bob generates ephemeral key r, computes:                   │ │
│  │    - R = r*G (ephemeral public key)                           │ │
│  │    - S = r*V (shared secret via ECDH)                         │ │
│  │    - P = K + hash(S)*G (stealth public key)                   │ │
│  │    - stealth_address = factory.compute_stealth_address(P)     │ │
│  │                                                               │ │
│  │ 3. Bob deposits funds into Tongo (confidential balance)        │ │
│  │    → Amount becomes hidden                                    │ │
│  │                                                               │ │
│  │ 4. Bob transfers FROM Tongo TO stealth_address                │ │
│  │    → Amount hidden (Tongo)                                    │ │
│  │    → Recipient unlinkable (stealth address)                   │ │
│  │    → Sender privacy depends on relayers/pool usage            │ │
│  │                                                               │ │
│  │ 5. Bob calls registry.announce(scheme_id, R, stealth_address, view_tag) │ │
│  │    → Can use relayer for sender privacy                       │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  RECEIVE (async):                                                 │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ 6. Alice scans Announcement events                            │ │
│  │    - Filter by view_tag for efficiency                        │ │
│  │    - Compute S' = v*R for matching announcements              │ │
│  │                                                               │ │
│  │ 7. Alice derives stealth private key: p = k + hash(S') mod n  │ │
│  │                                                               │ │
│  │ 8. Alice controls stealth_address with key p                  │ │
│  │    → Can interact with any Starknet protocol                  │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

### Privacy Guarantees with Integration

| Attack Vector | Protection | Mechanism |
|---------------|------------|-----------|
| Link recipient addresses | Stealth addresses | Each payment uses unique address |
| Observe amounts | Tongo | Confidential balances + ZK proofs |
| Trace sender | Relayers (optional) | Relayed announce/spend decouples sender |
| Timing analysis | Delays + batching | Timing obfuscation |
| Graph analysis | Privacy hygiene | Avoid consolidation; use fresh receivers |

### Roadmap

1. **Phase 1** (This SNIP): Stealth addresses for recipient privacy
2. **Phase 2**: Integration with Tongo for amount privacy
3. **Phase 3**: Relayer network for sender privacy
4. **Phase 4**: SNIP-42/43 integration for user-friendly addresses

## Related Work

- **ERC-5564**: Ethereum's stealth address standard (inspiration for this SNIP)
- **SNIP-6**: Starknet Standard Account Interface
- **SNIP-42**: Bech32m Address Encoding (future integration for user-friendly stealth addresses)
- **SNIP-43**: Unified Addresses and Viewing Keys (future integration for bundled receiver types)
- **Tongo**: Amount privacy protocol for Starknet ([tongo.cash](https://www.tongo.cash/))
- **Aztec Network**: Full privacy L2 on Ethereum (comparable end-state goal)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
