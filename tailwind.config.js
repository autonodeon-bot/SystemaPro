/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./pages/**/*.{js,ts,jsx,tsx}",
    "./*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        primary: '#0f172a',
        secondary: '#1e293b',
        accent: '#3b82f6',
        danger: '#ef4444',
        success: '#22c55e',
        warning: '#f59e0b',
      }
    }
  },
  plugins: [],
}

