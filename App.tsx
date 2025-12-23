import React, { useState } from 'react';
import { HashRouter, Routes, Route, NavLink, useLocation, useNavigate, Outlet } from 'react-router-dom';
import { LayoutDashboard, ClipboardList, BookOpen, Settings, Bell, User, Menu, X, FileText, Package, Users, FolderKanban, Calculator, FileCheck, Award, Sparkles, ListChecks, Smartphone, LogOut, CheckCircle2, Calendar } from 'lucide-react';
import { useAuth, AuthProvider } from './contexts/AuthContext';
import Dashboard from './pages/Dashboard';
import DynamicInspection from './pages/DynamicInspection';
import TechSpecs from './pages/TechSpecs';
import EquipmentManagement from './pages/EquipmentManagement';
import EquipmentHierarchy from './pages/EquipmentHierarchy';
import EquipmentDetails from './pages/EquipmentDetails';
import ProjectsManagement from './pages/ProjectsManagement';
import ResourceManagement from './pages/ResourceManagement';
import RegulatoryDocuments from './pages/RegulatoryDocuments';
import CompetenciesManagement from './pages/CompetenciesManagement';
import ReportGeneration from './pages/ReportGeneration';
import InspectionsList from './pages/InspectionsList';
import MobileApp from './pages/MobileApp';
import Changelog from './pages/Changelog';
import AssignmentsManagement from './pages/AssignmentsManagement';
import UsersManagement from './pages/UsersManagement';
import VerificationsManagement from './pages/VerificationsManagement';
import VerificationsCalendar from './pages/VerificationsCalendar';
import Login from './pages/Login';
import ProtectedRoute from './components/ProtectedRoute';

const SidebarItem = ({ to, icon: Icon, label }: { to: string, icon: any, label: string }) => {
  const location = useLocation();
  const isActive = location.pathname === to;
  return (
    <NavLink to={to} className={`flex items-center gap-3 px-4 py-3 rounded-lg transition-colors ${isActive ? 'bg-accent/20 text-accent border-r-2 border-accent' : 'text-slate-400 hover:bg-secondary hover:text-white'}`}>
      <Icon size={20} />
      <span className="font-medium">{label}</span>
    </NavLink>
  );
};

const Layout: React.FC = () => {
  const [isSidebarOpen, setSidebarOpen] = useState(false); // Закрыт по умолчанию на мобильных
  const { user, logout } = useAuth();
  const navigate = useNavigate();

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
    <div className="flex h-screen bg-primary overflow-hidden">
      {/* Sidebar */}
      <aside className={`${isSidebarOpen ? 'w-64' : 'w-20'} bg-secondary/50 border-r border-slate-700 transition-all duration-300 flex flex-col fixed md:relative z-30 h-full ${isSidebarOpen ? 'left-0' : '-left-20 md:left-0'}`}>
        <div className="p-4 flex items-center justify-between border-b border-slate-700 h-16">
          {isSidebarOpen && <div className="flex items-center gap-2 font-bold text-white text-lg tracking-wider"><div className="w-8 h-8 bg-accent rounded flex items-center justify-center">ES</div>ТД НГО</div>}
          <button onClick={() => setSidebarOpen(!isSidebarOpen)} className="p-1 hover:bg-slate-700 rounded text-slate-400">
            {isSidebarOpen ? <X size={20}/> : <Menu size={20}/>}
          </button>
        </div>
        
        <nav className="flex-1 p-3 space-y-2 overflow-y-auto">
          <SidebarItem to="/" icon={LayoutDashboard} label={isSidebarOpen ? "Дашборд" : ""} />
          <SidebarItem to="/equipment" icon={Package} label={isSidebarOpen ? "Оборудование" : ""} />
          <SidebarItem to="/equipment-hierarchy" icon={Package} label={isSidebarOpen ? "Оборудование для диагностики" : ""} />
          <SidebarItem to="/assignments" icon={ClipboardList} label={isSidebarOpen ? "Задания" : ""} />
          <SidebarItem to="/inspections-list" icon={ListChecks} label={isSidebarOpen ? "Чек-листы" : ""} />
          <SidebarItem to="/projects" icon={FolderKanban} label={isSidebarOpen ? "Проекты" : ""} />
          <SidebarItem to="/resources" icon={Calculator} label={isSidebarOpen ? "Ресурс оборудования" : ""} />
          <SidebarItem to="/reports" icon={Sparkles} label={isSidebarOpen ? "Генерация отчетов" : ""} />
          <SidebarItem to="/verifications" icon={CheckCircle2} label={isSidebarOpen ? "Поверки" : ""} />
          <SidebarItem to="/regulatory" icon={FileCheck} label={isSidebarOpen ? "Нормативные документы" : ""} />
          <SidebarItem to="/competencies" icon={Award} label={isSidebarOpen ? "Компетенции" : ""} />
          {user?.role === 'admin' && (
            <SidebarItem to="/users" icon={Users} label={isSidebarOpen ? "Сотрудники" : ""} />
          )}
          <SidebarItem to="/inspection" icon={ClipboardList} label={isSidebarOpen ? "Диагностика" : ""} />
          <SidebarItem to="/specs" icon={BookOpen} label={isSidebarOpen ? "Архитектура" : ""} />
          <SidebarItem to="/mobile-app" icon={Smartphone} label={isSidebarOpen ? "Мобильное приложение" : ""} />
          <div className="my-4 border-t border-slate-700"></div>
          <SidebarItem to="/changelog" icon={Sparkles} label={isSidebarOpen ? "Что нового?" : ""} />
          <SidebarItem to="/settings" icon={Settings} label={isSidebarOpen ? "Настройки" : ""} />
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
             <span className="text-xs text-slate-400 ml-2 hidden sm:inline">v3.6.2</span>
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
          <Outlet />
        </div>
      </main>
    </div>
  );
};

const App = () => {
  return (
    <AuthProvider>
      <HashRouter>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route
            element={
              <ProtectedRoute>
                <Layout />
              </ProtectedRoute>
            }
          >
            <Route path="/" element={<Dashboard />} />
            <Route path="/equipment" element={<EquipmentManagement />} />
            <Route path="/equipment/:id" element={<EquipmentDetails />} />
            <Route path="/equipment-hierarchy" element={<EquipmentHierarchy />} />
            <Route path="/inspections-list" element={<InspectionsList />} />
            <Route path="/projects" element={<ProjectsManagement />} />
            <Route path="/resources" element={<ResourceManagement />} />
            <Route path="/reports" element={<ReportGeneration />} />
            <Route path="/verifications" element={<VerificationsManagement />} />
            <Route path="/verifications-calendar" element={<VerificationsCalendar />} />
            <Route path="/regulatory" element={<RegulatoryDocuments />} />
            <Route path="/competencies" element={<CompetenciesManagement />} />
            <Route path="/users" element={<ProtectedRoute requiredRole="admin"><UsersManagement /></ProtectedRoute>} />
            <Route path="/inspection" element={<DynamicInspection />} />
            <Route path="/specs" element={<TechSpecs />} />
            <Route path="/mobile-app" element={<MobileApp />} />
            <Route path="/changelog" element={<Changelog />} />
            <Route path="/assignments" element={<AssignmentsManagement />} />
            <Route path="*" element={<div className="text-center text-slate-500 mt-20">Раздел в разработке</div>} />
          </Route>
        </Routes>
      </HashRouter>
    </AuthProvider>
  );
};

export default App;