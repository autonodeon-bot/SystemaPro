const CACHE_PREFIX = 'es_td_ngo_';
const TTL_MS = 5 * 60 * 1000; // 5 min

interface CacheEntry<T> {
  data: T;
  expiry: number;
}

export function getCached<T>(key: string): T | null {
  try {
    const raw = localStorage.getItem(CACHE_PREFIX + key);
    if (!raw) return null;
    const entry: CacheEntry<T> = JSON.parse(raw);
    if (Date.now() > entry.expiry) {
      localStorage.removeItem(CACHE_PREFIX + key);
      return null;
    }
    return entry.data;
  } catch {
    return null;
  }
}

export function setCache<T>(key: string, data: T, ttlMs = TTL_MS): void {
  try {
    const entry: CacheEntry<T> = { data, expiry: Date.now() + ttlMs };
    localStorage.setItem(CACHE_PREFIX + key, JSON.stringify(entry));
  } catch {
    /* ignore */
  }
}

export function invalidateCache(key: string): void {
  localStorage.removeItem(CACHE_PREFIX + key);
}
