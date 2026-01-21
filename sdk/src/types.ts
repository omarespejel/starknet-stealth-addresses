/**
 * Type Definitions for Starknet Stealth Addresses
 * 
 * Based on ERC-5564 adapted for Starknet's STARK curve
 */

import type { BigNumberish } from 'starknet';

/**
 * A point on the STARK curve (public key)
 */
export interface Point {
  x: bigint;
  y: bigint;
}

/**
 * Stealth Meta-Address
 * 
 * Contains the spending and viewing public keys that recipients publish
 * to receive stealth payments. Dual-key is supported on-chain.
 * 
 * For DKSAP:
 * - spendingKey: K = k*G (recipient's spending public key)
 * - viewingKey: V = v*G (viewing public key)
 */
export interface StealthMetaAddress {
  /** Spending public key (x, y) */
  spendingKey: Point;
  /** Viewing public key (x, y) */
  viewingKey: Point;
  /** Scheme ID (0 = single-key, 1 = dual-key) */
  schemeId: number;
}

/**
 * Ephemeral Key Pair
 * 
 * Generated fresh for each stealth payment
 */
export interface EphemeralKeyPair {
  /** Private key (random scalar) */
  privateKey: bigint;
  /** Public key R = r*G */
  publicKey: Point;
}

/**
 * Stealth Address Result
 * 
 * The output of generating a stealth address for a recipient
 */
export interface StealthAddressResult {
  /** The stealth contract address on Starknet */
  stealthAddress: string;
  /** The stealth public key (for account deployment) */
  stealthPubkey: Point;
  /** Ephemeral public key (to be announced) */
  ephemeralPubkey: Point;
  /** View tag for efficient scanning (1 byte) */
  viewTag: number;
  /** Shared secret (for deriving spending key) */
  sharedSecret: Point;
}

/**
 * Announcement
 * 
 * Published on-chain to notify recipients of stealth payments
 */
export interface Announcement {
  /** Scheme ID */
  schemeId: number;
  /** Ephemeral public key X */
  ephemeralPubkeyX: bigint;
  /** Ephemeral public key Y */
  ephemeralPubkeyY: bigint;
  /** View tag for efficient scanning */
  viewTag: number;
  /** The stealth address that received funds */
  stealthAddress: string;
  /** Optional metadata */
  metadata: bigint;
  /** Announcement index (if provided by event) */
  index?: number;
  /** Block number */
  blockNumber?: number;
  /** Transaction hash */
  txHash?: string;
}

/**
 * Scan Result
 * 
 * Result of scanning an announcement for ownership
 */
export interface ScanResult {
  /** Whether this announcement belongs to us */
  isOurs: boolean;
  /** The matched announcement (if isOurs) */
  announcement?: Announcement;
  /** The derived spending private key (if isOurs) */
  spendingKey?: bigint;
  /** The stealth address (if isOurs) */
  stealthAddress?: string;
}

/**
 * Configuration for the stealth SDK
 */
export interface StealthConfig {
  /** Registry contract address */
  registryAddress: string;
  /** Factory contract address */
  factoryAddress: string;
  /** RPC provider URL */
  rpcUrl: string;
  /** Chain ID */
  chainId: BigNumberish;
}

/**
 * Contract Address Computation Input
 */
export interface AddressComputationInput {
  /** Class hash of the StealthAccount contract */
  classHash: string;
  /** Deployer address (factory) */
  deployerAddress: string;
  /** Salt (unique per address) */
  salt: bigint;
  /** Constructor calldata [pubkey_x, pubkey_y] */
  constructorCalldata: [bigint, bigint];
}

/**
 * Withdrawal planning options
 */
export interface WithdrawalPlanOptions {
  /** Number of splits to create */
  splits?: number;
  /** Minimum delay in milliseconds */
  minDelayMs?: number;
  /** Maximum delay in milliseconds */
  maxDelayMs?: number;
}

/**
 * A planned withdrawal step
 */
export interface WithdrawalStep {
  amount: bigint;
  delayMs: number;
}
