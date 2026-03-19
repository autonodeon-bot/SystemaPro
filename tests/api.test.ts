import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { fetchWithRetry } from '../utils/apiWithRetry'
import { getCached, setCache, invalidateCache } from '../utils/cache'
import { API_BASE } from '../constants'

describe('API_BASE', () => {
  it('определена как строка', () => {
    expect(typeof API_BASE).toBe('string')
  })
})

describe('fetchWithRetry', () => {
  beforeEach(() => {
    vi.restoreAllMocks()
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('возвращает ответ при успешном запросе', async () => {
    const mockResponse = new Response(JSON.stringify({ ok: true }), { status: 200 })
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(mockResponse)

    const result = await fetchWithRetry('https://example.com/api/test')
    expect(result.ok).toBe(true)
    expect(result.status).toBe(200)
  })

  it('повторяет запрос при 500 ошибке сервера', async () => {
    const error500 = new Response('', { status: 500 })
    const success = new Response(JSON.stringify({ ok: true }), { status: 200 })

    vi.spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(error500)
      .mockResolvedValueOnce(success)

    const result = await fetchWithRetry('https://example.com/api/test')
    expect(result.status).toBe(200)
    expect(globalThis.fetch).toHaveBeenCalledTimes(2)
  })

  it('не повторяет при клиентской ошибке (4xx)', async () => {
    const error401 = new Response('Unauthorized', { status: 401 })
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(error401)

    const result = await fetchWithRetry('https://example.com/api/test')
    expect(result.status).toBe(401)
    expect(globalThis.fetch).toHaveBeenCalledTimes(1)
  })

  it('выбрасывает ошибку после исчерпания попыток', async () => {
    const error500 = new Response('', { status: 500 })
    vi.spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(error500)
      .mockResolvedValueOnce(error500)
      .mockResolvedValueOnce(error500)

    await expect(fetchWithRetry('https://example.com/api/test')).rejects.toThrow()
  })
})

describe('cache', () => {
  beforeEach(() => {
    localStorage.clear()
  })

  it('setCache + getCached возвращает сохранённые данные', () => {
    setCache('test-key', { value: 42 })
    const result = getCached<{ value: number }>('test-key')
    expect(result).toEqual({ value: 42 })
  })

  it('getCached возвращает null для несуществующего ключа', () => {
    const result = getCached('nonexistent')
    expect(result).toBeNull()
  })

  it('invalidateCache удаляет данные', () => {
    setCache('to-remove', 'data')
    invalidateCache('to-remove')
    expect(getCached('to-remove')).toBeNull()
  })

  it('getCached возвращает null для просроченных данных', () => {
    setCache('expired', 'data', -1)
    expect(getCached('expired')).toBeNull()
  })
})
