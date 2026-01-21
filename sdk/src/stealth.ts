/**
 * Stealth Address Generation and Key Derivation
 * 
 * Implements the Dual-Key Stealth Address Protocol (DKSAP) for Starknet.
 * 
 * ## Protocol Overview
 * 
 * 1. Recipient publishes meta-address: (K, V) = (k*G, v*G)
 * 2. Sender generates ephemeral key: r, R = r*G
 * 3. Sender computes shared secret: S = r*V = r*v*G
 * 4. Sender derives stealth pubkey: P = K + hash(S)*G = (k + hash(S))*G
 * 5. Recipient scans using: S' = v*R = v*r*G (same shared secret)
 * 6. Recipient derives private key: p = k + hash(S) mod n
 * 
 * Uses STARK curve: y² = x³ + αx + β (mod p)
 */

import { poseidonHashMany } from '@scure/starknet';
import { hash, ec, num } from 'starknet';
import type {
  Point,
  StealthMetaAddress,
  EphemeralKeyPair,
  StealthAddressResult,
  AddressComputationInput,
} from './types.js';

// ============================================================================
// STARK Curve Constants
// ============================================================================

/** STARK curve order (number of points) */
const CURVE_ORDER = BigInt(
  '0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f'
);

/** STARK curve prime field modulus */
const FIELD_PRIME = BigInt(
  '0x800000000000011000000000000000000000000000000000000000000000001'
);
const FIELD_HALF = (FIELD_PRIME - 1n) / 2n;

/** STARK curve coefficient alpha */
const CURVE_ALPHA = 1n;

/** STARK curve coefficient beta */
const CURVE_BETA = BigInt(
  '0x6f21413efbe40de150e596d72f7a8c5609ad26c15c915c1f4cdfcb99cee9e89'
);

// ============================================================================
// Validation Helpers
// ============================================================================

function modField(value: bigint): bigint {
  const res = value % FIELD_PRIME;
  return res >= 0n ? res : res + FIELD_PRIME;
}

function normalizePoint(point: Point): Point {
  if (point.y > FIELD_HALF) {
    return { x: point.x, y: FIELD_PRIME - point.y };
  }
  return point;
}

export function isPointOnCurve(point: Point): boolean {
  if (point.x <= 0n || point.y <= 0n) {
    return false;
  }
  if (point.x >= FIELD_PRIME || point.y >= FIELD_PRIME) {
    return false;
  }
  if (point.y > FIELD_HALF) {
    return false;
  }

  const lhs = modField(point.y * point.y);
  const rhs = modField(point.x * point.x * point.x + CURVE_ALPHA * point.x + CURVE_BETA);
  return lhs === rhs;
}

function assertPointOnCurve(point: Point, context: string): void {
  if (!isPointOnCurve(point)) {
    throw new Error(`Invalid ${context} point (not on STARK curve)`);
  }
}

function assertValidScalar(scalar: bigint, context: string): void {
  if (scalar <= 0n || scalar >= CURVE_ORDER) {
    throw new Error(`Invalid ${context} scalar`);
  }
}

// ============================================================================
// Key Generation
// ============================================================================

/**
 * Generate a random private key (scalar on STARK curve)
 */
export function generatePrivateKey(): bigint {
  const randomBytes = crypto.getRandomValues(new Uint8Array(32));
  let key = BigInt('0x' + Buffer.from(randomBytes).toString('hex'));
  // Ensure key is in valid range [1, n-1]
  key = key % (CURVE_ORDER - 1n) + 1n;
  return normalizePrivateKey(key);
}

function getRawPublicKey(privateKey: bigint): Point {
  const privHex = num.toHex(privateKey);
  const pubKey = ec.starkCurve.getPublicKey(privHex, false);
  // pubKey is Uint8Array in uncompressed format: 04 | x | y
  const hex = Buffer.from(pubKey).toString('hex');
  const x = BigInt('0x' + hex.slice(2, 66)); // Skip '04' prefix
  const y = BigInt('0x' + hex.slice(66, 130));
  return { x, y };
}

/**
 * Normalize a private key so its public key is canonical.
 */
export function normalizePrivateKey(privateKey: bigint): bigint {
  assertValidScalar(privateKey, 'private key');
  const raw = getRawPublicKey(privateKey);
  if (raw.y > FIELD_HALF) {
    return CURVE_ORDER - privateKey;
  }
  return privateKey;
}

/**
 * Derive public key from private key
 * 
 * @param privateKey - Private key scalar
 * @returns Public key point (x, y)
 */
export function getPublicKey(privateKey: bigint): Point {
  assertValidScalar(privateKey, 'private key');
  const raw = getRawPublicKey(privateKey);
  return normalizePoint(raw);
}

/**
 * Generate an ephemeral key pair for a stealth payment
 */
export function generateEphemeralKeyPair(): EphemeralKeyPair {
  const privateKey = generatePrivateKey();
  const publicKey = getPublicKey(privateKey);
  return { privateKey, publicKey };
}

/**
 * Create a stealth meta-address from spending and viewing keys
 * 
 * @param spendingPrivKey - Spending private key
 * @param viewingPrivKey - Viewing private key (optional, defaults to spending key)
 * @returns Meta-address with canonical public keys
 *
 * Security: treat private keys as sensitive and avoid logging them.
 */
export function createMetaAddress(
  spendingPrivKey: bigint,
  viewingPrivKey?: bigint
): StealthMetaAddress {
  const normalizedSpendingPrivKey = normalizePrivateKey(spendingPrivKey);
  const normalizedViewingPrivKey = viewingPrivKey
    ? normalizePrivateKey(viewingPrivKey)
    : normalizedSpendingPrivKey;

  const spendingKey = getPublicKey(normalizedSpendingPrivKey);
  const viewingKey = getPublicKey(normalizedViewingPrivKey);

  return {
    spendingKey,
    viewingKey,
    schemeId:
      viewingPrivKey && normalizedViewingPrivKey !== normalizedSpendingPrivKey ? 1 : 0,
  };
}

// ============================================================================
// ECDH and Stealth Address Generation
// ============================================================================

/**
 * Perform ECDH to compute shared secret
 * 
 * S = scalar * Point
 * 
 * @param scalar - Private key scalar
 * @param point - Public key point
 * @returns Shared secret point
 */
export function computeSharedSecret(scalar: bigint, point: Point): Point {
  const normalizedScalar = normalizePrivateKey(scalar);
  assertPointOnCurve(point, 'ECDH public key');

  // Use starknet's ec.starkCurve for point multiplication
  const pointHex = ec.starkCurve.ProjectivePoint.fromAffine({
    x: point.x,
    y: point.y,
  });
  
  const result = pointHex.multiply(normalizedScalar);
  const affine = result.toAffine();
  
  return {
    x: affine.x,
    y: affine.y,
  };
}

/**
 * Hash shared secret to derive a scalar
 * 
 * Uses Poseidon hash (Starknet native)
 */
export function hashSharedSecret(sharedSecret: Point): bigint {
  const hashResult = poseidonHashMany([sharedSecret.x, sharedSecret.y]);
  // Reduce modulo curve order to get valid scalar
  const hashScalar = hashResult % CURVE_ORDER;
  assertValidScalar(hashScalar, 'shared secret hash');
  return hashScalar;
}

/**
 * Compute view tag from shared secret
 * 
 * The view tag is the first byte of the hash, used for efficient scanning.
 * This reduces scanning cost by ~256x.
 */
export function computeViewTag(sharedSecret: Point): number {
  const hashResult = poseidonHashMany([sharedSecret.x, sharedSecret.y]);
  return Number(hashResult % 256n);
}

/**
 * Add two points on the STARK curve
 */
function addPoints(p1: Point, p2: Point): Point {
  const point1 = ec.starkCurve.ProjectivePoint.fromAffine({
    x: p1.x,
    y: p1.y,
  });
  const point2 = ec.starkCurve.ProjectivePoint.fromAffine({
    x: p2.x,
    y: p2.y,
  });
  
  const result = point1.add(point2);
  const affine = result.toAffine();
  
  return {
    x: affine.x,
    y: affine.y,
  };
}

/**
 * Derive stealth public key from meta-address
 * 
 * P = K + hash(S)*G where S = r*V
 * 
 * @param spendingPubkey - Recipient's spending public key (K)
 * @param sharedSecret - Shared secret point (S = r*V)
 * @returns Stealth public key (P)
 */
export function deriveStealthPubkey(
  spendingPubkey: Point,
  sharedSecret: Point
): Point {
  // Compute hash(S) * G
  const hashScalar = hashSharedSecret(sharedSecret);
  const hashPoint = getRawPublicKey(hashScalar);
  
  // P = K + hash(S)*G
  return normalizePoint(addPoints(spendingPubkey, hashPoint));
}

/**
 * Generate a stealth address for a recipient
 * 
 * This is the main function senders use to create stealth payments.
 * 
 * @param metaAddress - Recipient's stealth meta-address
 * @param factoryAddress - Factory contract address
 * @param accountClassHash - StealthAccount class hash
 * @returns Stealth address result with all necessary data
 */
export function generateStealthAddress(
  metaAddress: StealthMetaAddress,
  factoryAddress: string,
  accountClassHash: string
): StealthAddressResult {
  if (metaAddress.schemeId !== 0 && metaAddress.schemeId !== 1) {
    throw new Error('Unsupported scheme_id: only 0 or 1 is supported');
  }
  assertPointOnCurve(metaAddress.spendingKey, 'spending public key');
  assertPointOnCurve(metaAddress.viewingKey, 'viewing public key');

  // 1. Generate fresh ephemeral key pair
  const ephemeral = generateEphemeralKeyPair();
  
  // 2. Compute shared secret: S = r * V
  const sharedSecret = computeSharedSecret(
    ephemeral.privateKey,
    metaAddress.viewingKey
  );
  
  // 3. Derive stealth public key: P = K + hash(S)*G
  const stealthPubkey = deriveStealthPubkey(
    metaAddress.spendingKey,
    sharedSecret
  );
  
  // 4. Compute view tag for efficient scanning
  const viewTag = computeViewTag(sharedSecret);
  
  // 5. Compute salt (derived from ephemeral key for determinism)
  const salt = poseidonHashMany([ephemeral.publicKey.x, ephemeral.publicKey.y]);
  
  // 6. Compute the contract address
  const stealthAddress = computeStealthContractAddress({
    classHash: accountClassHash,
    deployerAddress: factoryAddress,
    salt,
    constructorCalldata: [stealthPubkey.x, stealthPubkey.y],
  });
  
  return {
    stealthAddress,
    stealthPubkey,
    ephemeralPubkey: ephemeral.publicKey,
    viewTag,
    sharedSecret,
  };
}

// ============================================================================
// Contract Address Computation
// ============================================================================

/**
 * Compute Starknet contract address
 * 
 * Uses the formula:
 * address = compute_hash_on_elements([
 *   PREFIX, deployer, salt, class_hash, compute_hash_on_elements([arg1, arg2])
 * ])
 */
export function computeStealthContractAddress(
  input: AddressComputationInput
): string {
  const { classHash, deployerAddress, salt, constructorCalldata } = input;

  return hash.calculateContractAddressFromHash(
    salt,
    classHash,
    constructorCalldata,
    deployerAddress
  );
}

// ============================================================================
// Recipient Key Derivation
// ============================================================================

/**
 * Derive the spending private key for a stealth address
 * 
 * This is used by the recipient to spend from a stealth address.
 * 
 * p = k + hash(S) mod n
 * 
 * @param spendingPrivKey - Recipient's spending private key (k)
 * @param sharedSecret - Shared secret (S = v*R = r*V)
 * @returns The derived spending private key for this stealth address
 *
 * Security: keep derived keys in memory only as long as needed.
 */
export function deriveStealthPrivateKey(
  spendingPrivKey: bigint,
  sharedSecret: Point
): bigint {
  const normalizedSpendingPrivKey = normalizePrivateKey(spendingPrivKey);
  const hashScalar = hashSharedSecret(sharedSecret);
  const derived = (normalizedSpendingPrivKey + hashScalar) % CURVE_ORDER;
  return normalizePrivateKey(derived);
}

/**
 * Check if an announcement belongs to us using view tag
 * 
 * This is the fast path for scanning - check view tag first.
 * 
 * @param viewingPrivKey - Our viewing private key
 * @param ephemeralPubkey - The ephemeral public key from announcement
 * @param announcedViewTag - The view tag from announcement
 * @returns true if view tag matches (potential match, needs full verification)
 */
export function checkViewTag(
  viewingPrivKey: bigint,
  ephemeralPubkey: Point,
  announcedViewTag: number
): boolean {
  try {
    // Compute S' = v * R
    const sharedSecret = computeSharedSecret(viewingPrivKey, ephemeralPubkey);
    const computedViewTag = computeViewTag(sharedSecret);
    return computedViewTag === announcedViewTag;
  } catch {
    return false;
  }
}

/**
 * Full verification that an announcement belongs to us
 * 
 * After view tag matches, verify the full stealth address.
 * 
 * @param spendingPubkey - Our spending public key
 * @param viewingPrivKey - Our viewing private key  
 * @param ephemeralPubkey - The ephemeral public key from announcement
 * @param announcedStealthAddress - The stealth address from announcement
 * @param factoryAddress - Factory contract address
 * @param accountClassHash - StealthAccount class hash
 * @returns The shared secret if this is ours, null otherwise
 */
export function verifyStealthAddress(
  spendingPubkey: Point,
  viewingPrivKey: bigint,
  ephemeralPubkey: Point,
  announcedStealthAddress: string,
  factoryAddress: string,
  accountClassHash: string
): Point | null {
  try {
    // Compute S' = v * R
    const sharedSecret = computeSharedSecret(viewingPrivKey, ephemeralPubkey);

    // Derive expected stealth pubkey: P' = K + hash(S')*G
    const stealthPubkey = deriveStealthPubkey(spendingPubkey, sharedSecret);

    // Compute salt
    const salt = poseidonHashMany([ephemeralPubkey.x, ephemeralPubkey.y]);

    // Compute expected address
    const expectedAddress = computeStealthContractAddress({
      classHash: accountClassHash,
      deployerAddress: factoryAddress,
      salt,
      constructorCalldata: [stealthPubkey.x, stealthPubkey.y],
    });

    // Compare addresses (case-insensitive hex comparison)
    if (expectedAddress.toLowerCase() === announcedStealthAddress.toLowerCase()) {
      return sharedSecret;
    }
  } catch {
    return null;
  }

  return null;
}

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Encode a meta-address for publishing (e.g., to registry)
 */
export function encodeMetaAddress(metaAddress: StealthMetaAddress): {
  spendingX: string;
  spendingY: string;
  viewingX: string;
  viewingY: string;
  schemeId: number;
} {
  return {
    spendingX: num.toHex(metaAddress.spendingKey.x),
    spendingY: num.toHex(metaAddress.spendingKey.y),
    viewingX: num.toHex(metaAddress.viewingKey.x),
    viewingY: num.toHex(metaAddress.viewingKey.y),
    schemeId: metaAddress.schemeId,
  };
}

/**
 * Decode a meta-address from on-chain format
 */
export function decodeMetaAddress(
  spendingX: string,
  spendingY: string,
  viewingX?: string,
  viewingY?: string,
  schemeId: number = 0
): StealthMetaAddress {
  if (schemeId !== 0 && schemeId !== 1) {
    throw new Error('Unsupported scheme_id: only 0 or 1 is supported');
  }

  const spendingKey: Point = {
    x: BigInt(spendingX),
    y: BigInt(spendingY),
  };
  assertPointOnCurve(spendingKey, 'spending public key');

  if (schemeId === 0) {
    if (viewingX && viewingY) {
      const vx = BigInt(viewingX);
      const vy = BigInt(viewingY);
      if (vx !== spendingKey.x || vy !== spendingKey.y) {
        throw new Error('Viewing key must match spending key for scheme_id 0');
      }
    }
    return {
      spendingKey,
      viewingKey: spendingKey,
      schemeId: 0,
    };
  }

  if (!viewingX || !viewingY) {
    throw new Error('Viewing key required for scheme_id 1');
  }

  const viewingKey: Point = {
    x: BigInt(viewingX),
    y: BigInt(viewingY),
  };
  assertPointOnCurve(viewingKey, 'viewing public key');

  return {
    spendingKey,
    viewingKey,
    schemeId: 1,
  };
}
