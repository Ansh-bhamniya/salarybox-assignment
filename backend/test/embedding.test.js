import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ApiError } from '../src/utils/ApiError.js';
import { DEFAULT_MODEL_VERSION, parseEmbedding, resolveModelVersion } from '../src/utils/embedding.js';

const unit = (n = 192) => Array.from({ length: n }, () => 1 / Math.sqrt(n));

function rejects(fn, message) {
  assert.throws(fn, (err) => err instanceof ApiError && err.status === 400 && (!message || err.message === message));
}

test('resolveModelVersion defaults for app builds that send no version', () => {
  assert.equal(resolveModelVersion(undefined), DEFAULT_MODEL_VERSION);
  assert.equal(resolveModelVersion(''), DEFAULT_MODEL_VERSION);
});

test('resolveModelVersion accepts a known version and rejects anything else', () => {
  assert.equal(resolveModelVersion('mobilefacenet-192-v1'), 'mobilefacenet-192-v1');
  rejects(() => resolveModelVersion('some-other-model'), 'Unsupported face model version');
  rejects(() => resolveModelVersion('constructor')); // not an inherited object property
  rejects(() => resolveModelVersion(42));
});

test('parseEmbedding accepts a valid unit vector, as a JSON string or an array', () => {
  assert.deepEqual(parseEmbedding(JSON.stringify(unit()), DEFAULT_MODEL_VERSION), unit());
  assert.deepEqual(parseEmbedding(unit(), DEFAULT_MODEL_VERSION), unit());
});

test('parseEmbedding rejects malformed JSON and non-arrays', () => {
  rejects(() => parseEmbedding('not json', DEFAULT_MODEL_VERSION), 'embedding must be a JSON array of numbers');
  rejects(() => parseEmbedding('{"a":1}', DEFAULT_MODEL_VERSION), 'embedding must be a JSON array of numbers');
  rejects(() => parseEmbedding('null', DEFAULT_MODEL_VERSION), 'embedding must be a JSON array of numbers');
});

test('parseEmbedding rejects non-numbers and non-finite numbers', () => {
  const withString = [...unit()];
  withString[3] = '0.1';
  rejects(() => parseEmbedding(withString, DEFAULT_MODEL_VERSION), 'embedding must be a JSON array of numbers');
  // 1e999 is valid JSON but parses to Infinity.
  rejects(() => parseEmbedding('[1e999]', DEFAULT_MODEL_VERSION), 'embedding must be a JSON array of numbers');
});

test('parseEmbedding rejects the wrong length (e.g. the legacy 8-value embeddings)', () => {
  rejects(() => parseEmbedding(unit(8), DEFAULT_MODEL_VERSION), 'embedding must have 192 values');
  rejects(() => parseEmbedding([], DEFAULT_MODEL_VERSION), 'embedding must have 192 values');
});

test('parseEmbedding rejects vectors that are not unit length', () => {
  rejects(() => parseEmbedding(unit().map((v) => v * 2), DEFAULT_MODEL_VERSION), 'embedding must be unit length');
  rejects(() => parseEmbedding(new Array(192).fill(0), DEFAULT_MODEL_VERSION), 'embedding must be unit length');
});

test('parseEmbedding tolerates float noise around unit length', () => {
  assert.equal(parseEmbedding(unit().map((v) => v * 1.005), DEFAULT_MODEL_VERSION).length, 192);
});
