import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { LogIn, Shield, AlertCircle } from 'lucide-react';

const Login: React.FC = () => {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const { login } = useAuth();
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      await login(username, password);
      navigate('/');
    } catch (err: any) {
      setError(err.message || 'Ошибка авторизации. Проверьте логин и пароль.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-primary flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        {/* Логотип и заголовок */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-20 h-20 bg-accent rounded-2xl mb-4">
            <Shield className="text-white" size={40} />
          </div>
          <h1 className="text-3xl font-bold text-white mb-2">ЕС ТД НГО</h1>
          <p className="text-slate-400">Единая цифровая платформа</p>
        </div>

        {/* Форма входа */}
        <div className="bg-secondary/50 rounded-xl p-8 border border-slate-700 shadow-xl">
          <h2 className="text-2xl font-bold text-white mb-6 text-center">Вход в систему</h2>

          {error && (
            <div className="mb-4 p-4 bg-red-500/20 border border-red-500/50 rounded-lg flex items-center gap-2 text-red-400">
              <AlertCircle size={20} />
              <span>{error}</span>
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-slate-300 mb-2">
                Логин
              </label>
              <input
                type="text"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                required
                className="w-full px-4 py-3 bg-primary border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:border-accent transition-colors"
                placeholder="Введите логин"
                autoComplete="username"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-slate-300 mb-2">
                Пароль
              </label>
              <div className="relative">
                <input
                  type={showPassword ? 'text' : 'password'}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  className="w-full px-4 py-3 bg-primary border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:border-accent transition-colors pr-12"
                  placeholder="Введите пароль"
                  autoComplete="current-password"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3 top-1/2 transform -translate-y-1/2 text-slate-400 hover:text-white transition-colors"
                >
                  {showPassword ? '👁️' : '👁️‍🗨️'}
                </button>
              </div>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full py-3 bg-accent hover:bg-accent/80 rounded-lg text-white font-semibold transition-colors flex items-center justify-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {loading ? (
                <>
                  <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin"></div>
                  <span>Вход...</span>
                </>
              ) : (
                <>
                  <LogIn size={20} />
                  <span>Войти</span>
                </>
              )}
            </button>
          </form>

          {/* Подсказка с тестовыми учетными записями */}
          <div className="mt-6 p-4 bg-slate-800/50 rounded-lg border border-slate-700">
            <p className="text-xs text-slate-400 mb-2">Тестовые учетные записи:</p>
            <div className="space-y-1 text-xs text-slate-300 font-mono">
              <div>admin / admin123</div>
              <div>chief_operator / chief123</div>
              <div>operator / operator123</div>
              <div>engineer1 / engineer123</div>
            </div>
          </div>
        </div>

        {/* Футер */}
        <p className="text-center text-slate-500 text-sm mt-6">
          Версия системы: 3.2.1 (2025-Q4)
        </p>
      </div>
    </div>
  );
};

export default Login;

