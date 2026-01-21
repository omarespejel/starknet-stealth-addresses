import { describe, it, expect, vi } from 'vitest';
import { hash } from 'starknet';
import {
  computeStealthContractAddress,
  createMetaAddress,
  decodeMetaAddress,
  generateStealthAddress,
  getPublicKey,
  computeSharedSecret,
  isPointOnCurve,
  verifyStealthAddress,
} from '../src/stealth.js';
import { StealthScanner } from '../src/scanner.js';

const config = {
  registryAddress: '0x1',
  factoryAddress: '0x2',
  rpcUrl: 'http://localhost:9545',
  chainId: '0x534e5f5345504f4c4941', // SN_SEPOLIA
};

describe('SDK address computation', () => {
  it('matches Starknet calculateContractAddressFromHash', () => {
    const input = {
      classHash: '0x1234',
      deployerAddress: '0x5678',
      salt: 42n,
      constructorCalldata: [1n, 2n] as [bigint, bigint],
    };

    const expected = hash.calculateContractAddressFromHash(
      input.salt,
      input.classHash,
      input.constructorCalldata,
      input.deployerAddress
    );

    const actual = computeStealthContractAddress(input);
    expect(actual.toLowerCase()).toBe(expected.toLowerCase());
  });
});

describe('SDK curve validation', () => {
  it('accepts valid curve points', () => {
    const pubkey = getPublicKey(1n);
    expect(isPointOnCurve(pubkey)).toBe(true);
  });

  it('rejects invalid points in computeSharedSecret', () => {
    expect(() => computeSharedSecret(1n, { x: 0n, y: 1n })).toThrow();
  });

  it('rejects dual-key meta-address creation', () => {
    expect(() => createMetaAddress(1n, 2n)).toThrow();
  });

  it('rejects non-zero scheme id in decodeMetaAddress', () => {
    expect(() => decodeMetaAddress('0x1', '0x2', undefined, undefined, 1)).toThrow();
  });
});

describe('SDK stealth address generation', () => {
  it('generates stealth address for supported scheme', () => {
    const meta = createMetaAddress(1n);
    const result = generateStealthAddress(meta, config.factoryAddress, '0x1234');
    expect(result.stealthAddress).toMatch(/^0x/i);
  });
});

describe('SDK event parsing', () => {
  it('parses Announcement event (current layout)', () => {
    const scanner: any = new StealthScanner(config);
    const event = {
      keys: ['0xselector', '0x0', '0x2a'],
      data: ['0x11', '0x22', '0x33', '0x44', '0x5'],
      block_number: 123,
      transaction_hash: '0xabc',
    };

    const parsed = scanner.parseAnnouncementEvent(event);
    expect(parsed.schemeId).toBe(0);
    expect(parsed.viewTag).toBe(0x2a);
    expect(parsed.ephemeralPubkeyX).toBe(0x11n);
    expect(parsed.ephemeralPubkeyY).toBe(0x22n);
    expect(parsed.stealthAddress).toBe('0x33');
    expect(parsed.metadata).toBe(0x44n);
    expect(parsed.index).toBe(5);
  });

  it('parses event and verifies stealth address', () => {
    const spendingPrivKey = 1n;
    const spendingPubkey = getPublicKey(spendingPrivKey);
    const meta = createMetaAddress(spendingPrivKey);

    const result = generateStealthAddress(meta, config.factoryAddress, '0x1234');
    const scanner: any = new StealthScanner(config);

    const event = {
      keys: ['0xselector', '0x0', `0x${result.viewTag.toString(16)}`],
      data: [
        `0x${result.ephemeralPubkey.x.toString(16)}`,
        `0x${result.ephemeralPubkey.y.toString(16)}`,
        result.stealthAddress,
        '0x0',
        '0x1',
      ],
    };

    const parsed = scanner.parseAnnouncementEvent(event);
    const sharedSecret = verifyStealthAddress(
      spendingPubkey,
      spendingPrivKey,
      { x: parsed.ephemeralPubkeyX, y: parsed.ephemeralPubkeyY },
      parsed.stealthAddress,
      config.factoryAddress,
      '0x1234'
    );

    expect(sharedSecret).not.toBeNull();
  });

  it('event parsing fuzz does not throw', () => {
    const scanner: any = new StealthScanner(config);

    function randomHex(): string {
      const n = Math.floor(Math.random() * Number.MAX_SAFE_INTEGER);
      return `0x${n.toString(16)}`;
    }

    for (let i = 0; i < 500; i++) {
      const keysLen = Math.floor(Math.random() * 4);
      const dataLen = Math.floor(Math.random() * 6);
      const keys = Array.from({ length: keysLen }, randomHex);
      const data = Array.from({ length: dataLen }, randomHex);

      expect(() => scanner.parseAnnouncementEvent({ keys, data })).not.toThrow();
    }
  });
});

describe('SDK pagination', () => {
  it('fetches all pages using continuation_token', async () => {
    const scanner: any = new StealthScanner(config);
    scanner.registryContract = {};

    const page1 = {
      events: [
        {
          keys: ['0xselector', '0x0', '0x01'],
          data: ['0x11', '0x22', '0x33', '0x44', '0x1'],
        },
      ],
      continuation_token: 'token-1',
    };
    const page2 = {
      events: [
        {
          keys: ['0xselector', '0x0', '0x02'],
          data: ['0x55', '0x66', '0x77', '0x88', '0x2'],
        },
      ],
      continuation_token: undefined,
    };

    scanner.provider = {
      getEvents: vi.fn().mockResolvedValueOnce(page1).mockResolvedValueOnce(page2),
    };

    const results = await scanner.fetchAnnouncements(0);
    expect(results.length).toBe(2);
  });
});
