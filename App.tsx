import React, { useState } from 'react';
import { HashRouter, Routes, Route, NavLink, useLocation } from 'react-router-dom';
import { LayoutDashboard, Map as MapIcon, ClipboardList, BookOpen, Settings, Bell, User, Menu, X, FileText, Package, Users, FolderKanban, Calculator, FileCheck, Award, Sparkles, ListChecks, FileBarChart } from 'lucide-react';
import Dashboard from './pages/Dashboard';
import PipelineMap from './pages/PipelineMap';
import DynamicInspection from './pages/DynamicInspection';
import TechSpecs from './pages/TechSpecs';
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

interface LayoutProps {
  children: React.ReactNode;
}

const Layout: React.FC<LayoutProps> = ({ children }) => {
  const [isSidebarOpen, setSidebarOpen] = useState(true);

  return (
    <div className="flex h-screen bg-primary">
      {/* Sidebar */}
      <aside className={`${isSidebarOpen ? 'w-64' : 'w-20'} bg-secondary/50 border-r border-slate-700 transition-all duration-300 flex flex-col fixed md:relative z-20 h-full`}>
        <div className="p-4 flex items-center justify-between border-b border-slate-700 h-16">
          {isSidebarOpen && <div className="flex items-center gap-2 font-bold text-white text-lg tracking-wider"><div className="w-8 h-8 bg-accent rounded flex items-center justify-center">ES</div>ТД НГО</div>}
          <button onClick={() => setSidebarOpen(!isSidebarOpen)} className="p-1 hover:bg-slate-700 rounded text-slate-400">
            {isSidebarOpen ? <X size={20}/> : <Menu size={20}/>}
          </button>
        </div>
        
        <nav className="flex-1 p-3 space-y-2 overflow-y-auto">
          <SidebarItem to="/" icon={LayoutDashboard} label={isSidebarOpen ? "Дашборд" : ""} />
          <SidebarItem to="/equipment" icon={Package} label={isSidebarOpen ? "Оборудование" : ""} />
          <SidebarItem to="/inspections-list" icon={ListChecks} label={isSidebarOpen ? "Чек-листы" : ""} />
          <SidebarItem to="/reports-expertise" icon={FileBarChart} label={isSidebarOpen ? "Отчеты и Экспертизы" : ""} />
          <SidebarItem to="/projects" icon={FolderKanban} label={isSidebarOpen ? "Проекты" : ""} />
          <SidebarItem to="/resources" icon={Calculator} label={isSidebarOpen ? "Ресурс оборудования" : ""} />
          <SidebarItem to="/reports" icon={Sparkles} label={isSidebarOpen ? "Генерация отчетов" : ""} />
          <SidebarItem to="/regulatory" icon={FileCheck} label={isSidebarOpen ? "Нормативные документы" : ""} />
          <SidebarItem to="/competencies" icon={Award} label={isSidebarOpen ? "Компетенции" : ""} />
          <SidebarItem to="/specialists" icon={Users} label={isSidebarOpen ? "Специалисты НК" : ""} />
          <SidebarItem to="/client-portal" icon={Users} label={isSidebarOpen ? "Клиентский портал" : ""} />
          <SidebarItem to="/map" icon={MapIcon} label={isSidebarOpen ? "Карта ОПО" : ""} />
          <SidebarItem to="/inspection" icon={ClipboardList} label={isSidebarOpen ? "Диагностика" : ""} />
          <SidebarItem to="/specs" icon={BookOpen} label={isSidebarOpen ? "Архитектура" : ""} />
          <div className="my-4 border-t border-slate-700"></div>
          <SidebarItem to="/settings" icon={Settings} label={isSidebarOpen ? "Настройки" : ""} />
        </nav>
        
        <div className="p-4 border-t border-slate-700">
          <div className="flex items-center gap-3">
             <div className="w-10 h-10 rounded-full bg-slate-600 flex items-center justify-center text-white font-bold">A</div>
             {isSidebarOpen && <div>
                <p className="text-sm font-bold text-white">Администратор</p>
                <p className="text-xs text-slate-400">ООО "ГазНефть"</p>
             </div>}
          </div>
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 flex flex-col min-w-0 overflow-hidden relative">
        {/* Header */}
        <header className="h-16 bg-primary/95 backdrop-blur border-b border-slate-700 flex items-center justify-between px-6 z-10">
           <h2 className="text-lg font-semibold text-white">Единая цифровая платформа</h2>
           <div className="flex items-center gap-4">
              <button className="relative p-2 text-slate-400 hover:text-white transition">
                 <Bell size={20} />
                 <span className="absolute top-1 right-1 w-2 h-2 bg-danger rounded-full"></span>
              </button>
           </div>
        </header>

        {/* Scrollable Area */}
        <div className="flex-1 overflow-auto p-6 scroll-smooth">
          {children}
        </div>
      </main>
    </div>
  );
};

const App = () => {
  return (
    <HashRouter>
      <Layout>
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/equipment" element={<EquipmentManagement />} />
          <Route path="/inspections-list" element={<InspectionsList />} />
          <Route path="/reports-expertise" element={<ReportsAndExpertise />} />
          <Route path="/projects" element={<ProjectsManagement />} />
          <Route path="/resources" element={<ResourceManagement />} />
          <Route path="/reports" element={<ReportGeneration />} />
          <Route path="/regulatory" element={<RegulatoryDocuments />} />
          <Route path="/competencies" element={<CompetenciesManagement />} />
          <Route path="/specialists" element={<SpecialistsManagement />} />
          <Route path="/client-portal" element={<ClientPortal />} />
          <Route path="/map" element={<PipelineMap />} />
          <Route path="/inspection" element={<DynamicInspection />} />
          <Route path="/specs" element={<TechSpecs />} />
          <Route path="*" element={<div className="text-center text-slate-500 mt-20">Раздел в разработке</div>} />
        </Routes>
      </Layout>
    </HashRouter>
  );
};

export default App;