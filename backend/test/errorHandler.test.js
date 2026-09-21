import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ApiError } from '../src/utils/ApiError.js';
import { errorHandler } from '../src/middleware/errorHandler.js';

function run(err) {
  const res = {
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
  errorHandler(err, {}, res, () => {});
  return res;
}

test('an ApiError with a code responds with both the message and the code', () => {
  const res = run(new ApiError(409, 'Your face is not enrolled yet.', 'not_enrolled'));
  assert.equal(res.statusCode, 409);
  assert.deepEqual(res.body, { error: 'Your face is not enrolled yet.', code: 'not_enrolled' });
});

test('an ApiError without a code keeps the original { error } shape', () => {
  const res = run(new ApiError(404, 'Staff not found'));
  assert.equal(res.statusCode, 404);
  assert.deepEqual(res.body, { error: 'Staff not found' });
});

test('an ApiError with details passes them through', () => {
  const details = { matches: [{ employeeId: 'E-1', similarity: 0.83 }] };
  const res = run(new ApiError(409, 'This face looks like an already enrolled staff member', 'duplicate_face', details));
  assert.equal(res.statusCode, 409);
  assert.deepEqual(res.body, {
    error: 'This face looks like an already enrolled staff member',
    code: 'duplicate_face',
    details,
  });
});
