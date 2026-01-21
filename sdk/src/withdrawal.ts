import type { WithdrawalPlanOptions, WithdrawalStep } from './types.js';

function randomFraction(): number {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return buf[0] / 0xffffffff;
}

function randomDelay(minMs: number, maxMs: number): number {
  if (maxMs <= minMs) {
    return minMs;
  }
  const t = randomFraction();
  return Math.floor(minMs + t * (maxMs - minMs));
}

/**
 * Create a withdrawal plan with randomized delays and amount splits.
 */
export function planWithdrawals(
  totalAmount: bigint,
  options: WithdrawalPlanOptions = {}
): WithdrawalStep[] {
  if (totalAmount <= 0n) {
    throw new Error('totalAmount must be positive');
  }

  const splits = Math.max(1, Math.floor(options.splits ?? 1));
  const minDelayMs = Math.max(0, Math.floor(options.minDelayMs ?? 0));
  const maxDelayMs = Math.max(minDelayMs, Math.floor(options.maxDelayMs ?? minDelayMs));

  if (splits === 1 || totalAmount < BigInt(splits)) {
    return [{ amount: totalAmount, delayMs: randomDelay(minDelayMs, maxDelayMs) }];
  }

  const weights = Array.from({ length: splits }, () => randomFraction());
  const weightSum = weights.reduce((acc, w) => acc + w, 0);

  let remaining = totalAmount;
  const steps: WithdrawalStep[] = [];

  for (let i = 0; i < splits; i++) {
    const isLast = i === splits - 1;
    const scaledWeight = Math.max(1, Math.floor((weights[i] / weightSum) * 1_000_000_000));
    const amount = isLast
      ? remaining
      : (totalAmount * BigInt(scaledWeight)) / 1_000_000_000n;

    remaining -= amount;
    steps.push({
      amount,
      delayMs: randomDelay(minDelayMs, maxDelayMs),
    });
  }

  return steps;
}
