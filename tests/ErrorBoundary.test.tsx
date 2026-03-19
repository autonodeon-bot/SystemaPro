import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useState } from 'react'
import ErrorBoundary from '../components/ErrorBoundary'

function ThrowingChild({ message = 'boom' }: { message?: string }): never {
  throw new Error(message)
}

describe('ErrorBoundary', () => {
  beforeEach(() => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('рендерит дочерние элементы, если ошибки нет', () => {
    render(
      <ErrorBoundary>
        <span>успешный контент</span>
      </ErrorBoundary>
    )
    expect(screen.getByText('успешный контент')).toBeInTheDocument()
  })

  it('перехватывает ошибку и показывает стандартный fallback с сообщением', () => {
    render(
      <ErrorBoundary>
        <ThrowingChild message="тестовая ошибка" />
      </ErrorBoundary>
    )
    expect(screen.getByText('Произошла ошибка')).toBeInTheDocument()
    expect(screen.getByText('тестовая ошибка')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /попробовать снова/i })).toBeInTheDocument()
  })

  it('показывает переданный fallback вместо стандартного UI', () => {
    render(
      <ErrorBoundary fallback={<div>кастомный запасной UI</div>}>
        <ThrowingChild />
      </ErrorBoundary>
    )
    expect(screen.getByText('кастомный запасной UI')).toBeInTheDocument()
    expect(screen.queryByText('Произошла ошибка')).not.toBeInTheDocument()
  })

  it('после «Попробовать снова» снова рендерит детей, если ошибка устранена', async () => {
    const user = userEvent.setup()
    function RecoveryTree() {
      const [broken, setBroken] = useState(true)
      return (
        <div>
          <button type="button" onClick={() => setBroken(false)}>
            исправить
          </button>
          <ErrorBoundary>
            {broken ? <ThrowingChild /> : <span>восстановлено</span>}
          </ErrorBoundary>
        </div>
      )
    }
    render(<RecoveryTree />)
    expect(screen.getByText('Произошла ошибка')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'исправить' }))
    await user.click(screen.getByRole('button', { name: /попробовать снова/i }))
    expect(screen.getByText('восстановлено')).toBeInTheDocument()
  })
})
