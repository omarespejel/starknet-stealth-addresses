# Privacy Analysis Report: Starknet Stealth Address Protocol

**Type**: Internal Security Analysis (NOT an external audit)  
**Date**: January 20, 2026  
**Scope**: Cairo smart contracts in `src/contracts/`  
**Methodology**: Code review + modern stealth address research (ERC-5564, Umbra study, BaseSAP)

---

## Executive Summary

The Starknet Stealth Address Protocol provides **recipient unlinkability** - the core goal of stealth addresses. However, several privacy gaps exist that could enable deanonymization through heuristics, similar to vulnerabilities found in Umbra (where 25-65% of transactions were deanonymized).

| Severity | Count | Description |
|----------|-------|-------------|
| **Critical** | 2 | Cryptographic validation gaps |
| **High** | 4 | Privacy leakage vectors |
| **Medium** | 5 | Design limitations |
| **Low/Info** | 6 | Best practice improvements |

---

## Critical Issues

### C-01: Public Key Validation Strategy

**Location**: `crypto/constants.cairo`, `stealth_account.cairo:221`

**Status**: RESOLVED - Using production-grade approach

**Description**: Public key validation now enforces **canonical Y** and **on-curve checks** at registration/deployment, with ECDSA validation at spend time as an additional safety layer.

**Security Model**:

| Layer | What | Protection |
|-------|------|------------|
| **Registration** | `is_valid_public_key()` | Rejects zero, non-canonical Y, and off-curve points |
| **ECDH (off-chain)** | SDK with `@scure/starknet` | Validates curve points + canonical Y |
| **Spending** | `check_ecdsa_signature` builtin | Rejects invalid keys |

**Rationale for Early Validation**:

1. **Registry hygiene**: Prevents invalid points from polluting the registry.
2. **ECDH safety**: Ensures off-chain ECDH never operates on invalid points.
3. **Defense in depth**: Keeps ECDSA validation as a backstop at spend time.

```cairo
// stealth_account.cairo:221 - Native ECDSA validates the key
check_ecdsa_signature(hash, pubkey_x, r, s)
```

**SDK Requirement**: The TypeScript SDK MUST use `@scure/starknet` for ECDH operations, which validates curve points:

```typescript
import { ProjectivePoint } from '@scure/starknet';
// Throws if point is not on curve
const point = ProjectivePoint.fromAffine({ x, y });
```

**References**: 
- OpenZeppelin Cairo Contracts (same approach)
- Starknet Core Library ECDSA implementation

---

### C-02: View Tag Leaks 8 Bits of Shared Secret

**Location**: `stealth_registry.cairo:94`, `crypto/view_tag.cairo`

**Description**: The view tag is the lowest 8 bits of `poseidon_hash(shared_secret)` and is published on-chain. While necessary for efficient scanning, this leaks information.

```cairo
pub fn compute_view_tag(shared_secret_x: felt252, shared_secret_y: felt252) -> u8 {
    let hash = poseidon_hash_span(array![shared_secret_x, shared_secret_y].span());
    let hash_u256: u256 = hash.into();
    let view_tag: u8 = (hash_u256 & 0xFF).try_into().unwrap();  // 8 bits leaked
    view_tag
}
```

**Impact**: 
- Reduces shared secret entropy by 8 bits for observers
- Enables filtering attacks where adversary can eliminate 255/256 of possible recipients
- Combined with other heuristics, significantly aids deanonymization

**Recommendation**: 
- Document this as an accepted trade-off (scanning efficiency vs. privacy)
- Consider optional "paranoid mode" without view tags
- Evaluate if 4-bit view tags provide sufficient scanning speedup with less leakage

---

## High Severity Issues

### H-01: Sender Address Exposed in Announcement Transaction

**Location**: `stealth_registry.cairo:201-228`

**Description**: The `announce()` function is called by the sender, exposing their address in the transaction.

```cairo
fn announce(
    ref self: ContractState,
    scheme_id: u8,
    ephemeral_pubkey_x: felt252,
    // ... sender's address visible as tx.sender
)
```

**Impact**: 
- Full sender deanonymization
- Enables graph analysis linking senders to recipients over time
- In Umbra study, this was a primary deanonymization vector

**Recommendation**:
1. Implement **relayer support**: Allow third-party relayers to submit announcements
2. Add meta-transaction support: Sender signs announcement, anyone can submit
3. Batch announcements: Multiple senders' announcements in single tx

---

### H-02: Transaction Amounts Fully Visible

**Location**: All contracts (fundamental design)

**Description**: The protocol does not hide transaction amounts. Any funds sent to stealth addresses are visible on-chain.

**Impact**:
- Distinctive amounts enable linking (e.g., "5000.123 STRK" is unique)
- Round amounts cluster and reveal patterns
- Amount correlation was used to deanonymize 40%+ of Umbra transactions

**Recommendation**:
1. Integrate with **Tongo** for amount hiding (mentioned in SNIP.md)
2. Recommend users split into common denominations
3. Add amount-padding utilities to SDK

---

### H-03: Timing Correlation Attack Vector

**Location**: Architectural (not contract-specific)

**Description**: No protection against timing analysis:
- Sender announces → Recipient scans → Recipient withdraws
- If withdrawal happens shortly after announcement, correlation is trivial

**Impact**:
- Timing patterns deanonymize recipients
- Umbra study: timing was a key heuristic for 25-65% deanonymization

**Recommendation**:
1. Document recommended withdrawal delays
2. Add optional timelock to stealth accounts
3. Encourage batched withdrawals
4. SDK should suggest random delays

---

### H-04: Meta-Address Registration Links Identity

**Location**: `stealth_registry.cairo:120-150`

**Description**: Registering a meta-address permanently links a known address to a stealth public key.

```cairo
fn register_stealth_meta_address(ref self: ContractState, ...) {
    let caller = get_caller_address();  // Links identity to meta-address
    // ...
    self.emit(MetaAddressRegistered { user: caller, ... });
}
```

**Impact**:
- Registration transaction reveals who owns which meta-address
- Once known, all future stealth payments to that meta-address are linkable to identity
- This is acceptable for the protocol design but should be clearly documented

**Recommendation**:
1. Document that registration creates a permanent public link
2. Suggest users register from a fresh/anonymous address
3. Consider allowing registration via signed message (meta-transactions)

---

## Medium Severity Issues

### M-01: Single-Key Scheme (No Viewing Key Separation)

**Location**: Architectural design

**Description**: The protocol uses a single spending key. There's no separate viewing key for delegated scanning.

**Impact**:
- Cannot delegate scanning to untrusted services without exposing spending capability
- If spending key is compromised, ALL privacy is lost (past and future)
- No watch-only wallet support

**Recommendation**:
1. Add dual-key support (DKSAP) in future version
2. Allow viewing key derivation for scanning delegation
3. Document current limitation in SNIP

---

### M-02: No Ephemeral Key Uniqueness Verification

**Location**: `stealth_registry.cairo:201-228`

**Description**: The `announce()` function doesn't verify ephemeral key uniqueness.

```cairo
fn announce(
    ref self: ContractState,
    scheme_id: u8,
    ephemeral_pubkey_x: felt252,  // No uniqueness check
    ephemeral_pubkey_y: felt252,
    // ...
)
```

**Impact**:
- Reusing ephemeral keys across payments to different recipients allows those recipients to compute each other's shared secrets
- Breaks unlinkability between payments

**Recommendation**:
1. Add ephemeral key uniqueness check (storage cost trade-off)
2. Or: Document as SDK responsibility with clear warnings
3. Or: Hash ephemeral key with sender address to namespace

---

### M-03: Announcement Index Enables Ordering Analysis

**Location**: `stealth_registry.cairo:100, 215-216`

**Description**: Each announcement has a sequential index.

```cairo
let index = self.announcement_count.read();
self.announcement_count.write(index + 1);
```

**Impact**:
- Enables precise temporal ordering of all stealth payments
- Combined with timing, aids correlation attacks
- Allows adversaries to track "first payment to new meta-address" patterns

**Recommendation**:
1. Remove index (use block number/tx hash for ordering)
2. Or batch announcements to reduce granularity
3. Document as accepted trade-off for indexing efficiency

---

### M-04: Salt Predictability in Address Computation

**Location**: `stealth_account_factory.cairo:94, 135-162`

**Description**: Salt is user-provided with no guidance on generation.

**Impact**:
- Predictable salts could enable pre-computation attacks
- Same (pubkey, salt) always produces same address - collision possible if salt reused

**Recommendation**:
1. Document salt generation best practices in SNIP
2. SDK should derive salt from ephemeral key: `salt = hash(ephemeral_private_key)`
3. Consider enforcing salt = hash(ephemeral_pubkey) in contract

---

### M-05: Factory Deployment Event Leaks Additional Metadata

**Location**: `stealth_account_factory.cairo:53-61`

**Description**: Deployment emits detailed event:

```cairo
struct StealthAccountDeployed {
    #[key]
    stealth_address: ContractAddress,
    pubkey_x: felt252,      // Stealth public key exposed
    salt: felt252,          // Salt exposed
    deployer: ContractAddress,  // Sender exposed
}
```

**Impact**:
- Links deployer to stealth address
- Exposes full stealth public key (not just address)
- Enables correlation between factory events and registry announcements

**Recommendation**:
1. Minimize event data: only emit stealth_address
2. Remove deployer from event (already linkable via tx.sender anyway)
3. Consider not emitting pubkey_x

---

## Low Severity / Informational

### L-01: No Protection Against Front-Running

**Description**: Announcements can be front-run. An attacker seeing a pending announcement could:
- Deploy a competing stealth account at the same address (if they can predict it)
- Analyze pending announcements before confirmation

**Recommendation**: Document atomic deploy+announce pattern in SNIP.

---

### L-02: Hardcoded Scheme ID

**Location**: `stealth_registry.cairo:137`

**Description**: `scheme_id` is hardcoded to 0.

```cairo
let meta_address = StealthMetaAddress {
    scheme_id: 0, // STARK curve ECDH - hardcoded
    // ...
};
```

**Recommendation**: Allow scheme_id as parameter for future-proofing.

---

### L-03: No Class Hash Update Mechanism

**Location**: `stealth_account_factory.cairo`

**Description**: `ClassHashUpdated` event exists but no update function.

**Recommendation**: Either remove the event or implement governance-controlled updates.

---

### L-04: Error Message in `__execute__` is Misleading

**Location**: `stealth_account.cairo:135-136`

```cairo
let result = call_contract_syscall(to, selector, calldata)
    .expect(Errors::DEPLOYMENT_FAILED);  // Should be CALL_FAILED
```

**Recommendation**: Change to `Errors::CALL_FAILED`.

---

### L-05: No Nonce Management in StealthAccount

**Description**: Account relies on protocol-level nonce. No internal nonce tracking for replay protection in edge cases.

**Recommendation**: Document reliance on protocol nonce. Consider adding internal nonce for meta-transactions.

---

### L-06: Constants Not Validated Against STARK Curve Specification

**Location**: `crypto/constants.cairo`

**Recommendation**: Add comments with references to official STARK curve specification. Consider compile-time validation.

---

## Comparison with Umbra Deanonymization Study

The [Umbra Anonymity Analysis (2023)](https://arxiv.org/abs/2308.01703) found 25-65% of stealth payments deanonymizable. Key heuristics used:

| Heuristic | Umbra Vulnerable? | This Protocol Vulnerable? |
|-----------|-------------------|---------------------------|
| Amount matching | Yes | **Yes** - amounts visible |
| Timing correlation | Yes | **Yes** - no delays |
| Sender linkage | Yes | **Yes** - sender in tx |
| Withdrawal patterns | Yes | **Yes** - no guidance |
| Gas price fingerprinting | Yes | Partially - Starknet fees different |
| Ephemeral key reuse | Rare | Possible - no enforcement |

**Assessment**: This protocol is similarly vulnerable to the heuristics that broke Umbra's privacy.

---

## Recommendations Summary

### Immediate (Before SNIP Submission)

1. ~~**Public key validation** [C-01]~~ - RESOLVED: Using production-grade approach (ECDSA builtin + SDK validation)
2. ~~**Document privacy limitations** clearly in SNIP [All issues]~~ - DONE
3. ~~**Fix error message** in stealth_account.cairo [L-04]~~ - FIXED

### Short-Term (v1.1)

4. **Implement relayer support** for announcements [H-01]
5. **Add salt derivation guidance** to SNIP and SDK [M-04]
6. **Minimize factory event data** [M-05]

### Medium-Term (v2.0)

7. **Integrate with Tongo** for amount privacy [H-02]
8. **Add dual-key support** (viewing key separation) [M-01]
9. **Implement timelocks** or delay recommendations [H-03]

### Long-Term

10. **Consider post-quantum** schemes (lattice-based) for future-proofing
11. **Build relayer network** for sender privacy
12. **Implement note-based model** with nullifiers for stronger guarantees

---

## Conclusion

The protocol correctly implements the core stealth address primitive and provides **recipient unlinkability** against casual observers. However, it inherits the same vulnerabilities found in production systems like Umbra:

- **Amounts are visible** → Easy correlation
- **Sender is exposed** → Full sender deanonymization  
- **Timing is unprotected** → Correlation attacks
- **No viewing key separation** → All-or-nothing privacy

For a production-grade privacy system, integration with **Tongo** (amount hiding) and **relayer infrastructure** (sender hiding) is essential. The current implementation is suitable as a foundation but should not be marketed as providing "strong privacy" without these additions.

**Risk Rating**: **MEDIUM-HIGH** for privacy guarantees

The protocol is **cryptographically sound** for its stated goal (recipient unlinkability) but **practically vulnerable** to the same deanonymization techniques that compromised Umbra.

---

## References

1. [Anonymity Analysis of Umbra Stealth Address Scheme](https://arxiv.org/abs/2308.01703) - 2023
2. [BaseSAP: Modular Stealth Address Protocol](https://arxiv.org/abs/2306.14272) - 2023
3. [ERC-5564: Stealth Addresses](https://eips.ethereum.org/EIPS/eip-5564)
4. [HE-DKSAP: Homomorphic Encryption for Stealth Addresses](https://arxiv.org/abs/2312.10698) - 2023
5. [SNIP-10: Privacy-Preserving Transactions on Starknet](https://community.starknet.io/t/snip-10/)
6. [Invalid Curve Attacks on ECDH](https://safecurves.cr.yp.to/)
