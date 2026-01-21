import { describe, it, expect, vi } from 'vitest';
import fc from 'fast-check';
import { hash } from 'starknet';
import {
  computeStealthContractAddress,
  createMetaAddress,
  decodeMetaAddress,
  generateStealthAddress,
  getPublicKey,
  deriveStealthPrivateKey,
  deriveStealthPubkey,
  computeSharedSecret,
  computeViewTag,
  isPointOnCurve,
  normalizePrivateKey,
  verifyStealthAddress,
  checkViewTag,
} from '../src/stealth.js';
import { StealthScanner } from '../src/scanner.js';

const config = {
  registryAddress: '0x1',
  factoryAddress: '0x2',
  rpcUrl: 'http://localhost:9545',
  chainId: '0x534e5f5345504f4c4941', // SN_SEPOLIA
};

const CURVE_ORDER = BigInt(
  '0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f'
);

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

  it('accepts dual-key meta-address creation', () => {
    const meta = createMetaAddress(1n, 2n);
    expect(meta.schemeId).toBe(1);
    expect(meta.spendingKey.x).not.toBe(meta.viewingKey.x);
  });

  it('rejects scheme 1 without viewing key', () => {
    expect(() => decodeMetaAddress('0x1', '0x2', undefined, undefined, 1)).toThrow();
  });

  it('decodes dual-key meta-address', () => {
    const spending = getPublicKey(1n);
    const viewing = getPublicKey(2n);
    const meta = decodeMetaAddress(
      `0x${spending.x.toString(16)}`,
      `0x${spending.y.toString(16)}`,
      `0x${viewing.x.toString(16)}`,
      `0x${viewing.y.toString(16)}`,
      1
    );
    expect(meta.schemeId).toBe(1);
    expect(meta.viewingKey.x).toBe(viewing.x);
  });

  it('returns false on invalid ephemeral key for view tag', () => {
    const validPrivKey = 1n;
    const invalidPoint = { x: 0n, y: 1n };
    expect(checkViewTag(validPrivKey, invalidPoint, 0)).toBe(false);
  });

  it('returns null on invalid ephemeral key for verify', () => {
    const spendingPubkey = getPublicKey(1n);
    const invalidPoint = { x: 0n, y: 1n };
    const result = verifyStealthAddress(
      spendingPubkey,
      1n,
      invalidPoint,
      '0x1',
      config.factoryAddress,
      '0x1234'
    );
    expect(result).toBeNull();
  });

  it('stealth pubkey matches derived private key', () => {
    const spendingPrivKey = 1n;
    const viewingPrivKey = 2n;
    const meta = createMetaAddress(spendingPrivKey, viewingPrivKey);
    const result = generateStealthAddress(meta, config.factoryAddress, '0x1234');
    const derivedPriv = deriveStealthPrivateKey(spendingPrivKey, result.sharedSecret);
    const derivedPub = getPublicKey(derivedPriv);
    expect(derivedPub.x).toBe(result.stealthPubkey.x);
    expect(derivedPub.y).toBe(result.stealthPubkey.y);
  });
});

describe('SDK property tests', () => {
  const keyArb = fc.oneof(
    fc.constant(1n),
    fc.constant(CURVE_ORDER - 1n),
    fc.bigInt({ min: 1n, max: CURVE_ORDER - 1n })
  );

  it('ECDH is symmetric', () => {
    fc.assert(
      fc.property(keyArb, keyArb, (aRaw, bRaw) => {
        const a = normalizePrivateKey(aRaw);
        const b = normalizePrivateKey(bRaw);
        const A = getPublicKey(a);
        const B = getPublicKey(b);
        const s1 = computeSharedSecret(a, B);
        const s2 = computeSharedSecret(b, A);
        return s1.x === s2.x && s1.y === s2.y;
      }),
      { numRuns: 500 }
    );
  });

  it('derived pubkey matches derived private key', () => {
    fc.assert(
      fc.property(keyArb, keyArb, keyArb, (kRaw, vRaw, rRaw) => {
        const k = normalizePrivateKey(kRaw);
        const v = normalizePrivateKey(vRaw);
        const r = normalizePrivateKey(rRaw);
        const K = getPublicKey(k);
        const V = getPublicKey(v);
        const shared = computeSharedSecret(r, V);
        const P = deriveStealthPubkey(K, shared);
        const p = deriveStealthPrivateKey(k, shared);
        const P2 = getPublicKey(p);
        return P.x === P2.x && P.y === P2.y;
      }),
      { numRuns: 500 }
    );
  });

  it('view tag round-trip holds', () => {
    fc.assert(
      fc.property(keyArb, keyArb, (vRaw, rRaw) => {
        const v = normalizePrivateKey(vRaw);
        const r = normalizePrivateKey(rRaw);
        const R = getPublicKey(r);
        const shared = computeSharedSecret(r, getPublicKey(v));
        const tag = computeViewTag(shared);
        return checkViewTag(v, R, tag);
      }),
      { numRuns: 500 }
    );
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
