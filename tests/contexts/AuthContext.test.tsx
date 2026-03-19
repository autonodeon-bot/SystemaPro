import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { AuthProvider, useAuth } from '../../contexts/AuthContext'

vi.mock('../../constants', () => ({
  API_BASE: 'http://test-api',
}))

const baseUser = {
  id: 'u1',
  username: 'tester',
  email: 't@test.ru',
  full_name: 'Test User',
  role: 'engineer',
  permissions: ['reports:read'],
}

function AuthConsumer() {
  const { user, token, loading, login, logout, isAuthenticated, getToken, hasRole, hasPermission } =
    useAuth()
  return (
    <div>
      <span data-testid="loading">{loading ? 'yes' : 'no'}</span>
      <span data-testid="auth">{isAuthenticated ? 'in' : 'out'}</span>
      <span data-testid="user">{user?.username ?? 'none'}</span>
      <span data-testid="token">{token ?? 'none'}</span>
      <span data-testid="getToken">{getToken() ?? 'none'}</span>
      <span data-testid="hasAdmin">{hasRole('admin') ? 'yes' : 'no'}</span>
      <span data-testid="hasPerm">{hasPermission('reports:read') ? 'yes' : 'no'}</span>
      <button type="button" onClick={() => login('u', 'p')}>
        login
      </button>
      <button type="button" onClick={() => logout()}>
        logout
      </button>
    </div>
  )
}

describe('AuthContext', () => {
  beforeEach(() => {
    localStorage.clear()
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify(baseUser), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    )
  })

  afterEach(() => {
    vi.restoreAllMocks()
    localStorage.clear()
  })

  it('useAuth вне AuthProvider выбрасывает ошибку', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    expect(() => render(<AuthConsumer />)).toThrow('useAuth must be used within an AuthProvider')
    spy.mockRestore()
  })

  it('после монтирования без сохранённых данных loading становится false и пользователь не авторизован', async () => {
    vi.mocked(fetch).mockResolvedValue(
      new Response(JSON.stringify(baseUser), { status: 200, headers: { 'Content-Type': 'application/json' } })
    )
    render(
      <AuthProvider>
        <AuthConsumer />
      </AuthProvider>
    )
    await waitFor(() => expect(screen.getByTestId('loading')).toHaveTextContent('no'))
    expect(screen.getByTestId('auth')).toHaveTextContent('out')
  })

  it('login сохраняет токен и пользователя в localStorage при успешном ответе', async () => {
    const user = userEvent.setup()
    vi.mocked(fetch)
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ access_token: 'jwt-123' }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify(baseUser), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      )
    render(
      <AuthProvider>
        <AuthConsumer />
      </AuthProvider>
    )
    await waitFor(() => expect(screen.getByTestId('loading')).toHaveTextContent('no'))
    await user.click(screen.getByRole('button', { name: 'login' }))
    await waitFor(() => {
      expect(localStorage.getItem('token')).toBe('jwt-123')
      expect(JSON.parse(localStorage.getItem('user')!)).toMatchObject({ username: 'tester' })
      expect(screen.getByTestId('auth')).toHaveTextContent('in')
      expect(screen.getByTestId('token')).toHaveTextContent('jwt-123')
    })
  })

  it('login пробрасывает ошибку при неверных учётных данных', async () => {
    const user = userEvent.setup()
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify({ detail: 'Неверный логин или пароль' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    )
    const onError = vi.fn()
    function LoginWithCatch() {
      const { login, loading } = useAuth()
      const run = async () => {
        try {
          await login('bad', 'bad')
        } catch (e) {
          onError((e as Error).message)
        }
      }
      return (
        <div>
          <span data-testid="loading">{loading ? 'yes' : 'no'}</span>
          <button type="button" onClick={run}>
            try-login
          </button>
        </div>
      )
    }
    render(
      <AuthProvider>
        <LoginWithCatch />
      </AuthProvider>
    )
    await waitFor(() => expect(screen.getByTestId('loading')).toHaveTextContent('no'))
    await user.click(screen.getByRole('button', { name: 'try-login' }))
    await waitFor(() => {
      expect(onError).toHaveBeenCalledWith('Неверный логин или пароль')
    })
    expect(localStorage.getItem('token')).toBeNull()
  })

  it('logout очищает состояние и localStorage', async () => {
    const user = userEvent.setup()
    vi.mocked(fetch)
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ access_token: 'jwt-123' }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify(baseUser), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      )
    render(
      <AuthProvider>
        <AuthConsumer />
      </AuthProvider>
    )
    await waitFor(() => expect(screen.getByTestId('loading')).toHaveTextContent('no'))
    await user.click(screen.getByRole('button', { name: 'login' }))
    await waitFor(() => expect(screen.getByTestId('auth')).toHaveTextContent('in'))
    await user.click(screen.getByRole('button', { name: 'logout' }))
    await waitFor(() => {
      expect(screen.getByTestId('auth')).toHaveTextContent('out')
      expect(localStorage.getItem('token')).toBeNull()
      expect(localStorage.getItem('user')).toBeNull()
    })
  })

  it('getToken возвращает токен из localStorage, если state ещё пустой', async () => {
    localStorage.setItem('token', 'only-storage')
    render(
      <AuthProvider>
        <AuthConsumer />
      </AuthProvider>
    )
    await waitFor(() => expect(screen.getByTestId('loading')).toHaveTextContent('no'))
    expect(screen.getByTestId('getToken')).toHaveTextContent('only-storage')
  })

  it('hasRole и hasPermission отражают данные пользователя после входа', async () => {
    const user = userEvent.setup()
    const adminUser = { ...baseUser, role: 'admin' }
    vi.mocked(fetch)
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ access_token: 't' }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify(adminUser), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      )
    render(
      <AuthProvider>
        <AuthConsumer />
      </AuthProvider>
    )
    await waitFor(() => expect(screen.getByTestId('loading')).toHaveTextContent('no'))
    await user.click(screen.getByRole('button', { name: 'login' }))
    await waitFor(() => {
      expect(screen.getByTestId('hasAdmin')).toHaveTextContent('yes')
      expect(screen.getByTestId('hasPerm')).toHaveTextContent('yes')
    })
  })

  it('при сохранённом токене вызывает verifyToken и обновляет пользователя при ответе 200', async () => {
    localStorage.setItem('token', 'saved-tok')
    localStorage.setItem('user', JSON.stringify({ ...baseUser, username: 'stale' }))
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify({ ...baseUser, username: 'fresh' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    )
    render(
      <AuthProvider>
        <AuthConsumer />
      </AuthProvider>
    )
    await waitFor(() => {
      expect(screen.getByTestId('user')).toHaveTextContent('fresh')
    })
    expect(JSON.parse(localStorage.getItem('user')!).username).toBe('fresh')
  })

  it('при невалидном токене verifyToken очищает сессию', async () => {
    localStorage.setItem('token', 'bad')
    localStorage.setItem('user', JSON.stringify(baseUser))
    vi.mocked(fetch).mockResolvedValueOnce(new Response('', { status: 401 }))
    render(
      <AuthProvider>
        <AuthConsumer />
      </AuthProvider>
    )
    await waitFor(() => {
      expect(localStorage.getItem('token')).toBeNull()
      expect(screen.getByTestId('auth')).toHaveTextContent('out')
    })
  })

  it('повреждённые данные user в localStorage удаляются при инициализации', async () => {
    localStorage.setItem('token', 'x')
    localStorage.setItem('user', '{not-json')
    render(
      <AuthProvider>
        <AuthConsumer />
      </AuthProvider>
    )
    await waitFor(() => expect(screen.getByTestId('loading')).toHaveTextContent('no'))
    expect(localStorage.getItem('token')).toBeNull()
    expect(localStorage.getItem('user')).toBeNull()
  })
})
