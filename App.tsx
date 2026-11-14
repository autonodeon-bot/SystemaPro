import React, { useState, lazy, Suspense } from 'react';
import { HashRouter, Routes, Route, NavLink, useLocation, Outlet, Navigate } from 'react-router-dom';
import { LayoutDashboard, ClipboardList, BookOpen, Settings, Menu, X, FileText, Package, Users, FolderKanban, FileCheck, Award, Sparkles, ListChecks, Smartphone, LogOut, CheckCircle2, Sun, Moon, Shield, Wrench, HelpCircle, Building2, Map, Layers, AlertTriangle, Trash2, Gauge, Image as ImageIcon, Wallet, Network, PenTool } from 'lucide-react';
import {
  APP_VERSION,
  APP_HEADER_TITLE,
  SYSTEM_SIDEBAR_BADGE_LETTER,
  SYSTEM_SIDEBAR_TITLE_AFTER_BADGE,
  SYSTEM_SHORT_NAME,
} from './constants';
import { useAuth, AuthProvider } from './contexts/AuthContext';
import { useTheme } from './contexts/ThemeContext';
import Login from './pages/Login';
import Landing from './pages/Landing';
import ProtectedRoute from './components/ProtectedRoute';
import ErrorBoundary from './components/ErrorBoundary';

const SettingsPage = lazy(() => import('./pages/Settings'));
const Dashboard = lazy(() => import('./pages/Dashboard'));
const DynamicInspection = lazy(() => import('./pages/DynamicInspection'));
const TechSpecs = lazy(() => import('./pages/TechSpecs'));
const EquipmentManagement = lazy(() => import('./pages/EquipmentManagement'));
const EquipmentDetails = lazy(() => import('./pages/EquipmentDetails'));
const ProjectsManagement = lazy(() => import('./pages/ProjectsManagement'));
const BillingOverview = lazy(() => import('./pages/BillingOverview'));
const ResourceManagement = lazy(() => import('./pages/ResourceManagement'));
const RegulatoryDocuments = lazy(() => import('./pages/RegulatoryDocuments'));
const CompetenciesManagement = lazy(() => import('./pages/CompetenciesManagement'));
const ReportGeneration = lazy(() => import('./pages/ReportGeneration'));
const ReportViewer = lazy(() => import('./pages/ReportViewer'));
const InspectionsList = lazy(() => import('./pages/InspectionsList'));
const MobileApp = lazy(() => import('./pages/MobileApp'));
const Changelog = lazy(() => import('./pages/Changelog'));
const Glossary = lazy(() => import('./pages/Glossary'));
const AssignmentsManagement = lazy(() => import('./pages/AssignmentsManagement'));
const UsersManagement = lazy(() => import('./pages/UsersManagement'));
const VerificationsManagement = lazy(() => import('./pages/VerificationsManagement'));
const VerificationsCalendar = lazy(() => import('./pages/VerificationsCalendar'));
const ReportTemplates = lazy(() => import('./pages/ReportTemplates'));
const ReportOrgSettings = lazy(() => import('./pages/ReportOrgSettings'));
const EnterpriseCards = lazy(() => import('./pages/EnterpriseCards'));
const AdminPanel = lazy(() => import('./pages/AdminPanel'));
const EngineerPanel = lazy(() => import('./pages/EngineerPanel'));
const ClientPortal = lazy(() => import('./pages/ClientPortal'));
const PipelineMap = lazy(() => import('./pages/PipelineMap'));
const ReportsAndExpertise = lazy(() => import('./pages/ReportsAndExpertise'));
const ProtocolConstructor = lazy(() => import('./pages/ProtocolConstructor'));
const DrawingTemplatesManager = lazy(() => import('./pages/DrawingTemplatesManager'));
const VesselSchemeConstructor = lazy(() => import('./pages/VesselSchemeConstructor'));
const DiagnosticMenuManager = lazy(() => import('./pages/DiagnosticMenuManager'));
const InspectionObjectTemplatesManager = lazy(() => import('./pages/InspectionObjectTemplatesManager'));
const DefectStatement = lazy(() => import('./pages/DefectStatement'));
const InspectionsTrash = lazy(() => import('./pages/InspectionsTrash'));
const InstrumentRegistry = lazy(() => import('./pages/InstrumentRegistry'));
const OpoRegistry = lazy(() => import('./pages/OpoRegistry'));

const PageLoader = () => (
  <div className="flex items-center justify-center h-64">
    <div className="flex flex-col items-center gap-3">
      <div className="w-10 h-10 rounded-full border-2 border-transparent border-t-[var(--accent)] border-r-[var(--accent)] animate-spin" />
      <span className="text-xs text-[var(--text-muted)] animate-pulse">Загрузка...</span>
    </div>
  </div>
);

const sidebarLabels: Record<string,string> = {
  '/dashboard':'Обзор', '/equipment':'Оборудование', '/assignments':'Задания', '/inspections-list':'Обследования',
  '/reports':'Отчёты', '/verifications':'Поверки', '/instrument-registry':'Реестр приборов', '/opo-registry':'Реестр ОПО',
  '/defect-statement':'Ведомость дефектов', '/regulatory':'Нормативные документы', '/competencies':'Компетенции',
  '/protocol-constructor':'Шаблоны протоколов', '/drawing-templates':'Шаблоны чертежей', '/vessel-scheme-constructor':'Конструктор сосуда',
  '/diagnostic-menu':'Меню диагностики', '/inspection-object-templates':'Шаблоны обследований', '/inspections-trash':'Корзина',
  '/admin':'Администрирование', '/users':'Сотрудники', '/report-templates':'Шаблоны отчётов', '/report-org-settings':'Данные отчёта',
  '/enterprise-cards':'Предприятия', '/pipeline-map':'Расположение сотрудников', '/projects':'Проекты', '/billing':'Финансы',
  '/specs':'Архитектура', '/glossary':'Глоссарий', '/mobile-app':'Приложение Android', '/changelog':'Что нового', '/settings':'Настройки'
};
const SidebarItem = ({ to, icon: Icon, label }: { to: string, icon: any, label: string }) => {
  const location = useLocation();
  const isActive = location.pathname === to;
  return (
    <NavLink
      to={to}
      className={`sp-sidebar-item ${isActive ? 'active' : ''} ${!label ? 'justify-center px-0' : ''}`}
      aria-label={label || sidebarLabels[to] || to}
      title={!label ? sidebarLabels[to] || to : undefined}
    >
      <Icon size={18} className="shrink-0" />
      {label && <span>{label}</span>}
    </NavLink>
  );
};

const Layout: React.FC = () => {
  const [isSidebarOpen, setSidebarOpen] = useState(false); // Закрыт по умолчанию на мобильных
  const location = useLocation();
  const { user, logout } = useAuth();
  const { theme, toggleTheme } = useTheme();

  // Открываем sidebar на десктопе автоматически
  React.useEffect(() => {
    const checkScreenSize = () => {
      if (window.innerWidth >= 768) {
        setSidebarOpen(true);
      } else {
        setSidebarOpen(false);
      }
    };
    checkScreenSize();
    window.addEventListener('resize', checkScreenSize);
    return () => window.removeEventListener('resize', checkScreenSize);
  }, []);

  const roleLabel = (role?: string) => {
    const labels: Record<string, string> = {
      admin: 'Администратор', chief_operator: 'Ст. оператор',
      operator: 'Оператор', engineer: 'Инженер', client: 'Клиент',
    };
    return labels[role ?? ''] ?? role ?? 'Пользователь';
  };

  const avatarLetter = user?.full_name
    ? user.full_name.charAt(0).toUpperCase()
    : user?.username?.charAt(0).toUpperCase() ?? 'A';

  return (
    <div className="sp-workspace flex h-screen overflow-hidden" style={{ background: 'var(--gradient-bg)', backgroundAttachment: 'fixed' }}>

      {/* ── Sidebar ────────────────────────────────────────────────────── */}
      <aside
        className={`
          sp-sidebar overflow-hidden flex flex-col fixed md:relative z-30 h-full
          transition-all duration-300
          ${isSidebarOpen ? 'w-64' : 'w-[68px]'}
          ${isSidebarOpen ? 'left-0' : '-left-[68px] md:left-0'}
        `}
      >
        {/* Logo strip */}
        <div
          className="flex items-center gap-3 px-3 h-16 border-b shrink-0"
          style={{ borderColor: 'rgba(99,130,246,0.15)' }}
        >
          <div
            className="sp-on-accent w-9 h-9 shrink-0 rounded-[10px] flex items-center justify-center text-white font-bold text-sm shadow-md"
            style={{ background: 'var(--gradient-accent)', boxShadow: '0 2px 10px rgba(59,130,246,0.4)' }}
            title={SYSTEM_SHORT_NAME}
          >
            {SYSTEM_SIDEBAR_BADGE_LETTER}
          </div>
          {isSidebarOpen && (
            <span className="font-bold text-app-text text-base tracking-tight truncate flex-1" title={SYSTEM_SHORT_NAME}>
              {SYSTEM_SIDEBAR_TITLE_AFTER_BADGE}
            </span>
          )}
          <button
            onClick={() => setSidebarOpen(!isSidebarOpen)}
            aria-label="Свернуть меню"
            className={`p-1.5 rounded-lg transition-colors shrink-0 ${!isSidebarOpen ? "hidden" : ""}`}
            style={{ color: 'var(--text-secondary)' }}
            onMouseEnter={e => (e.currentTarget.style.background = 'rgba(99,130,246,0.15)')}
            onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
          >
            {isSidebarOpen ? <X size={18}/> : <Menu size={18}/>}
          </button>
        </div>

        {/* Navigation */}
        <nav aria-label="Основная навигация" className="flex-1 px-2 py-3 space-y-1 overflow-y-auto overflow-x-hidden">
          <SidebarItem to="/dashboard" icon={LayoutDashboard} label={isSidebarOpen ? 'Обзор' : ''} />
          {user?.role !== 'client' && <>
            <SidebarItem to="/assignments" icon={ClipboardList} label={isSidebarOpen ? (user?.role === 'engineer' ? 'Мои задания' : 'Задания') : ''} />
            <SidebarItem to="/inspections-list" icon={ListChecks} label={isSidebarOpen ? 'Обследования' : ''} />
          </>}
          {['admin','chief_operator','operator'].includes(user?.role || '') && <SidebarItem to="/equipment" icon={Package} label={isSidebarOpen ? 'Оборудование' : ''} />}
          <SidebarItem to="/reports" icon={FileText} label={isSidebarOpen ? 'Отчёты' : ''} />
          {[
            {name:'Контроль', icon:Gauge, items:[
              ...(user?.role !== 'client' ? [['/instrument-registry',Gauge],['/defect-statement',AlertTriangle]] : []),
              ...(['admin','chief_operator','operator'].includes(user?.role || '') ? [['/verifications',CheckCircle2],['/opo-registry',Shield]] : []),
              ...(['admin','chief_operator'].includes(user?.role || '') ? [['/inspections-trash',Trash2]] : [])]},
            {name:'Инструменты',icon:Wrench,items:['admin','chief_operator','operator'].includes(user?.role || '') ? [['/protocol-constructor',Layers],['/drawing-templates',ImageIcon],['/vessel-scheme-constructor',PenTool],['/diagnostic-menu',Network],['/inspection-object-templates',ListChecks]] : []},
            {name:'Управление',icon:Users,items:[
              ...(['admin','chief_operator'].includes(user?.role || '') ? [['/billing',Wallet]] : []),
              ...(user?.role === 'admin' ? [['/projects',FolderKanban],['/admin',Shield],['/users',Users],['/report-templates',FileText],['/report-org-settings',FileText],['/enterprise-cards',Building2],['/pipeline-map',Map]] : [])]},
            {name:'Справочники',icon:BookOpen,items:user?.role === 'admin' ? [['/regulatory',FileCheck],['/competencies',Award],['/glossary',HelpCircle],['/specs',BookOpen]] : []},
          ].filter(group=>group.items.length).map(group=><details key={group.name} open={group.items.some(([path])=>location.pathname===path) || undefined} className="sp-nav-group">
            <summary title={group.name} aria-label={group.name} className="sp-sidebar-item cursor-pointer list-none"><group.icon size={18} className="shrink-0" />{isSidebarOpen && <span>{group.name}</span>}</summary>
            {group.items.map(([path,Icon])=><SidebarItem key={path as string} to={path as string} icon={Icon} label={isSidebarOpen ? sidebarLabels[path as string] : ''} />)}
          </details>)}
          <div className="my-3 border-t border-app-line" />
          <SidebarItem to="/mobile-app" icon={Smartphone} label={isSidebarOpen ? 'Приложение Android' : ''} />
          <SidebarItem to="/changelog" icon={Sparkles} label={isSidebarOpen ? 'Что нового' : ''} />
          <SidebarItem to="/settings" icon={Settings} label={isSidebarOpen ? 'Настройки' : ''} />
          <button onClick={toggleTheme} aria-label={theme==='dark'?'Дневная тема':'Ночная тема'} title={theme==='dark'?'Дневная тема':'Ночная тема'} className="sp-sidebar-item w-full">
            {theme==='dark'?<Sun size={18}/>:<Moon size={18}/>} {isSidebarOpen && <span>{theme==='dark'?'Дневная тема':'Ночная тема'}</span>}
          </button>
        </nav>

        {/* User block */}
        <div
          className="px-3 py-3 border-t shrink-0"
          style={{ borderColor: 'rgba(99,130,246,0.12)' }}
        >
          <div className="flex items-center gap-3">
            <div
              className="sp-on-accent w-9 h-9 shrink-0 rounded-full flex items-center justify-center font-bold text-sm text-white sp-on-accent shadow"
              style={{ background: 'linear-gradient(135deg,#4f6edb,#7c5cbf)', boxShadow: '0 2px 8px rgba(79,110,219,0.35)' }}
            >
              {avatarLetter}
            </div>
            {isSidebarOpen && (
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-app-text truncate">{user?.full_name || user?.username}</p>
                <p className="text-[11px] truncate" style={{ color: 'var(--text-secondary)' }}>{roleLabel(user?.role)}</p>
              </div>
            )}
            {isSidebarOpen && (
              <button
                onClick={() => { logout(); window.location.href = '/#/login'; }}
                aria-label="Свернуть меню"
            className={`p-1.5 rounded-lg transition-colors shrink-0 ${!isSidebarOpen ? "hidden" : ""}`}
                style={{ color: 'rgba(248,113,113,0.7)' }}
                title="Выйти"
                onMouseEnter={e => (e.currentTarget.style.background = 'rgba(239,68,68,0.12)')}
                onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
              >
                <LogOut size={16} />
              </button>
            )}
          </div>
        </div>
      </aside>

      {/* Mobile overlay */}
      {isSidebarOpen && (
        <div
          className="fixed inset-0 z-20 md:hidden"
          style={{ background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(2px)' }}
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* ── Main ───────────────────────────────────────────────────────── */}
      <main className="flex-1 flex flex-col min-w-0 overflow-hidden relative">

        {/* Header */}
        <header
          className="sp-header min-h-[60px] flex items-center justify-between px-4 md:px-6 z-10 shrink-0"
          style={{ minHeight: 60 }}
        >
          <div className="flex items-center gap-3 min-w-0">
            <button
              onClick={() => setSidebarOpen(!isSidebarOpen)}
              aria-label={isSidebarOpen ? "Закрыть меню" : "Открыть меню"}
              aria-expanded={isSidebarOpen}
              className="p-2 rounded-lg transition-colors shrink-0"
              style={{ color: 'var(--text-secondary)' }}
            >
              <Menu size={20} />
            </button>
            <div className="min-w-0">
              <span
                className="text-sm font-semibold leading-tight block truncate"
                style={{ color: 'var(--text-primary)' }}
              >
                {sidebarLabels[location.pathname] ? `Монитор · ${sidebarLabels[location.pathname]}` : APP_HEADER_TITLE}
              </span>
              <span
                className="text-[11px] tabular-nums"
                style={{ color: 'var(--text-muted)' }}
              >
                v{APP_VERSION}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-2">
            {/* Theme toggle desktop */}
            <button
              onClick={toggleTheme}
              className="hidden md:flex p-2 rounded-lg transition-colors"
              style={{ color: 'var(--text-secondary)' }}
              title={theme === 'dark' ? 'Светлая тема' : 'Тёмная тема'}
              onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-tertiary)')}
              onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
            >
              {theme === 'dark' ? <Sun size={18}/> : <Moon size={18}/>}
            </button>

            {/* User chip */}
            <div
              className="hidden sm:flex items-center gap-2 px-3 py-1.5 rounded-xl"
              style={{ background: 'var(--bg-glass)', border: '1px solid var(--border-subtle)', backdropFilter: 'blur(8px)' }}
            >
              <div
                className="sp-on-accent w-6 h-6 rounded-full flex items-center justify-center text-white text-xs font-bold shrink-0"
                style={{ background: 'linear-gradient(135deg,#4f6edb,#7c5cbf)' }}
              >
                {avatarLetter}
              </div>
              <span className="text-xs font-medium max-w-[120px] truncate" style={{ color: 'var(--text-primary)' }}>
                {user?.full_name || user?.username}
              </span>
            </div>

            {/* Logout */}
            <button
              onClick={() => { logout(); window.location.href = '/#/login'; }}
              className="flex items-center gap-1.5 px-3 py-2 rounded-lg transition-colors text-sm font-medium"
              style={{ color: 'rgba(248,113,113,0.85)' }}
              title="Выйти"
              onMouseEnter={e => (e.currentTarget.style.background = 'rgba(239,68,68,0.1)')}
              onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
            >
              <LogOut size={16} />
              <span className="hidden sm:inline">Выйти</span>
            </button>
          </div>
        </header>

        {/* Page content */}
        <div className="flex-1 overflow-auto p-4 md:p-6 scroll-smooth">
          <ErrorBoundary>
            <Suspense fallback={<PageLoader />}>
              <Outlet />
            </Suspense>
          </ErrorBoundary>
        </div>
      </main>
    </div>
  );
};

const HomePage = () => {
  const { isAuthenticated, loading } = useAuth();
  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen" style={{ background: 'var(--gradient-bg)' }}>
        <div className="text-center sp-fade-in">
          <div
            className="sp-on-accent w-12 h-12 rounded-2xl mx-auto mb-5 flex items-center justify-center font-bold text-white text-lg shadow-lg"
            style={{ background: 'var(--gradient-accent)', boxShadow: '0 4px 20px rgba(59,130,246,0.4)' }}
          >М</div>
          <div className="w-8 h-8 rounded-full border-2 border-transparent border-t-[var(--accent)] mx-auto animate-spin mb-3" />
          <p className="text-sm" style={{ color: 'var(--text-muted)' }}>Загрузка системы...</p>
        </div>
      </div>
    );
  }
  if (!isAuthenticated) return <Landing />;
  return <Navigate to="/dashboard" replace />;
};

const App = () => {
  return (
    <AuthProvider>
      <HashRouter>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route path="/" element={<HomePage />} />
          <Route
            element={
              <ProtectedRoute>
                <Layout />
              </ProtectedRoute>
            }
          >
            <Route path="/dashboard" element={<Dashboard />} />
            <Route path="/equipment" element={<EquipmentManagement />} />
            <Route path="/equipment/:id" element={<EquipmentDetails />} />
            <Route path="/equipment-hierarchy" element={<EquipmentManagement />} />
            <Route path="/inspections-list" element={<InspectionsList />} />
            <Route path="/projects" element={<ProjectsManagement />} />
            <Route path="/billing" element={<BillingOverview />} />
            <Route path="/resources" element={<ResourceManagement />} />
            <Route path="/reports" element={<ReportGeneration />} />
            <Route path="/report-viewer/:inspectionId" element={<ReportViewer />} />
            <Route path="/verifications" element={<VerificationsManagement />} />
            <Route path="/verifications-calendar" element={<VerificationsCalendar />} />
            <Route path="/instrument-registry" element={<InstrumentRegistry />} />
            <Route path="/opo-registry" element={<OpoRegistry />} />
            <Route path="/regulatory" element={<RegulatoryDocuments />} />
            <Route path="/competencies" element={<CompetenciesManagement />} />
            <Route path="/admin" element={<ProtectedRoute requiredRole="admin"><AdminPanel /></ProtectedRoute>} />
            <Route path="/engineer-panel" element={<EngineerPanel />} />
            <Route path="/users" element={<ProtectedRoute requiredRole="admin"><UsersManagement /></ProtectedRoute>} />
            <Route path="/report-templates" element={<ProtectedRoute requiredRole="admin"><ReportTemplates /></ProtectedRoute>} />
            <Route path="/report-org-settings" element={<ProtectedRoute requiredRole="admin"><ReportOrgSettings /></ProtectedRoute>} />
            <Route path="/enterprise-cards" element={<ProtectedRoute requiredRole="admin"><EnterpriseCards /></ProtectedRoute>} />
            <Route path="/inspection" element={<DynamicInspection />} />
            <Route path="/specs" element={<TechSpecs />} />
            <Route path="/glossary" element={<Glossary />} />
            <Route path="/mobile-app" element={<MobileApp />} />
            <Route path="/changelog" element={<Changelog />} />
            <Route path="/settings" element={<SettingsPage />} />
            <Route path="/assignments" element={<AssignmentsManagement />} />
            <Route
              path="/client-portal"
              element={
                <ProtectedRoute requiredRole="client">
                  <ClientPortal />
                </ProtectedRoute>
              }
            />
            <Route path="/pipeline-map" element={<PipelineMap />} />
            <Route path="/reports-expertise" element={<ReportsAndExpertise />} />
            <Route path="/protocol-constructor" element={<ProtocolConstructor />} />
            <Route path="/drawing-templates" element={<DrawingTemplatesManager />} />
            <Route path="/vessel-scheme-constructor" element={<VesselSchemeConstructor />} />
            <Route path="/diagnostic-menu" element={<DiagnosticMenuManager />} />
            <Route path="/inspection-object-templates" element={<InspectionObjectTemplatesManager />} />
            <Route path="/defect-statement" element={<DefectStatement />} />
            <Route path="/inspections-trash" element={<ProtectedRoute allowedRoles={['admin','chief_operator']}><InspectionsTrash /></ProtectedRoute>} />
            <Route path="*" element={<div className="text-center text-app-text3 mt-20">Раздел в разработке</div>} />
          </Route>
        </Routes>
      </HashRouter>
    </AuthProvider>
  );
};

export default App;

