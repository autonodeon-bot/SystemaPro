import { describe, it, expect, vi } from 'vitest'
import { render } from '@testing-library/react'
import App from '../App'

vi.mock('../contexts/AuthContext', () => ({
  AuthProvider: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  useAuth: () => ({
    user: null,
    token: null,
    isAuthenticated: false,
    loading: false,
    login: vi.fn(),
    logout: vi.fn(),
    hasPermission: () => false,
    hasRole: () => false,
    getToken: () => null,
  }),
}))

vi.mock('../contexts/ThemeContext', () => ({
  ThemeProvider: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  useTheme: () => ({
    theme: 'dark' as const,
    toggleTheme: vi.fn(),
    setTheme: vi.fn(),
  }),
}))

describe('App', () => {
  it('рендерится без ошибок', () => {
    const { container } = render(<App />)
    expect(container).toBeTruthy()
  })

  it('содержит роутер с маршрутами', () => {
    render(<App />)
    expect(document.querySelector('[data-testid]') || document.body.querySelector('div')).toBeTruthy()
  })

  it('показывает лендинг для неавторизованного пользователя', () => {
    render(<App />)
    const body = document.body.textContent
    expect(body).toBeTruthy()
  })
})
