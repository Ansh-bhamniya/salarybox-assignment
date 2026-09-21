/**
 * Splits Supabase public storage URLs into `{ bucket: [path, ...] }`, keeping
 * only the buckets in [buckets] (so a URL that is not one of ours is never
 * touched). Anything that does not look like a public object URL is ignored.
 */
export function storagePathsByBucket(urls, buckets) {
  const grouped = {};
  for (const url of new Set(urls)) {
    if (typeof url !== 'string') continue;
    const match = url.match(/\/storage\/v1\/object\/public\/([^/]+)\/([^?#]+)/);
    if (!match) continue;
    const [, bucket, path] = match;
    if (!buckets.includes(bucket)) continue;
    (grouped[bucket] ??= []).push(decodeURIComponent(path));
  }
  return grouped;
}
