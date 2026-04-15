import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import {
  LogIn,
  Package,
  ClipboardList,
  FileCheck,
  BarChart2,
  Award,
  Smartphone,
  Shield,
  FileText,
  Users,
  FolderKanban,
  Activity,
  Zap,
  ChevronRight,
  Gauge,
  Database,
  Lock,
} from 'lucide-react';
import { APP_VERSION, SYSTEM_SHORT_NAME, PLATFORM_FULL_TITLE } from '../constants';

const FEATURES = [
  {
    icon: Package,
    title: 'Реестр оборудования',
    text: 'Иерархия предприятий, филиалов и цехов. Учёт сосудов, трубопроводов, резервуаров.',
    color: 'from-blue-500/20 to-cyan-500/20',
    iconBg: 'bg-blue-500/20',
    iconColor: 'text-blue-400',
  },
  {
    icon: ClipboardList,
    title: 'Задания и обследования',
    text: 'Назначение заданий инженерам, чек-листы, контроль сроков и статусов.',
    color: 'from-violet-500/20 to-purple-500/20',
    iconBg: 'bg-violet-500/20',
    iconColor: 'text-violet-400',
  },
  {
    icon: FileCheck,
    title: 'Отчёты и экспертиза',
    text: 'Генерация отчётов Word и PDF, шаблоны, привязка к обследованиям.',
    color: 'from-emerald-500/20 to-teal-500/20',
    iconBg: 'bg-emerald-500/20',
    iconColor: 'text-emerald-400',
  },
  {
    icon: BarChart2,
    title: 'Поверки и календарь',
    text: 'Учёт средств измерений, сроки поверок, календарь напоминаний.',
    color: 'from-amber-500/20 to-orange-500/20',
    iconBg: 'bg-amber-500/20',
    iconColor: 'text-amber-400',
  },
  {
    icon: Award,
    title: 'Компетенции и НК',
    text: 'Специалисты ВИК, УЗК, УЗТ. Удостоверения и области аттестации.',
    color: 'from-rose-500/20 to-pink-500/20',
    iconBg: 'bg-rose-500/20',
    iconColor: 'text-rose-400',
  },
  {
    icon: Smartphone,
    title: 'Мобильное приложение',
    text: 'Обследования в поле, фото с GPS, офлайн-режим, синхронизация.',
    color: 'from-accent/20 to-blue-600/20',
    iconBg: 'bg-accent/20',
    iconColor: 'text-accent',
  },
  {
    icon: FileText,
    title: 'Нормативные документы',
    text: 'База нормативов и регламентов для технического диагностирования.',
    color: 'from-slate-500/20 to-slate-600/20',
    iconBg: 'bg-slate-500/20',
    iconColor: 'text-slate-300',
  },
  {
    icon: Users,
    title: 'Роли и доступ',
    text: 'Администратор, инженер. Управление пользователями и правами.',
    color: 'from-indigo-500/20 to-blue-500/20',
    iconBg: 'bg-indigo-500/20',
    iconColor: 'text-indigo-400',
  },
  {
    icon: FolderKanban,
    title: 'Проекты и клиенты',
    text: 'Проекты, статистика, привязка оборудования к проектам.',
    color: 'from-cyan-500/20 to-blue-500/20',
    iconBg: 'bg-cyan-500/20',
    iconColor: 'text-cyan-400',
  },
  {
    icon: Shield,
    title: 'Администрирование',
    text: 'Шаблоны отчётов, настройки системы, резервное копирование.',
    color: 'from-slate-600/20 to-slate-700/20',
    iconBg: 'bg-slate-600/20',
    iconColor: 'text-slate-400',
  },
];

const STATS = [
  { icon: Database, value: 'Единый реестр', label: 'Оборудование и иерархия' },
  { icon: Activity, value: 'Обследования', label: 'Чек-листы и задания' },
  { icon: Gauge, value: 'Отчёты', label: 'Word, PDF, экспертиза' },
  { icon: Lock, value: 'Безопасность', label: 'Роли и доступ' },
];

const Landing: React.FC = () => {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    const t = requestAnimationFrame(() => setMounted(true));
    return () => cancelAnimationFrame(t);
  }, []);

  return (
    <div className="h-screen overflow-y-auto overflow-x-hidden bg-[#0a0f1a]">
      {/* Background effects */}
      <div className="fixed inset-0 pointer-events-none">
        <div className="absolute inset-0 bg-gradient-to-br from-slate-950 via-slate-900/95 to-slate-950" />
        <div
          className="absolute inset-0 opacity-30"
          style={{
            backgroundImage: `radial-gradient(ellipse 80% 50% at 50% -20%, rgba(59, 130, 246, 0.25), transparent),
                             radial-gradient(ellipse 60% 40% at 80% 50%, rgba(59, 130, 246, 0.08), transparent),
                             radial-gradient(ellipse 50% 30% at 20% 80%, rgba(99, 102, 241, 0.06), transparent)`,
          }}
        />
        <div
          className="absolute inset-0 opacity-40"
          style={{
            backgroundImage: `linear-gradient(rgba(15, 23, 42, 0.7) 1px, transparent 1px),
                             linear-gradient(90deg, rgba(15, 23, 42, 0.7) 1px, transparent 1px)`,
            backgroundSize: '64px 64px',
          }}
        />
      </div>

      <div className="relative max-w-6xl mx-auto px-4 sm:px-6 py-12 sm:py-20">
        {/* Кнопка Войти — всегда видна в шапке */}
        <div className="fixed top-4 right-4 z-50">
          <Link
            to="/login"
            className="inline-flex items-center gap-2 bg-accent hover:bg-blue-600 text-white font-semibold px-5 py-2.5 rounded-xl shadow-lg shadow-accent/25 hover:shadow-accent/40 transition-all duration-200"
          >
            <LogIn size={20} />
            Войти в систему
          </Link>
        </div>

        {/* Hero */}
        <header
          className={`text-center mb-16 sm:mb-24 transition-all duration-1000 ${
            mounted ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-8'
          }`}
        >
          <div className="inline-flex items-center justify-center w-24 h-24 rounded-2xl mb-8 landing-float border border-slate-700/80 bg-gradient-to-br from-accent/20 to-blue-600/20 shadow-lg shadow-accent/10">
            <span className="text-4xl font-black tracking-tight text-white drop-shadow-sm">
              <span className="text-accent">М</span>
            </span>
          </div>
          <h1 className="text-5xl sm:text-6xl md:text-7xl font-black text-white tracking-tight mb-4">
            {SYSTEM_SHORT_NAME}
          </h1>
          <p className="text-lg sm:text-xl text-slate-300 max-w-3xl mx-auto mb-4 font-medium leading-relaxed px-2">
            {PLATFORM_FULL_TITLE}
          </p>
          <p className="text-sm sm:text-base text-slate-500 max-w-2xl mx-auto mb-4">
            Техническое диагностирование и неразрушающий контроль оборудования на ОПО
          </p>
          <p className="text-sm text-slate-500 mb-6">Версия {APP_VERSION}</p>
          <Link
            to="/login"
            className="inline-flex items-center gap-3 bg-accent hover:bg-blue-600 text-white font-semibold px-8 py-4 rounded-xl shadow-lg shadow-accent/25 hover:scale-105 active:scale-100 transition-all duration-300"
          >
            <LogIn size={22} />
            Войти в систему
          </Link>
        </header>

        {/* Infographic strip */}
        <section
          className={`grid grid-cols-2 md:grid-cols-4 gap-4 mb-20 transition-all duration-700 delay-200 ${
            mounted ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-6'
          }`}
        >
          {STATS.map((s, i) => (
            <div
              key={s.value}
              className="flex flex-col items-center text-center p-5 rounded-2xl bg-slate-800/40 border border-slate-700/60 backdrop-blur-sm hover:border-accent/30 hover:bg-slate-800/60 transition-all duration-300 group"
              style={{ transitionDelay: `${250 + i * 50}ms` }}
            >
              <div className="w-12 h-12 rounded-xl bg-accent/20 flex items-center justify-center mb-3 group-hover:scale-110 group-hover:bg-accent/30 transition-transform duration-300">
                <s.icon className="text-accent" size={22} />
              </div>
              <span className="font-bold text-white text-sm">{s.value}</span>
              <span className="text-xs text-slate-500 mt-0.5">{s.label}</span>
            </div>
          ))}
        </section>

        {/* Section title */}
        <h2
          className={`text-2xl sm:text-3xl font-bold text-white mb-10 flex items-center gap-3 transition-all duration-700 delay-300 ${
            mounted ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4'
          }`}
        >
          <Zap className="text-accent" size={32} />
          Возможности системы
        </h2>

        {/* Feature grid */}
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-5 mb-20">
          {FEATURES.map((f, i) => (
            <div
              key={f.title}
              className={`rounded-2xl border bg-gradient-to-br ${f.color} border-slate-700/60 backdrop-blur-sm overflow-hidden opacity-0 p-5 sm:p-6 group hover:border-slate-600 transition-all duration-300 ${
                mounted ? 'landing-fade-in-up landing-stagger-' + (Math.min(i + 1, 10)) : ''
              }`}
            >
              <div className="flex gap-4">
                <div
                  className={`flex-shrink-0 w-14 h-14 rounded-xl ${f.iconBg} flex items-center justify-center ${f.iconColor} group-hover:scale-105 transition-transform duration-300`}
                >
                  <f.icon size={26} />
                </div>
                <div className="flex-1 min-w-0">
                  <h3 className="font-semibold text-white mb-1.5 flex items-center gap-1">
                    {f.title}
                    <ChevronRight className="opacity-40 group-hover:opacity-100 group-hover:translate-x-0.5 -translate-x-0.5 transition-all duration-200 flex-shrink-0" size={18} />
                  </h3>
                  <p className="text-sm text-slate-400 leading-relaxed">{f.text}</p>
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* CTA */}
        <section
          className={`text-center transition-all duration-700 delay-500 ${
            mounted ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-6'
          }`}
        >
          <div className="inline-flex flex-col sm:flex-row items-center gap-4 p-8 rounded-3xl bg-slate-800/50 border border-slate-700/70 backdrop-blur-sm">
            <p className="text-slate-300 font-medium">
              Войдите в систему для доступа к дашборду, оборудованию и отчётам
            </p>
            <Link
              to="/login"
              className="inline-flex items-center gap-3 bg-accent hover:bg-blue-600 text-white font-semibold px-8 py-4 rounded-xl shadow-lg shadow-accent/25 hover:shadow-accent/40 hover:scale-105 active:scale-100 transition-all duration-300"
            >
              <LogIn size={22} />
              Войти в систему
            </Link>
          </div>
        </section>

        <footer className="mt-20 pt-10 border-t border-slate-800 text-center text-slate-500 text-sm">
          NeftMonitor — единая платформа для учёта оборудования, обследований и отчётности
        </footer>
      </div>
    </div>
  );
};

export default Landing;
