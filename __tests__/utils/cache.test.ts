import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { getCached, setCache, invalidateCache } from '../../utils/cache';

const CACHE_PREFIX = 'es_td_ngo_';

describe('cache утилиты', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe('setCache / getCached', () => {
    it('сохраняет и возвращает данные', () => {
      setCache('test-key', { foo: 'bar' });
      const result = getCached<{ foo: string }>('test-key');
      expect(result).toEqual({ foo: 'bar' });
    });

    it('сохраняет строковые данные', () => {
      setCache('str-key', 'hello');
      expect(getCached<string>('str-key')).toBe('hello');
    });

    it('сохраняет массивы', () => {
      setCache('arr-key', [1, 2, 3]);
      expect(getCached<number[]>('arr-key')).toEqual([1, 2, 3]);
    });

    it('сохраняет числа', () => {
      setCache('num-key', 42);
      expect(getCached<number>('num-key')).toBe(42);
    });

    it('сохраняет boolean', () => {
      setCache('bool-key', true);
      expect(getCached<boolean>('bool-key')).toBe(true);
    });

    it('сохраняет null как данные', () => {
      setCache('null-key', null);
      expect(getCached('null-key')).toBeNull();
    });

    it('использует правильный префикс ключа', () => {
      setCache('my-key', 'value');
      const raw = localStorage.getItem(CACHE_PREFIX + 'my-key');
      expect(raw).not.toBeNull();
      const parsed = JSON.parse(raw!);
      expect(parsed.data).toBe('value');
    });
  });

  describe('TTL (время жизни)', () => {
    it('данные доступны в пределах TTL', () => {
      setCache('ttl-key', 'alive', 10000);

      vi.advanceTimersByTime(5000);

      expect(getCached('ttl-key')).toBe('alive');
    });

    it('данные удаляются после истечения TTL', () => {
      setCache('ttl-key', 'expired', 5000);

      vi.advanceTimersByTime(5001);

      expect(getCached('ttl-key')).toBeNull();
    });

    it('данные удаляются ровно на границе TTL', () => {
      setCache('edge-key', 'value', 1000);

      vi.advanceTimersByTime(1001);

      expect(getCached('edge-key')).toBeNull();
    });

    it('использует TTL по умолчанию 5 минут', () => {
      setCache('default-ttl', 'data');

      vi.advanceTimersByTime(4 * 60 * 1000);
      expect(getCached('default-ttl')).toBe('data');

      vi.advanceTimersByTime(2 * 60 * 1000);
      expect(getCached('default-ttl')).toBeNull();
    });

    it('поддерживает кастомный TTL', () => {
      setCache('custom-ttl', 'data', 60000);

      vi.advanceTimersByTime(30000);
      expect(getCached('custom-ttl')).toBe('data');

      vi.advanceTimersByTime(31000);
      expect(getCached('custom-ttl')).toBeNull();
    });
  });

  describe('getCached', () => {
    it('возвращает null для несуществующего ключа', () => {
      expect(getCached('nonexistent')).toBeNull();
    });

    it('возвращает null для повреждённых данных', () => {
      localStorage.setItem(CACHE_PREFIX + 'bad', 'not-json');
      expect(getCached('bad')).toBeNull();
    });

    it('удаляет просроченную запись из localStorage', () => {
      setCache('cleanup', 'old', 1000);

      vi.advanceTimersByTime(2000);

      getCached('cleanup');

      expect(localStorage.getItem(CACHE_PREFIX + 'cleanup')).toBeNull();
    });
  });

  describe('invalidateCache', () => {
    it('удаляет запись из кэша', () => {
      setCache('to-remove', 'data');
      expect(getCached('to-remove')).toBe('data');

      invalidateCache('to-remove');
      expect(getCached('to-remove')).toBeNull();
    });

    it('не выбрасывает ошибку для несуществующего ключа', () => {
      expect(() => invalidateCache('no-such-key')).not.toThrow();
    });

    it('не затрагивает другие ключи', () => {
      setCache('keep-this', 'keep');
      setCache('remove-this', 'remove');

      invalidateCache('remove-this');

      expect(getCached('keep-this')).toBe('keep');
      expect(getCached('remove-this')).toBeNull();
    });
  });

  describe('изоляция ключей', () => {
    it('разные ключи хранят независимые данные', () => {
      setCache('key-a', 'alpha');
      setCache('key-b', 'beta');

      expect(getCached('key-a')).toBe('alpha');
      expect(getCached('key-b')).toBe('beta');
    });

    it('перезапись ключа обновляет данные', () => {
      setCache('overwrite', 'old');
      setCache('overwrite', 'new');

      expect(getCached('overwrite')).toBe('new');
    });

    it('перезапись обновляет TTL', () => {
      setCache('refresh', 'v1', 5000);

      vi.advanceTimersByTime(4000);
      setCache('refresh', 'v2', 5000);

      vi.advanceTimersByTime(4000);
      expect(getCached('refresh')).toBe('v2');
    });
  });
});
