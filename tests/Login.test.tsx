import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import Login from '../pages/Login'

vi.mock('../contexts/AuthContext', () => ({
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

const renderLogin = () =>
  render(
    <MemoryRouter>
      <Login />
    </MemoryRouter>
  )

describe('Login', () => {
  it('рендерит форму входа', () => {
    renderLogin()
    expect(screen.getByText('Вход в систему')).toBeInTheDocument()
  })

  it('содержит поле ввода логина', () => {
    renderLogin()
    expect(screen.getByLabelText('Логин')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('Введите логин')).toBeInTheDocument()
  })

  it('содержит поле ввода пароля', () => {
    renderLogin()
    expect(screen.getByLabelText('Пароль')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('Введите пароль')).toBeInTheDocument()
  })

  it('содержит кнопку входа', () => {
    renderLogin()
    expect(screen.getByRole('button', { name: /войти/i })).toBeInTheDocument()
  })

  it('поле пароля имеет тип password', () => {
    renderLogin()
    const passwordInput = screen.getByLabelText('Пароль')
    expect(passwordInput).toHaveAttribute('type', 'password')
  })

  it('показывает версию системы', () => {
    renderLogin()
    expect(screen.getByText(/версия системы/i)).toBeInTheDocument()
  })
})
