import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { ThemeProvider, useTheme } from '../contexts/ThemeContext';
function Probe() { const {theme,toggleTheme}=useTheme(); return <button onClick={toggleTheme}>{theme}</button>; }
beforeEach(()=>localStorage.clear());
afterEach(cleanup);
describe('предпочтения дневной темы',()=>{
  it('начинает с дневной темы и переводит прежнюю автоматическую ночную тему',()=>{
    localStorage.setItem('theme','dark');
    render(<ThemeProvider><Probe/></ThemeProvider>);
    expect(screen.getByRole('button',{name:'light'})).toBeInTheDocument();
    expect(document.documentElement).toHaveClass('light');
  });
  it('сохраняет явный выбор ночной темы после повторного открытия',()=>{
    const first=render(<ThemeProvider><Probe/></ThemeProvider>);
    fireEvent.click(screen.getByRole('button',{name:'light'}));
    expect(document.documentElement).toHaveClass('dark');
    first.unmount();
    render(<ThemeProvider><Probe/></ThemeProvider>);
    expect(screen.getByRole('button',{name:'dark'})).toBeInTheDocument();
  });
});
