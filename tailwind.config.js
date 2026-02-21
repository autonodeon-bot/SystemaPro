/** @type {import('tailwindcss').Config} */
export default {
  content: [
    './index.html',
    './App.tsx',
    './index.tsx',
    './components/**/*.{ts,tsx}',
    './contexts/**/*.{ts,tsx}',
    './pages/**/*.{ts,tsx}',
    './src/**/*.{ts,tsx}',
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        primary: {
          DEFAULT: '#0f172a',
          light: '#f8fafc',
        },
        secondary: {
          DEFAULT: '#1e293b',
          light: '#f1f5f9',
        },
        accent: '#3b82f6',
        danger: '#ef4444',
        success: '#22c55e',
        warning: '#f59e0b',
        surface: '#334155',
        border: '#475569',
      },
      borderRadius: {
        xl: '0.75rem',
        '2xl': '1rem',
      },
      boxShadow: {
        soft: '0 8px 24px rgba(2, 6, 23, 0.24)',
      },
    },
  },
  plugins: [],
};


