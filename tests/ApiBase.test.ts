import { afterEach, describe, expect, it, vi } from 'vitest';

afterEach(() => {
  vi.unstubAllEnvs();
  vi.resetModules();
});

describe('адрес API в опубликованной сборке', () => {
  it.each(['http://127.0.0.1:8010', 'http://localhost:8000', 'https://other-server.example', ''])
    ('использует текущий хост даже при VITE_API_BASE=%s', async (configured) => {
      vi.stubEnv('DEV', false);
      vi.stubEnv('VITE_API_BASE', configured);
      const { API_BASE } = await import('../constants');
      expect(API_BASE).toBe('');
    });

  it('сохраняет отдельный адрес локального API в dev', async () => {
    vi.stubEnv('DEV', true);
    vi.stubEnv('VITE_API_BASE', 'http://127.0.0.1:8010/');
    const { API_BASE } = await import('../constants');
    expect(API_BASE).toBe('http://127.0.0.1:8010');
  });
});
