import { ApiError } from './ApiError.js';

const SIDES = ['left', 'right'];
const MAX_PAYLOAD_BYTES = 2048;

/** Outcomes the app may report for a failed check. */
export const ATTEMPT_OUTCOMES = ['liveness_failed', 'no_match'];

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const isNumber = (value) => typeof value === 'number' && Number.isFinite(value);

function bad(message) {
  return new ApiError(400, message);
}

function numbers(value, name, { count, limit }) {
  if (!Array.isArray(value) || value.length !== count || !value.every((n) => isNumber(n) && Math.abs(n) <= limit)) {
    throw bad(`liveness.${name} must be ${count} numbers within ±${limit}`);
  }
  return value;
}

/**
 * Validates what the app says its head-turn check saw (the JSON string the app
 * sends, or an already-parsed object) and returns just the known fields. Nothing
 * else is stored, and the size is capped, so it cannot be used to stuff the
 * database.
 */
export function parseLiveness(raw) {
  let value = raw;
  if (typeof raw === 'string') {
    if (Buffer.byteLength(raw) > MAX_PAYLOAD_BYTES) throw bad('liveness is too large');
    try {
      value = JSON.parse(raw);
    } catch {
      throw bad('liveness must be a JSON object');
    }
  }
  if (!isObject(value)) throw bad('liveness must be a JSON object');
  if (value.version !== 1) throw bad('unsupported liveness version');

  const { challenge } = value;
  if (!Array.isArray(challenge) || challenge.length < 1 || challenge.length > 4 || !challenge.every((s) => SIDES.includes(s))) {
    throw bad("liveness.challenge must be 1 to 4 turns, each 'left' or 'right'");
  }
  if (!isNumber(value.durationMs) || value.durationMs < 300 || value.durationMs > 120000) {
    throw bad('liveness.durationMs must be between 300 and 120000');
  }
  const peakYaws = numbers(value.peakYaws, 'peakYaws', { count: challenge.length, limit: 180 });
  const peakTurnRatios = numbers(value.peakTurnRatios, 'peakTurnRatios', { count: challenge.length, limit: 2 });
  if (!isNumber(value.baselineYaw) || Math.abs(value.baselineYaw) > 90) throw bad('liveness.baselineYaw is invalid');
  if (!isNumber(value.baselineRatio) || Math.abs(value.baselineRatio) > 2) throw bad('liveness.baselineRatio is invalid');

  const sameFaceMin = value.sameFaceMin ?? null;
  if (sameFaceMin !== null && (!isNumber(sameFaceMin) || sameFaceMin < -1 || sameFaceMin > 1)) {
    throw bad('liveness.sameFaceMin must be between -1 and 1, or null');
  }

  return {
    version: 1,
    challenge,
    durationMs: value.durationMs,
    peakYaws,
    peakTurnRatios,
    baselineYaw: value.baselineYaw,
    baselineRatio: value.baselineRatio,
    sameFaceMin,
  };
}

/** Validates a report of a failed check: `{ outcome, reason? }`. */
export function parseAttempt(body) {
  if (!isObject(body)) throw bad('outcome is required');

  const { outcome, reason } = body;
  if (!ATTEMPT_OUTCOMES.includes(outcome)) {
    throw bad(`outcome must be one of: ${ATTEMPT_OUTCOMES.join(', ')}`);
  }
  if (reason !== undefined && reason !== null && (typeof reason !== 'string' || !/^[a-zA-Z_]{1,40}$/.test(reason))) {
    throw bad('reason must be a short word such as "timeout"');
  }
  return { outcome, reason: reason ?? null };
}
