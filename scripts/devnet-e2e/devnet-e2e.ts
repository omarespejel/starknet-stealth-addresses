/// <reference types="node" />
import { Account, RpcProvider, Contract, CallData, hash, json, num, ETransactionVersion } from 'starknet';
import { poseidonHashMany } from '@scure/starknet';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { config as loadEnv } from 'dotenv';

import {
  createMetaAddress,
  generateStealthAddress,
  StealthScanner,
  normalizePrivateKey,
} from '../../sdk/src/index.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const envPath = path.join(__dirname, '../../.env');
loadEnv({ path: envPath });

const NETWORK = (process.env.E2E_NETWORK || 'devnet').toLowerCase();
const IS_DEVNET = NETWORK === 'devnet';
const DEFAULT_DEVNET_RPC = 'http://127.0.0.1:5050/rpc';
const RPC_URL =
  process.env.E2E_RPC_URL
  || (IS_DEVNET
    ? (process.env.DEVNET_RPC_URL || DEFAULT_DEVNET_RPC)
    : (process.env.SEPOLIA_RPC_URL || process.env.RPC_URL || ''));
const ACCOUNT_ADDRESS =
  process.env.E2E_ACCOUNT_ADDRESS
  || (IS_DEVNET
    ? (process.env.DEVNET_ACCOUNT_ADDRESS || '')
    : (process.env.ACCOUNT_ADDRESS || process.env.SEPOLIA_ACCOUNT_ADDRESS || ''));
const PRIVATE_KEY =
  process.env.E2E_ACCOUNT_PRIVATE_KEY
  || (IS_DEVNET
    ? (process.env.DEVNET_ACCOUNT_PRIVATE_KEY || '')
    : (process.env.PRIVATE_KEY || process.env.SEPOLIA_ACCOUNT_PRIVATE_KEY || ''));
const REGISTRY_OWNER =
  process.env.E2E_REGISTRY_OWNER
  || (IS_DEVNET ? process.env.DEVNET_REGISTRY_OWNER : process.env.REGISTRY_OWNER)
  || ACCOUNT_ADDRESS;
const STRK_TOKEN_ADDRESS =
  process.env.E2E_STRK_ADDRESS
  || process.env.DEVNET_STRK_ADDRESS
  || process.env.STRK_TOKEN_ADDRESS
  || '0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d';
const SCAN_FROM = Number(process.env.E2E_SCAN_FROM || '0');

function resolveTxVersion(value?: string) {
  if (!value) return ETransactionVersion.V3;
  const normalized = value.trim().toLowerCase();
  return ETransactionVersion.V3;
}

const TX_VERSION = resolveTxVersion(process.env.E2E_TX_VERSION || process.env.DEVNET_TX_VERSION);

const artifactsDir = path.join(__dirname, '../../target/dev');
const deploymentsDir = path.join(__dirname, '../../deployments');

function loadJson(fileName: string): any {
  const raw = fs.readFileSync(path.join(artifactsDir, fileName), 'utf-8');
  return json.parse(raw);
}

function normalizeAbi(abi: unknown): any {
  if (typeof abi === 'string') {
    return json.parse(abi);
  }
  return abi;
}

function readDeployments(fileName: string): any {
  const raw = fs.readFileSync(path.join(deploymentsDir, fileName), 'utf-8');
  return JSON.parse(raw);
}

function toUint256(amount: bigint) {
  const lowMask = (1n << 128n) - 1n;
  return {
    low: amount & lowMask,
    high: amount >> 128n,
  };
}

async function declareIfNeeded(
  account: Account,
  provider: RpcProvider,
  name: string,
  sierra: any,
  casm: any
): Promise<string> {
  try {
    const declareResponse = await account.declare(
      { contract: sierra, casm },
      { version: TX_VERSION }
    );
    await provider.waitForTransaction(declareResponse.transaction_hash);
    console.log(`[OK] Declared ${name}: ${declareResponse.class_hash}`);
    return declareResponse.class_hash;
  } catch (e: any) {
    if (e.message?.includes('already declared') || e.message?.includes('CLASS_ALREADY_DECLARED')) {
      const classHash = hash.computeContractClassHash(sierra);
      console.log(`[i] ${name} already declared: ${classHash}`);
      return classHash;
    }
    throw e;
  }
}

async function main() {
  console.log(`[ * ] E2E (${NETWORK}): deploy → announce → scan\n`);

  if (!RPC_URL) {
    console.error('[X] Set E2E_RPC_URL (or DEVNET_RPC_URL / SEPOLIA_RPC_URL)');
    process.exit(1);
  }
  if (!ACCOUNT_ADDRESS || !PRIVATE_KEY) {
    console.error('[X] Set E2E_ACCOUNT_ADDRESS and E2E_ACCOUNT_PRIVATE_KEY');
    process.exit(1);
  }

  const provider = new RpcProvider({ nodeUrl: RPC_URL, blockIdentifier: 'latest' });
  // Devnet doesn't accept "pending" for block_id; force latest for nonce reads.
  const account = new Account({
    provider,
    address: ACCOUNT_ADDRESS,
    signer: PRIVATE_KEY,
    transactionVersion: TX_VERSION,
  });

  const chainId = await provider.getChainId();
  console.log(`[i] Chain ID: ${chainId}`);
  console.log(`[i] TX version: ${TX_VERSION}`);
  console.log(`[i] Account: ${ACCOUNT_ADDRESS}\n`);

  const registrySierra = loadJson('starknet_stealth_addresses_StealthRegistry.contract_class.json');
  const registryCasm = loadJson('starknet_stealth_addresses_StealthRegistry.compiled_contract_class.json');
  const accountSierra = loadJson('starknet_stealth_addresses_StealthAccount.contract_class.json');
  const accountCasm = loadJson('starknet_stealth_addresses_StealthAccount.compiled_contract_class.json');
  const factorySierra = loadJson('starknet_stealth_addresses_StealthAccountFactory.contract_class.json');
  const factoryCasm = loadJson('starknet_stealth_addresses_StealthAccountFactory.compiled_contract_class.json');

  let registryClassHash: string;
  let accountClassHash: string;
  let factoryClassHash: string;
  let registryAddress: string;
  let factoryAddress: string;

  if (IS_DEVNET) {
    registryClassHash = await declareIfNeeded(account, provider, 'StealthRegistry', registrySierra, registryCasm);
    accountClassHash = await declareIfNeeded(account, provider, 'StealthAccount', accountSierra, accountCasm);
    factoryClassHash = await declareIfNeeded(account, provider, 'StealthAccountFactory', factorySierra, factoryCasm);

    console.log('\n[*] Deploying registry...');
    const registryDeploy = await account.deployContract({
      classHash: registryClassHash,
      constructorCalldata: CallData.compile({
        owner: REGISTRY_OWNER,
      }),
    }, { version: TX_VERSION });
    await provider.waitForTransaction(registryDeploy.transaction_hash);
    registryAddress = registryDeploy.contract_address;
    console.log(`[OK] Registry: ${registryAddress}`);

    console.log('[*] Deploying factory...');
    const factoryDeploy = await account.deployContract({
      classHash: factoryClassHash,
      constructorCalldata: CallData.compile({
        account_class_hash: accountClassHash,
      }),
    }, { version: TX_VERSION });
    await provider.waitForTransaction(factoryDeploy.transaction_hash);
    factoryAddress = factoryDeploy.contract_address;
    console.log(`[OK] Factory: ${factoryAddress}\n`);
  } else {
    const deployments = readDeployments('sepolia.json');
    registryAddress = deployments?.contracts?.StealthRegistry;
    factoryAddress = deployments?.contracts?.StealthAccountFactory;
    registryClassHash = deployments?.classHashes?.StealthRegistry
      || hash.computeContractClassHash(registrySierra);
    accountClassHash = deployments?.classHashes?.StealthAccount
      || hash.computeContractClassHash(accountSierra);
    factoryClassHash = deployments?.classHashes?.StealthAccountFactory
      || hash.computeContractClassHash(factorySierra);

    if (!registryAddress || !factoryAddress) {
      console.error('[X] Missing contract addresses in deployments/sepolia.json');
      process.exit(1);
    }
    console.log(`[OK] Registry: ${registryAddress}`);
    console.log(`[OK] Factory:  ${factoryAddress}\n`);
  }

  const registry = new Contract({
    abi: normalizeAbi(registrySierra.abi),
    address: registryAddress,
    providerOrAccount: account,
  });
  const factory = new Contract({
    abi: normalizeAbi(factorySierra.abi),
    address: factoryAddress,
    providerOrAccount: account,
  });

  // Recipient setup
  const spendingPrivKey = normalizePrivateKey(123456789n);
  const viewingPrivKey = normalizePrivateKey(987654321n);
  const meta = createMetaAddress(spendingPrivKey, viewingPrivKey);

  const hasMetaResp = await registry.has_meta_address(ACCOUNT_ADDRESS);
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
    const updateTx = await registry.update_stealth_meta_address(
      meta.spendingKey.x,
      meta.spendingKey.y,
      meta.viewingKey.x,
      meta.viewingKey.y,
      meta.schemeId
    );
    await provider.waitForTransaction(updateTx.transaction_hash);
    console.log('[OK] Meta-address updated');
  } else {
    console.log('[*] Registering meta-address...');
    const registerTx = await registry.register_stealth_meta_address(
      meta.spendingKey.x,
      meta.spendingKey.y,
      meta.viewingKey.x,
      meta.viewingKey.y,
      meta.schemeId
    );
    await provider.waitForTransaction(registerTx.transaction_hash);
    console.log('[OK] Meta-address registered');
  }

  // Sender generates stealth address
  console.log('[*] Generating stealth address...');
  const stealth = generateStealthAddress(meta, factoryAddress, accountClassHash);
  const salt = poseidonHashMany([stealth.ephemeralPubkey.x, stealth.ephemeralPubkey.y]);

  console.log(`[i] Stealth address: ${stealth.stealthAddress}`);
  console.log('[*] Deploying stealth account...');
  const deployTx = await factory.deploy_stealth_account(
    stealth.stealthPubkey.x,
    stealth.stealthPubkey.y,
    salt
  );
  await provider.waitForTransaction(deployTx.transaction_hash);

  console.log('[*] Announcing payment...');
  const announceTx = await registry.announce(
    meta.schemeId,
    stealth.ephemeralPubkey.x,
    stealth.ephemeralPubkey.y,
    stealth.stealthAddress,
    stealth.viewTag,
    0
  );
  await provider.waitForTransaction(announceTx.transaction_hash);
  console.log('[OK] Announcement emitted\n');

  const fundAmount = 1_000_000_000_000_000_000n; // 1 STRK (18 decimals)
  console.log('[*] Funding stealth address with STRK...');
  const fundCall = {
    contractAddress: STRK_TOKEN_ADDRESS,
    entrypoint: 'transfer',
    calldata: CallData.compile({
      recipient: stealth.stealthAddress,
      amount: toUint256(fundAmount),
    }),
  };
  const fundTx = await account.execute([fundCall]);
  await provider.waitForTransaction(fundTx.transaction_hash);
  console.log(`[OK] Funded stealth address with ${fundAmount.toString()} wei`);

  // Scan via SDK against devnet RPC
  const scanner = new StealthScanner({
    registryAddress,
    factoryAddress,
    rpcUrl: RPC_URL,
    chainId,
  });
  await scanner.initialize(normalizeAbi(registrySierra.abi), accountClassHash);

  const wrongSpendingPriv = normalizePrivateKey(111n);
  const wrongViewingPriv = normalizePrivateKey(222n);
  const wrongMeta = createMetaAddress(wrongSpendingPriv, wrongViewingPriv);

  console.log('[*] Scanning with unrelated keys (privacy check)...');
  const wrongResults = await scanner.scan(
    wrongMeta.spendingKey,
    wrongViewingPriv,
    wrongSpendingPriv,
    SCAN_FROM
  );
  if (wrongResults.length !== 0) {
    throw new Error('Privacy check failed: unrelated keys matched announcements');
  }
  console.log('[OK] Privacy check passed (no matches for unrelated keys)');

  console.log('[*] Scanning for announcements...');
  const results = await scanner.scan(meta.spendingKey, viewingPrivKey, spendingPrivKey, SCAN_FROM);

  if (results.length === 0) {
    throw new Error('No matching announcements found');
  }

  const normalizeAddress = (value: unknown) => {
    if (typeof value === 'string') {
      return value.toLowerCase();
    }
    try {
      return num.toHex(value as any).toLowerCase();
    } catch {
      return String(value).toLowerCase();
    }
  };
  const expectedStealth = normalizeAddress(stealth.stealthAddress);
  const matches = results.filter((result) => (
    normalizeAddress(result.stealthAddress) === expectedStealth
  ));

  if (matches.length === 0) {
    throw new Error('No matching announcements found for current stealth address');
  }

  console.log(`[OK] Found ${matches.length} matching announcement(s) for current stealth address`);
  const derivedKey = matches[matches.length - 1].spendingKey!;
  console.log(`[OK] Derived stealth key: ${num.toHex(derivedKey)}`);

  const stealthAccount = new Account({
    provider,
    address: stealth.stealthAddress,
    signer: num.toHex(derivedKey),
    cairoVersion: '1',
    transactionVersion: TX_VERSION,
  });

  const spendAmount = 100_000_000_000_000_000n; // 0.1 STRK
  console.log('[*] Spending from stealth account...');
  const spendCall = {
    contractAddress: STRK_TOKEN_ADDRESS,
    entrypoint: 'transfer',
    calldata: CallData.compile({
      recipient: ACCOUNT_ADDRESS,
      amount: toUint256(spendAmount),
    }),
  };
  const spendTx = await stealthAccount.execute([spendCall]);
  await provider.waitForTransaction(spendTx.transaction_hash);
  console.log(`[OK] Stealth spend sent ${spendAmount.toString()} wei`);
  console.log(`[OK] E2E (${NETWORK}) complete`);
}

main().catch((err) => {
  console.error(`[X] E2E (${NETWORK}) failed:`, err);
  process.exit(1);
});
