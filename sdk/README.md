# Starknet Stealth Addresses SDK

TypeScript SDK for generating and scanning stealth addresses on Starknet.

> **Live on Sepolia Testnet** - Try it now!

## Deployed Contracts (Sepolia)

| Contract | Address |
|----------|---------|
| **StealthRegistry** | [`0x0638f00436e34e4d932b2f173eabcfb20e9173585ae5862bc1778fb645e0991c`](https://sepolia.starkscan.co/contract/0x0638f00436e34e4d932b2f173eabcfb20e9173585ae5862bc1778fb645e0991c) |
| **StealthAccountFactory** | [`0x06a715a0a2147db921bb25f4ed880cc4dba2a434851b8b32e6b1ca9ac31aa7cb`](https://sepolia.starkscan.co/contract/0x06a715a0a2147db921bb25f4ed880cc4dba2a434851b8b32e6b1ca9ac31aa7cb) |
| **StealthAccount** (class hash) | `0xfe0c0abc68d8c9e9e5dd708e49d4a8547a16c1449c5f16af881c2c98e8bcdd` |

```typescript
// Sepolia Configuration (updated 2026-01-20)
const SEPOLIA_CONFIG = {
  registryAddress: '0x0638f00436e34e4d932b2f173eabcfb20e9173585ae5862bc1778fb645e0991c',
  factoryAddress: '0x06a715a0a2147db921bb25f4ed880cc4dba2a434851b8b32e6b1ca9ac31aa7cb',
  accountClassHash: '0xfe0c0abc68d8c9e9e5dd708e49d4a8547a16c1449c5f16af881c2c98e8bcdd',
  rpcUrl: 'https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_10/YOUR_API_KEY',
  chainId: '0x534e5f5345504f4c4941',
};
```

## Features

- **ECDH Key Exchange**: Generate shared secrets using STARK curve
- **Stealth Address Generation**: Create one-time addresses for recipients
- **Efficient Scanning**: View tags provide ~256x speedup
- **Contract Address Computation**: Pre-compute addresses before deployment
- **Full TypeScript Support**: Complete type definitions
- **Production Ready**: 87 Cairo tests passing + SDK unit tests, deployed on Sepolia

## Installation

```bash
npm install @starknet-stealth/sdk
# or
pnpm add @starknet-stealth/sdk
```

## Quick Start

### Recipient: Create Meta-Address

```typescript
import {
  generatePrivateKey,
  getPublicKey,
  createMetaAddress,
  encodeMetaAddress,
} from '@starknet-stealth/sdk';

// Generate key pair
const spendingPrivKey = generatePrivateKey();

// Create meta-address (single-key scheme)
const metaAddress = createMetaAddress(spendingPrivKey);

// Encode for publishing to registry
const encoded = encodeMetaAddress(metaAddress);
console.log('Spending Key X:', encoded.spendingX);

// Publish to StealthRegistry contract
await registry.register_stealth_meta_address(
  encoded.spendingX,
  encoded.spendingY
);
```

### Sender: Generate Stealth Address

```typescript
import {
  decodeMetaAddress,
  generateStealthAddress,
} from '@starknet-stealth/sdk';

// Fetch recipient's meta-address from registry
const recipientMeta = await registry.get_stealth_meta_address(recipientAddress);

// Decode meta-address
const metaAddress = decodeMetaAddress(
  recipientMeta.spending_x,
  recipientMeta.spending_y
);

// Generate stealth address
const result = generateStealthAddress(
  metaAddress,
  FACTORY_ADDRESS,
  ACCOUNT_CLASS_HASH
);

console.log('Stealth Address:', result.stealthAddress);
console.log('View Tag:', result.viewTag);
console.log('Ephemeral Pubkey:', result.ephemeralPubkey);

// Deploy and send funds
await factory.deploy_stealth_account(
  result.stealthPubkey.x,
  result.stealthPubkey.y,
  salt
);

// Announce the payment
await registry.announce(
  0, // scheme_id
  result.ephemeralPubkey.x,
  result.ephemeralPubkey.y,
  result.stealthAddress,
  result.viewTag,
  0 // metadata
);
```

### Recipient: Scan for Payments

```typescript
import { StealthScanner } from '@starknet-stealth/sdk';

const scanner = new StealthScanner({
  registryAddress: REGISTRY_ADDRESS,
  factoryAddress: FACTORY_ADDRESS,
  rpcUrl: 'https://starknet-mainnet.public.blastapi.io',
  chainId: '0x534e5f4d41494e',
});

await scanner.initialize(REGISTRY_ABI, ACCOUNT_CLASS_HASH);

// Scan from block 0
const results = await scanner.scan(
  spendingPubkey,
  spendingPrivKey, // viewingPrivKey (single-key scheme)
  spendingPrivKey,
  0 // fromBlock
);

for (const result of results) {
  if (result.isOurs) {
    console.log('Found payment!');
    console.log('Stealth Address:', result.stealthAddress);
    console.log('Spending Key:', result.spendingKey);
    
    // Use spendingKey to control the stealth account
  }
}

// Get scanning statistics
const stats = scanner.getStats();
console.log(`Scanned ${stats.totalAnnouncements} announcements`);
console.log(`Found ${stats.confirmedMatches} payments`);
console.log(`Scan time: ${stats.scanTimeMs}ms`);
```

## Protocol Overview

This SDK currently supports the **single-key** variant of DKSAP (viewing key = spending key). Dual-key meta-addresses are not yet supported on-chain.

1. **Recipient publishes meta-address**: `K = k*G`
2. **Sender generates ephemeral key**: `r, R = r*G`
3. **Sender computes shared secret**: `S = r*K`
4. **Sender derives stealth pubkey**: `P = K + hash(S)*G`
5. **Recipient scans using**: `S' = k*R`
6. **Recipient derives private key**: `p = k + hash(S) mod n`

## View Tags

View tags are the first byte of `hash(S)`, used for efficient scanning:

- Before view tags: ~1ms per announcement (full ECDH + verification)
- After view tags: ~0.1ms per announcement (byte comparison)
- False positive rate: ~0.39% (1/256)

## API Reference

### Key Generation

```typescript
generatePrivateKey(): bigint
getPublicKey(privateKey: bigint): Point
generateEphemeralKeyPair(): EphemeralKeyPair
createMetaAddress(spendingPrivKey: bigint): StealthMetaAddress
```

### Stealth Address Generation

```typescript
generateStealthAddress(
  metaAddress: StealthMetaAddress,
  factoryAddress: string,
  accountClassHash: string
): StealthAddressResult

computeStealthContractAddress(input: AddressComputationInput): string
```

### Key Derivation

Note: For the single-key scheme, `viewingPrivKey` is the same as `spendingPrivKey`.

```typescript
deriveStealthPrivateKey(
  spendingPrivKey: bigint,
  sharedSecret: Point
): bigint

checkViewTag(
  viewingPrivKey: bigint,
  ephemeralPubkey: Point,
  announcedViewTag: number
): boolean

verifyStealthAddress(
  spendingPubkey: Point,
  viewingPrivKey: bigint,
  ephemeralPubkey: Point,
  announcedStealthAddress: string,
  factoryAddress: string,
  accountClassHash: string
): Point | null
```

### Scanning

```typescript
class StealthScanner {
  constructor(config: StealthConfig)
  initialize(registryAbi: any[], accountClassHash: string): Promise<void>
  scan(
    spendingPubkey: Point,
    viewingPrivKey: bigint,
    spendingPrivKey: bigint,
    fromBlock?: number,
    toBlock?: number
  ): Promise<ScanResult[]>
  getStats(): ScanStats
}
```

## Security Considerations

- **Private keys**: Never expose spending or viewing private keys
- **Shared secrets**: Derived deterministically, don't store unless needed
- **View tags**: Provide efficiency, not security (1/256 false positive rate)
- **RPC providers**: Use trusted providers to prevent address correlation

## Project Status

### What's Complete

| Component | Status | Details |
|-----------|--------|---------|
| **Cairo Contracts** | Complete | Registry, Factory, Account |
| **Test Suite** | 87 Cairo tests + SDK unit tests | Unit, Security, Fuzz, Stress, Gas |
| **TypeScript SDK** | Complete | ECDH, scanning, types |
| **Sepolia Deployment** | Live | Contracts deployed and verified |

### Project Structure

```
starknet-stealth-addresses/
├── src/                              # Cairo contracts
│   ├── contracts/
│   │   ├── stealth_registry.cairo    # Meta-address storage + announcements
│   │   ├── stealth_account.cairo     # SNIP-6 compliant stealth account
│   │   └── stealth_account_factory.cairo # Deterministic deployment
│   ├── crypto/                       # Cryptographic utilities
│   └── interfaces/                   # Contract interfaces
├── tests/                            # 56 comprehensive tests
├── sdk/                              # This TypeScript SDK
│   └── src/
│       ├── stealth.ts                # ECDH, address generation
│       ├── scanner.ts                # Announcement scanning
│       └── types.ts                  # Type definitions
└── deployments/
    └── sepolia.json                  # Deployed addresses
```

### Related SNIPs

This implementation is designed to complement:
- **SNIP-42**: Bech32m Address Encoding (shielded address format)
- **SNIP-43**: Unified Addresses & Viewing Keys

## Contributing

Contributions welcome! Please read our contributing guidelines and submit PRs.

## License

MIT
