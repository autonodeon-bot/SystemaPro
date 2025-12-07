import React from 'react';
import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, CartesianGrid, LineChart, Line } from 'recharts';
import { AlertTriangle, CheckCircle, Clock, Activity } from 'lucide-react';
import { INSPECTION_TASKS } from '../constants';
import { RiskLevel } from '../types';

const data = [
  { name: 'Янв', issues: 4, checked: 20 },
  { name: 'Фев', issues: 3, checked: 25 },
  { name: 'Мар', issues: 2, checked: 22 },
  { name: 'Апр', issues: 6, checked: 30 },
  { name: 'Май', issues: 8, checked: 35 },
  { name: 'Июн', issues: 5, checked: 28 },
];

const StatCard = ({ title, value, sub, icon: Icon, color }: { title: string, value: string, sub: string, icon: any, color: string }) => (
  <div className="bg-secondary rounded-xl p-6 border border-slate-700 shadow-lg relative overflow-hidden group">
    <div className={`absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity ${color}`}>
        <Icon size={64} />
    </div>
    <div className="relative z-10">
        <p className="text-slate-400 text-sm font-medium mb-1">{title}</p>
        <h3 className="text-3xl font-bold text-white mb-2">{value}</h3>
        <p className="text-xs text-slate-500">{sub}</p>
    </div>
  </div>
);

const RiskBadge = ({ level }: { level: RiskLevel }) => {
  const colors = {
    [RiskLevel.LOW]: 'bg-success/20 text-success border-success/30',
    [RiskLevel.MEDIUM]: 'bg-warning/20 text-warning border-warning/30',
    [RiskLevel.HIGH]: 'bg-orange-500/20 text-orange-400 border-orange-500/30',
    [RiskLevel.CRITICAL]: 'bg-danger/20 text-danger border-danger/30',
  };
  return (
    <span className={`px-2 py-1 rounded text-xs border font-bold ${colors[level]}`}>
      {level}
    </span>
  );
};

const Dashboard = () => {
  return (
    <div className="space-y-4 sm:space-y-6">
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 sm:gap-6">
        <StatCard title="Всего объектов" value="1,248" sub="+12 новых за месяц" icon={Activity} color="text-blue-500" />
        <StatCard title="Критические дефекты" value="3" sub="Требуют немедленного внимания" icon={AlertTriangle} color="text-red-500" />
        <StatCard title="Проверено (мес)" value="86" sub="98% выполнение плана" icon={CheckCircle} color="text-green-500" />
        <StatCard title="В работе" value="14" sub="Текущие инспекции" icon={Clock} color="text-yellow-500" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 sm:gap-6">
        {/* Main Chart */}
        <div className="lg:col-span-2 bg-secondary rounded-xl p-4 sm:p-6 border border-slate-700 overflow-hidden">
          <h3 className="text-base sm:text-lg font-bold text-white mb-4 sm:mb-6">Динамика выявления дефектов</h3>
          <div className="h-64 sm:h-80 w-full overflow-x-auto">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={data}>
                <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
                <XAxis dataKey="name" stroke="#94a3b8" />
                <YAxis stroke="#94a3b8" />
                <Tooltip 
                    contentStyle={{ backgroundColor: '#1e293b', borderColor: '#475569', color: '#fff' }}
                />
                <Bar dataKey="checked" name="Проверено" fill="#3b82f6" radius={[4, 4, 0, 0]} />
                <Bar dataKey="issues" name="Дефекты" fill="#ef4444" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Task List */}
        <div className="bg-secondary rounded-xl p-4 sm:p-6 border border-slate-700 flex flex-col">
           <h3 className="text-base sm:text-lg font-bold text-white mb-4">Ближайшие инспекции</h3>
           <div className="flex-1 overflow-y-auto space-y-4 pr-2">
             {INSPECTION_TASKS.map(task => (
               <div key={task.id} className="p-3 bg-slate-800/50 rounded-lg border border-slate-700 hover:border-slate-500 transition">
                  <div className="flex justify-between items-start mb-2">
                    <span className="text-sm font-bold text-white">{task.equipmentName}</span>
                    <RiskBadge level={task.riskLevel} />
                  </div>
                  <div className="flex justify-between text-xs text-slate-400">
                     <span>{task.type}</span>
                     <span>{task.date}</span>
                  </div>
                  <div className="mt-2 text-xs text-slate-500">
                    Ответственный: <span className="text-slate-300">{task.assignee}</span>
                  </div>
               </div>
             ))}
           </div>
           <button className="w-full mt-4 py-2 bg-accent/10 text-accent rounded-lg text-sm font-medium hover:bg-accent/20 transition">
             Перейти к графику
           </button>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;