import { describe, it, expect, beforeEach } from 'vitest'
import { getCached, setCache, invalidateCache } from '../utils/cache'
import { API_BASE } from '../constants'

describe('API_BASE', () => {
  it('определена как строка', () => {
    expect(typeof API_BASE).toBe('string')
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
