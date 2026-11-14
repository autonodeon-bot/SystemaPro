import React from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { AuthProvider, useAuth } from '../contexts/AuthContext';

function LoginProbe() {
  const { login, isAuthenticated } = useAuth();
  const [error, setError] = React.useState('');
  return <>
    <button onClick={() => login('test', 'test-password').catch(e => setError(e.message))}>Войти</button>
    <div role="status">{isAuthenticated ? 'Вход выполнен' : error}</div>
  </>;
}

beforeEach(() => localStorage.clear());
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

describe('вход через API', () => {
  it('показывает понятное сообщение при сетевой ошибке', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Failed to fetch')));
    render(<AuthProvider><LoginProbe /></AuthProvider>);
    fireEvent.click(screen.getByRole('button', { name: 'Войти' }));
    expect(await screen.findByText('Не удалось подключиться к серверу. Проверьте соединение и повторите вход.')).toBeInTheDocument();
    expect(localStorage.getItem('token')).toBeNull();
  });

  it('сохраняет сообщение сервера о неверном пароле', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({ detail: 'Неверный логин или пароль' }), { status: 401 })));
    render(<AuthProvider><LoginProbe /></AuthProvider>);
    fireEvent.click(screen.getByRole('button', { name: 'Войти' }));
    expect(await screen.findByText('Неверный логин или пароль')).toBeInTheDocument();
  });

  it('завершает вход после получения токена и профиля', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ access_token: 'test-token' }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ id: 'test-id', username: 'test', role: 'engineer', permissions: [] }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);
    render(<AuthProvider><LoginProbe /></AuthProvider>);
    fireEvent.click(screen.getByRole('button', { name: 'Войти' }));
    expect(await screen.findByText('Вход выполнен')).toBeInTheDocument();
    expect(fetchMock.mock.calls[0][0]).toMatch(/\/api\/auth\/login$/);
    expect(fetchMock.mock.calls[1][0]).toMatch(/\/api\/auth\/me$/);
    expect(localStorage.getItem('token')).toBe('test-token');
  });
});
