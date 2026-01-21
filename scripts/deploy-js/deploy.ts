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
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';

// Get directory path
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Configuration
const RPC_URL = process.env.RPC_URL || 'https://starknet-sepolia.public.blastapi.io/rpc/v0_7';
const PRIVATE_KEY = process.env.PRIVATE_KEY || '';
const ACCOUNT_ADDRESS = process.env.ACCOUNT_ADDRESS || '';

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
  
  const account = new Account(
    provider,
    ACCOUNT_ADDRESS,
    PRIVATE_KEY
  );

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

  // Step 1: Declare StealthRegistry
  console.log('[*] Step 1/4: Declaring StealthRegistry...');
  let registryClassHash: string;
  try {
    const declareResponse = await account.declare({
      contract: registrySierra,
      casm: registryCasm,
    });
    await provider.waitForTransaction(declareResponse.transaction_hash);
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
    constructorCalldata: [],
  });
  await provider.waitForTransaction(registryDeployResponse.transaction_hash);
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
  };

  const deploymentsDir = path.join(__dirname, '../../deployments');
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }
  
  fs.writeFileSync(
    path.join(deploymentsDir, 'sepolia.json'),
    JSON.stringify(deploymentInfo, null, 2)
  );
  console.log('\n[*] Deployment info saved to: deployments/sepolia.json');
}

main().catch(console.error);
