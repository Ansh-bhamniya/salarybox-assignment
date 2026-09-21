import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ApiError } from '../src/utils/ApiError.js';
import { ATTEMPT_OUTCOMES, parseAttempt, parseLiveness } from '../src/utils/liveness.js';

const valid = () => ({
  version: 1,
  challenge: ['left', 'right'],
  durationMs: 4200,
  peakYaws: [-19.4, 21.1],
  peakTurnRatios: [0.253, -0.281],
  baselineYaw: 1.2,
  baselineRatio: 0.06,
  sameFaceMin: 0.71,
});

function rejects(fn, message) {
  assert.throws(fn, (err) => err instanceof ApiError && err.status === 400 && (!message || err.message.includes(message)));
}

test('parseLiveness accepts what the app sends, as a JSON string or an object', () => {
  assert.deepEqual(parseLiveness(JSON.stringify(valid())), valid());
  assert.deepEqual(parseLiveness(valid()), valid());
});

test('parseLiveness keeps only the known fields, so nothing else can be stored', () => {
  const noisy = { ...valid(), notes: 'x'.repeat(100), admin: true, nested: { a: 1 } };
  assert.deepEqual(parseLiveness(noisy), valid());
});

test('a null same-face score is fine (nothing to compare)', () => {
  assert.equal(parseLiveness({ ...valid(), sameFaceMin: null }).sameFaceMin, null);
  const { sameFaceMin, ...without } = valid();
  assert.equal(parseLiveness(without).sameFaceMin, null);
});

test('parseLiveness rejects what is not a JSON object', () => {
  rejects(() => parseLiveness('not json'), 'JSON object');
  rejects(() => parseLiveness('[1,2]'), 'JSON object');
  rejects(() => parseLiveness('null'), 'JSON object');
  rejects(() => parseLiveness(42), 'JSON object');
});

test('parseLiveness rejects a payload that is too large', () => {
  rejects(() => parseLiveness(JSON.stringify({ ...valid(), pad: 'x'.repeat(3000) })), 'too large');
});

test('parseLiveness rejects an unknown version', () => {
  rejects(() => parseLiveness({ ...valid(), version: 2 }), 'version');
  const { version, ...without } = valid();
  rejects(() => parseLiveness(without), 'version');
});

test('parseLiveness rejects a bad challenge', () => {
  rejects(() => parseLiveness({ ...valid(), challenge: [] }), 'challenge');
  rejects(() => parseLiveness({ ...valid(), challenge: ['left', 'up'] }), 'challenge');
  rejects(() => parseLiveness({ ...valid(), challenge: ['left', 'right', 'left', 'right', 'left'] }), 'challenge');
  rejects(() => parseLiveness({ ...valid(), challenge: 'left' }), 'challenge');
});

test('parseLiveness rejects an implausible duration', () => {
  rejects(() => parseLiveness({ ...valid(), durationMs: 10 }), 'durationMs');
  rejects(() => parseLiveness({ ...valid(), durationMs: 999999 }), 'durationMs');
  rejects(() => parseLiveness({ ...valid(), durationMs: '4200' }), 'durationMs');
  rejects(() => parseLiveness({ ...valid(), durationMs: null }), 'durationMs');
});

test('parseLiveness needs one peak per turn, all sensible numbers', () => {
  rejects(() => parseLiveness({ ...valid(), peakYaws: [10] }), 'peakYaws');
  rejects(() => parseLiveness({ ...valid(), peakYaws: [10, 999] }), 'peakYaws');
  rejects(() => parseLiveness({ ...valid(), peakYaws: [10, 'a'] }), 'peakYaws');
  rejects(() => parseLiveness({ ...valid(), peakTurnRatios: [0.2, 9] }), 'peakTurnRatios');
  rejects(() => parseLiveness({ ...valid(), peakTurnRatios: [0.2, null] }), 'peakTurnRatios');
});

test('parseLiveness rejects non-finite numbers (which JSON cannot carry, but 1e999 parses to Infinity)', () => {
  rejects(() => parseLiveness('{"version":1,"challenge":["left"],"durationMs":1e999,"peakYaws":[1],"peakTurnRatios":[0.2],"baselineYaw":0,"baselineRatio":0}'), 'durationMs');
});

test('parseLiveness rejects a bad baseline or same-face score', () => {
  rejects(() => parseLiveness({ ...valid(), baselineYaw: 500 }), 'baselineYaw');
  rejects(() => parseLiveness({ ...valid(), baselineRatio: 'x' }), 'baselineRatio');
  rejects(() => parseLiveness({ ...valid(), sameFaceMin: 1.5 }), 'sameFaceMin');
  rejects(() => parseLiveness({ ...valid(), sameFaceMin: 'high' }), 'sameFaceMin');
});

test('parseAttempt accepts the known outcomes, with or without a reason', () => {
  assert.deepEqual(parseAttempt({ outcome: 'liveness_failed', reason: 'wrongDirection' }), {
    outcome: 'liveness_failed',
    reason: 'wrongDirection',
  });
  assert.deepEqual(parseAttempt({ outcome: 'no_match' }), { outcome: 'no_match', reason: null });
  assert.deepEqual(parseAttempt({ outcome: 'no_match', reason: null }), { outcome: 'no_match', reason: null });
  for (const outcome of ATTEMPT_OUTCOMES) assert.equal(parseAttempt({ outcome }).outcome, outcome);
});

test('parseAttempt rejects anything else, including outcomes only the server may write', () => {
  rejects(() => parseAttempt({ outcome: 'not_enrolled' }), 'outcome');
  rejects(() => parseAttempt({ outcome: 'passed' }), 'outcome');
  rejects(() => parseAttempt({}), 'outcome');
  rejects(() => parseAttempt(undefined), 'outcome');
  rejects(() => parseAttempt('liveness_failed'), 'outcome');
  rejects(() => parseAttempt([]), 'outcome');
});

test('parseAttempt rejects a reason that is not a short word', () => {
  rejects(() => parseAttempt({ outcome: 'no_match', reason: 'has spaces' }), 'reason');
  rejects(() => parseAttempt({ outcome: 'no_match', reason: 'x'.repeat(41) }), 'reason');
  rejects(() => parseAttempt({ outcome: 'no_match', reason: 7 }), 'reason');
  rejects(() => parseAttempt({ outcome: 'no_match', reason: "'; drop table" }), 'reason');
});
