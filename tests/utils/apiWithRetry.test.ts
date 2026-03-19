import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { fetchWithRetry } from '../../utils/apiWithRetry'

describe('fetchWithRetry', () => {
  beforeEach(() => {
    vi.restoreAllMocks()
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.restoreAllMocks()
  })

  it('возвращает ответ при первом успешном запросе', async () => {
    const ok = new Response(JSON.stringify({ a: 1 }), { status: 200 })
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(ok)
    const res = await fetchWithRetry('https://example.com/x')
    expect(res.ok).toBe(true)
    expect(res.status).toBe(200)
    expect(globalThis.fetch).toHaveBeenCalledTimes(1)
  })

  it('не повторяет запрос при ответе 4xx', async () => {
    const res401 = new Response('nope', { status: 401 })
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(res401)
    const res = await fetchWithRetry('https://example.com/x')
    expect(res.status).toBe(401)
    expect(globalThis.fetch).toHaveBeenCalledTimes(1)
  })

  it('повторяет запрос при 500 и возвращает успешный ответ со второй попытки', async () => {
    vi.useFakeTimers()
    const fail = new Response('', { status: 500 })
    const ok = new Response('ok', { status: 200 })
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(fail).mockResolvedValueOnce(ok)
    const p = fetchWithRetry('https://example.com/x')
    await vi.advanceTimersByTimeAsync(1000)
    const res = await p
    expect(res.status).toBe(200)
    expect(globalThis.fetch).toHaveBeenCalledTimes(2)
  })

  it('увеличивает задержку между повторными попытками', async () => {
    vi.useFakeTimers()
    const fail = new Response('', { status: 503 })
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(fail)
    const p = fetchWithRetry('https://example.com/x')
    const rejected = expect(p).rejects.toThrow('HTTP 503')
    expect(globalThis.fetch).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(999)
    expect(globalThis.fetch).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(1)
    expect(globalThis.fetch).toHaveBeenCalledTimes(2)
    await vi.advanceTimersByTimeAsync(1999)
    expect(globalThis.fetch).toHaveBeenCalledTimes(2)
    await vi.advanceTimersByTimeAsync(1)
    expect(globalThis.fetch).toHaveBeenCalledTimes(3)
    await rejected
  })

  it('повторяет при сетевой ошибке fetch и затем возвращает ответ', async () => {
    vi.useFakeTimers()
    const ok = new Response('ok', { status: 200 })
    vi.spyOn(globalThis, 'fetch')
      .mockRejectedValueOnce(new TypeError('network failed'))
      .mockResolvedValueOnce(ok)
    const p = fetchWithRetry('https://example.com/x')
    await vi.advanceTimersByTimeAsync(1000)
    const res = await p
    expect(res.ok).toBe(true)
    expect(globalThis.fetch).toHaveBeenCalledTimes(2)
  })

  it('после трёх неудачных попыток выбрасывает последнюю ошибку', async () => {
    vi.useFakeTimers()
    const fail = new Response('', { status: 500 })
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(fail)
    const p = fetchWithRetry('https://example.com/x')
    const rejected = expect(p).rejects.toThrow('HTTP 500')
    await vi.runAllTimersAsync()
    await rejected
    expect(globalThis.fetch).toHaveBeenCalledTimes(3)
  })

  it('пробрасывает последнюю сетевую ошибку после исчерпания попыток', async () => {
    vi.useFakeTimers()
    const err = new TypeError('network down')
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(err)
    const p = fetchWithRetry('https://example.com/x')
    const rejected = expect(p).rejects.toThrow('network down')
    await vi.runAllTimersAsync()
    await rejected
    expect(globalThis.fetch).toHaveBeenCalledTimes(3)
  })

  it('передаёт options в fetch', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 204 }))
    const init = { method: 'POST', headers: { 'X-Test': '1' } }
    await fetchWithRetry('https://example.com/x', init)
    expect(globalThis.fetch).toHaveBeenCalledWith('https://example.com/x', init)
  })
})
