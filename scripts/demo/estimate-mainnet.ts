import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { config as loadEnv } from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const envPath = path.join(__dirname, '../../.env');
loadEnv({ path: envPath });

const MAINNET_RPC_URL =
  process.env.MAINNET_RPC_URL
  || process.env.RPC_URL_MAINNET
  || 'https://starknet-mainnet.g.alchemy.com/starknet/version/rpc/v0_10/cf52O0RwFy1mEB0uoYsel';
const defaultSourcePath = path.join(__dirname, '../../deployments/sepolia_costs.json');
const sourcePath = process.env.SEPOLIA_COSTS_PATH || defaultSourcePath;
const outputPath = path.join(__dirname, '../../deployments/mainnet_estimate.json');

type GasPrices = {
  l1GasPriceFri: bigint;
  l1DataGasPriceFri: bigint;
  l2GasPriceFri: bigint;
  sources: {
    l1: string;
    l1Data: string;
    l2: string;
  };
};

function toBigInt(value: unknown): bigint {
  if (typeof value === 'bigint') return value;
  if (typeof value === 'number') return BigInt(value);
  if (typeof value === 'string') {
    return value.startsWith('0x') ? BigInt(value) : BigInt(value);
  }
  throw new Error(`Unsupported numeric value: ${String(value)}`);
}

function pickPrice(priceObj: any, label: string): { value: bigint; source: string } {
  if (priceObj === null || priceObj === undefined) {
    throw new Error(`Missing gas price for ${label}`);
  }
  if (typeof priceObj === 'string' || typeof priceObj === 'number' || typeof priceObj === 'bigint') {
    return { value: toBigInt(priceObj), source: 'direct' };
  }
  if (priceObj.price_in_fri !== undefined) {
    return { value: toBigInt(priceObj.price_in_fri), source: 'price_in_fri' };
  }
  if (priceObj.price_in_wei !== undefined) {
    return { value: toBigInt(priceObj.price_in_wei), source: 'price_in_wei' };
  }
  throw new Error(`Unsupported gas price object for ${label}`);
}

async function fetchJsonRpc(method: string, params: unknown[]) {
  const res = await fetch(MAINNET_RPC_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: Date.now(),
      method,
      params,
    }),
  });
  const body = await res.json();
  if (body.error) {
    throw new Error(body.error.message || 'RPC error');
  }
  return body.result;
}

async function getMainnetGasPrices(): Promise<GasPrices> {
  const block = await fetchJsonRpc('starknet_getBlockWithTxHashes', ['latest']);
  const header = block?.block_header || block;

  const l1Gas = header?.l1_gas_price ?? header?.l1GasPrice;
  const l1Data = header?.l1_data_gas_price ?? header?.l1DataGasPrice;
  const l2Gas = header?.l2_gas_price ?? header?.l2GasPrice;

  const l1 = pickPrice(l1Gas, 'l1_gas_price');
  const l1DataPicked = pickPrice(l1Data, 'l1_data_gas_price');
  const l2 = pickPrice(l2Gas, 'l2_gas_price');

  return {
    l1GasPriceFri: l1.value,
    l1DataGasPriceFri: l1DataPicked.value,
    l2GasPriceFri: l2.value,
    sources: {
      l1: l1.source,
      l1Data: l1DataPicked.source,
      l2: l2.source,
    },
  };
}

function formatStrk(amountFri: bigint): string {
  const str = amountFri.toString().padStart(19, '0');
  const whole = str.slice(0, -18);
  const frac = str.slice(-18);
  return `${whole}.${frac}`.replace(/\.?0+$/, '');
}

function sumFees(entries: Array<{ feeFri: bigint }>): bigint {
  return entries.reduce((acc, e) => acc + e.feeFri, 0n);
}

async function main() {
  if (!fs.existsSync(sourcePath)) {
    throw new Error(`Missing sepolia costs file: ${sourcePath}`);
  }

  const sepolia = JSON.parse(fs.readFileSync(sourcePath, 'utf-8'));
  const prices = await getMainnetGasPrices();

  const rows = Object.entries(sepolia.transactions).map(([name, tx]: any) => {
    const resources = tx?.costs?.executionResources || {};
    const l2Gas = BigInt(resources.l2_gas || 0);
    const l1Gas = BigInt(resources.l1_gas || 0);
    const l1DataGas = BigInt(resources.l1_data_gas || 0);
    const feeFri =
      l2Gas * prices.l2GasPriceFri
      + l1Gas * prices.l1GasPriceFri
      + l1DataGas * prices.l1DataGasPriceFri;
    return {
      name,
      l2Gas,
      l1Gas,
      l1DataGas,
      feeFri,
    };
  });

  const totalFeeFri = sumFees(rows);
  const output = {
    network: 'mainnet',
    timestamp: new Date().toISOString(),
    source: path.relative(process.cwd(), sourcePath),
    rpcUrl: MAINNET_RPC_URL,
    gasPrices: {
      l1GasPriceFri: prices.l1GasPriceFri.toString(),
      l1DataGasPriceFri: prices.l1DataGasPriceFri.toString(),
      l2GasPriceFri: prices.l2GasPriceFri.toString(),
      sources: prices.sources,
    },
    estimates: rows.map((row) => ({
      step: row.name,
      l2Gas: row.l2Gas.toString(),
      l1Gas: row.l1Gas.toString(),
      l1DataGas: row.l1DataGas.toString(),
      feeFri: row.feeFri.toString(),
      feeStrk: formatStrk(row.feeFri),
    })),
    total: {
      feeFri: totalFeeFri.toString(),
      feeStrk: formatStrk(totalFeeFri),
    },
  };

  fs.writeFileSync(outputPath, JSON.stringify(output, null, 2));

  console.log('[OK] Mainnet estimate written to', outputPath);
  console.log('[i] Total estimated fee (STRK):', output.total.feeStrk);
}

main().catch((err) => {
  console.error('[X] Mainnet estimate failed:', err.message);
  process.exit(1);
});
