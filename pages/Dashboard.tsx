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
  // SP-2026: плоская поверхность, крупные цифры, тонкий акцент вместо гигантской "тени" иконки
  <div className="sp-stat sp-animate-in group">
    <div className="flex items-start justify-between">
      <div className="flex-1 min-w-0">
        <p className="sp-stat__label">{title}</p>
        {loading ? (
          <div className="sp-skeleton h-9 w-24 my-1" />
        ) : (
          <h3 className="sp-stat__value">{value}</h3>
        )}
        <p className="sp-stat__sub">{sub}</p>
      </div>
      <div
        className={`shrink-0 w-10 h-10 rounded-lg flex items-center justify-center transition-transform group-hover:scale-105 ${color}`}
        style={{
          background: 'var(--bg-tertiary)',
          border: '1px solid var(--border-subtle)',
        }}
      >
        <Icon size={18} />
      </div>
    </div>
  </div>
);

const getPriorityBadge = (p: string) => {
  const map: Record<string, { label: string; cls: string }> = {
    LOW: { label: 'Низкий', cls: 'bg-app-text3/20 text-app-text2 border-app-text3/30' },
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
      <div className="sp-surface p-4 sm:p-5 sp-animate-in">
        <div className="flex items-center gap-2 mb-2">
          <Sparkles className="text-[var(--accent)]" size={18} />
          <h3 className="font-semibold" style={{ color: 'var(--text-primary)' }}>Что нового</h3>
          <span className="ind-chip ind-chip--info ind-mono" style={{ marginLeft: 'auto' }}>v{APP_VERSION}</span>
        </div>
        <p className="text-xs mb-2" style={{ color: 'var(--text-muted)' }}>
          Актуально на {RELEASE_NOTES_DATE} — последние доработки web, mobile и backend:
        </p>
        <ul className="text-sm list-disc list-inside space-y-1.5 marker:text-[var(--accent)]" style={{ color: 'var(--text-secondary)' }}>
          {DASHBOARD_WHATS_NEW_ITEMS.map((line) => (
            <li key={line}>{line}</li>
          ))}
        </ul>
        <a href="#/changelog" className="mt-2 inline-block text-sm" style={{ color: 'var(--accent)' }}>
          Открыть список изменений →
        </a>
      </div>

      {(verificationAlerts.expired > 0 || verificationAlerts.warning7 > 0 || verificationAlerts.warning30 > 0) && (
        <div className="sp-surface p-4 sm:p-5 sp-animate-in">
          <div className="flex items-center gap-2 mb-3">
            <CheckCircle2 className="text-[var(--accent)]" size={18} />
            <h3 className="font-semibold" style={{ color: 'var(--text-primary)' }}>Предупреждения о поверках оборудования</h3>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            {verificationAlerts.expired > 0 && (
              <div className="sp-surface-flat p-3" style={{ borderColor: 'rgba(239,68,68,0.25)', background: 'var(--danger-bg)' }}>
                <div className="text-sm flex items-center gap-1" style={{ color: 'var(--danger)' }}>
                  <AlertTriangle size={15} /> Просрочено
                </div>
                <div className="text-2xl font-bold mt-1 tabular-nums" style={{ color: 'var(--danger)' }}>{verificationAlerts.expired}</div>
              </div>
            )}
            {verificationAlerts.warning7 > 0 && (
              <div className="sp-surface-flat p-3" style={{ borderColor: 'rgba(245,158,11,0.25)', background: 'var(--warning-bg)' }}>
                <div className="text-sm flex items-center gap-1" style={{ color: 'var(--warning)' }}>
                  <AlertTriangle size={15} /> Истекает ≤7 дней
                </div>
                <div className="text-2xl font-bold mt-1 tabular-nums" style={{ color: 'var(--warning)' }}>{verificationAlerts.warning7}</div>
              </div>
            )}
            {verificationAlerts.warning30 > 0 && (
              <div className="sp-surface-flat p-3" style={{ borderColor: 'rgba(245,158,11,0.18)', background: 'rgba(245,158,11,0.06)' }}>
                <div className="text-sm flex items-center gap-1" style={{ color: 'var(--warning)' }}>
                  <Clock size={15} /> Истекает ≤30 дней
                </div>
                <div className="text-2xl font-bold mt-1 tabular-nums" style={{ color: 'var(--warning)' }}>{verificationAlerts.warning30}</div>
              </div>
            )}
          </div>
          <a href="#/verifications" className="mt-3 inline-block text-sm" style={{ color: 'var(--accent)' }}>
            Перейти к управлению поверками →
          </a>
        </div>
      )}

      {stats && (
        <div className="sp-surface p-4 sm:p-5 sp-animate-in">
          <div className="flex items-center gap-2 mb-3">
            <BarChart2 className="text-[var(--accent)]" size={18} />
            <h3 className="font-semibold" style={{ color: 'var(--text-primary)' }}>Статистика за {stats.period_days} дней</h3>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div className="flex items-center gap-3 p-3 sp-surface-flat">
              <Activity size={22} style={{ color: 'var(--accent)' }} />
              <div>
                <div className="text-xl font-bold tabular-nums" style={{ color: 'var(--text-primary)' }}>{stats.inspections}</div>
                <div className="text-xs" style={{ color: 'var(--text-muted)' }}>Обследований</div>
              </div>
            </div>
            <div className="flex items-center gap-3 p-3 sp-surface-flat">
              <FileText size={22} style={{ color: 'var(--success)' }} />
              <div>
                <div className="text-xl font-bold tabular-nums" style={{ color: 'var(--text-primary)' }}>{stats.reports}</div>
                <div className="text-xs" style={{ color: 'var(--text-muted)' }}>Отчётов</div>
              </div>
            </div>
            <div className="flex items-center gap-3 p-3 sp-surface-flat">
              <ClipboardList size={22} style={{ color: 'var(--warning)' }} />
              <div>
                <div className="text-xl font-bold tabular-nums" style={{ color: 'var(--text-primary)' }}>{stats.assignments}</div>
                <div className="text-xs" style={{ color: 'var(--text-muted)' }}>Заданий</div>
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
        <div className="lg:col-span-2 sp-surface p-4 sm:p-6 overflow-hidden sp-animate-in">
          <h3 className="text-base sm:text-lg font-bold mb-4 sm:mb-6" style={{ color: 'var(--text-primary)' }}>Динамика обследований по месяцам</h3>
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
              <div className="flex items-center justify-center h-full text-app-text3">
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

        <div className="sp-surface p-4 sm:p-6 flex flex-col sp-animate-in">
          <h3 className="text-base sm:text-lg font-bold mb-4" style={{ color: 'var(--text-primary)' }}>Ближайшие задания</h3>
          <div className="flex-1 overflow-y-auto space-y-3 pr-2">
            {assignmentsLoading ? (
              Array.from({ length: 3 }).map((_, i) => (
                <div key={i} className="sp-surface-flat p-3 space-y-2">
                  <div className="sp-skeleton h-4 w-3/4" />
                  <div className="sp-skeleton h-3 w-1/2" />
                  <div className="sp-skeleton h-3 w-1/3" />
                </div>
              ))
            ) : upcomingAssignments.length > 0 ? (
              upcomingAssignments.map(task => (
                <div key={task.id} className="sp-surface-flat p-3 transition hover:border-[var(--border-accent)]">
                  <div className="flex justify-between items-start mb-2 gap-2">
                    <div className="flex-1 min-w-0">
                      <span className="text-sm font-semibold block truncate" style={{ color: 'var(--text-primary)' }}>{task.equipment_name}</span>
                      <span className="text-xs ind-mono" style={{ color: 'var(--text-muted)' }}>{task.equipment_code}</span>
                    </div>
                    {getPriorityBadge(task.priority)}
                  </div>
                  <div className="flex justify-between text-xs" style={{ color: 'var(--text-secondary)' }}>
                    <span>{getTypeLabel(task.assignment_type)}</span>
                    {task.due_date && (
                      <span className="flex items-center gap-1 ind-mono">
                        <Calendar size={12} />
                        {new Date(task.due_date).toLocaleDateString('ru-RU')}
                      </span>
                    )}
                  </div>
                  {task.assigned_to_name && (
                    <div className="mt-2 text-xs flex items-center gap-1" style={{ color: 'var(--text-muted)' }}>
                      <User size={12} />
                      <span style={{ color: 'var(--text-secondary)' }}>{task.assigned_to_name}</span>
                    </div>
                  )}
                </div>
              ))
            ) : (
              <div className="text-center py-6" style={{ color: 'var(--text-muted)' }}>
                <ClipboardList className="mx-auto mb-2 opacity-30" size={32} />
                <p className="text-sm">Нет активных заданий</p>
              </div>
            )}
          </div>
          <a
            href="#/assignments"
            className="ind-btn ind-btn--primary w-full mt-4"
          >
            Перейти к заданиям
          </a>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
