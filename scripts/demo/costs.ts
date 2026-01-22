/// <reference types="node" />
import { Account, RpcProvider, Contract, CallData, num, ETransactionVersion } from 'starknet';
import { config as loadEnv } from 'dotenv';
import { poseidonHashMany } from '@scure/starknet';
import {
  createMetaAddress,
  generateStealthAddress,
  deriveStealthPrivateKey,
  normalizePrivateKey,
} from '../../sdk/src/index.js';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const envPath = path.join(__dirname, '../../.env');
loadEnv({ path: envPath });

const CONFIG = {
  rpcUrl: process.env.RPC_URL || 'https://api.zan.top/public/starknet-sepolia',
  accountAddress: process.env.ACCOUNT_ADDRESS || '',
  privateKey: process.env.PRIVATE_KEY || '',
  registryAddress: '0x30e391e0fb3020ccdf4d087ef3b9ac43dae293fe77c96897ced8cc86a92c1f0',
  factoryAddress: '0x2175848fdac537a13a84aa16b5c1d7cdd4ea063cd7ed344266b99ccc4395085',
  accountClassHash: '0x30d37d3acccb722a61acb177f6a5c197adb26c6ef09cb9ba55d426ebf07a427',
  strkTokenAddress:
    process.env.STRK_ADDRESS
    || '0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d',
};

const deploymentsPath = path.join(__dirname, '../../deployments/sepolia.json');
if (fs.existsSync(deploymentsPath)) {
  try {
    const deployments = JSON.parse(fs.readFileSync(deploymentsPath, 'utf-8'));
    CONFIG.registryAddress =
      deployments?.contracts?.StealthRegistry || CONFIG.registryAddress;
    CONFIG.factoryAddress =
      deployments?.contracts?.StealthAccountFactory || CONFIG.factoryAddress;
    CONFIG.accountClassHash =
      deployments?.classHashes?.StealthAccount || CONFIG.accountClassHash;
  } catch (err) {
    console.warn('[!] Failed to load deployments/sepolia.json:', (err as Error).message);
  }
}

const REGISTRY_ABI = [
  {
    type: 'function',
    name: 'register_stealth_meta_address',
    inputs: [
      { name: 'spending_pubkey_x', type: 'felt' },
      { name: 'spending_pubkey_y', type: 'felt' },
      { name: 'viewing_pubkey_x', type: 'felt' },
      { name: 'viewing_pubkey_y', type: 'felt' },
      { name: 'scheme_id', type: 'felt' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'update_stealth_meta_address',
    inputs: [
      { name: 'spending_pubkey_x', type: 'felt' },
      { name: 'spending_pubkey_y', type: 'felt' },
      { name: 'viewing_pubkey_x', type: 'felt' },
      { name: 'viewing_pubkey_y', type: 'felt' },
      { name: 'scheme_id', type: 'felt' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'has_meta_address',
    inputs: [{ name: 'user', type: 'felt' }],
    outputs: [{ name: 'result', type: 'felt' }],
  },
  {
    type: 'function',
    name: 'announce',
    inputs: [
      { name: 'scheme_id', type: 'felt' },
      { name: 'ephemeral_pubkey_x', type: 'felt' },
      { name: 'ephemeral_pubkey_y', type: 'felt' },
      { name: 'stealth_address', type: 'felt' },
      { name: 'view_tag', type: 'felt' },
      { name: 'metadata', type: 'felt' },
    ],
    outputs: [],
  },
];

const FACTORY_ABI = [
  {
    type: 'function',
    name: 'deploy_stealth_account',
    inputs: [
      { name: 'stealth_pubkey_x', type: 'felt' },
      { name: 'stealth_pubkey_y', type: 'felt' },
      { name: 'salt', type: 'felt' },
    ],
    outputs: [{ name: 'address', type: 'felt' }],
  },
];

function normalizeBigInt(value: unknown) {
  if (typeof value === 'bigint') return value.toString();
  return value;
}

function pickCosts(receipt: any) {
  return {
    actualFee: receipt?.actual_fee ?? receipt?.actualFee ?? null,
    executionResources: receipt?.execution_resources ?? receipt?.executionResources ?? null,
    l1Gas: receipt?.l1_gas ?? receipt?.l1Gas ?? null,
    l1DataGas: receipt?.l1_data_gas ?? receipt?.l1DataGas ?? null,
    l2Gas: receipt?.l2_gas ?? receipt?.l2Gas ?? null,
  };
}

function toUint256(amount: bigint) {
  const lowMask = (1n << 128n) - 1n;
  return {
    low: amount & lowMask,
    high: amount >> 128n,
  };
}

function isRateLimitError(err: any): boolean {
  const message = err?.message || '';
  return (
    message.includes('cu limit exceeded')
    || message.includes('Request too fast')
    || err?.baseError?.code === -32011
  );
}

async function withRateLimitRetry<T>(fn: () => Promise<T>, label: string): Promise<T> {
  const maxAttempts = 5;
  let attempt = 0;
  while (true) {
    try {
      return await fn();
    } catch (err: any) {
      attempt += 1;
      if (attempt >= maxAttempts || !isRateLimitError(err)) {
        throw err;
      }
      const delayMs = 1500 * attempt;
      console.warn(`[!] ${label} rate-limited, retrying in ${delayMs}ms...`);
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
}

function isInvalidNonceError(err: any): boolean {
  const message = err?.message || '';
  return message.includes('Invalid transaction nonce') || err?.baseError?.code === 52;
}

async function main() {
  if (!CONFIG.accountAddress || !CONFIG.privateKey) {
    throw new Error('Set ACCOUNT_ADDRESS and PRIVATE_KEY to run cost report');
  }

  const provider = new RpcProvider({ nodeUrl: CONFIG.rpcUrl });
  const account = new Account({
    provider,
    address: CONFIG.accountAddress,
    signer: CONFIG.privateKey,
    transactionVersion: ETransactionVersion.V3,
  });
  const registry = new Contract({
    abi: REGISTRY_ABI,
    address: CONFIG.registryAddress,
    providerOrAccount: account,
  });
  const factory = new Contract({
    abi: FACTORY_ABI,
    address: CONFIG.factoryAddress,
    providerOrAccount: account,
  });

  let nextNonce = BigInt(await account.getNonce());
  async function sendWithNonce<T>(fn: (nonce: bigint) => Promise<T>, label: string): Promise<T> {
    let attempts = 0;
    while (true) {
      attempts += 1;
      try {
        return await withRateLimitRetry(async () => {
          const tx = await fn(nextNonce);
          nextNonce += 1n;
          return tx;
        }, label);
      } catch (err: any) {
        if (isInvalidNonceError(err) && attempts < 3) {
          nextNonce = BigInt(await account.getNonce());
          continue;
        }
        throw err;
      }
    }
  }

  const results: Record<string, { hash: string; costs: any }> = {};
  const spendingPrivKey = normalizePrivateKey(123456789n);
  const viewingPrivKey = normalizePrivateKey(987654321n);
  const meta = createMetaAddress(spendingPrivKey, viewingPrivKey);

  const hasMetaResp = await registry.has_meta_address(CONFIG.accountAddress);
  let hasMetaRaw: unknown = (hasMetaResp as any)?.result ?? hasMetaResp ?? 0;
  if (Array.isArray(hasMetaRaw)) {
    hasMetaRaw = hasMetaRaw[0];
  }
  let hasMeta = false;
  if (typeof hasMetaRaw === 'boolean') {
    hasMeta = hasMetaRaw;
  } else if (hasMetaRaw && typeof hasMetaRaw === 'object') {
    const obj = hasMetaRaw as any;
    if (typeof obj.value === 'boolean') {
      hasMeta = obj.value;
    } else if (obj.low !== undefined || obj.high !== undefined) {
      const low = obj.low ?? 0;
      const high = obj.high ?? 0;
      hasMeta = BigInt(low) !== 0n || BigInt(high) !== 0n;
    } else if (obj[0] !== undefined) {
      hasMeta = BigInt(obj[0]) !== 0n;
    }
  } else {
    hasMeta = BigInt(hasMetaRaw as any) !== 0n;
  }

  if (hasMeta) {
    console.log('[*] Updating meta-address...');
    const tx = await sendWithNonce(
      (nonce) => registry.invoke(
        'update_stealth_meta_address',
        [
          meta.spendingKey.x,
          meta.spendingKey.y,
          meta.viewingKey.x,
          meta.viewingKey.y,
          meta.schemeId,
        ],
        { nonce: num.toHex(nonce) }
      ),
      'update meta-address'
    );
    await provider.waitForTransaction(tx.transaction_hash);
    const receipt = await provider.getTransactionReceipt(tx.transaction_hash);
    results.updateMeta = { hash: tx.transaction_hash, costs: pickCosts(receipt) };
  } else {
    console.log('[*] Registering meta-address...');
    const tx = await sendWithNonce(
      (nonce) => registry.invoke(
        'register_stealth_meta_address',
        [
          meta.spendingKey.x,
          meta.spendingKey.y,
          meta.viewingKey.x,
          meta.viewingKey.y,
          meta.schemeId,
        ],
        { nonce: num.toHex(nonce) }
      ),
      'register meta-address'
    );
    await provider.waitForTransaction(tx.transaction_hash);
    const receipt = await provider.getTransactionReceipt(tx.transaction_hash);
    results.registerMeta = { hash: tx.transaction_hash, costs: pickCosts(receipt) };
  }

  console.log('[*] Generating stealth address...');
  const stealth = generateStealthAddress(meta, CONFIG.factoryAddress, CONFIG.accountClassHash);
  const salt = poseidonHashMany([stealth.ephemeralPubkey.x, stealth.ephemeralPubkey.y]);

  console.log('[*] Deploying stealth account...');
  const deployTx = await sendWithNonce(
    (nonce) => factory.invoke(
      'deploy_stealth_account',
      [
        stealth.stealthPubkey.x,
        stealth.stealthPubkey.y,
        salt,
      ],
      { nonce: num.toHex(nonce) }
    ),
    'deploy stealth account'
  );
  await provider.waitForTransaction(deployTx.transaction_hash);
  const deployReceipt = await provider.getTransactionReceipt(deployTx.transaction_hash);
  results.deployStealth = { hash: deployTx.transaction_hash, costs: pickCosts(deployReceipt) };

  console.log('[*] Announcing payment...');
  const announceTx = await sendWithNonce(
    (nonce) => registry.invoke(
      'announce',
      [
        meta.schemeId,
        stealth.ephemeralPubkey.x,
        stealth.ephemeralPubkey.y,
        stealth.stealthAddress,
        stealth.viewTag,
        0,
      ],
      { nonce: num.toHex(nonce) }
    ),
    'announce'
  );
  await provider.waitForTransaction(announceTx.transaction_hash);
  const announceReceipt = await provider.getTransactionReceipt(announceTx.transaction_hash);
  results.announce = { hash: announceTx.transaction_hash, costs: pickCosts(announceReceipt) };

  console.log('[*] Funding stealth address with STRK...');
  const fundAmount = 1_000_000_000_000_000_000n; // 1 STRK
  const fundTx = await sendWithNonce(
    (nonce) => account.execute(
      [
        {
          contractAddress: CONFIG.strkTokenAddress,
          entrypoint: 'transfer',
          calldata: CallData.compile({
            recipient: stealth.stealthAddress,
            amount: toUint256(fundAmount),
          }),
        },
      ],
      { nonce: num.toHex(nonce) }
    ),
    'fund stealth address'
  );
  await provider.waitForTransaction(fundTx.transaction_hash);
  const fundReceipt = await provider.getTransactionReceipt(fundTx.transaction_hash);
  results.fund = { hash: fundTx.transaction_hash, costs: pickCosts(fundReceipt) };

  console.log('[*] Spending from stealth account...');
  const derived = deriveStealthPrivateKey(spendingPrivKey, stealth.sharedSecret);
  const stealthAccount = new Account({
    provider,
    address: stealth.stealthAddress,
    signer: num.toHex(derived),
    cairoVersion: '1',
    transactionVersion: ETransactionVersion.V3,
  });
  const spendAmount = 100_000_000_000_000_000n; // 0.1 STRK
  const spendTx = await withRateLimitRetry(
    () => stealthAccount.execute([
      {
        contractAddress: CONFIG.strkTokenAddress,
        entrypoint: 'transfer',
        calldata: CallData.compile({
          recipient: CONFIG.accountAddress,
          amount: toUint256(spendAmount),
        }),
      },
    ]),
    'spend from stealth account'
  );
  await provider.waitForTransaction(spendTx.transaction_hash);
  const spendReceipt = await provider.getTransactionReceipt(spendTx.transaction_hash);
  results.spend = { hash: spendTx.transaction_hash, costs: pickCosts(spendReceipt) };

  const output = {
    network: 'sepolia',
    timestamp: new Date().toISOString(),
    account: CONFIG.accountAddress,
    registryAddress: CONFIG.registryAddress,
    factoryAddress: CONFIG.factoryAddress,
    stealthAddress: stealth.stealthAddress,
    transactions: results,
  };

  const outputPath = path.join(__dirname, '../../deployments/sepolia_costs.json');
  fs.writeFileSync(outputPath, JSON.stringify(output, (_key, value) => normalizeBigInt(value), 2));
  console.log(`[OK] Cost report written to ${outputPath}`);
}

main().catch((err) => {
  console.error('[X] Cost report failed:', err);
  process.exit(1);
});
