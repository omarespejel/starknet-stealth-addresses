/**
 * Stealth Address Scanner
 * 
 * Efficiently scans blockchain announcements to find stealth payments.
 * Uses view tags for ~256x speedup in scanning.
 * 
 * ## Scanning Process
 * 
 * 1. Fetch announcements from registry contract
 * 2. Quick filter using view tags (1 byte comparison)
 * 3. Full verification for view tag matches
 * 4. Derive spending keys for confirmed matches
 */

import { RpcProvider, Contract, num } from 'starknet';
import type {
  Point,
  Announcement,
  ScanResult,
  StealthConfig,
} from './types.js';
import {
  checkViewTag,
  verifyStealthAddress,
  deriveStealthPrivateKey,
  computeSharedSecret,
} from './stealth.js';

// ============================================================================
// Scanner Class
// ============================================================================

/**
 * StealthScanner - Scans for incoming stealth payments
 * 
 * Usage:
 * ```typescript
 * const scanner = new StealthScanner(config);
 * const results = await scanner.scan(spendingPubkey, viewingPrivKey, fromBlock);
 * 
 * for (const result of results) {
 *   if (result.isOurs) {
 *     console.log(`Found payment at ${result.stealthAddress}`);
 *     console.log(`Spending key: ${result.spendingKey}`);
 *   }
 * }
 * ```
 */
export class StealthScanner {
  private provider: RpcProvider;
  private config: StealthConfig;
  private registryContract: Contract | null = null;
  private accountClassHash: string | null = null;
  
  // Scanning statistics
  public stats = {
    totalAnnouncements: 0,
    viewTagMatches: 0,
    confirmedMatches: 0,
    scanTimeMs: 0,
  };
  
  constructor(config: StealthConfig) {
    this.config = config;
    this.provider = new RpcProvider({ nodeUrl: config.rpcUrl });
  }
  
  /**
   * Initialize the scanner with contract ABIs
   */
  async initialize(registryAbi: any[], accountClassHash: string): Promise<void> {
    this.registryContract = new Contract(
      registryAbi,
      this.config.registryAddress,
      this.provider
    );
    this.accountClassHash = accountClassHash;
  }
  
  /**
   * Scan for announcements belonging to us
   * 
   * @param spendingPubkey - Our spending public key
   * @param viewingPrivKey - Our viewing private key
   * @param spendingPrivKey - Our spending private key (for key derivation)
   * @param fromBlock - Start block for scanning (default: 0)
   * @param toBlock - End block for scanning (default: latest)
   * @returns Array of scan results
   */
  async scan(
    spendingPubkey: Point,
    viewingPrivKey: bigint,
    spendingPrivKey: bigint,
    fromBlock: number = 0,
    toBlock?: number
  ): Promise<ScanResult[]> {
    const startTime = Date.now();
    const results: ScanResult[] = [];
    
    // Reset stats
    this.stats = {
      totalAnnouncements: 0,
      viewTagMatches: 0,
      confirmedMatches: 0,
      scanTimeMs: 0,
    };
    
    // Fetch announcements
    const announcements = await this.fetchAnnouncements(fromBlock, toBlock);
    this.stats.totalAnnouncements = announcements.length;
    
    // Scan each announcement
    for (const announcement of announcements) {
      const result = await this.checkAnnouncement(
        announcement,
        spendingPubkey,
        viewingPrivKey,
        spendingPrivKey
      );
      
      if (result.isOurs) {
        results.push(result);
      }
    }
    
    this.stats.scanTimeMs = Date.now() - startTime;
    return results;
  }
  
  /**
   * Check a single announcement
   */
  async checkAnnouncement(
    announcement: Announcement,
    spendingPubkey: Point,
    viewingPrivKey: bigint,
    spendingPrivKey: bigint
  ): Promise<ScanResult> {
    const ephemeralPubkey: Point = {
      x: announcement.ephemeralPubkeyX,
      y: announcement.ephemeralPubkeyY,
    };
    
    // Step 1: Quick view tag check (fast path)
    let viewTagMatches = false;
    try {
      viewTagMatches = checkViewTag(
        viewingPrivKey,
        ephemeralPubkey,
        announcement.viewTag
      );
    } catch {
      // Invalid curve point or scalar, treat as not ours
      return { isOurs: false };
    }
    
    if (!viewTagMatches) {
      return { isOurs: false };
    }
    
    this.stats.viewTagMatches++;
    
    // Step 2: Full verification (only if view tag matches)
    if (!this.accountClassHash) {
      throw new Error('Scanner not initialized - call initialize() first');
    }
    
    let sharedSecret: Point | null = null;
    try {
      sharedSecret = verifyStealthAddress(
        spendingPubkey,
        viewingPrivKey,
        ephemeralPubkey,
        announcement.stealthAddress,
        this.config.factoryAddress,
        this.accountClassHash
      );
    } catch {
      return { isOurs: false };
    }
    
    if (!sharedSecret) {
      // False positive from view tag collision
      return { isOurs: false };
    }
    
    this.stats.confirmedMatches++;
    
    // Step 3: Derive spending key
    const derivedSpendingKey = deriveStealthPrivateKey(
      spendingPrivKey,
      sharedSecret
    );
    
    return {
      isOurs: true,
      announcement,
      spendingKey: derivedSpendingKey,
      stealthAddress: announcement.stealthAddress,
    };
  }
  
  /**
   * Fetch announcements from the registry contract
   */
  async fetchAnnouncements(
    fromBlock: number,
    toBlock?: number
  ): Promise<Announcement[]> {
    // In a real implementation, you would use events.getEvents()
    // This is a simplified version using direct event fetching
    
    if (!this.registryContract) {
      throw new Error('Scanner not initialized - call initialize() first');
    }
    
    const announcements: Announcement[] = [];
    
    try {
      let continuation: string | undefined = undefined;
      let page = 0;
      const maxPages = 1000;

      while (true) {
        const eventResponse = await this.provider.getEvents({
          address: this.config.registryAddress,
          from_block: { block_number: fromBlock },
          to_block: toBlock ? { block_number: toBlock } : 'latest',
          keys: [],
          chunk_size: 1000,
          continuation_token: continuation,
        });

        for (const event of eventResponse.events) {
          const announcement = this.parseAnnouncementEvent(event);
          if (announcement) {
            announcements.push(announcement);
          }
        }

        continuation = eventResponse.continuation_token;
        if (!continuation) {
          break;
        }

        page += 1;
        if (page > maxPages) {
          throw new Error('Event pagination limit exceeded');
        }
      }
    } catch (error) {
      console.error('Error fetching announcements:', error);
      throw error;
    }
    
    return announcements;
  }
  
  /**
   * Parse a raw event into an Announcement
   */
  private parseAnnouncementEvent(event: any): Announcement | null {
    try {
      // The event data structure depends on your contract's event definition
      // This is a generic parser - adjust based on actual event structure
      const data = event.data || [];
      const keys = event.keys || [];
      
      // Expected event structure (current):
      // keys[0] = event selector
      // keys[1] = scheme_id (indexed)
      // keys[2] = view_tag (indexed)
      // data[0] = ephemeral_pubkey_x
      // data[1] = ephemeral_pubkey_y
      // data[2] = stealth_address (felt)
      // data[3] = metadata
      // data[4] = index
      //
      // Legacy layout (fallback):
      // keys[0] = event selector
      // keys[1] = view_tag (indexed)
      // data[0] = scheme_id
      // data[1] = ephemeral_pubkey_x
      // data[2] = ephemeral_pubkey_y
      // data[3] = stealth_address
      // data[4] = metadata
      if (data.length < 5) {
        return null;
      }

      let schemeId = 0;
      let viewTag = 0;
      let ephemeralPubkeyX: bigint;
      let ephemeralPubkeyY: bigint;
      let stealthAddress: string;
      let metadata: bigint;
      let index: number | undefined;

      if (keys.length >= 3) {
        schemeId = Number(BigInt(keys[1]) % 256n);
        viewTag = Number(BigInt(keys[2]) % 256n);
        ephemeralPubkeyX = BigInt(data[0]);
        ephemeralPubkeyY = BigInt(data[1]);
        stealthAddress = num.toHex(BigInt(data[2]));
        metadata = BigInt(data[3] || 0);
        index = data[4] !== undefined ? Number(BigInt(data[4])) : undefined;
      } else if (keys.length >= 2) {
        schemeId = Number(data[0]);
        viewTag = Number(BigInt(keys[1]) % 256n);
        ephemeralPubkeyX = BigInt(data[1]);
        ephemeralPubkeyY = BigInt(data[2]);
        stealthAddress = num.toHex(BigInt(data[3]));
        metadata = BigInt(data[4] || 0);
      } else {
        return null;
      }

      return {
        schemeId,
        ephemeralPubkeyX,
        ephemeralPubkeyY,
        stealthAddress,
        viewTag,
        metadata,
        blockNumber: event.block_number,
        txHash: event.transaction_hash,
        index,
      };
    } catch (error) {
      console.error('Error parsing announcement event:', error);
      return null;
    }
  }
  
  /**
   * Get scanning statistics
   */
  getStats(): {
    totalAnnouncements: number;
    viewTagMatches: number;
    confirmedMatches: number;
    scanTimeMs: number;
    falsePositiveRate: number;
  } {
    const falsePositives = this.stats.viewTagMatches - this.stats.confirmedMatches;
    const falsePositiveRate = this.stats.viewTagMatches > 0
      ? falsePositives / this.stats.viewTagMatches
      : 0;
    
    return {
      ...this.stats,
      falsePositiveRate,
    };
  }
}

// ============================================================================
// Batch Scanner for Multiple Recipients
// ============================================================================

/**
 * BatchScanner - Scan for multiple recipients at once
 * 
 * Useful for services that manage multiple stealth addresses
 */
export class BatchScanner {
  private scanner: StealthScanner;
  
  constructor(config: StealthConfig) {
    this.scanner = new StealthScanner(config);
  }
  
  async initialize(registryAbi: any[], accountClassHash: string): Promise<void> {
    await this.scanner.initialize(registryAbi, accountClassHash);
  }
  
  /**
   * Scan for multiple recipients
   * 
   * @param recipients - Array of recipient key sets
   * @param fromBlock - Start block
   * @param toBlock - End block
   * @returns Map of recipient index to their scan results
   */
  async scanBatch(
    recipients: Array<{
      spendingPubkey: Point;
      viewingPrivKey: bigint;
      spendingPrivKey: bigint;
    }>,
    fromBlock: number = 0,
    toBlock?: number
  ): Promise<Map<number, ScanResult[]>> {
    const results = new Map<number, ScanResult[]>();
    
    // Initialize result arrays
    for (let i = 0; i < recipients.length; i++) {
      results.set(i, []);
    }
    
    // Fetch announcements once
    const announcements = await this.scanner.fetchAnnouncements(fromBlock, toBlock);
    
    // Check each announcement against all recipients
    for (const announcement of announcements) {
      for (let i = 0; i < recipients.length; i++) {
        const recipient = recipients[i];
        const result = await this.scanner.checkAnnouncement(
          announcement,
          recipient.spendingPubkey,
          recipient.viewingPrivKey,
          recipient.spendingPrivKey
        );
        
        if (result.isOurs) {
          results.get(i)!.push(result);
        }
      }
    }
    
    return results;
  }
}

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Estimate scanning time based on number of announcements
 * 
 * @param numAnnouncements - Number of announcements to scan
 * @returns Estimated time in milliseconds
 */
export function estimateScanTime(numAnnouncements: number): number {
  // Rough estimates based on typical performance:
  // - View tag check: ~0.1ms per announcement
  // - Full verification: ~1ms per view tag match
  // - Assuming 1/256 view tag match rate
  
  const viewTagCheckTime = numAnnouncements * 0.1;
  const fullVerificationTime = (numAnnouncements / 256) * 1;
  
  return viewTagCheckTime + fullVerificationTime;
}

/**
 * Calculate expected false positive rate
 * 
 * With 8-bit view tags, expected false positive rate is 1/256 ≈ 0.39%
 */
export function expectedFalsePositiveRate(): number {
  return 1 / 256;
}
