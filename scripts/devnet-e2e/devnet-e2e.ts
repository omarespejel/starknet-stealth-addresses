import { Account, RpcProvider, Contract, CallData, hash, json, num } from 'starknet';
import { poseidonHashMany } from '@scure/starknet';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { config as loadEnv } from 'dotenv';

import {
  createMetaAddress,
  generateStealthAddress,
  StealthScanner,
} from '../../sdk/src/index.js';

loadEnv();

const RPC_URL = process.env.DEVNET_RPC_URL || 'http://127.0.0.1:5050/rpc';
const ACCOUNT_ADDRESS = process.env.DEVNET_ACCOUNT_ADDRESS || '';
const PRIVATE_KEY = process.env.DEVNET_ACCOUNT_PRIVATE_KEY || '';
const TX_VERSION = '0x3';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const artifactsDir = path.join(__dirname, '../../target/dev');

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
  console.log('[*] Devnet E2E: deploy → announce → scan\n');

  if (!ACCOUNT_ADDRESS || !PRIVATE_KEY) {
    console.error('[X] Set DEVNET_ACCOUNT_ADDRESS and DEVNET_ACCOUNT_PRIVATE_KEY');
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
  console.log(`[i] Account: ${ACCOUNT_ADDRESS}\n`);

  const registrySierra = loadJson('starknet_stealth_addresses_StealthRegistry.contract_class.json');
  const registryCasm = loadJson('starknet_stealth_addresses_StealthRegistry.compiled_contract_class.json');
  const accountSierra = loadJson('starknet_stealth_addresses_StealthAccount.contract_class.json');
  const accountCasm = loadJson('starknet_stealth_addresses_StealthAccount.compiled_contract_class.json');
  const factorySierra = loadJson('starknet_stealth_addresses_StealthAccountFactory.contract_class.json');
  const factoryCasm = loadJson('starknet_stealth_addresses_StealthAccountFactory.compiled_contract_class.json');

  const registryClassHash = await declareIfNeeded(account, provider, 'StealthRegistry', registrySierra, registryCasm);
  const accountClassHash = await declareIfNeeded(account, provider, 'StealthAccount', accountSierra, accountCasm);
  const factoryClassHash = await declareIfNeeded(account, provider, 'StealthAccountFactory', factorySierra, factoryCasm);

  console.log('\n[*] Deploying registry...');
  const registryDeploy = await account.deployContract({
    classHash: registryClassHash,
    constructorCalldata: [],
  }, { version: TX_VERSION });
  await provider.waitForTransaction(registryDeploy.transaction_hash);
  const registryAddress = registryDeploy.contract_address;
  console.log(`[OK] Registry: ${registryAddress}`);

  console.log('[*] Deploying factory...');
  const factoryDeploy = await account.deployContract({
    classHash: factoryClassHash,
    constructorCalldata: CallData.compile({
      account_class_hash: accountClassHash,
    }),
  }, { version: TX_VERSION });
  await provider.waitForTransaction(factoryDeploy.transaction_hash);
  const factoryAddress = factoryDeploy.contract_address;
  console.log(`[OK] Factory: ${factoryAddress}\n`);

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
  const spendingPrivKey = 123456789n;
  const meta = createMetaAddress(spendingPrivKey);

  console.log('[*] Registering meta-address...');
  const registerTx = await registry.register_stealth_meta_address(
    meta.spendingKey.x,
    meta.spendingKey.y
  );
  await provider.waitForTransaction(registerTx.transaction_hash);
  console.log('[OK] Meta-address registered');

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
    0,
    stealth.ephemeralPubkey.x,
    stealth.ephemeralPubkey.y,
    stealth.stealthAddress,
    stealth.viewTag,
    0
  );
  await provider.waitForTransaction(announceTx.transaction_hash);
  console.log('[OK] Announcement emitted\n');

  // Scan via SDK against devnet RPC
  const scanner = new StealthScanner({
    registryAddress,
    factoryAddress,
    rpcUrl: RPC_URL,
    chainId,
  });
  await scanner.initialize(registrySierra.abi, accountClassHash);

  console.log('[*] Scanning for announcements...');
  const results = await scanner.scan(meta.spendingKey, spendingPrivKey, spendingPrivKey, 0);

  if (results.length === 0) {
    throw new Error('No matching announcements found');
  }

  console.log(`[OK] Found ${results.length} matching announcement(s)`);
  console.log(`[OK] Derived stealth key: ${num.toHex(results[0].spendingKey!)}`);
  console.log('[OK] Devnet E2E complete');
}

main().catch((err) => {
  console.error('[X] Devnet E2E failed:', err);
  process.exit(1);
});
