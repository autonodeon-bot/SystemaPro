import React, { useState, lazy, Suspense } from 'react';
import { HashRouter, Routes, Route, NavLink, useLocation, Outlet, Navigate } from 'react-router-dom';
import { LayoutDashboard, ClipboardList, BookOpen, Settings, Bell, Menu, X, FileText, Package, Users, FolderKanban, FileCheck, Award, Sparkles, ListChecks, Smartphone, LogOut, CheckCircle2, Sun, Moon, Shield, Wrench, HelpCircle, Building2, Map, Briefcase } from 'lucide-react';
import { APP_VERSION } from './constants';
import { useAuth, AuthProvider } from './contexts/AuthContext';
import { useTheme } from './contexts/ThemeContext';
import Login from './pages/Login';
import Landing from './pages/Landing';
import ProtectedRoute from './components/ProtectedRoute';
import ErrorBoundary from './components/ErrorBoundary';

const Dashboard = lazy(() => import('./pages/Dashboard'));
const DynamicInspection = lazy(() => import('./pages/DynamicInspection'));
const TechSpecs = lazy(() => import('./pages/TechSpecs'));
const EquipmentManagement = lazy(() => import('./pages/EquipmentManagement'));
const EquipmentHierarchy = lazy(() => import('./pages/EquipmentHierarchy'));
const EquipmentDetails = lazy(() => import('./pages/EquipmentDetails'));
const ProjectsManagement = lazy(() => import('./pages/ProjectsManagement'));
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
const AdminPanel = lazy(() => import('./pages/AdminPanel'));
const EngineerPanel = lazy(() => import('./pages/EngineerPanel'));
const ClientPortal = lazy(() => import('./pages/ClientPortal'));
const PipelineMap = lazy(() => import('./pages/PipelineMap'));
const ReportsAndExpertise = lazy(() => import('./pages/ReportsAndExpertise'));

const PageLoader = () => (
  <div className="flex items-center justify-center h-64">
    <div className="inline-block w-8 h-8 border-4 border-accent border-t-transparent rounded-full animate-spin" />
  </div>
);

const SidebarItem = ({ to, icon: Icon, label }: { to: string, icon: any, label: string }) => {
  const location = useLocation();
  const { theme } = useTheme();
  const isActive = location.pathname === to;
  return (
    <NavLink to={to} className={`flex items-center gap-3 px-4 py-3 rounded-lg transition-colors ${isActive ? 'bg-accent/20 text-accent border-r-2 border-accent' : theme === 'dark' ? 'text-slate-400 hover:bg-secondary hover:text-white' : 'text-slate-600 hover:bg-secondary-light hover:text-slate-900'}`}>
      <Icon size={20} />
      <span className="font-medium">{label}</span>
    </NavLink>
  );
};

const Layout: React.FC = () => {
  const [isSidebarOpen, setSidebarOpen] = useState(false); // Закрыт по умолчанию на мобильных
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

  return (
    <div className={`flex h-screen overflow-hidden ${theme === 'dark' ? 'bg-primary' : 'bg-primary-light'} transition-colors duration-300`}>
      {/* Sidebar */}
      <aside className={`${isSidebarOpen ? 'w-64' : 'w-20'} ${theme === 'dark' ? 'bg-secondary/50 border-slate-700' : 'bg-secondary-light/50 border-slate-300'} border-r transition-all duration-300 flex flex-col fixed md:relative z-30 h-full ${isSidebarOpen ? 'left-0' : '-left-20 md:left-0'}`}>
        <div className="p-4 flex items-center justify-between border-b border-slate-700 h-16">
          {isSidebarOpen && <div className="flex items-center gap-2 font-bold text-white text-lg tracking-wider"><div className="w-8 h-8 bg-accent rounded flex items-center justify-center">ES</div>ТД НГО</div>}
          <button onClick={() => setSidebarOpen(!isSidebarOpen)} className="p-1 hover:bg-slate-700 rounded text-slate-400">
            {isSidebarOpen ? <X size={20}/> : <Menu size={20}/>}
          </button>
        </div>
        
        <nav className="flex-1 p-3 space-y-2 overflow-y-auto">
          {/* Дашборд — все роли */}
          <SidebarItem to="/dashboard" icon={LayoutDashboard} label={isSidebarOpen ? "Дашборд" : ""} />

          {/* Оборудование и Иерархия — admin, chief_operator, operator */}
          {(user?.role === 'admin' || user?.role === 'chief_operator' || user?.role === 'operator') && (
            <>
              <SidebarItem to="/equipment" icon={Package} label={isSidebarOpen ? "Оборудование" : ""} />
              <SidebarItem to="/equipment-hierarchy" icon={Building2} label={isSidebarOpen ? "Иерархия" : ""} />
            </>
          )}

          {/* Задания — admin, chief_operator, operator, engineer */}
          {user?.role !== 'client' && (
            <SidebarItem to="/assignments" icon={ClipboardList} label={isSidebarOpen ? (user?.role === 'engineer' ? "Мои задания" : "Задания") : ""} />
          )}

          {/* Обследования — admin, chief_operator, operator, engineer */}
          {user?.role !== 'client' && (
            <SidebarItem to="/inspections-list" icon={ListChecks} label={isSidebarOpen ? "Обследования" : ""} />
          )}

          {/* Проекты — только admin */}
          {user?.role === 'admin' && (
            <SidebarItem to="/projects" icon={FolderKanban} label={isSidebarOpen ? "Проекты" : ""} />
          )}

          {/* Отчёты — все роли */}
          <SidebarItem to="/reports" icon={Sparkles} label={isSidebarOpen ? "Отчёты" : ""} />

          {/* Поверки — admin, chief_operator, operator */}
          {(user?.role === 'admin' || user?.role === 'chief_operator' || user?.role === 'operator') && (
            <SidebarItem to="/verifications" icon={CheckCircle2} label={isSidebarOpen ? "Поверки" : ""} />
          )}

          {/* Нормативные документы и Компетенции — admin */}
          {user?.role === 'admin' && (
            <>
              <SidebarItem to="/regulatory" icon={FileCheck} label={isSidebarOpen ? "Нормативные документы" : ""} />
              <SidebarItem to="/competencies" icon={Award} label={isSidebarOpen ? "Компетенции" : ""} />
            </>
          )}

          {/* Админ-панель, Сотрудники, Шаблоны — admin */}
          {user?.role === 'admin' && (
            <>
              <SidebarItem to="/admin" icon={Shield} label={isSidebarOpen ? "Админ-панель" : ""} />
              <SidebarItem to="/users" icon={Users} label={isSidebarOpen ? "Сотрудники" : ""} />
              <SidebarItem to="/report-templates" icon={FileText} label={isSidebarOpen ? "Шаблоны отчетов" : ""} />
            </>
          )}

          {/* Карта трубопроводов — admin, chief_operator */}
          {(user?.role === 'admin' || user?.role === 'chief_operator') && (
            <SidebarItem to="/pipeline-map" icon={Map} label={isSidebarOpen ? "Карта трубопроводов" : ""} />
          )}

          {/* Моя панель — engineer */}
          {user?.role === 'engineer' && (
            <SidebarItem to="/engineer-panel" icon={Wrench} label={isSidebarOpen ? "Моя панель" : ""} />
          )}

          {/* Портал клиента — client */}
          {user?.role === 'client' && (
            <SidebarItem to="/client-portal" icon={Briefcase} label={isSidebarOpen ? "Мои отчёты" : ""} />
          )}

          {/* Технические разделы — admin */}
          {user?.role === 'admin' && (
            <>
              <SidebarItem to="/specs" icon={BookOpen} label={isSidebarOpen ? "Архитектура" : ""} />
              <SidebarItem to="/glossary" icon={HelpCircle} label={isSidebarOpen ? "Глоссарий" : ""} />
              <SidebarItem to="/mobile-app" icon={Smartphone} label={isSidebarOpen ? "Мобильное приложение" : ""} />
            </>
          )}

          <div className="my-4 border-t border-slate-700"></div>
          <SidebarItem to="/changelog" icon={Sparkles} label={isSidebarOpen ? "Что нового?" : ""} />
          <SidebarItem to="/settings" icon={Settings} label={isSidebarOpen ? "Настройки" : ""} />
          <button
            onClick={toggleTheme}
            className={`flex items-center gap-3 px-4 py-3 rounded-lg transition-colors text-slate-400 hover:bg-secondary hover:text-white w-full text-left`}
          >
            {theme === 'dark' ? <Sun size={20} /> : <Moon size={20} />}
            {isSidebarOpen && <span className="font-medium">Светлая тема</span>}
          </button>
        </nav>
        
        <div className="p-4 border-t border-slate-700">
          <div className="flex items-center gap-3 mb-2">
             <div className="w-10 h-10 rounded-full bg-slate-600 flex items-center justify-center text-white font-bold">
               {user?.full_name ? user.full_name.charAt(0).toUpperCase() : user?.username?.charAt(0).toUpperCase() || 'A'}
             </div>
             {isSidebarOpen && <div className="flex-1">
                <p className="text-sm font-bold text-white">{user?.full_name || user?.username || 'Администратор'}</p>
                <p className="text-xs text-slate-400">{user?.role === 'admin' ? 'Администратор' : user?.role || 'Пользователь'}</p>
             </div>}
          </div>
          {isSidebarOpen && (
            <button
              onClick={() => {
                logout();
                // Жесткий переход, чтобы гарантированно сбросить состояние сессии
                window.location.href = '/#/login';
              }}
              className="w-full flex items-center gap-2 px-3 py-2 rounded-lg text-red-400 hover:bg-red-500/10 hover:text-red-300 transition-colors"
            >
              <LogOut size={16} />
              <span className="text-sm font-medium">Выйти</span>
            </button>
          )}
        </div>
      </aside>

      {/* Mobile overlay */}
      {isSidebarOpen && (
        <div 
          className="fixed inset-0 bg-black/50 z-20 md:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* Main Content */}
      <main className="flex-1 flex flex-col min-w-0 overflow-hidden relative md:ml-0">
        {/* Header */}
        <header className="h-16 bg-primary/95 backdrop-blur border-b border-slate-700 flex items-center justify-between px-4 md:px-6 z-10">
           <div className="flex items-center gap-3">
             <button 
               onClick={() => setSidebarOpen(!isSidebarOpen)}
               className="md:hidden p-2 text-slate-400 hover:text-white transition"
             >
               <Menu size={20} />
             </button>
             <h2 className="text-base md:text-lg font-semibold text-white">Единая цифровая платформа</h2>
             <span className="text-xs text-slate-400 ml-2 hidden sm:inline">v{APP_VERSION}</span>
           </div>
           <div className="flex items-center gap-4">
              <button className="relative p-2 text-slate-400 hover:text-white transition">
                 <Bell size={20} />
                 <span className="absolute top-1 right-1 w-2 h-2 bg-danger rounded-full"></span>
              </button>
              <button
                onClick={() => {
                  logout();
                  window.location.href = '/#/login';
                }}
                className="flex items-center gap-2 px-3 py-2 rounded-lg text-red-400 hover:bg-red-500/10 hover:text-red-300 transition-colors"
                title="Выйти"
              >
                <LogOut size={18} />
                <span className="hidden sm:inline text-sm font-medium">Выйти</span>
              </button>
           </div>
        </header>

        {/* Scrollable Area */}
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
      <div className="flex items-center justify-center min-h-screen bg-primary">
        <div className="text-center">
          <div className="inline-block w-8 h-8 border-4 border-accent border-t-transparent rounded-full animate-spin mb-4" />
          <p className="text-slate-400">Загрузка...</p>
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
            <Route path="/equipment-hierarchy" element={<EquipmentHierarchy />} />
            <Route path="/inspections-list" element={<InspectionsList />} />
            <Route path="/projects" element={<ProjectsManagement />} />
            <Route path="/resources" element={<ResourceManagement />} />
            <Route path="/reports" element={<ReportGeneration />} />
            <Route path="/report-viewer/:inspectionId" element={<ReportViewer />} />
            <Route path="/verifications" element={<VerificationsManagement />} />
            <Route path="/verifications-calendar" element={<VerificationsCalendar />} />
            <Route path="/regulatory" element={<RegulatoryDocuments />} />
            <Route path="/competencies" element={<CompetenciesManagement />} />
            <Route path="/admin" element={<ProtectedRoute requiredRole="admin"><AdminPanel /></ProtectedRoute>} />
            <Route path="/engineer-panel" element={<EngineerPanel />} />
            <Route path="/users" element={<ProtectedRoute requiredRole="admin"><UsersManagement /></ProtectedRoute>} />
            <Route path="/report-templates" element={<ProtectedRoute requiredRole="admin"><ReportTemplates /></ProtectedRoute>} />
            <Route path="/inspection" element={<DynamicInspection />} />
            <Route path="/specs" element={<TechSpecs />} />
            <Route path="/glossary" element={<Glossary />} />
            <Route path="/mobile-app" element={<MobileApp />} />
            <Route path="/changelog" element={<Changelog />} />
            <Route path="/assignments" element={<AssignmentsManagement />} />
            <Route path="/client-portal" element={<ClientPortal />} />
            <Route path="/pipeline-map" element={<PipelineMap />} />
            <Route path="/reports-expertise" element={<ReportsAndExpertise />} />
            <Route path="*" element={<div className="text-center text-slate-500 mt-20">Раздел в разработке</div>} />
          </Route>
        </Routes>
      </HashRouter>
    </AuthProvider>
  );
};

export default App;

