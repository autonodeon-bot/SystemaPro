import React, { useState } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { LogIn } from 'lucide-react';
import { APP_VERSION, PLATFORM_FULL_TITLE } from '../constants';

const Login: React.FC = () => {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const { login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  const from = (location.state as any)?.from?.pathname || '/dashboard';

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      await login(username, password);
      navigate(from, { replace: true });
    } catch (err: any) {
      setError(err.message || 'Ошибка авторизации');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-app-deep via-app-panel to-app-soft p-4">
      <div className="w-full max-w-md">
        <div className="sp-glass rounded-2xl shadow-soft p-8">
          <div className="text-center mb-8">
            <div className="inline-flex items-center justify-center w-16 h-16 bg-accent/20 rounded-full mb-4">
              <LogIn className="w-8 h-8 text-accent" />
            </div>
            <h1 className="text-2xl font-bold text-app-text mb-2">Вход в систему</h1>
            <p className="text-accent font-semibold text-sm leading-snug">{PLATFORM_FULL_TITLE}</p>
          </div>

          <form onSubmit={handleSubmit} className="space-y-6">
            {error && (
              <div className="bg-red-500/10 border border-red-500/50 rounded-lg p-3 text-red-400 text-sm">
                {error}
              </div>
            )}

            <div>
              <label htmlFor="username" className="block text-sm font-medium text-app-text2 mb-2">
                Логин
              </label>
              <input
                id="username"
                type="text"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                required
                className="w-full px-4 py-3 bg-app-panel border border-app-line rounded-lg text-app-text placeholder-app-text3 focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent"
                placeholder="Введите логин"
                autoComplete="username"
              />
            </div>

            <div>
              <label htmlFor="password" className="block text-sm font-medium text-app-text2 mb-2">
                Пароль
              </label>
              <input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                className="w-full px-4 py-3 bg-app-panel border border-app-line rounded-lg text-app-text placeholder-app-text3 focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent"
                placeholder="Введите пароль"
                autoComplete="current-password"
              />
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full bg-accent hover:bg-accent/90 text-white font-semibold py-3 px-4 rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
            >
              {loading ? (
                <>
                  <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin"></div>
                  <span>Вход...</span>
                </>
              ) : (
                <>
                  <LogIn className="w-5 h-5" />
                  <span>Войти</span>
                </>
              )}
            </button>
          </form>

          <div className="mt-6 text-center text-sm text-app-text3">
            <p>Версия системы: v{APP_VERSION}</p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Login;
