/**
 * Deploy Stealth Address Contracts to Starknet Sepolia
 * 
 * Usage:
 *   1. Copy .env.example to .env and fill in your credentials
 *   2. npm install
 *   3. npm run deploy
 */

import { 
  Account, 
  RpcProvider, 
  Contract, 
  json,
  stark,
  hash,
  CallData,
  constants
} from 'starknet';
import { config as loadEnv } from 'dotenv';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';

// Get directory path
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const envPath = path.join(__dirname, '../../.env');
loadEnv({ path: envPath });

function resolveTxVersion(value?: string): '0x3' {
  if (!value) return '0x3';
  const normalized = value.trim().toLowerCase();
  if (normalized === '0x3' || normalized === '3' || normalized === 'v3') {
    return '0x3';
  }
  return '0x3';
}

// Configuration
const RPC_URL = process.env.RPC_URL || 'https://api.zan.top/public/starknet-sepolia';
const PRIVATE_KEY = process.env.PRIVATE_KEY || '';
const ACCOUNT_ADDRESS = process.env.ACCOUNT_ADDRESS || '';
const REGISTRY_OWNER = process.env.REGISTRY_OWNER || ACCOUNT_ADDRESS;
const TX_VERSION = resolveTxVersion(process.env.TX_VERSION);

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

async function main() {
  console.log('[*] Deploying Stealth Address Contracts to Starknet Sepolia\n');
  
  // Validate environment
  if (!PRIVATE_KEY || !ACCOUNT_ADDRESS) {
    console.error('[X] Error: Set PRIVATE_KEY and ACCOUNT_ADDRESS environment variables');
    console.error('    Export them or create a .env file');
    process.exit(1);
  }

  // Initialize provider and account
  console.log('[*] Connecting to Starknet Sepolia...');
  const provider = new RpcProvider({ nodeUrl: RPC_URL });
  
  const account = new Account({
    provider,
    address: ACCOUNT_ADDRESS,
    signer: PRIVATE_KEY,
    transactionVersion: TX_VERSION,
  });

  // Verify connection
  try {
    const chainId = await provider.getChainId();
    console.log(`    Chain ID: ${chainId}`);
    console.log(`    Account: ${ACCOUNT_ADDRESS}`);
  } catch (e) {
    console.error('[X] Failed to connect to RPC');
    throw e;
  }

  // Load contract artifacts
  const artifactsDir = path.join(__dirname, '../../target/dev');
  
  const registrySierra = json.parse(
    fs.readFileSync(path.join(artifactsDir, 'starknet_stealth_addresses_StealthRegistry.contract_class.json'), 'utf-8')
  );
  const registryCasm = json.parse(
    fs.readFileSync(path.join(artifactsDir, 'starknet_stealth_addresses_StealthRegistry.compiled_contract_class.json'), 'utf-8')
  );

  const accountSierra = json.parse(
    fs.readFileSync(path.join(artifactsDir, 'starknet_stealth_addresses_StealthAccount.contract_class.json'), 'utf-8')
  );
  const accountCasm = json.parse(
    fs.readFileSync(path.join(artifactsDir, 'starknet_stealth_addresses_StealthAccount.compiled_contract_class.json'), 'utf-8')
  );

  const factorySierra = json.parse(
    fs.readFileSync(path.join(artifactsDir, 'starknet_stealth_addresses_StealthAccountFactory.contract_class.json'), 'utf-8')
  );
  const factoryCasm = json.parse(
    fs.readFileSync(path.join(artifactsDir, 'starknet_stealth_addresses_StealthAccountFactory.compiled_contract_class.json'), 'utf-8')
  );

  console.log('[OK] Contract artifacts loaded\n');

  const transactions: Record<string, { hash: string; costs: any }> = {};

  // Step 1: Declare StealthRegistry
  console.log('[*] Step 1/4: Declaring StealthRegistry...');
  let registryClassHash: string;
  try {
    const declareResponse = await account.declare({
      contract: registrySierra,
      casm: registryCasm,
    });
    await provider.waitForTransaction(declareResponse.transaction_hash);
    const receipt = await provider.getTransactionReceipt(declareResponse.transaction_hash);
    transactions.registryDeclare = {
      hash: declareResponse.transaction_hash,
      costs: pickCosts(receipt),
    };
    registryClassHash = declareResponse.class_hash;
    console.log(`    [OK] Class hash: ${registryClassHash}`);
  } catch (e: any) {
    if (e.message?.includes('already declared') || e.message?.includes('StarknetErrorCode.CLASS_ALREADY_DECLARED')) {
      registryClassHash = hash.computeContractClassHash(registrySierra);
      console.log(`    [i] Already declared: ${registryClassHash}`);
    } else {
      throw e;
    }
  }

  // Step 2: Declare StealthAccount
  console.log('\n[*] Step 2/4: Declaring StealthAccount...');
  let accountClassHash: string;
  try {
    const declareResponse = await account.declare({
      contract: accountSierra,
      casm: accountCasm,
    });
    await provider.waitForTransaction(declareResponse.transaction_hash);
    const receipt = await provider.getTransactionReceipt(declareResponse.transaction_hash);
    transactions.accountDeclare = {
      hash: declareResponse.transaction_hash,
      costs: pickCosts(receipt),
    };
    accountClassHash = declareResponse.class_hash;
    console.log(`    [OK] Class hash: ${accountClassHash}`);
  } catch (e: any) {
    if (e.message?.includes('already declared') || e.message?.includes('StarknetErrorCode.CLASS_ALREADY_DECLARED')) {
      accountClassHash = hash.computeContractClassHash(accountSierra);
      console.log(`    [i] Already declared: ${accountClassHash}`);
    } else {
      throw e;
    }
  }

  // Step 3: Declare StealthAccountFactory
  console.log('\n[*] Step 3/4: Declaring StealthAccountFactory...');
  let factoryClassHash: string;
  try {
    const declareResponse = await account.declare({
      contract: factorySierra,
      casm: factoryCasm,
    });
    await provider.waitForTransaction(declareResponse.transaction_hash);
    const receipt = await provider.getTransactionReceipt(declareResponse.transaction_hash);
    transactions.factoryDeclare = {
      hash: declareResponse.transaction_hash,
      costs: pickCosts(receipt),
    };
    factoryClassHash = declareResponse.class_hash;
    console.log(`    [OK] Class hash: ${factoryClassHash}`);
  } catch (e: any) {
    if (e.message?.includes('already declared') || e.message?.includes('StarknetErrorCode.CLASS_ALREADY_DECLARED')) {
      factoryClassHash = hash.computeContractClassHash(factorySierra);
      console.log(`    [i] Already declared: ${factoryClassHash}`);
    } else {
      throw e;
    }
  }

  // Step 4: Deploy contracts
  console.log('\n[*] Step 4/4: Deploying contracts...');

  // Deploy Registry
  console.log('    Deploying StealthRegistry...');
  const registryDeployResponse = await account.deployContract({
    classHash: registryClassHash,
    constructorCalldata: CallData.compile({
      owner: REGISTRY_OWNER,
    }),
  });
  await provider.waitForTransaction(registryDeployResponse.transaction_hash);
  const registryReceipt = await provider.getTransactionReceipt(registryDeployResponse.transaction_hash);
  transactions.registryDeploy = {
    hash: registryDeployResponse.transaction_hash,
    costs: pickCosts(registryReceipt),
  };
  const registryAddress = registryDeployResponse.contract_address;
  console.log(`    [OK] Registry: ${registryAddress}`);

  // Deploy Factory
  console.log('    Deploying StealthAccountFactory...');
  const factoryDeployResponse = await account.deployContract({
    classHash: factoryClassHash,
    constructorCalldata: CallData.compile({
      account_class_hash: accountClassHash,
    }),
  });
  await provider.waitForTransaction(factoryDeployResponse.transaction_hash);
  const factoryReceipt = await provider.getTransactionReceipt(factoryDeployResponse.transaction_hash);
  transactions.factoryDeploy = {
    hash: factoryDeployResponse.transaction_hash,
    costs: pickCosts(factoryReceipt),
  };
  const factoryAddress = factoryDeployResponse.contract_address;
  console.log(`    [OK] Factory: ${factoryAddress}`);

  // Summary
  console.log('\n===================================================================');
  console.log('                    DEPLOYMENT COMPLETE');
  console.log('===================================================================\n');
  console.log('Network: Starknet Sepolia\n');
  console.log('Class Hashes:');
  console.log(`  StealthRegistry:       ${registryClassHash}`);
  console.log(`  StealthAccount:        ${accountClassHash}`);
  console.log(`  StealthAccountFactory: ${factoryClassHash}`);
  console.log('\nContract Addresses:');
  console.log(`  StealthRegistry:       ${registryAddress}`);
  console.log(`  StealthAccountFactory: ${factoryAddress}`);
  console.log('\nExplorer Links:');
  console.log(`  Registry: https://sepolia.starkscan.co/contract/${registryAddress}`);
  console.log(`  Factory:  https://sepolia.starkscan.co/contract/${factoryAddress}`);

  // Save deployment info
  const deploymentInfo = {
    network: 'sepolia',
    timestamp: new Date().toISOString(),
    classHashes: {
      StealthRegistry: registryClassHash,
      StealthAccount: accountClassHash,
      StealthAccountFactory: factoryClassHash,
    },
    contracts: {
      StealthRegistry: registryAddress,
      StealthAccountFactory: factoryAddress,
    },
    transactions,
  };

  const deploymentsDir = path.join(__dirname, '../../deployments');
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }
  
  fs.writeFileSync(
    path.join(deploymentsDir, 'sepolia.json'),
    JSON.stringify(deploymentInfo, (_key, value) => normalizeBigInt(value), 2)
  );
  console.log('\n[*] Deployment info saved to: deployments/sepolia.json');
}

main().catch(console.error);
