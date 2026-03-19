import type { ReactNode } from 'react'
import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import ProtectedRoute from '../components/ProtectedRoute'

const mockUseAuth = vi.fn()

vi.mock('../contexts/AuthContext', () => ({
  useAuth: () => mockUseAuth(),
}))

function renderProtectedRoute(ui: ReactNode, initialEntry = '/protected') {
  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <Routes>
        <Route path="/protected" element={<ProtectedRoute>{ui}</ProtectedRoute>} />
        <Route path="/login" element={<div>страница входа</div>} />
      </Routes>
    </MemoryRouter>
  )
}

describe('ProtectedRoute', () => {
  it('показывает индикатор загрузки, пока auth в состоянии loading', () => {
    mockUseAuth.mockReturnValue({
      isAuthenticated: false,
      hasRole: () => false,
      hasPermission: () => false,
      loading: true,
    })
    renderProtectedRoute(<div>секрет</div>)
    expect(screen.getByText('Загрузка...')).toBeInTheDocument()
    expect(screen.queryByText('секрет')).not.toBeInTheDocument()
  })

  it('редиректит на /login, если пользователь не авторизован', () => {
    mockUseAuth.mockReturnValue({
      isAuthenticated: false,
      hasRole: () => false,
      hasPermission: () => false,
      loading: false,
    })
    renderProtectedRoute(<div>секрет</div>)
    expect(screen.getByText('страница входа')).toBeInTheDocument()
    expect(screen.queryByText('секрет')).not.toBeInTheDocument()
  })

  it('рендерит children при авторизации без дополнительных требований', () => {
    mockUseAuth.mockReturnValue({
      isAuthenticated: true,
      hasRole: () => true,
      hasPermission: () => true,
      loading: false,
    })
    renderProtectedRoute(<div>секрет</div>)
    expect(screen.getByText('секрет')).toBeInTheDocument()
  })

  it('блокирует доступ, если не хватает роли', () => {
    mockUseAuth.mockReturnValue({
      isAuthenticated: true,
      hasRole: () => false,
      hasPermission: () => true,
      loading: false,
    })
    render(
      <MemoryRouter initialEntries={['/protected-admin']}>
        <Routes>
          <Route
            path="/protected-admin"
            element={
              <ProtectedRoute requiredRole="admin">
                <div>админка</div>
              </ProtectedRoute>
            }
          />
          <Route path="/login" element={<div>страница входа</div>} />
        </Routes>
      </MemoryRouter>
    )
    expect(screen.getByText('Доступ запрещен')).toBeInTheDocument()
    expect(screen.getByText('Требуется роль: admin')).toBeInTheDocument()
    expect(screen.queryByText('админка')).not.toBeInTheDocument()
  })

  it('пропускает при совпадении requiredRole', () => {
    mockUseAuth.mockReturnValue({
      isAuthenticated: true,
      hasRole: (r: string) => r === 'admin',
      hasPermission: () => false,
      loading: false,
    })
    render(
      <MemoryRouter initialEntries={['/protected-admin']}>
        <Routes>
          <Route
            path="/protected-admin"
            element={
              <ProtectedRoute requiredRole="admin">
                <div>админка</div>
              </ProtectedRoute>
            }
          />
          <Route path="/login" element={<div>страница входа</div>} />
        </Routes>
      </MemoryRouter>
    )
    expect(screen.getByText('админка')).toBeInTheDocument()
  })

  it('блокирует доступ при отсутствии requiredPermission', () => {
    mockUseAuth.mockReturnValue({
      isAuthenticated: true,
      hasRole: () => true,
      hasPermission: () => false,
      loading: false,
    })
    render(
      <MemoryRouter initialEntries={['/protected-perm']}>
        <Routes>
          <Route
            path="/protected-perm"
            element={
              <ProtectedRoute requiredPermission="reports:read">
                <div>отчёты</div>
              </ProtectedRoute>
            }
          />
          <Route path="/login" element={<div>страница входа</div>} />
        </Routes>
      </MemoryRouter>
    )
    expect(screen.getByText('Доступ запрещен')).toBeInTheDocument()
    expect(screen.getByText('Недостаточно прав доступа')).toBeInTheDocument()
  })

  it('пропускает при наличии requiredPermission', () => {
    mockUseAuth.mockReturnValue({
      isAuthenticated: true,
      hasRole: () => false,
      hasPermission: (p: string) => p === 'reports:read',
      loading: false,
    })
    render(
      <MemoryRouter initialEntries={['/protected-perm']}>
        <Routes>
          <Route
            path="/protected-perm"
            element={
              <ProtectedRoute requiredPermission="reports:read">
                <div>отчёты</div>
              </ProtectedRoute>
            }
          />
          <Route path="/login" element={<div>страница входа</div>} />
        </Routes>
      </MemoryRouter>
    )
    expect(screen.getByText('отчёты')).toBeInTheDocument()
  })
})
