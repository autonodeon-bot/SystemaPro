import React, { useState, useEffect } from 'react';
import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, CartesianGrid } from 'recharts';
import { AlertTriangle, CheckCircle, Clock, Activity, CheckCircle2, Sparkles, BarChart2, FileText, ClipboardList, Calendar, User } from 'lucide-react';
import {
  API_BASE,
  APP_VERSION,
  DASHBOARD_WHATS_NEW_ITEMS,
  RELEASE_NOTES_DATE,
  getAssignmentTypeLabel,
} from '../constants';

interface DashboardStats {
  inspections: number;
  reports: number;
  assignments: number;
  period_days: number;
  by_month?: { month: string; count: number }[];
}

interface UpcomingAssignment {
  id: string;
  equipment_name: string;
  equipment_code: string;
  priority: string;
  status: string;
  due_date: string | null;
  assigned_to_name: string | null;
  assignment_type: string;
}

const StatCard = ({ title, value, sub, icon: Icon, color, loading }: {
  title: string; value: string; sub: string; icon: React.ElementType; color: string; loading?: boolean;
}) => (
  <div className="bg-secondary/80 rounded-2xl p-6 border border-slate-700/70 shadow-soft relative overflow-hidden group">
    <div className={`absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity ${color}`}>
      <Icon size={64} />
    </div>
    <div className="relative z-10">
      <p className="text-slate-400 text-sm font-medium mb-1">{title}</p>
      {loading ? (
        <div className="h-9 w-20 bg-slate-700 rounded animate-pulse mb-2" />
      ) : (
        <h3 className="text-3xl font-bold text-white mb-2">{value}</h3>
      )}
      <p className="text-xs text-slate-500">{sub}</p>
    </div>
  </div>
);

const getPriorityBadge = (p: string) => {
  const map: Record<string, { label: string; cls: string }> = {
    LOW: { label: 'Низкий', cls: 'bg-slate-500/20 text-slate-300 border-slate-500/30' },
    NORMAL: { label: 'Обычный', cls: 'bg-blue-500/20 text-blue-300 border-blue-500/30' },
    HIGH: { label: 'Высокий', cls: 'bg-orange-500/20 text-orange-400 border-orange-500/30' },
    URGENT: { label: 'Срочный', cls: 'bg-red-500/20 text-red-400 border-red-500/30' },
  };
  const v = map[p] || map.NORMAL;
  return <span className={`px-2 py-1 rounded text-xs border font-bold ${v.cls}`}>{v.label}</span>;
};

const getTypeLabel = (t: string) => getAssignmentTypeLabel(t);

const Dashboard = () => {
  const [verificationAlerts, setVerificationAlerts] = useState<{
    expired: number; warning7: number; warning30: number;
  }>({ expired: 0, warning7: 0, warning30: 0 });
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [statsLoading, setStatsLoading] = useState(true);
  const [upcomingAssignments, setUpcomingAssignments] = useState<UpcomingAssignment[]>([]);
  const [assignmentsLoading, setAssignmentsLoading] = useState(true);
  const [equipmentCount, setEquipmentCount] = useState<number | null>(null);
  const [inProgressCount, setInProgressCount] = useState<number>(0);

  useEffect(() => {
    loadVerificationAlerts();
    loadStats();
    loadUpcomingAssignments();
    loadEquipmentCount();
  }, []);

  const getHeaders = (): HeadersInit => {
    const token = localStorage.getItem('token');
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (token) headers['Authorization'] = `Bearer ${token}`;
    return headers;
  };

  const loadStats = async () => {
    try {
      setStatsLoading(true);
      const res = await fetch(`${API_BASE}/api/stats?days=30`, { headers: getHeaders() });
      if (res.ok) setStats(await res.json());
    } catch (e) {
      console.error('Ошибка загрузки статистики:', e);
    } finally {
      setStatsLoading(false);
    }
  };

  const loadUpcomingAssignments = async () => {
    try {
      setAssignmentsLoading(true);
      const headers = getHeaders();
      const [pendingRes, progressRes] = await Promise.all([
        fetch(`${API_BASE}/api/assignments?status=PENDING&limit=5`, { headers }),
        fetch(`${API_BASE}/api/assignments?status=IN_PROGRESS&limit=10`, { headers }),
      ]);
      let combined: UpcomingAssignment[] = [];
      if (pendingRes.ok) {
        const data = await pendingRes.json();
        combined = [...combined, ...(Array.isArray(data) ? data : [])];
      }
      if (progressRes.ok) {
        const data = await progressRes.json();
        const items = Array.isArray(data) ? data : [];
        setInProgressCount(items.length);
        combined = [...combined, ...items];
      }
      combined.sort((a, b) => {
        if (!a.due_date) return 1;
        if (!b.due_date) return -1;
        return new Date(a.due_date).getTime() - new Date(b.due_date).getTime();
      });
      setUpcomingAssignments(combined.slice(0, 5));
    } catch (e) {
      console.error('Ошибка загрузки заданий:', e);
    } finally {
      setAssignmentsLoading(false);
    }
  };

  const loadEquipmentCount = async () => {
    try {
      const res = await fetch(`${API_BASE}/api/equipment?limit=1`, { headers: getHeaders() });
      if (res.ok) {
        const data = await res.json();
        if (data.total !== undefined) {
          setEquipmentCount(data.total);
        } else if (Array.isArray(data.items)) {
          setEquipmentCount(data.items.length);
        } else if (Array.isArray(data)) {
          setEquipmentCount(data.length);
        }
      }
    } catch (e) {
      console.error('Ошибка загрузки кол-ва оборудования:', e);
    }
  };

  const loadVerificationAlerts = async () => {
    try {
      const headers = getHeaders();
      const expiredRes = await fetch(`${API_BASE}/api/verification-equipment?is_active=true`, { headers });
      if (expiredRes.ok) {
        const expired = await expiredRes.json();
        const expiredCount = expired.filter((e: any) => e.is_expired).length;
        const warning7Count = expired.filter((e: any) => !e.is_expired && e.days_until_expiry !== null && e.days_until_expiry <= 7 && e.days_until_expiry > 0).length;
        const warning30Count = expired.filter((e: any) => !e.is_expired && e.days_until_expiry !== null && e.days_until_expiry <= 30 && e.days_until_expiry > 7).length;
        setVerificationAlerts({ expired: expiredCount, warning7: warning7Count, warning30: warning30Count });
      }
    } catch (error) {
      console.error('Ошибка загрузки предупреждений о поверках:', error);
    }
  };

  const chartData = stats?.by_month?.map(item => ({
    name: item.month,
    'Обследований': item.count,
  })) || [];

  return (
    <div className="space-y-4 sm:space-y-6">
      <div className="bg-secondary/60 rounded-2xl p-4 border border-slate-700/70 shadow-soft">
        <div className="flex items-center gap-2 mb-2">
          <Sparkles className="text-accent" size={20} />
          <h3 className="text-white font-semibold">Что нового</h3>
        </div>
        <p className="text-slate-400 text-xs mb-2">
          Версия {APP_VERSION}, актуально на {RELEASE_NOTES_DATE} — последние доработки web, mobile и backend:
        </p>
        <ul className="text-slate-300 text-sm list-disc list-inside space-y-1.5 marker:text-accent">
          {DASHBOARD_WHATS_NEW_ITEMS.map((line) => (
            <li key={line}>{line}</li>
          ))}
        </ul>
        <a href="#/changelog" className="mt-2 inline-block text-sm text-blue-400 hover:text-blue-300">
          Открыть список изменений →
        </a>
      </div>

      {(verificationAlerts.expired > 0 || verificationAlerts.warning7 > 0 || verificationAlerts.warning30 > 0) && (
        <div className="bg-secondary/60 rounded-2xl p-4 border border-slate-700/70 shadow-soft">
          <div className="flex items-center gap-2 mb-3">
            <CheckCircle2 className="text-blue-400" size={20} />
            <h3 className="text-white font-semibold">Предупреждения о поверках оборудования</h3>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            {verificationAlerts.expired > 0 && (
              <div className="bg-red-500/10 rounded-lg p-3 border border-red-500/20">
                <div className="text-red-400 text-sm flex items-center gap-1">
                  <AlertTriangle size={16} />
                  Просрочено
                </div>
                <div className="text-xl font-bold text-red-400 mt-1">{verificationAlerts.expired}</div>
              </div>
            )}
            {verificationAlerts.warning7 > 0 && (
              <div className="bg-orange-500/10 rounded-lg p-3 border border-orange-500/20">
                <div className="text-orange-400 text-sm flex items-center gap-1">
                  <AlertTriangle size={16} />
                  Истекает ≤7 дней
                </div>
                <div className="text-xl font-bold text-orange-400 mt-1">{verificationAlerts.warning7}</div>
              </div>
            )}
            {verificationAlerts.warning30 > 0 && (
              <div className="bg-yellow-500/10 rounded-lg p-3 border border-yellow-500/20">
                <div className="text-yellow-400 text-sm flex items-center gap-1">
                  <Clock size={16} />
                  Истекает ≤30 дней
                </div>
                <div className="text-xl font-bold text-yellow-400 mt-1">{verificationAlerts.warning30}</div>
              </div>
            )}
          </div>
          <a href="#/verifications" className="mt-3 inline-block text-sm text-blue-400 hover:text-blue-300">
            Перейти к управлению поверками →
          </a>
        </div>
      )}

      {stats && (
        <div className="bg-secondary/60 rounded-2xl p-4 border border-slate-700/70 shadow-soft">
          <div className="flex items-center gap-2 mb-3">
            <BarChart2 className="text-accent" size={20} />
            <h3 className="text-white font-semibold">Статистика за {stats.period_days} дней</h3>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div className="flex items-center gap-3 p-3 bg-slate-800/50 rounded-lg">
              <Activity className="text-blue-400" size={24} />
              <div>
                <div className="text-xl font-bold text-white">{stats.inspections}</div>
                <div className="text-xs text-slate-400">Обследований</div>
              </div>
            </div>
            <div className="flex items-center gap-3 p-3 bg-slate-800/50 rounded-lg">
              <FileText className="text-green-400" size={24} />
              <div>
                <div className="text-xl font-bold text-white">{stats.reports}</div>
                <div className="text-xs text-slate-400">Отчётов</div>
              </div>
            </div>
            <div className="flex items-center gap-3 p-3 bg-slate-800/50 rounded-lg">
              <ClipboardList className="text-yellow-400" size={24} />
              <div>
                <div className="text-xl font-bold text-white">{stats.assignments}</div>
                <div className="text-xs text-slate-400">Заданий</div>
              </div>
            </div>
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 sm:gap-6">
        <StatCard
          title="Всего объектов"
          value={equipmentCount !== null ? equipmentCount.toLocaleString('ru-RU') : '—'}
          sub="Зарегистрировано в системе"
          icon={Activity}
          color="text-blue-500"
          loading={equipmentCount === null && statsLoading}
        />
        <StatCard
          title="Обследований"
          value={stats?.inspections?.toString() ?? '—'}
          sub={`За ${stats?.period_days ?? 30} дней`}
          icon={CheckCircle}
          color="text-green-500"
          loading={statsLoading}
        />
        <StatCard
          title="Отчётов"
          value={stats?.reports?.toString() ?? '—'}
          sub={`За ${stats?.period_days ?? 30} дней`}
          icon={FileText}
          color="text-purple-500"
          loading={statsLoading}
        />
        <StatCard
          title="В работе"
          value={inProgressCount.toString()}
          sub="Текущие задания"
          icon={Clock}
          color="text-yellow-500"
          loading={assignmentsLoading}
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 sm:gap-6">
        <div className="lg:col-span-2 bg-secondary/80 rounded-2xl p-4 sm:p-6 border border-slate-700/70 shadow-soft overflow-hidden">
          <h3 className="text-base sm:text-lg font-bold text-white mb-4 sm:mb-6">Динамика обследований по месяцам</h3>
          <div className="h-64 sm:h-80 w-full overflow-x-auto">
            {chartData.length > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
                  <XAxis dataKey="name" stroke="#94a3b8" />
                  <YAxis stroke="#94a3b8" />
                  <Tooltip contentStyle={{ backgroundColor: '#1e293b', borderColor: '#475569', color: '#fff' }} />
                  <Bar dataKey="Обследований" name="Обследований" fill="#3b82f6" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="flex items-center justify-center h-full text-slate-400">
                {statsLoading ? (
                  <div className="flex items-center gap-3">
                    <div className="w-5 h-5 border-2 border-accent border-t-transparent rounded-full animate-spin" />
                    <span>Данные загружаются...</span>
                  </div>
                ) : (
                  <span>Нет данных за выбранный период</span>
                )}
              </div>
            )}
          </div>
        </div>

        <div className="bg-secondary/80 rounded-2xl p-4 sm:p-6 border border-slate-700/70 shadow-soft flex flex-col">
          <h3 className="text-base sm:text-lg font-bold text-white mb-4">Ближайшие задания</h3>
          <div className="flex-1 overflow-y-auto space-y-4 pr-2">
            {assignmentsLoading ? (
              Array.from({ length: 3 }).map((_, i) => (
                <div key={i} className="p-3 bg-slate-800/50 rounded-lg border border-slate-700 animate-pulse">
                  <div className="h-4 w-3/4 bg-slate-700 rounded mb-2" />
                  <div className="h-3 w-1/2 bg-slate-700 rounded mb-2" />
                  <div className="h-3 w-1/3 bg-slate-700 rounded" />
                </div>
              ))
            ) : upcomingAssignments.length > 0 ? (
              upcomingAssignments.map(task => (
                <div key={task.id} className="p-3 bg-slate-800/50 rounded-lg border border-slate-700 hover:border-slate-500 transition">
                  <div className="flex justify-between items-start mb-2">
                    <div className="flex-1 min-w-0">
                      <span className="text-sm font-bold text-white block truncate">{task.equipment_name}</span>
                      <span className="text-xs text-slate-500 font-mono">{task.equipment_code}</span>
                    </div>
                    {getPriorityBadge(task.priority)}
                  </div>
                  <div className="flex justify-between text-xs text-slate-400">
                    <span>{getTypeLabel(task.assignment_type)}</span>
                    {task.due_date && (
                      <span className="flex items-center gap-1">
                        <Calendar size={12} />
                        {new Date(task.due_date).toLocaleDateString('ru-RU')}
                      </span>
                    )}
                  </div>
                  {task.assigned_to_name && (
                    <div className="mt-2 text-xs text-slate-500 flex items-center gap-1">
                      <User size={12} />
                      <span className="text-slate-300">{task.assigned_to_name}</span>
                    </div>
                  )}
                </div>
              ))
            ) : (
              <div className="text-center text-slate-500 py-6">
                <ClipboardList className="mx-auto mb-2 opacity-30" size={32} />
                <p className="text-sm">Нет активных заданий</p>
              </div>
            )}
          </div>
          <a
            href="#/assignments"
            className="w-full mt-4 py-2 bg-accent/10 text-accent rounded-lg text-sm font-medium hover:bg-accent/20 transition text-center block"
          >
            Перейти к заданиям
          </a>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
