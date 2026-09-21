import { test } from 'node:test';
import assert from 'node:assert/strict';
import { storagePathsByBucket } from '../src/utils/storage-paths.js';

const buckets = ['enrollment-photos', 'attendance-selfies'];
const base = 'https://abc.supabase.co/storage/v1/object/public';

test('groups public URLs by bucket and returns the paths inside each', () => {
  const grouped = storagePathsByBucket(
    [`${base}/enrollment-photos/a.jpg`, `${base}/attendance-selfies/b.jpg`, `${base}/enrollment-photos/c.jpg`],
    buckets,
  );
  assert.deepEqual(grouped, {
    'enrollment-photos': ['a.jpg', 'c.jpg'],
    'attendance-selfies': ['b.jpg'],
  });
});

test('the same URL twice is listed once', () => {
  const url = `${base}/enrollment-photos/a.jpg`;
  assert.deepEqual(storagePathsByBucket([url, url], buckets), { 'enrollment-photos': ['a.jpg'] });
});

test('a bucket that is not ours is never touched', () => {
  assert.deepEqual(storagePathsByBucket([`${base}/somebody-elses/a.jpg`], buckets), {});
});

test('empty, missing and unrelated values are ignored', () => {
  assert.deepEqual(storagePathsByBucket([null, undefined, '', 'https://example.com/a.jpg', 42], buckets), {});
});

test('a query string is not part of the path, and encoded characters are decoded', () => {
  const grouped = storagePathsByBucket([`${base}/attendance-selfies/my%20file.jpg?t=1`], buckets);
  assert.deepEqual(grouped, { 'attendance-selfies': ['my file.jpg'] });
});
