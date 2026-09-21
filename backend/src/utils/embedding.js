import { ApiError } from './ApiError.js';

// Face-model versions the server accepts, and the embedding length each one
// produces. Templates are only ever compared within one version.
export const MODEL_VERSIONS = {
  'mobilefacenet-192-v1': { dimension: 192 },
};

// App builds that predate model versioning don't send one.
export const DEFAULT_MODEL_VERSION = 'mobilefacenet-192-v1';

// The app L2-normalises embeddings, so their length should be 1 (within float
// noise). Anything else is a malformed or tampered upload.
const UNIT_NORM_TOLERANCE = 0.02;

export function resolveModelVersion(raw) {
  const version = raw === undefined || raw === '' ? DEFAULT_MODEL_VERSION : raw;
  if (typeof version !== 'string' || !Object.hasOwn(MODEL_VERSIONS, version)) {
    throw new ApiError(400, 'Unsupported face model version');
  }
  return version;
}

/** Accepts the JSON string the app sends (or an already-parsed array) and returns a validated number[]. */
export function parseEmbedding(raw, modelVersion) {
  let value = raw;
  if (typeof raw === 'string') {
    try {
      value = JSON.parse(raw);
    } catch {
      throw new ApiError(400, 'embedding must be a JSON array of numbers');
    }
  }

  if (!Array.isArray(value) || value.some((n) => typeof n !== 'number' || !Number.isFinite(n))) {
    throw new ApiError(400, 'embedding must be a JSON array of numbers');
  }

  const { dimension } = MODEL_VERSIONS[modelVersion];
  if (value.length !== dimension) {
    throw new ApiError(400, `embedding must have ${dimension} values`);
  }

  const norm = Math.sqrt(value.reduce((sum, n) => sum + n * n, 0));
  if (Math.abs(norm - 1) > UNIT_NORM_TOLERANCE) {
    throw new ApiError(400, 'embedding must be unit length');
  }

  return value;
}

export const MAX_TEMPLATES_PER_ENROLMENT = 5;

/** Accepts a JSON string (or array) holding 1..5 embeddings and returns them validated. */
export function parseEmbeddingSet(raw, modelVersion) {
  let value = raw;
  if (typeof raw === 'string') {
    try {
      value = JSON.parse(raw);
    } catch {
      throw new ApiError(400, 'embeddings must be a JSON array of embeddings');
    }
  }

  if (!Array.isArray(value) || value.length < 1 || value.length > MAX_TEMPLATES_PER_ENROLMENT) {
    throw new ApiError(400, `embeddings must contain 1 to ${MAX_TEMPLATES_PER_ENROLMENT} embeddings`);
  }
  return value.map((embedding) => parseEmbedding(embedding, modelVersion));
}
