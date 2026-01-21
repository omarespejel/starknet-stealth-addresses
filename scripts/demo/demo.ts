/**
 * Starknet Stealth Addresses Demo
 * 
 * This script demonstrates a complete stealth payment flow on Sepolia testnet:
 * 1. Alice registers her meta-address (spending + viewing keys)
 * 2. Bob looks up Alice's meta-address
 * 3. Bob generates a stealth address for Alice
 * 4. Bob deploys the stealth account and announces the payment
 * 5. Alice scans and finds her payment
 * 
 * Run: npm run demo
 */

import { 
  Account, 
  RpcProvider, 
  Contract, 
  CallData,
  hash,
  ec,
  stark,
  num
} from 'starknet';
import { poseidonHashMany } from '@scure/starknet';

// ============================================================================
// CONFIGURATION
// ============================================================================

const CONFIG = {
  rpcUrl: process.env.RPC_URL || 'https://api.zan.top/public/starknet-sepolia',
  
  // Deployed contracts on Sepolia
  registryAddress: '0x04320728f5b57648dc569a247cb9acf475ec1a0ff17368be127b3621ca2e363a',
  factoryAddress: '0x06cc6d9ff45a63bf5a15e48dcf27928a9547ac49f540255abca86eb39272c83e',
  accountClassHash: '0xfe0c0abc68d8c9e9e5dd708e49d4a8547a16c1449c5f16af881c2c98e8bcdd',
  
  // Demo account (set via environment variable)
  accountAddress: process.env.ACCOUNT_ADDRESS || '',
  privateKey: process.env.PRIVATE_KEY || '',
};

// Contract ABIs (minimal for demo)
const REGISTRY_ABI = [
  {
    type: "function",
    name: "register_stealth_meta_address",
    inputs: [
      { name: "spending_key_x", type: "felt" },
      { name: "spending_key_y", type: "felt" }
    ],
    outputs: []
  },
  {
    type: "function",
    name: "get_stealth_meta_address",
    inputs: [{ name: "user", type: "felt" }],
    outputs: [{ name: "x", type: "felt" }, { name: "y", type: "felt" }]
  },
  {
    type: "function",
    name: "has_meta_address",
    inputs: [{ name: "user", type: "felt" }],
    outputs: [{ name: "result", type: "felt" }]
  },
  {
    type: "function",
    name: "announce",
    inputs: [
      { name: "scheme_id", type: "felt" },
      { name: "ephemeral_pubkey_x", type: "felt" },
      { name: "ephemeral_pubkey_y", type: "felt" },
      { name: "stealth_address", type: "felt" },
      { name: "view_tag", type: "felt" },
      { name: "metadata", type: "felt" }
    ],
    outputs: []
  },
  {
    type: "function",
    name: "get_announcement_count",
    inputs: [],
    outputs: [{ name: "count", type: "felt" }]
  }
];

const FACTORY_ABI = [
  {
    type: "function",
    name: "deploy_stealth_account",
    inputs: [
      { name: "stealth_pubkey_x", type: "felt" },
      { name: "stealth_pubkey_y", type: "felt" },
      { name: "salt", type: "felt" }
    ],
    outputs: [{ name: "address", type: "felt" }]
  },
  {
    type: "function",
    name: "get_deployment_count",
    inputs: [],
    outputs: [{ name: "count", type: "felt" }]
  }
];

// ============================================================================
// CRYPTO UTILITIES
// ============================================================================

const CURVE_ORDER = BigInt('0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f');

function generatePrivateKey(): bigint {
  const randomBytes = new Uint8Array(32);
  crypto.getRandomValues(randomBytes);
  let key = BigInt('0x' + Buffer.from(randomBytes).toString('hex'));
  return (key % (CURVE_ORDER - 1n)) + 1n;
}

function getPublicKey(privateKey: bigint): { x: bigint; y: bigint } {
  // Convert bigint to hex string (without 0x prefix, padded to 64 chars)
  const privKeyHex = privateKey.toString(16).padStart(64, '0');
  const pubKey = ec.starkCurve.getPublicKey(privKeyHex, false);
  const hex = Buffer.from(pubKey).toString('hex');
  return {
    x: BigInt('0x' + hex.slice(2, 66)),
    y: BigInt('0x' + hex.slice(66, 130)),
  };
}

function computeSharedSecret(scalar: bigint, point: { x: bigint; y: bigint }): { x: bigint; y: bigint } {
  const p = ec.starkCurve.ProjectivePoint.fromAffine({ x: point.x, y: point.y });
  // Convert scalar to proper format
  const scalarHex = scalar.toString(16).padStart(64, '0');
  const result = p.multiply(BigInt('0x' + scalarHex));
  const affine = result.toAffine();
  return { x: affine.x, y: affine.y };
}

function hashSharedSecret(secret: { x: bigint; y: bigint }): bigint {
  return poseidonHashMany([secret.x, secret.y]) % CURVE_ORDER;
}

function computeViewTag(secret: { x: bigint; y: bigint }): number {
  return Number(poseidonHashMany([secret.x, secret.y]) % 256n);
}

function addPoints(p1: { x: bigint; y: bigint }, p2: { x: bigint; y: bigint }): { x: bigint; y: bigint } {
  const point1 = ec.starkCurve.ProjectivePoint.fromAffine({ x: p1.x, y: p1.y });
  const point2 = ec.starkCurve.ProjectivePoint.fromAffine({ x: p2.x, y: p2.y });
  const result = point1.add(point2);
  const affine = result.toAffine();
  return { x: affine.x, y: affine.y };
}

// ============================================================================
// DEMO
// ============================================================================

async function main() {
  console.log('');
  console.log('===================================================================');
  console.log('       STARKNET STEALTH ADDRESSES - LIVE DEMO');
  console.log('===================================================================');
  console.log('');

  // Check for private key
  if (!CONFIG.privateKey) {
    console.log('[!] Set PRIVATE_KEY environment variable to run full demo');
    console.log('    Example: PRIVATE_KEY=0x... npm run demo');
    console.log('');
    console.log('Running in READ-ONLY mode (will show current contract state)');
    console.log('');
  }

  // Initialize provider
  console.log('[*] Connecting to Starknet Sepolia...');
  const provider = new RpcProvider({ nodeUrl: CONFIG.rpcUrl });
  
  const chainId = await provider.getChainId();
  console.log(`    [OK] Connected! Chain ID: ${chainId}`);
  console.log('');

  // Initialize contracts
  const registry = new Contract(REGISTRY_ABI, CONFIG.registryAddress, provider);
  const factory = new Contract(FACTORY_ABI, CONFIG.factoryAddress, provider);

  // Show current state
  console.log('[*] Current Contract State:');
  console.log('    Registry:', CONFIG.registryAddress);
  console.log('    Factory: ', CONFIG.factoryAddress);
  
  try {
    const announcementCount = await registry.get_announcement_count();
    console.log(`    Announcements: ${announcementCount}`);
  } catch (e) {
    console.log('    Announcements: (unable to fetch)');
  }
  
  try {
    const deploymentCount = await factory.get_deployment_count();
    console.log(`    Deployments: ${deploymentCount}`);
  } catch (e) {
    console.log('    Deployments: (unable to fetch)');
  }
  console.log('');

  if (!CONFIG.privateKey) {
    console.log('===================================================================');
    console.log('   To run the full demo with transactions, set PRIVATE_KEY');
    console.log('===================================================================');
    return;
  }

  // Initialize account for transactions
  const account = new Account(provider, CONFIG.accountAddress, CONFIG.privateKey);
  registry.connect(account);
  factory.connect(account);

  // =========================================================================
  // STEP 1: Alice generates her stealth meta-address
  // =========================================================================
  console.log('===================================================================');
  console.log('   STEP 1: Alice creates her stealth meta-address');
  console.log('===================================================================');
  console.log('');

  // Generate Alice's keys
  const aliceSpendingPrivKey = generatePrivateKey();
  const aliceSpendingPubKey = getPublicKey(aliceSpendingPrivKey);
  
  console.log('   [*] Alice generates her spending key pair:');
  console.log(`       Private: ${num.toHex(aliceSpendingPrivKey).slice(0, 20)}...`);
  console.log(`       Public X: ${num.toHex(aliceSpendingPubKey.x).slice(0, 20)}...`);
  console.log(`       Public Y: ${num.toHex(aliceSpendingPubKey.y).slice(0, 20)}...`);
  console.log('');

  // Register meta-address
  console.log('   [*] Registering meta-address on-chain...');
  try {
    const registerTx = await registry.register_stealth_meta_address(
      num.toHex(aliceSpendingPubKey.x),
      num.toHex(aliceSpendingPubKey.y)
    );
    console.log(`       TX: ${registerTx.transaction_hash}`);
    await provider.waitForTransaction(registerTx.transaction_hash);
    console.log('       [OK] Meta-address registered!');
  } catch (e: any) {
    if (e.message?.includes('already registered')) {
      console.log('       [i] Meta-address already registered');
    } else {
      console.log(`       [!] ${e.message?.slice(0, 50)}...`);
    }
  }
  console.log('');

  // =========================================================================
  // STEP 2: Bob generates stealth address for Alice
  // =========================================================================
  console.log('===================================================================');
  console.log('   STEP 2: Bob generates a stealth address for Alice');
  console.log('===================================================================');
  console.log('');

  // Bob generates ephemeral key
  const bobEphemeralPrivKey = generatePrivateKey();
  const bobEphemeralPubKey = getPublicKey(bobEphemeralPrivKey);
  
  console.log('   [*] Bob generates ephemeral key pair:');
  console.log(`       Ephemeral Public X: ${num.toHex(bobEphemeralPubKey.x).slice(0, 20)}...`);
  console.log('');

  // Compute shared secret: S = r * K (ephemeral_priv * alice_pub)
  const sharedSecret = computeSharedSecret(bobEphemeralPrivKey, aliceSpendingPubKey);
  console.log('   [*] Bob computes shared secret (ECDH):');
  console.log(`       S = r * K`);
  console.log(`       Secret X: ${num.toHex(sharedSecret.x).slice(0, 20)}...`);
  console.log('');

  // Derive stealth public key: P = K + hash(S)*G
  const hashScalar = hashSharedSecret(sharedSecret);
  const hashPoint = getPublicKey(hashScalar);
  const stealthPubKey = addPoints(aliceSpendingPubKey, hashPoint);
  
  console.log('   [*] Bob derives stealth public key:');
  console.log(`       P = K + hash(S)*G`);
  console.log(`       Stealth X: ${num.toHex(stealthPubKey.x).slice(0, 20)}...`);
  console.log(`       Stealth Y: ${num.toHex(stealthPubKey.y).slice(0, 20)}...`);
  console.log('');

  // Compute view tag
  const viewTag = computeViewTag(sharedSecret);
  console.log(`   [*] View tag: ${viewTag} (for efficient scanning)`);
  console.log('');

  // =========================================================================
  // STEP 3: Bob deploys stealth account
  // =========================================================================
  console.log('===================================================================');
  console.log('   STEP 3: Bob deploys the stealth account');
  console.log('===================================================================');
  console.log('');

  const salt = poseidonHashMany([bobEphemeralPubKey.x, bobEphemeralPubKey.y]);
  
  console.log('   [*] Deploying stealth account via factory...');
  let stealthAddress: string = '';
  
  try {
    const deployTx = await factory.deploy_stealth_account(
      num.toHex(stealthPubKey.x),
      num.toHex(stealthPubKey.y),
      num.toHex(salt)
    );
    console.log(`       TX: ${deployTx.transaction_hash}`);
    await provider.waitForTransaction(deployTx.transaction_hash);
    
    // Get deployed address from events or receipt
    const receipt = await provider.getTransactionReceipt(deployTx.transaction_hash);
    // @ts-ignore
    if (receipt.events && receipt.events.length > 0) {
      // @ts-ignore
      stealthAddress = receipt.events[0].data[0] || 'deployed';
    }
    console.log('       [OK] Stealth account deployed!');
    console.log(`       Address: ${stealthAddress || '(check explorer)'}`);
  } catch (e: any) {
    console.log(`       [!] ${e.message?.slice(0, 80)}...`);
    stealthAddress = '0x...deployed';
  }
  console.log('');

  // =========================================================================
  // STEP 4: Bob announces the payment
  // =========================================================================
  console.log('===================================================================');
  console.log('   STEP 4: Bob announces the payment');
  console.log('===================================================================');
  console.log('');

  console.log('   [*] Publishing announcement on-chain...');
  try {
    const announceTx = await registry.announce(
      0, // scheme_id
      num.toHex(bobEphemeralPubKey.x),
      num.toHex(bobEphemeralPubKey.y),
      stealthAddress || '0x1',
      viewTag,
      0 // metadata
    );
    console.log(`       TX: ${announceTx.transaction_hash}`);
    await provider.waitForTransaction(announceTx.transaction_hash);
    console.log('       [OK] Announcement published!');
  } catch (e: any) {
    console.log(`       [!] ${e.message?.slice(0, 80)}...`);
  }
  console.log('');

  // =========================================================================
  // STEP 5: Alice scans and finds payment
  // =========================================================================
  console.log('===================================================================');
  console.log('   STEP 5: Alice scans and finds her payment');
  console.log('===================================================================');
  console.log('');

  console.log('   [*] Alice scans announcements with her viewing key...');
  console.log('');
  
  // Simulate scanning (in real app, would fetch from events)
  console.log('   [*] Announcement found:');
  console.log(`       Ephemeral X: ${num.toHex(bobEphemeralPubKey.x).slice(0, 20)}...`);
  console.log(`       View Tag: ${viewTag}`);
  console.log('');
  
  // Alice computes shared secret: S' = k * R
  const aliceSharedSecret = computeSharedSecret(aliceSpendingPrivKey, bobEphemeralPubKey);
  const aliceViewTag = computeViewTag(aliceSharedSecret);
  
  console.log('   [*] Alice computes shared secret:');
  console.log(`       S\' = k * R`);
  console.log(`       Computed view tag: ${aliceViewTag}`);
  
  if (aliceViewTag === viewTag) {
    console.log('       [OK] VIEW TAG MATCHES! This is Alice\'s payment!');
    console.log('');
    
    // Derive spending key
    const aliceStealthPrivKey = (aliceSpendingPrivKey + hashSharedSecret(aliceSharedSecret)) % CURVE_ORDER;
    console.log('   [*] Alice derives stealth private key:');
    console.log(`       p = k + hash(S) mod n`);
    console.log(`       Private key: ${num.toHex(aliceStealthPrivKey).slice(0, 20)}...`);
    console.log('');
    console.log('   [OK] Alice can now spend from the stealth address!');
  } else {
    console.log('       [X] View tag mismatch - not Alice\'s payment');
  }
  
  console.log('');
  console.log('===================================================================');
  console.log('                    DEMO COMPLETE!');
  console.log('===================================================================');
  console.log('');
  console.log('Explorer Links:');
  console.log(`  Registry: https://sepolia.starkscan.co/contract/${CONFIG.registryAddress}`);
  console.log(`  Factory:  https://sepolia.starkscan.co/contract/${CONFIG.factoryAddress}`);
  console.log('');
}

main().catch(console.error);
