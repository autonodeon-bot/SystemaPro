import React, { useState } from 'react';
import { HashRouter, Routes, Route, NavLink, useLocation, Navigate } from 'react-router-dom';
import { LayoutDashboard, Map as MapIcon, ClipboardList, BookOpen, Settings, Bell, User, Menu, X, FileText, Package, Users, FolderKanban, Calculator, FileCheck, Award, Sparkles, ListChecks, FileBarChart, Smartphone, Shield, LogOut } from 'lucide-react';
import { AuthProvider, useAuth } from './contexts/AuthContext';
import ProtectedRoute from './components/ProtectedRoute';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import PipelineMap from './pages/PipelineMap';
import DynamicInspection from './pages/DynamicInspection';
import TechSpecs from './pages/TechSpecs';
import Changelog from './pages/Changelog';
import Changelog from './pages/Changelog';
import EquipmentManagement from './pages/EquipmentManagement';
import ClientPortal from './pages/ClientPortal';
import ProjectsManagement from './pages/ProjectsManagement';
import ResourceManagement from './pages/ResourceManagement';
import RegulatoryDocuments from './pages/RegulatoryDocuments';
import CompetenciesManagement from './pages/CompetenciesManagement';
import ReportGeneration from './pages/ReportGeneration';
import InspectionsList from './pages/InspectionsList';
import ReportsAndExpertise from './pages/ReportsAndExpertise';
import SpecialistsManagement from './pages/SpecialistsManagement';
import MobileApp from './pages/MobileApp';
import AdminPanel from './pages/AdminPanel';
import EngineerPanel from './pages/EngineerPanel';

const SidebarItem = ({ to, icon: Icon, label, onClick }: { to: string, icon: any, label: string, onClick?: () => void }) => {
  const location = useLocation();
  const isActive = location.pathname === to;
  return (
    <NavLink 
      to={to} 
      onClick={onClick}
      className={`flex items-center gap-3 px-4 py-3 rounded-lg transition-colors whitespace-nowrap ${isActive ? 'bg-accent/20 text-accent border-r-2 border-accent' : 'text-slate-400 hover:bg-secondary hover:text-white'}`}
    >
      <Icon size={20} className="flex-shrink-0" />
      {label && <span className="font-medium">{label}</span>}
    </NavLink>
  );
};

interface LayoutProps {
  children: React.ReactNode;
}

const Layout: React.FC<LayoutProps> = ({ children }) => {
  const [isSidebarOpen, setSidebarOpen] = useState(false);
  const [isMobileMenuOpen, setMobileMenuOpen] = useState(false);
  const { user, logout, hasRole, hasPermission } = useAuth();

  return (
    <div className="flex h-screen bg-primary overflow-hidden">
      {/* Mobile Overlay */}
      {isMobileMenuOpen && (
        <div 
          className="fixed inset-0 bg-black/50 z-30 lg:hidden"
          onClick={() => setMobileMenuOpen(false)}
        />
      )}

      {/* Sidebar */}
      <aside className={`
        ${isSidebarOpen ? 'w-64' : 'w-0 lg:w-20'} 
        bg-secondary/50 border-r border-slate-700 transition-all duration-300 
        flex flex-col fixed lg:relative z-40 h-full
        ${isMobileMenuOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'}
      `}>
        <div className="p-4 flex items-center justify-between border-b border-slate-700 h-16 min-w-[256px] lg:min-w-0">
          {isSidebarOpen && <div className="flex items-center gap-2 font-bold text-white text-lg tracking-wider whitespace-nowrap"><div className="w-8 h-8 bg-accent rounded flex items-center justify-center">ES</div>ТД НГО</div>}
          <button 
            onClick={() => {
              setSidebarOpen(!isSidebarOpen);
              if (window.innerWidth < 1024) setMobileMenuOpen(false);
            }} 
            className="p-1 hover:bg-slate-700 rounded text-slate-400 ml-auto lg:ml-0"
          >
            {isSidebarOpen ? <X size={20}/> : <Menu size={20}/>}
          </button>
        </div>
        
        <nav className="flex-1 p-3 space-y-2 overflow-y-auto min-w-[256px] lg:min-w-0">
          <SidebarItem to="/" icon={LayoutDashboard} label={isSidebarOpen ? "Дашборд" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          <SidebarItem to="/equipment" icon={Package} label={isSidebarOpen ? "Оборудование" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          <SidebarItem to="/inspections-list" icon={ListChecks} label={isSidebarOpen ? "Чек-листы" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          <SidebarItem to="/reports-expertise" icon={FileBarChart} label={isSidebarOpen ? "Отчеты и Экспертизы" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          <SidebarItem to="/projects" icon={FolderKanban} label={isSidebarOpen ? "Проекты" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          <SidebarItem to="/resources" icon={Calculator} label={isSidebarOpen ? "Ресурс оборудования" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          <SidebarItem to="/reports" icon={Sparkles} label={isSidebarOpen ? "Генерация отчетов" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          <SidebarItem to="/regulatory" icon={FileCheck} label={isSidebarOpen ? "Нормативные документы" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          <SidebarItem to="/competencies" icon={Award} label={isSidebarOpen ? "Компетенции" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          <SidebarItem to="/specialists" icon={Users} label={isSidebarOpen ? "Специалисты НК" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          <SidebarItem to="/mobile-app" icon={Smartphone} label={isSidebarOpen ? "Мобильное приложение" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          
          {/* Раздел для инженеров */}
          {hasRole('engineer') && (
            <>
              <div className="my-4 border-t border-slate-700"></div>
              <SidebarItem to="/engineer" icon={Award} label={isSidebarOpen ? "Мои сертификаты" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
            </>
          )}
          
          {/* Админские разделы */}
          {(hasRole('admin') || hasRole('chief_operator')) && (
            <>
              <div className="my-4 border-t border-slate-700"></div>
              <SidebarItem to="/admin" icon={Shield} label={isSidebarOpen ? "Админ панель" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
            </>
          )}
          
          {/* Операторские разделы */}
          {(hasRole('admin') || hasRole('chief_operator') || hasRole('operator')) && (
            <SidebarItem to="/client-portal" icon={Users} label={isSidebarOpen ? "Клиентский портал" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          )}
          
          <SidebarItem to="/map" icon={MapIcon} label={isSidebarOpen ? "Карта ОПО" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          <SidebarItem to="/inspection" icon={ClipboardList} label={isSidebarOpen ? "Диагностика" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          <SidebarItem to="/specs" icon={BookOpen} label={isSidebarOpen ? "Архитектура" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          <SidebarItem to="/changelog" icon={FileText} label={isSidebarOpen ? "История изменений" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
          <div className="my-4 border-t border-slate-700"></div>
          <SidebarItem to="/settings" icon={Settings} label={isSidebarOpen ? "Настройки" : ""} onClick={() => window.innerWidth < 1024 && setMobileMenuOpen(false)} />
        </nav>
        
        <div className="p-4 border-t border-slate-700">
          {user && (
            <div className="space-y-3">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-full bg-accent flex items-center justify-center text-white font-bold">
                  {user.full_name?.[0]?.toUpperCase() || user.username[0].toUpperCase()}
                </div>
                {isSidebarOpen && (
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-bold text-white truncate">{user.full_name || user.username}</p>
                    <p className="text-xs text-slate-400 capitalize">{user.role}</p>
                  </div>
                )}
              </div>
              {isSidebarOpen && (
                <button
                  onClick={logout}
                  className="w-full flex items-center gap-2 px-3 py-2 bg-red-500/20 hover:bg-red-500/30 rounded-lg text-red-400 transition-colors text-sm font-medium"
                >
                  <LogOut size={16} />
                  <span>Выйти</span>
                </button>
              )}
            </div>
          )}
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 flex flex-col min-w-0 overflow-hidden relative lg:ml-0">
        {/* Header */}
        <header className="h-16 bg-primary/95 backdrop-blur border-b border-slate-700 flex items-center justify-between px-4 sm:px-6 z-10">
           <div className="flex items-center gap-4">
             <button 
               onClick={() => {
                 setMobileMenuOpen(true);
                 setSidebarOpen(true);
               }}
               className="lg:hidden p-2 text-slate-400 hover:text-white transition"
             >
               <Menu size={20} />
             </button>
             <h2 className="text-base sm:text-lg font-semibold text-white truncate">Единая цифровая платформа</h2>
           </div>
           <div className="flex items-center gap-2 sm:gap-4">
              <button className="relative p-2 text-slate-400 hover:text-white transition">
                 <Bell size={20} />
                 <span className="absolute top-1 right-1 w-2 h-2 bg-danger rounded-full"></span>
              </button>
           </div>
        </header>

        {/* Scrollable Area */}
        <div className="flex-1 overflow-auto p-4 sm:p-6 scroll-smooth">
          <div className="max-w-full">
            {children}
          </div>
        </div>
      </main>
    </div>
  );
};

const AppRoutes = () => {
  const { isAuthenticated, loading } = useAuth();

  // Показываем загрузку при проверке авторизации
  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-primary">
        <div className="text-center">
          <div className="inline-block w-8 h-8 border-4 border-accent border-t-transparent rounded-full animate-spin mb-4"></div>
          <p className="text-slate-400">Загрузка...</p>
        </div>
      </div>
    );
  }

  return (
    <Routes>
      <Route 
        path="/login" 
        element={isAuthenticated ? <Navigate to="/" replace /> : <Login />} 
      />
      <Route
        path="/"
        element={
          <ProtectedRoute>
            <Layout>
              <Dashboard />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/equipment"
        element={
          <ProtectedRoute>
            <Layout>
              <EquipmentManagement />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/inspections-list"
        element={
          <ProtectedRoute>
            <Layout>
              <InspectionsList />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/reports-expertise"
        element={
          <ProtectedRoute>
            <Layout>
              <ReportsAndExpertise />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/projects"
        element={
          <ProtectedRoute>
            <Layout>
              <ProjectsManagement />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/resources"
        element={
          <ProtectedRoute>
            <Layout>
              <ResourceManagement />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/reports"
        element={
          <ProtectedRoute>
            <Layout>
              <ReportGeneration />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/regulatory"
        element={
          <ProtectedRoute>
            <Layout>
              <RegulatoryDocuments />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/competencies"
        element={
          <ProtectedRoute>
            <Layout>
              <CompetenciesManagement />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/specialists"
        element={
          <ProtectedRoute>
            <Layout>
              <SpecialistsManagement />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/mobile-app"
        element={
          <ProtectedRoute>
            <Layout>
              <MobileApp />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/admin"
        element={
          <ProtectedRoute requiredRole="admin">
            <Layout>
              <AdminPanel />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/engineer"
        element={
          <ProtectedRoute requiredRole="engineer">
            <Layout>
              <EngineerPanel />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/client-portal"
        element={
          <ProtectedRoute>
            <Layout>
              <ClientPortal />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/map"
        element={
          <ProtectedRoute>
            <Layout>
              <PipelineMap />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/inspection"
        element={
          <ProtectedRoute>
            <Layout>
              <DynamicInspection />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/specs"
        element={
          <ProtectedRoute>
            <Layout>
              <TechSpecs />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route
        path="/changelog"
        element={
          <ProtectedRoute>
            <Layout>
              <Changelog />
            </Layout>
          </ProtectedRoute>
        }
      />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
};

const App = () => {
  return (
    <AuthProvider>
      <HashRouter>
        <AppRoutes />
      </HashRouter>
    </AuthProvider>
  );
};

export default App;