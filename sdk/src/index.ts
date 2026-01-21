/**
 * Starknet Stealth Addresses SDK
 * 
 * A TypeScript SDK for generating and scanning stealth addresses on Starknet.
 * 
 * ## Quick Start
 * 
 * ```typescript
 * import {
 *   generatePrivateKey,
 *   createMetaAddress,
 *   generateStealthAddress,
 *   StealthScanner,
 * } from '@starknet-stealth/sdk';
 * 
 * // Recipient: Create meta-address
 * const spendingKey = generatePrivateKey();
 * const viewingKey = generatePrivateKey();
 * const metaAddress = createMetaAddress(spendingKey, viewingKey);
 * 
 * // Sender: Generate stealth address
 * const result = generateStealthAddress(
 *   metaAddress,
 *   FACTORY_ADDRESS,
 *   ACCOUNT_CLASS_HASH
 * );
 * 
 * // Recipient: Scan for payments
 * const scanner = new StealthScanner(config);
 * const payments = await scanner.scan(spendingPubkey, viewingKey, spendingKey);
 * ```
 * 
 * @packageDocumentation
 */

// Types
export type {
  Point,
  StealthMetaAddress,
  EphemeralKeyPair,
  StealthAddressResult,
  Announcement,
  ScanResult,
  StealthConfig,
  AddressComputationInput,
  WithdrawalPlanOptions,
  WithdrawalStep,
} from './types.js';

// Key generation and ECDH
export {
  generatePrivateKey,
  normalizePrivateKey,
  getPublicKey,
  generateEphemeralKeyPair,
  createMetaAddress,
  computeSharedSecret,
  hashSharedSecret,
  computeViewTag,
  isPointOnCurve,
  deriveStealthPubkey,
  generateStealthAddress,
  computeStealthContractAddress,
  deriveStealthPrivateKey,
  checkViewTag,
  verifyStealthAddress,
  encodeMetaAddress,
  decodeMetaAddress,
} from './stealth.js';

// Scanner
export {
  StealthScanner,
  BatchScanner,
  estimateScanTime,
  expectedFalsePositiveRate,
} from './scanner.js';

// Withdrawal helpers
export { planWithdrawals } from './withdrawal.js';

// Constants
export const SCHEME_ID = {
  SINGLE_KEY: 0,
  DUAL_KEY: 1,
} as const;

export const VIEW_TAG_BITS = 8;
export const VIEW_TAG_FALSE_POSITIVE_RATE = 1 / 256;
