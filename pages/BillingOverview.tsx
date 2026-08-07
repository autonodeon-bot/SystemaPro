import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Link, Navigate } from 'react-router-dom';
import {
  Wallet,
  RefreshCw,
  Search,
  FolderKanban,
  CalendarClock,
  AlertCircle,
  Plus,
  Receipt,
  Trash2,
  FileText,
  Download,
} from 'lucide-react';
import { API_BASE } from '../constants';
import { useAuth } from '../contexts/AuthContext';
import { useToast } from '../contexts/ToastContext';

interface Client {
  id: string;
  name: string;
}

interface ProjectRow {
  id: string;
  client_id: string | null;
  name: string;
  status: string;
  deadline?: string | null;
  budget?: number | null;
}

interface ProjectInvoiceRow {
  id: string;
  project_id: string;
  invoice_number: string | null;
  amount: number;
  currency: string;
  status: string;
  issued_date: string | null;
  due_date: string | null;
  paid_date: string | null;
  description: string | null;
  payments_total?: number;
}

interface InvoicePaymentLine {
  id: string;
  amount: number;
  payment_date: string | null;
  note: string | null;
}

interface ProjectContractRow {
  id: string;
  project_id: string;
  contract_number: string | null;
  title: string | null;
  signed_date: string | null;
  end_date: string | null;
  amount: number | null;
  status: string;
  notes: string | null;
}

const STATUS_LABELS: Record<string, string> = {
  PLANNED: 'Запланирован',
  IN_PROGRESS: 'В работе',
  COMPLETED: 'Завершён',
  CANCELLED: 'Отменён',
};

const INVOICE_STATUS_LABELS: Record<string, string> = {
  DRAFT: 'Черновик',
  ISSUED: 'Выставлен',
  PAID: 'Оплачен',
  CANCELLED: 'Отменён',
};

const CONTRACT_STATUS_LABELS: Record<string, string> = {
  ACTIVE: 'Действует',
  CLOSED: 'Закрыт',
};

function formatMoney(n: number): string {
  return new Intl.NumberFormat('ru-RU', {
    style: 'currency',
    currency: 'RUB',
    maximumFractionDigits: 0,
  }).format(n);
}

function parseDeadline(s: string | null | undefined): Date | null {
  if (!s) return null;
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? null : d;
}

function formatRuDate(s: string | null | undefined): string {
  const d = parseDeadline(s);
  return d ? d.toLocaleDateString('ru-RU') : '—';
}

function escapeCsvField(v: string, sep: string): string {
  const s = v ?? '';
  if (s.includes(sep) || s.includes('"') || s.includes('\n') || s.includes('\r')) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

function downloadCsvFile(filename: string, header: string[], body: (string | number)[][]): void {
  const sep = ';';
  const lines = [
    header.map((h) => escapeCsvField(h, sep)).join(sep),
    ...body.map((row) => row.map((c) => escapeCsvField(String(c), sep)).join(sep)),
  ];
  const blob = new Blob([`\uFEFF${lines.join('\n')}`], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

const BillingOverview = () => {
  const { user, getToken } = useAuth();
  const toast = useToast();
  const [projects, setProjects] = useState<ProjectRow[]>([]);
  const [clients, setClients] = useState<Client[]>([]);
  const [invoices, setInvoices] = useState<ProjectInvoiceRow[]>([]);
  const [contracts, setContracts] = useState<ProjectContractRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [showInvoiceForm, setShowInvoiceForm] = useState(false);
  const [savingInvoice, setSavingInvoice] = useState(false);
  const [invoiceActionId, setInvoiceActionId] = useState<string | null>(null);
  const [showContractForm, setShowContractForm] = useState(false);
  const [savingContract, setSavingContract] = useState(false);
  const [contractActionId, setContractActionId] = useState<string | null>(null);
  const [paymentModalForInvoiceId, setPaymentModalForInvoiceId] = useState<string | null>(null);
  const [paymentLines, setPaymentLines] = useState<InvoicePaymentLine[]>([]);
  const [loadingPaymentLines, setLoadingPaymentLines] = useState(false);
  const [savingPayment, setSavingPayment] = useState(false);
  const [deletingPaymentId, setDeletingPaymentId] = useState<string | null>(null);
  const [paymentForm, setPaymentForm] = useState({ amount: '', payment_date: '', note: '' });
  const [contractForm, setContractForm] = useState({
    project_id: '',
    contract_number: '',
    title: '',
    amount: '',
    status: 'ACTIVE',
    signed_date: '',
    end_date: '',
    notes: '',
  });
  const [invoiceForm, setInvoiceForm] = useState({
    project_id: '',
    invoice_number: '',
    amount: '',
    status: 'DRAFT',
    issued_date: '',
    due_date: '',
    description: '',
  });

  const allowed = user?.role === 'admin' || user?.role === 'chief_operator';
  const isAdmin = user?.role === 'admin';

  const authHeaders = useCallback((): HeadersInit => {
    const token = getToken();
    const h: HeadersInit = { 'Content-Type': 'application/json' };
    if (token) h['Authorization'] = `Bearer ${token}`;
    return h;
  }, [getToken]);

  const loadData = useCallback(async () => {
    setLoading(true);
    setError(null);
    const headers = authHeaders();
    try {
      const [pr, cl, inv, con] = await Promise.all([
        fetch(`${API_BASE}/api/projects`, { headers }),
        fetch(`${API_BASE}/api/clients`, { headers }),
        fetch(`${API_BASE}/api/project-invoices`, { headers }),
        fetch(`${API_BASE}/api/project-contracts`, { headers }),
      ]);

      let plist: ProjectRow[] = [];
      let clist: Client[] = [];
      let ilist: ProjectInvoiceRow[] = [];
      let ctlist: ProjectContractRow[] = [];
      const errs: string[] = [];

      if (pr.ok) {
        const j = await pr.json();
        plist = j.items || j.projects || [];
      } else {
        const t = await pr.text().catch(() => '');
        errs.push(`Проекты: HTTP ${pr.status} ${t.slice(0, 80)}`);
      }

      if (cl.ok) {
        const j = await cl.json();
        clist = j.items || j.clients || [];
      } else {
        const t = await cl.text().catch(() => '');
        errs.push(`Клиенты: HTTP ${cl.status} ${t.slice(0, 80)}`);
      }

      if (inv.ok) {
        const j = await inv.json();
        ilist = j.items || [];
      } else if (inv.status === 401 || inv.status === 403) {
        errs.push('Счета: нет доступа (проверьте авторизацию)');
      } else {
        const t = await inv.text().catch(() => '');
        errs.push(`Счета: HTTP ${inv.status} ${t.slice(0, 80)}`);
      }

      if (con.ok) {
        const j = await con.json();
        ctlist = j.items || [];
      } else if (con.status === 401 || con.status === 403) {
        errs.push('Договоры: нет доступа (проверьте авторизацию)');
      } else {
        const t = await con.text().catch(() => '');
        errs.push(`Договоры: HTTP ${con.status} ${t.slice(0, 80)}`);
      }

      setProjects(plist);
      setClients(clist);
      setInvoices(ilist);
      setContracts(ctlist);

      if (errs.length) {
        setError(errs.join(' · '));
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [authHeaders]);

  useEffect(() => {
    if (!allowed) return;
    loadData();
  }, [allowed, loadData]);

  const clientNameById = useMemo(() => {
    const m = new Map<string, string>();
    for (const c of clients) m.set(c.id, c.name);
    return m;
  }, [clients]);

  const stats = useMemo(() => {
    let totalBudget = 0;
    let projectsWithBudget = 0;
    const perStatus: Record<string, number> = {};
    const now = new Date();
    const horizon = new Date(now);
    horizon.setDate(horizon.getDate() + 30);
    let deadlineSoon = 0;
    let overdueDeadline = 0;

    for (const p of projects) {
      perStatus[p.status] = (perStatus[p.status] || 0) + 1;
      const b = p.budget;
      if (b != null && typeof b === 'number' && !Number.isNaN(b)) {
        totalBudget += b;
        projectsWithBudget += 1;
      }
      const d = parseDeadline(p.deadline);
      if (!d) continue;
      const doneOrCancelled = p.status === 'COMPLETED' || p.status === 'CANCELLED';
      if (doneOrCancelled) continue;
      if (d < now) overdueDeadline += 1;
      else if (d <= horizon) deadlineSoon += 1;
    }

    return {
      totalBudget,
      projectsWithBudget,
      perStatus,
      deadlineSoon,
      overdueDeadline,
      totalProjects: projects.length,
    };
  }, [projects]);

  const invoiceTotals = useMemo(() => {
    let paymentsSum = 0;
    let outstanding = 0;
    for (const inv of invoices) {
      if (inv.status === 'CANCELLED') continue;
      const amt = typeof inv.amount === 'number' && !Number.isNaN(inv.amount) ? inv.amount : 0;
      const pt =
        typeof inv.payments_total === 'number' && !Number.isNaN(inv.payments_total)
          ? inv.payments_total
          : 0;
      paymentsSum += pt;
      if (inv.status === 'PAID') continue;
      outstanding += Math.max(0, amt - pt);
    }
    return { paymentsSum, outstanding };
  }, [invoices]);

  const contractTotals = useMemo(() => {
    let activeCount = 0;
    let activeSum = 0;
    for (const c of contracts) {
      if (c.status !== 'ACTIVE') continue;
      activeCount += 1;
      const a = c.amount;
      if (typeof a === 'number' && !Number.isNaN(a)) activeSum += a;
    }
    return { activeCount, activeSum };
  }, [contracts]);

  const filteredProjects = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return projects;
    return projects.filter((p) => {
      const cn = (p.client_id ? clientNameById.get(p.client_id) : null) || '';
      return p.name.toLowerCase().includes(q) || cn.toLowerCase().includes(q);
    });
  }, [projects, search, clientNameById]);

  const projectNameById = useMemo(() => {
    const m = new Map<string, string>();
    for (const p of projects) m.set(p.id, p.name);
    return m;
  }, [projects]);

  const exportBillingCsv = useCallback(() => {
    const stamp = new Date().toISOString().slice(0, 10);
    const projRows = projects.map((p) => [
      p.name,
      p.client_id ? clientNameById.get(p.client_id) ?? '' : '',
      STATUS_LABELS[p.status] || p.status,
      p.budget != null && typeof p.budget === 'number' ? String(p.budget) : '',
      p.deadline ?? '',
    ]);
    downloadCsvFile(
      `billing-projects-${stamp}.csv`,
      ['Проект', 'Клиент', 'Статус', 'Бюджет', 'Дедлайн'],
      projRows,
    );

    const invRows = invoices.map((i) => [
      i.invoice_number ?? '',
      projectNameById.get(i.project_id) ?? '',
      i.amount,
      i.payments_total ?? 0,
      INVOICE_STATUS_LABELS[i.status] || i.status,
      i.issued_date ?? '',
      i.paid_date ?? '',
      (i.description ?? '').replace(/\r?\n/g, ' '),
    ]);
    downloadCsvFile(
      `billing-invoices-${stamp}.csv`,
      ['Номер_счета', 'Проект', 'Сумма', 'Платежи', 'Статус', 'Дата_счета', 'Дата_оплаты', 'Примечание'],
      invRows,
    );

    const conRows = contracts.map((c) => [
      c.contract_number ?? '',
      (c.title ?? '').replace(/\r?\n/g, ' '),
      projectNameById.get(c.project_id) ?? '',
      c.amount ?? '',
      CONTRACT_STATUS_LABELS[c.status] || c.status,
      c.signed_date ?? '',
      c.end_date ?? '',
    ]);
    downloadCsvFile(
      `billing-contracts-${stamp}.csv`,
      ['Номер_договора', 'Предмет', 'Проект', 'Сумма', 'Статус', 'Подписан', 'Окончание'],
      conRows,
    );
    toast.success('Скачано 3 CSV-файла');
  }, [projects, invoices, contracts, clientNameById, projectNameById, toast]);

  const submitInvoice = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!invoiceForm.project_id || !invoiceForm.amount.trim()) {
      toast.error('Укажите проект и сумму');
      return;
    }
    const amount = parseFloat(invoiceForm.amount.replace(',', '.'));
    if (Number.isNaN(amount) || amount <= 0) {
      toast.error('Некорректная сумма');
      return;
    }
    setSavingInvoice(true);
    try {
      const body: Record<string, unknown> = {
        project_id: invoiceForm.project_id,
        amount,
        status: invoiceForm.status,
      };
      if (invoiceForm.invoice_number.trim()) body.invoice_number = invoiceForm.invoice_number.trim();
      if (invoiceForm.issued_date) body.issued_date = invoiceForm.issued_date;
      if (invoiceForm.due_date) body.due_date = invoiceForm.due_date;
      if (invoiceForm.description.trim()) body.description = invoiceForm.description.trim();

      const res = await fetch(`${API_BASE}/api/project-invoices`, {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify(body),
      });
      if (!res.ok) {
        let msg = `HTTP ${res.status}`;
        try {
          const j = await res.json();
          if (j.detail) msg = typeof j.detail === 'string' ? j.detail : JSON.stringify(j.detail);
        } catch {
          /* ignore */
        }
        toast.error(msg);
        return;
      }
      toast.success('Счёт добавлен');
      setInvoiceForm({
        project_id: '',
        invoice_number: '',
        amount: '',
        status: 'DRAFT',
        issued_date: '',
        due_date: '',
        description: '',
      });
      setShowInvoiceForm(false);
      await loadData();
    } finally {
      setSavingInvoice(false);
    }
  };

  const markInvoicePaid = async (id: string) => {
    setInvoiceActionId(id);
    try {
      const res = await fetch(`${API_BASE}/api/project-invoices/${id}`, {
        method: 'PATCH',
        headers: authHeaders(),
        body: JSON.stringify({ status: 'PAID' }),
      });
      if (!res.ok) {
        let msg = `HTTP ${res.status}`;
        try {
          const j = await res.json();
          if (j.detail) msg = typeof j.detail === 'string' ? j.detail : JSON.stringify(j.detail);
        } catch {
          /* ignore */
        }
        toast.error(msg);
        return;
      }
      toast.success('Отмечено как оплачено');
      await loadData();
    } finally {
      setInvoiceActionId(null);
    }
  };

  const deleteInvoice = async (id: string) => {
    if (!window.confirm('Удалить счёт? Действие необратимо.')) return;
    setInvoiceActionId(id);
    try {
      const res = await fetch(`${API_BASE}/api/project-invoices/${id}`, {
        method: 'DELETE',
        headers: authHeaders(),
      });
      if (!res.ok) {
        let msg = `HTTP ${res.status}`;
        try {
          const j = await res.json();
          if (j.detail) msg = typeof j.detail === 'string' ? j.detail : JSON.stringify(j.detail);
        } catch {
          /* ignore */
        }
        toast.error(msg);
        return;
      }
      toast.success('Счёт удалён');
      await loadData();
    } finally {
      setInvoiceActionId(null);
    }
  };

  const loadPaymentLines = async (invoiceId: string) => {
    setLoadingPaymentLines(true);
    try {
      const res = await fetch(`${API_BASE}/api/project-invoices/${invoiceId}/payments`, {
        headers: authHeaders(),
      });
      if (!res.ok) {
        let msg = `HTTP ${res.status}`;
        try {
          const j = await res.json();
          if (j.detail) msg = typeof j.detail === 'string' ? j.detail : JSON.stringify(j.detail);
        } catch {
          /* ignore */
        }
        toast.error(msg);
        setPaymentLines([]);
        return;
      }
      const j = await res.json();
      setPaymentLines(j.items || []);
    } finally {
      setLoadingPaymentLines(false);
    }
  };

  const openPaymentModal = (inv: ProjectInvoiceRow) => {
    if (inv.status === 'CANCELLED') {
      toast.error('Счёт отменён');
      return;
    }
    setPaymentModalForInvoiceId(inv.id);
    setPaymentForm({
      amount: '',
      payment_date: new Date().toISOString().slice(0, 10),
      note: '',
    });
    loadPaymentLines(inv.id);
  };

  const submitPayment = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!paymentModalForInvoiceId) return;
    const am = parseFloat(paymentForm.amount.replace(',', '.'));
    if (Number.isNaN(am) || am <= 0) {
      toast.error('Укажите сумму платежа');
      return;
    }
    setSavingPayment(true);
    try {
      const body: Record<string, unknown> = {
        amount: am,
        payment_date: paymentForm.payment_date || undefined,
      };
      if (paymentForm.note.trim()) body.note = paymentForm.note.trim();
      const res = await fetch(`${API_BASE}/api/project-invoices/${paymentModalForInvoiceId}/payments`, {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify(body),
      });
      if (!res.ok) {
        let msg = `HTTP ${res.status}`;
        try {
          const j = await res.json();
          if (j.detail) msg = typeof j.detail === 'string' ? j.detail : JSON.stringify(j.detail);
        } catch {
          /* ignore */
        }
        toast.error(msg);
        return;
      }
      toast.success('Платёж записан');
      setPaymentForm((f) => ({ ...f, amount: '', note: '' }));
      await loadPaymentLines(paymentModalForInvoiceId);
      await loadData();
    } finally {
      setSavingPayment(false);
    }
  };

  const deleteInvoicePayment = async (paymentId: string) => {
    if (!window.confirm('Удалить запись об оплате?')) return;
    setDeletingPaymentId(paymentId);
    try {
      const res = await fetch(`${API_BASE}/api/project-invoice-payments/${paymentId}`, {
        method: 'DELETE',
        headers: authHeaders(),
      });
      if (!res.ok) {
        let msg = `HTTP ${res.status}`;
        try {
          const j = await res.json();
          if (j.detail) msg = typeof j.detail === 'string' ? j.detail : JSON.stringify(j.detail);
        } catch {
          /* ignore */
        }
        toast.error(msg);
        return;
      }
      toast.success('Запись об оплате удалена');
      if (paymentModalForInvoiceId) {
        await loadPaymentLines(paymentModalForInvoiceId);
      }
      await loadData();
    } finally {
      setDeletingPaymentId(null);
    }
  };

  const submitContract = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!contractForm.project_id) {
      toast.error('Выберите проект');
      return;
    }
    setSavingContract(true);
    try {
      const body: Record<string, unknown> = {
        project_id: contractForm.project_id,
        status: contractForm.status,
      };
      if (contractForm.contract_number.trim()) body.contract_number = contractForm.contract_number.trim();
      if (contractForm.title.trim()) body.title = contractForm.title.trim();
      if (contractForm.signed_date) body.signed_date = contractForm.signed_date;
      if (contractForm.end_date) body.end_date = contractForm.end_date;
      if (contractForm.notes.trim()) body.notes = contractForm.notes.trim();
      if (contractForm.amount.trim()) {
        const am = parseFloat(contractForm.amount.replace(',', '.'));
        if (Number.isNaN(am) || am < 0) {
          toast.error('Некорректная сумма договора');
          setSavingContract(false);
          return;
        }
        body.amount = am;
      }

      const res = await fetch(`${API_BASE}/api/project-contracts`, {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify(body),
      });
      if (!res.ok) {
        let msg = `HTTP ${res.status}`;
        try {
          const j = await res.json();
          if (j.detail) msg = typeof j.detail === 'string' ? j.detail : JSON.stringify(j.detail);
        } catch {
          /* ignore */
        }
        toast.error(msg);
        return;
      }
      toast.success('Договор добавлен');
      setContractForm({
        project_id: '',
        contract_number: '',
        title: '',
        amount: '',
        status: 'ACTIVE',
        signed_date: '',
        end_date: '',
        notes: '',
      });
      setShowContractForm(false);
      await loadData();
    } finally {
      setSavingContract(false);
    }
  };

  const closeContract = async (id: string) => {
    if (!window.confirm('Закрыть договор (статус «Закрыт»)?')) return;
    setContractActionId(id);
    try {
      const res = await fetch(`${API_BASE}/api/project-contracts/${id}`, {
        method: 'PATCH',
        headers: authHeaders(),
        body: JSON.stringify({ status: 'CLOSED' }),
      });
      if (!res.ok) {
        let msg = `HTTP ${res.status}`;
        try {
          const j = await res.json();
          if (j.detail) msg = typeof j.detail === 'string' ? j.detail : JSON.stringify(j.detail);
        } catch {
          /* ignore */
        }
        toast.error(msg);
        return;
      }
      toast.success('Договор закрыт');
      await loadData();
    } finally {
      setContractActionId(null);
    }
  };

  const deleteContract = async (id: string) => {
    if (!window.confirm('Удалить договор? Только для администратора.')) return;
    setContractActionId(id);
    try {
      const res = await fetch(`${API_BASE}/api/project-contracts/${id}`, {
        method: 'DELETE',
        headers: authHeaders(),
      });
      if (!res.ok) {
        let msg = `HTTP ${res.status}`;
        try {
          const j = await res.json();
          if (j.detail) msg = typeof j.detail === 'string' ? j.detail : JSON.stringify(j.detail);
        } catch {
          /* ignore */
        }
        toast.error(msg);
        return;
      }
      toast.success('Договор удалён');
      await loadData();
    } finally {
      setContractActionId(null);
    }
  };

  if (!allowed) {
    return <Navigate to="/dashboard" replace />;
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-24 text-app-text3 gap-2">
        <RefreshCw className="animate-spin shrink-0" size={20} />
        Загрузка финансовой сводки…
      </div>
    );
  }

  const activeProjects =
    (stats.perStatus['PLANNED'] || 0) + (stats.perStatus['IN_PROGRESS'] || 0);

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-app-text flex items-center gap-2">
            <Wallet className="text-accent shrink-0" size={28} />
            Финансы и биллинг
          </h1>
          <p className="text-app-text3 text-sm mt-1 max-w-2xl">
            Бюджеты проектов, договоры и счета на оплату. Акты, накладные и обмен с 1С — следующим этапом.
          </p>
        </div>
        <div className="flex flex-col items-stretch sm:items-end gap-2">
          <div className="flex flex-wrap gap-2 justify-end">
            <button
              type="button"
              onClick={exportBillingCsv}
              className="inline-flex items-center justify-center gap-2 px-3 py-2 rounded-lg bg-app-panel border border-app-line text-app-text text-sm font-semibold hover:border-accent/40"
            >
              <Download size={16} />
              CSV
            </button>
            <button
              type="button"
              onClick={() => loadData()}
              className="inline-flex items-center justify-center gap-2 px-3 py-2 rounded-lg bg-app-panel border border-app-line text-app-text text-sm font-semibold hover:border-accent/40"
            >
              <RefreshCw size={16} />
              Обновить
            </button>
            <button
              type="button"
              onClick={() => {
                setShowContractForm((v) => !v);
                setShowInvoiceForm(false);
              }}
              className="inline-flex items-center justify-center gap-2 px-4 py-2 rounded-lg bg-app-panel border border-app-line text-app-text text-sm font-semibold hover:border-accent/40"
            >
              <FileText size={18} />
              Новый договор
            </button>
            <button
              type="button"
              onClick={() => {
                setShowInvoiceForm((v) => !v);
                setShowContractForm(false);
              }}
              className="inline-flex items-center justify-center gap-2 px-4 py-2 rounded-lg bg-accent/10 border border-accent/30 text-accent text-sm font-semibold hover:bg-accent/20"
            >
              <Plus size={18} />
              Новый счёт
            </button>
            {isAdmin && (
              <Link
                to="/projects"
                className="inline-flex items-center justify-center gap-2 px-4 py-2 rounded-lg bg-accent/10 border border-accent/30 text-accent text-sm font-semibold hover:bg-accent/20 whitespace-nowrap"
              >
                <FolderKanban size={18} />
                Проекты и бюджеты
              </Link>
            )}
          </div>
          {user?.role === 'chief_operator' && (
            <p className="text-xs text-app-text3 text-right max-w-xs">
              Изменение бюджетов проектов выполняет администратор в разделе «Проекты».
            </p>
          )}
        </div>
      </div>

      {error && (
        <div className="rounded-xl border border-red-500/40 bg-red-500/10 text-red-200 px-4 py-3 text-sm flex items-start gap-2">
          <AlertCircle className="shrink-0 mt-0.5" size={18} />
          <span>{error}</span>
        </div>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
        <div className="bg-app-panel rounded-xl border border-app-line p-4">
          <p className="text-app-text3 text-sm">Сумма бюджетов</p>
          <p className="text-white text-2xl font-bold mt-1">{formatMoney(stats.totalBudget)}</p>
          <p className="text-xs text-app-text3 mt-2">
            В {stats.projectsWithBudget} из {stats.totalProjects} проектов
          </p>
        </div>
        <div className="bg-app-panel rounded-xl border border-app-line p-4">
          <p className="text-app-text3 text-sm">Активные проекты</p>
          <p className="text-white text-2xl font-bold mt-1">{activeProjects}</p>
          <p className="text-xs text-app-text3 mt-2">Запланировано и в работе</p>
        </div>
        <div className="bg-app-panel rounded-xl border border-blue-500/35 p-4">
          <p className="text-app-text3 text-sm flex items-center gap-1">
            <FileText size={14} className="text-blue-400" />
            Договоры (действуют)
          </p>
          <p className="text-white text-2xl font-bold mt-1">{contractTotals.activeCount}</p>
          <p className="text-xs text-app-text3 mt-2">
            На сумму {formatMoney(contractTotals.activeSum)}
          </p>
        </div>
        <div className="bg-app-panel rounded-xl border border-green-500/35 p-4">
          <p className="text-app-text3 text-sm flex items-center gap-1">
            <Receipt size={14} className="text-green-400" />
            Поступления (платежи)
          </p>
          <p className="text-white text-2xl font-bold mt-1">{formatMoney(invoiceTotals.paymentsSum)}</p>
          <p className="text-xs text-app-text3 mt-2">Сумма строк оплат по счетам</p>
        </div>
        <div className="bg-app-panel rounded-xl border border-amber-500/35 p-4">
          <p className="text-app-text3 text-sm">Остаток к оплате</p>
          <p className="text-white text-2xl font-bold mt-1">{formatMoney(invoiceTotals.outstanding)}</p>
          <p className="text-xs text-app-text3 mt-2">По незакрытым счетам (кроме отменённых)</p>
        </div>
        <div className="bg-app-panel rounded-xl border border-yellow-500/35 p-4">
          <p className="text-app-text3 text-sm flex items-center gap-1">
            <CalendarClock size={14} className="text-yellow-400" />
            Дедлайн ≤ 30 дн.
          </p>
          <p className="text-white text-2xl font-bold mt-1">{stats.deadlineSoon}</p>
          <p className="text-xs text-app-text3 mt-2">По проектам</p>
        </div>
        <div className="bg-app-panel rounded-xl border border-red-500/35 p-4 sm:col-span-2 xl:col-span-1">
          <p className="text-app-text3 text-sm">Просрочен дедлайн</p>
          <p className="text-white text-2xl font-bold mt-1">{stats.overdueDeadline}</p>
          <p className="text-xs text-app-text3 mt-2">По проектам</p>
        </div>
      </div>

      {showInvoiceForm && (
        <div className="bg-app-panel rounded-xl border border-app-line p-6">
          <h2 className="text-lg font-bold text-app-text mb-4 flex items-center gap-2">
            <Receipt className="text-accent" size={20} />
            Новый счёт по проекту
          </h2>
          <form onSubmit={submitInvoice} className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="md:col-span-2">
              <label className="text-sm text-app-text3 block mb-1">Проект *</label>
              <select
                required
                value={invoiceForm.project_id}
                onChange={(e) => setInvoiceForm({ ...invoiceForm, project_id: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
              >
                <option value="">— Выберите проект —</option>
                {projects.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="text-sm text-app-text3 block mb-1">Номер счёта</label>
              <input
                type="text"
                value={invoiceForm.invoice_number}
                onChange={(e) => setInvoiceForm({ ...invoiceForm, invoice_number: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
                placeholder="Напр. СЧ-2026-001"
              />
            </div>
            <div>
              <label className="text-sm text-app-text3 block mb-1">Сумма, ₽ *</label>
              <input
                type="text"
                inputMode="decimal"
                required
                value={invoiceForm.amount}
                onChange={(e) => setInvoiceForm({ ...invoiceForm, amount: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
                placeholder="0"
              />
            </div>
            <div>
              <label className="text-sm text-app-text3 block mb-1">Статус</label>
              <select
                value={invoiceForm.status}
                onChange={(e) => setInvoiceForm({ ...invoiceForm, status: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
              >
                <option value="DRAFT">Черновик</option>
                <option value="ISSUED">Выставлен</option>
                <option value="PAID">Оплачен</option>
              </select>
            </div>
            <div>
              <label className="text-sm text-app-text3 block mb-1">Дата счёта</label>
              <input
                type="date"
                value={invoiceForm.issued_date}
                onChange={(e) => setInvoiceForm({ ...invoiceForm, issued_date: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
              />
            </div>
            <div>
              <label className="text-sm text-app-text3 block mb-1">Срок оплаты</label>
              <input
                type="date"
                value={invoiceForm.due_date}
                onChange={(e) => setInvoiceForm({ ...invoiceForm, due_date: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
              />
            </div>
            <div className="md:col-span-2">
              <label className="text-sm text-app-text3 block mb-1">Примечание</label>
              <textarea
                value={invoiceForm.description}
                onChange={(e) => setInvoiceForm({ ...invoiceForm, description: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text min-h-[72px]"
                placeholder="Назначение платежа, договор…"
              />
            </div>
            <div className="md:col-span-2 flex gap-2">
              <button
                type="submit"
                disabled={savingInvoice}
                className="bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-accent/80 disabled:opacity-50"
              >
                {savingInvoice ? 'Сохранение…' : 'Сохранить счёт'}
              </button>
              <button
                type="button"
                onClick={() => setShowInvoiceForm(false)}
                className="bg-app-soft px-4 py-2 rounded-lg text-app-text font-bold hover:bg-app-softer"
              >
                Отмена
              </button>
            </div>
          </form>
        </div>
      )}

      <div>
        <h2 className="text-lg font-bold text-app-text mb-3 flex items-center gap-2">
          <Receipt size={20} className="text-accent" />
          Счета по проектам
        </h2>
        <div className="bg-app-panel rounded-xl border border-app-line overflow-x-auto">
          <table className="w-full text-sm min-w-[960px]">
            <thead>
              <tr className="border-b border-app-line text-left text-app-text3">
                <th className="p-3 font-semibold">Номер</th>
                <th className="p-3 font-semibold">Проект</th>
                <th className="p-3 font-semibold">Сумма</th>
                <th className="p-3 font-semibold">Платежи</th>
                <th className="p-3 font-semibold">Остаток</th>
                <th className="p-3 font-semibold">Статус</th>
                <th className="p-3 font-semibold">Выставлен</th>
                <th className="p-3 font-semibold">Оплата</th>
                <th className="p-3 font-semibold min-w-[200px]">Действия</th>
              </tr>
            </thead>
            <tbody>
              {invoices.length === 0 ? (
                <tr>
                  <td colSpan={9} className="p-8 text-center text-app-text3">
                    Счетов пока нет — добавьте первый блоком выше.
                  </td>
                </tr>
              ) : (
                invoices.map((inv) => {
                  const busy = invoiceActionId === inv.id;
                  const canPay = inv.status === 'ISSUED' || inv.status === 'DRAFT';
                  const pt =
                    typeof inv.payments_total === 'number' && !Number.isNaN(inv.payments_total)
                      ? inv.payments_total
                      : 0;
                  const rem = Math.max(0, inv.amount - pt);
                  return (
                    <tr key={inv.id} className="border-b border-app-line/70 hover:bg-app-deep/40">
                      <td className="p-3 text-app-text font-mono text-xs">
                        {inv.invoice_number || '—'}
                      </td>
                      <td className="p-3 text-app-text">
                        {projectNameById.get(inv.project_id) || '—'}
                      </td>
                      <td className="p-3 tabular-nums text-app-text">{formatMoney(inv.amount)}</td>
                      <td className="p-3 tabular-nums text-app-text2">{formatMoney(pt)}</td>
                      <td className="p-3 tabular-nums text-app-text2">{formatMoney(rem)}</td>
                      <td className="p-3 text-app-text2">
                        {INVOICE_STATUS_LABELS[inv.status] || inv.status}
                      </td>
                      <td className="p-3 text-app-text2 whitespace-nowrap">
                        {formatRuDate(inv.issued_date)}
                      </td>
                      <td className="p-3 text-app-text2 whitespace-nowrap">
                        {formatRuDate(inv.paid_date)}
                      </td>
                      <td className="p-3">
                        <div className="flex flex-wrap gap-1">
                          {inv.status !== 'CANCELLED' && (
                            <button
                              type="button"
                              disabled={busy}
                              onClick={() => openPaymentModal(inv)}
                              className="text-xs px-2 py-1 rounded bg-blue-500/15 text-blue-200 border border-blue-500/30 hover:bg-blue-500/25 disabled:opacity-50"
                            >
                              Платёж
                            </button>
                          )}
                          {canPay && (
                            <button
                              type="button"
                              disabled={busy}
                              onClick={() => markInvoicePaid(inv.id)}
                              className="text-xs px-2 py-1 rounded bg-green-500/15 text-green-300 border border-green-500/30 hover:bg-green-500/25 disabled:opacity-50"
                            >
                              Оплачен
                            </button>
                          )}
                          {isAdmin && (
                            <button
                              type="button"
                              disabled={busy}
                              onClick={() => deleteInvoice(inv.id)}
                              className="text-xs px-2 py-1 rounded bg-red-500/10 text-red-300 border border-red-500/30 hover:bg-red-500/20 disabled:opacity-50 inline-flex items-center gap-1"
                            >
                              <Trash2 size={12} />
                              Удалить
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      {showContractForm && (
        <div className="bg-app-panel rounded-xl border border-app-line p-6">
          <h2 className="text-lg font-bold text-app-text mb-4 flex items-center gap-2">
            <FileText className="text-accent" size={20} />
            Новый договор по проекту
          </h2>
          <form onSubmit={submitContract} className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="md:col-span-2">
              <label className="text-sm text-app-text3 block mb-1">Проект *</label>
              <select
                required
                value={contractForm.project_id}
                onChange={(e) => setContractForm({ ...contractForm, project_id: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
              >
                <option value="">— Выберите проект —</option>
                {projects.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="text-sm text-app-text3 block mb-1">Номер договора</label>
              <input
                type="text"
                value={contractForm.contract_number}
                onChange={(e) => setContractForm({ ...contractForm, contract_number: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
                placeholder="Напр. ДГ-12/2026"
              />
            </div>
            <div>
              <label className="text-sm text-app-text3 block mb-1">Сумма договора, ₽</label>
              <input
                type="text"
                inputMode="decimal"
                value={contractForm.amount}
                onChange={(e) => setContractForm({ ...contractForm, amount: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
                placeholder="Необязательно"
              />
            </div>
            <div className="md:col-span-2">
              <label className="text-sm text-app-text3 block mb-1">Предмет / название</label>
              <input
                type="text"
                value={contractForm.title}
                onChange={(e) => setContractForm({ ...contractForm, title: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
                placeholder="Кратко о договоре"
              />
            </div>
            <div>
              <label className="text-sm text-app-text3 block mb-1">Дата подписания</label>
              <input
                type="date"
                value={contractForm.signed_date}
                onChange={(e) => setContractForm({ ...contractForm, signed_date: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
              />
            </div>
            <div>
              <label className="text-sm text-app-text3 block mb-1">Дата окончания</label>
              <input
                type="date"
                value={contractForm.end_date}
                onChange={(e) => setContractForm({ ...contractForm, end_date: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
              />
            </div>
            <div>
              <label className="text-sm text-app-text3 block mb-1">Статус</label>
              <select
                value={contractForm.status}
                onChange={(e) => setContractForm({ ...contractForm, status: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
              >
                <option value="ACTIVE">Действует</option>
                <option value="CLOSED">Закрыт</option>
              </select>
            </div>
            <div className="md:col-span-2">
              <label className="text-sm text-app-text3 block mb-1">Примечания</label>
              <textarea
                value={contractForm.notes}
                onChange={(e) => setContractForm({ ...contractForm, notes: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text min-h-[72px]"
              />
            </div>
            <div className="md:col-span-2 flex gap-2">
              <button
                type="submit"
                disabled={savingContract}
                className="bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-accent/80 disabled:opacity-50"
              >
                {savingContract ? 'Сохранение…' : 'Сохранить договор'}
              </button>
              <button
                type="button"
                onClick={() => setShowContractForm(false)}
                className="bg-app-soft px-4 py-2 rounded-lg text-app-text font-bold hover:bg-app-softer"
              >
                Отмена
              </button>
            </div>
          </form>
        </div>
      )}

      <div>
        <h2 className="text-lg font-bold text-app-text mb-3 flex items-center gap-2">
          <FileText size={20} className="text-accent" />
          Договоры по проектам
        </h2>
        <div className="bg-app-panel rounded-xl border border-app-line overflow-x-auto">
          <table className="w-full text-sm min-w-[800px]">
            <thead>
              <tr className="border-b border-app-line text-left text-app-text3">
                <th className="p-3 font-semibold">Номер</th>
                <th className="p-3 font-semibold">Предмет</th>
                <th className="p-3 font-semibold">Проект</th>
                <th className="p-3 font-semibold">Сумма</th>
                <th className="p-3 font-semibold">Подписан</th>
                <th className="p-3 font-semibold">Окончание</th>
                <th className="p-3 font-semibold">Статус</th>
                <th className="p-3 font-semibold w-44">Действия</th>
              </tr>
            </thead>
            <tbody>
              {contracts.length === 0 ? (
                <tr>
                  <td colSpan={8} className="p-8 text-center text-app-text3">
                    Договоров пока нет.
                  </td>
                </tr>
              ) : (
                contracts.map((c) => {
                  const busy = contractActionId === c.id;
                  const canClose = c.status === 'ACTIVE';
                  const amt =
                    c.amount != null && typeof c.amount === 'number' && !Number.isNaN(c.amount)
                      ? formatMoney(c.amount)
                      : '—';
                  return (
                    <tr key={c.id} className="border-b border-app-line/70 hover:bg-app-deep/40">
                      <td className="p-3 text-app-text font-mono text-xs">{c.contract_number || '—'}</td>
                      <td className="p-3 text-app-text2 max-w-[200px] truncate" title={c.title || ''}>
                        {c.title || '—'}
                      </td>
                      <td className="p-3 text-app-text">{projectNameById.get(c.project_id) || '—'}</td>
                      <td className="p-3 tabular-nums text-app-text">{amt}</td>
                      <td className="p-3 text-app-text2 whitespace-nowrap">{formatRuDate(c.signed_date)}</td>
                      <td className="p-3 text-app-text2 whitespace-nowrap">{formatRuDate(c.end_date)}</td>
                      <td className="p-3 text-app-text2">{CONTRACT_STATUS_LABELS[c.status] || c.status}</td>
                      <td className="p-3">
                        <div className="flex flex-wrap gap-1">
                          {canClose && (
                            <button
                              type="button"
                              disabled={busy}
                              onClick={() => closeContract(c.id)}
                              className="text-xs px-2 py-1 rounded bg-amber-500/15 text-amber-200 border border-amber-500/30 hover:bg-amber-500/25 disabled:opacity-50"
                            >
                              Закрыть
                            </button>
                          )}
                          {isAdmin && (
                            <button
                              type="button"
                              disabled={busy}
                              onClick={() => deleteContract(c.id)}
                              className="text-xs px-2 py-1 rounded bg-red-500/10 text-red-300 border border-red-500/30 hover:bg-red-500/20 disabled:opacity-50 inline-flex items-center gap-1"
                            >
                              <Trash2 size={12} />
                              Удалить
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      <div className="relative max-w-md">
        <Search
          className="absolute left-3 top-1/2 -translate-y-1/2 text-app-text3 pointer-events-none"
          size={18}
        />
        <input
          type="search"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Поиск по названию проекта или клиенту…"
          className="w-full bg-app-deep border border-app-line rounded-lg pl-10 pr-3 py-2 text-app-text text-sm placeholder:text-app-text3/70"
        />
      </div>

      <div className="bg-app-panel rounded-xl border border-app-line overflow-x-auto">
        <table className="w-full text-sm min-w-[640px]">
          <thead>
            <tr className="border-b border-app-line text-left text-app-text3">
              <th className="p-3 font-semibold">Проект</th>
              <th className="p-3 font-semibold">Клиент</th>
              <th className="p-3 font-semibold">Статус</th>
              <th className="p-3 font-semibold text-right">Бюджет</th>
              <th className="p-3 font-semibold">Дедлайн</th>
            </tr>
          </thead>
          <tbody>
            {filteredProjects.length === 0 ? (
              <tr>
                <td colSpan={5} className="p-8 text-center text-app-text3">
                  {projects.length === 0 ? 'Нет проектов для отображения' : 'Ничего не найдено по запросу'}
                </td>
              </tr>
            ) : (
              filteredProjects.map((p) => {
                const b = p.budget;
                const budgetText =
                  b != null && typeof b === 'number' && !Number.isNaN(b) ? formatMoney(b) : '—';
                const dl = parseDeadline(p.deadline);
                return (
                  <tr key={p.id} className="border-b border-app-line/70 hover:bg-app-deep/40">
                    <td className="p-3 text-app-text font-medium">{p.name}</td>
                    <td className="p-3 text-app-text2">
                      {p.client_id ? clientNameById.get(p.client_id) || '—' : '—'}
                    </td>
                    <td className="p-3 text-app-text2">{STATUS_LABELS[p.status] || p.status}</td>
                    <td className="p-3 text-right tabular-nums text-app-text">{budgetText}</td>
                    <td className="p-3 text-app-text2 whitespace-nowrap">
                      {dl ? dl.toLocaleDateString('ru-RU') : '—'}
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      {paymentModalForInvoiceId && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          onClick={() => setPaymentModalForInvoiceId(null)}
          role="presentation"
        >
          <div
            className="bg-app-panel rounded-xl border border-app-line max-w-lg w-full max-h-[85vh] overflow-y-auto p-6 shadow-xl"
            onClick={(e) => e.stopPropagation()}
            role="dialog"
            aria-modal="true"
          >
            <div className="flex justify-between items-start gap-2 mb-4">
              <h3 className="text-lg font-bold text-app-text">Платежи по счёту</h3>
              <button
                type="button"
                className="text-app-text3 hover:text-app-text text-xl leading-none"
                onClick={() => setPaymentModalForInvoiceId(null)}
                aria-label="Закрыть"
              >
                ×
              </button>
            </div>
            {(() => {
              const inv = invoices.find((i) => i.id === paymentModalForInvoiceId);
              if (!inv) return null;
              const pt =
                typeof inv.payments_total === 'number' && !Number.isNaN(inv.payments_total)
                  ? inv.payments_total
                  : 0;
              return (
                <p className="text-sm text-app-text3 mb-4">
                  {projectNameById.get(inv.project_id) || '—'} · {inv.invoice_number || 'без номера'} · к оплате{' '}
                  {formatMoney(Math.max(0, inv.amount - pt))} из {formatMoney(inv.amount)}
                </p>
              );
            })()}
            <p className="text-xs text-app-text3 mb-3">
              При удалении проводок статус счёта пересчитывается по сумме оплат; полностью без строк — для закрытия
              счёта используйте кнопку «Оплачен» или одну проводку на полную сумму.
            </p>
            {loadingPaymentLines ? (
              <p className="text-app-text3 text-sm py-4">Загрузка списка…</p>
            ) : (
              <ul className="space-y-2 mb-4 max-h-44 overflow-y-auto border border-app-line rounded-lg p-2 bg-app-deep/40">
                {paymentLines.length === 0 ? (
                  <li className="text-app-text3 text-sm px-2 py-1">Записей оплат пока нет</li>
                ) : (
                  paymentLines.map((pl) => (
                    <li
                      key={pl.id}
                      className="text-sm flex flex-wrap items-center justify-between gap-2 border-b border-app-line/50 last:border-0 pb-2 last:pb-0"
                    >
                      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1 min-w-0 flex-1">
                        <span className="text-app-text font-semibold tabular-nums">{formatMoney(pl.amount)}</span>
                        <span className="text-app-text3 shrink-0">{formatRuDate(pl.payment_date)}</span>
                        {pl.note ? (
                          <span className="text-app-text2 text-xs w-full">{pl.note}</span>
                        ) : null}
                      </div>
                      <button
                        type="button"
                        onClick={() => deleteInvoicePayment(pl.id)}
                        disabled={deletingPaymentId === pl.id}
                        className="shrink-0 p-1.5 rounded-lg text-app-text3 hover:text-red-400 hover:bg-red-500/10 disabled:opacity-40"
                        title="Удалить запись"
                        aria-label="Удалить запись об оплате"
                      >
                        <Trash2 size={16} />
                      </button>
                    </li>
                  ))
                )}
              </ul>
            )}
            <form onSubmit={submitPayment} className="space-y-3 border-t border-app-line pt-4">
              <div>
                <label className="text-sm text-app-text3 block mb-1">Сумма платежа, ₽ *</label>
                <input
                  type="text"
                  inputMode="decimal"
                  required
                  value={paymentForm.amount}
                  onChange={(e) => setPaymentForm({ ...paymentForm, amount: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Дата платежа</label>
                <input
                  type="date"
                  value={paymentForm.payment_date}
                  onChange={(e) => setPaymentForm({ ...paymentForm, payment_date: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Примечание</label>
                <input
                  type="text"
                  value={paymentForm.note}
                  onChange={(e) => setPaymentForm({ ...paymentForm, note: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded-lg p-2 text-app-text"
                  placeholder="Номер ПП, назначение…"
                />
              </div>
              <div className="flex gap-2 flex-wrap">
                <button
                  type="submit"
                  disabled={savingPayment}
                  className="bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-accent/80 disabled:opacity-50"
                >
                  {savingPayment ? 'Сохранение…' : 'Записать платёж'}
                </button>
                <p className="text-xs text-app-text3 self-center">
                  При полной сумме счёт станет «Оплачен» автоматически.
                </p>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};

export default BillingOverview;
