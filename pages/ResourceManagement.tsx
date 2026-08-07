import React, { useState, useEffect, useCallback } from 'react';
import { Calculator, TrendingUp, AlertTriangle, FlaskConical, ChevronDown, ChevronUp } from 'lucide-react';
import { API_BASE } from '../constants';
import { useAuth } from '../contexts/AuthContext';

interface Equipment {
  id: string;
  name: string;
  serial_number?: string;
  location?: string;
}

interface Resource {
  id: string;
  equipment_id: string;
  remaining_resource_years?: number;
  resource_end_date?: string;
  extension_years?: number;
  extension_date?: string;
  status: string;
  document_number?: string;
  calculation_method?: string | null;
  calculation_data?: Record<string, unknown>;
}

interface ResidualLifeApiResponse {
  methodology: string;
  residual_years: number;
  status: string;
  details: Record<string, unknown>;
}

const RD_METHOD_LABEL = 'РД 09-539-03 (остаточный ресурс по толщинометрии)';

const ResourceManagement = () => {
  const { getToken } = useAuth();
  const authHeaders = useCallback(
    (json = true): HeadersInit => {
      const h: Record<string, string> = { Authorization: `Bearer ${getToken()}` };
      if (json) h['Content-Type'] = 'application/json';
      return h;
    },
    [getToken],
  );

  const [equipment, setEquipment] = useState<Equipment[]>([]);
  const [resources, setResources] = useState<Resource[]>([]);
  const [selectedEquipment, setSelectedEquipment] = useState<Equipment | null>(null);
  const [showAddForm, setShowAddForm] = useState(false);
  const [loading, setLoading] = useState(true);

  const [formData, setFormData] = useState({
    equipment_id: '',
    remaining_resource_years: '',
    resource_end_date: '',
    extension_years: '',
    extension_date: '',
    calculation_method: '',
    document_number: '',
    status: 'ACTIVE',
    calculation_data: null as Record<string, unknown> | null,
  });

  const [calcOpen, setCalcOpen] = useState(true);
  const [calcLoading, setCalcLoading] = useState(false);
  const [calcError, setCalcError] = useState<string | null>(null);
  const [calcResult, setCalcResult] = useState<ResidualLifeApiResponse | null>(null);
  const [calcInputs, setCalcInputs] = useState({
    t_factual: '',
    t_nominal: '',
    t_allow: '',
    service_years: '',
    corrosion_rate_mm_year: '',
    safety_factor: '1.0',
    opo_hazard_class: '',
  });

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      const token = getToken();
      if (!token) {
        setLoading(false);
        return;
      }
      const [eqRes, resRes] = await Promise.all([
        fetch(`${API_BASE}/api/equipment?limit=1000`, { headers: authHeaders() }),
        fetch(`${API_BASE}/api/equipment-resources`, { headers: authHeaders() }),
      ]);

      const eqData = await eqRes.json();
      const resData = await resRes.json();

      setEquipment(eqData.items || []);
      setResources(resData.items || []);
    } catch (error) {
      console.error('Ошибка загрузки данных:', error);
    } finally {
      setLoading(false);
    }
  };

  const parseOptionalFloat = (s: string): number | undefined => {
    const t = s.trim();
    if (!t) return undefined;
    const n = parseFloat(t.replace(',', '.'));
    return Number.isFinite(n) ? n : undefined;
  };

  const runResidualLifeCalc = async () => {
    setCalcError(null);
    setCalcResult(null);
    const tF = parseOptionalFloat(calcInputs.t_factual);
    const tN = parseOptionalFloat(calcInputs.t_nominal);
    const tAllow = parseOptionalFloat(calcInputs.t_allow);
    const svc = parseOptionalFloat(calcInputs.service_years);
    const corrosion = parseOptionalFloat(calcInputs.corrosion_rate_mm_year);
    const kz = parseOptionalFloat(calcInputs.safety_factor) ?? 1.0;

    if (tF === undefined || tN === undefined) {
      setCalcError('Укажите фактическую t_факт и номинальную t_ном толщину (мм).');
      return;
    }
    if (corrosion === undefined && svc === undefined) {
      setCalcError('Заполните срок эксплуатации (лет) или измеренную скорость коррозии (мм/год).');
      return;
    }

    const body: Record<string, unknown> = {
      t_factual: tF,
      t_nominal: tN,
      safety_factor: kz,
    };
    if (tAllow !== undefined) body.t_allow = tAllow;
    if (svc !== undefined) body.service_years = svc;
    if (corrosion !== undefined) body.corrosion_rate_mm_year = corrosion;
    const opo = calcInputs.opo_hazard_class.trim();
    if (opo) body.opo_hazard_class = opo.toUpperCase();

    setCalcLoading(true);
    try {
      const res = await fetch(`${API_BASE}/api/diagnostic/residual-life`, {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify(body),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        let msg = `Ошибка ${res.status}`;
        if (Array.isArray(data.detail)) {
          msg = data.detail
            .map((x: { msg?: string; loc?: unknown[] }) => x.msg || JSON.stringify(x))
            .join('; ');
        } else if (typeof data.detail === 'string') {
          msg = data.detail;
        }
        setCalcError(msg);
        return;
      }
      setCalcResult(data as ResidualLifeApiResponse);
    } catch (e) {
      setCalcError(e instanceof Error ? e.message : 'Ошибка запроса');
    } finally {
      setCalcLoading(false);
    }
  };

  const applyCalcToForm = () => {
    if (!calcResult) return;
    const years = calcResult.residual_years;
    const end = new Date();
    end.setFullYear(end.getFullYear() + Math.floor(years));
    const snapshot = {
      methodology: calcResult.methodology,
      api_status: calcResult.status,
      details: calcResult.details,
      input: {
        t_factual: parseOptionalFloat(calcInputs.t_factual),
        t_nominal: parseOptionalFloat(calcInputs.t_nominal),
        t_allow: parseOptionalFloat(calcInputs.t_allow) ?? null,
        service_years: parseOptionalFloat(calcInputs.service_years) ?? null,
        corrosion_rate_mm_year: parseOptionalFloat(calcInputs.corrosion_rate_mm_year) ?? null,
        safety_factor: parseOptionalFloat(calcInputs.safety_factor) ?? 1.0,
        opo_hazard_class: calcInputs.opo_hazard_class.trim() || null,
      },
    };
    setFormData((prev) => ({
      ...prev,
      remaining_resource_years: String(years),
      resource_end_date: end.toISOString().slice(0, 10),
      calculation_method: RD_METHOD_LABEL,
      calculation_data: snapshot,
    }));
    setShowAddForm(true);
  };

  const statusColor = (st: string) => {
    if (st === 'OK') return 'text-green-400';
    if (st === 'WARNING') return 'text-amber-400';
    if (st === 'REJECTED') return 'text-red-400';
    return 'text-app-text2';
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const payload: Record<string, unknown> = {
        equipment_id: formData.equipment_id,
        remaining_resource_years: formData.remaining_resource_years
          ? parseFloat(formData.remaining_resource_years)
          : null,
        resource_end_date: formData.resource_end_date || null,
        extension_years: formData.extension_years ? parseFloat(formData.extension_years) : null,
        extension_date: formData.extension_date || null,
        calculation_method: formData.calculation_method || null,
        document_number: formData.document_number || null,
        status: formData.status,
        calculation_data: formData.calculation_data || {},
      };

      const response = await fetch(`${API_BASE}/api/equipment-resources`, {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify(payload),
      });

      if (response.ok) {
        setShowAddForm(false);
        setFormData({
          equipment_id: '',
          remaining_resource_years: '',
          resource_end_date: '',
          extension_years: '',
          extension_date: '',
          calculation_method: '',
          document_number: '',
          status: 'ACTIVE',
          calculation_data: null,
        });
        loadData();
        alert('Ресурс успешно добавлен');
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось добавить ресурс'}`);
      }
    } catch (error) {
      console.error('Ошибка создания ресурса:', error);
      alert('Ошибка создания ресурса');
    }
  };

  const getEquipmentResource = (equipmentId: string) => {
    return resources.find((r) => r.equipment_id === equipmentId && r.status === 'ACTIVE');
  };

  const calculateDaysUntilExpiry = (endDate?: string) => {
    if (!endDate) return null;
    const end = new Date(endDate);
    const now = new Date();
    const diff = end.getTime() - now.getTime();
    return Math.ceil(diff / (1000 * 60 * 60 * 24));
  };

  if (loading) {
    return <div className="text-center text-app-text3 mt-20">Загрузка...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-app-text">Управление ресурсом оборудования</h1>
        <button
          type="button"
          onClick={() => setShowAddForm(true)}
          className="bg-accent/10 text-accent border border-accent/20 px-4 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-accent/20"
        >
          <Calculator size={16} /> Добавить ресурс
        </button>
      </div>

      <div className="bg-app-panel rounded-xl border border-app-line overflow-hidden">
        <button
          type="button"
          className="w-full flex items-center justify-between px-5 py-4 text-left hover:bg-app-deep/80 transition"
          onClick={() => setCalcOpen(!calcOpen)}
        >
          <div className="flex items-center gap-3">
            <FlaskConical className="text-accent" size={22} />
            <div>
              <p className="font-semibold text-app-text">Расчёт остаточного ресурса (РД 09-539-03)</p>
              <p className="text-xs text-app-text3 mt-0.5">
                По минимальной толщине стенки; результат можно перенести в карточку ресурса.
              </p>
            </div>
          </div>
          {calcOpen ? <ChevronUp className="text-app-text3" /> : <ChevronDown className="text-app-text3" />}
        </button>
        {calcOpen && (
          <div className="px-5 pb-5 pt-0 border-t border-app-line space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 pt-4">
              <div>
                <label className="text-xs text-app-text3 block mb-1">t факт, мм (минимальная)</label>
                <input
                  type="text"
                  inputMode="decimal"
                  value={calcInputs.t_factual}
                  onChange={(e) => setCalcInputs((s) => ({ ...s, t_factual: e.target.value }))}
                  className="w-full bg-app-deep border border-app-line rounded-lg px-3 py-2 text-app-text text-sm"
                />
              </div>
              <div>
                <label className="text-xs text-app-text3 block mb-1">t ном, мм (номинальная / проектная)</label>
                <input
                  type="text"
                  inputMode="decimal"
                  value={calcInputs.t_nominal}
                  onChange={(e) => setCalcInputs((s) => ({ ...s, t_nominal: e.target.value }))}
                  className="w-full bg-app-deep border border-app-line rounded-lg px-3 py-2 text-app-text text-sm"
                />
              </div>
              <div>
                <label className="text-xs text-app-text3 block mb-1">t отбр, мм (необязательно)</label>
                <input
                  type="text"
                  inputMode="decimal"
                  placeholder="по умолчанию 0,5 × t ном"
                  value={calcInputs.t_allow}
                  onChange={(e) => setCalcInputs((s) => ({ ...s, t_allow: e.target.value }))}
                  className="w-full bg-app-deep border border-app-line rounded-lg px-3 py-2 text-app-text text-sm"
                />
              </div>
              <div>
                <label className="text-xs text-app-text3 block mb-1">Срок эксплуатации, лет</label>
                <input
                  type="text"
                  inputMode="decimal"
                  placeholder="если нет скорости коррозии"
                  value={calcInputs.service_years}
                  onChange={(e) => setCalcInputs((s) => ({ ...s, service_years: e.target.value }))}
                  className="w-full bg-app-deep border border-app-line rounded-lg px-3 py-2 text-app-text text-sm"
                />
              </div>
              <div>
                <label className="text-xs text-app-text3 block mb-1">Скорость коррозии, мм/год</label>
                <input
                  type="text"
                  inputMode="decimal"
                  placeholder="если известна из мониторинга"
                  value={calcInputs.corrosion_rate_mm_year}
                  onChange={(e) => setCalcInputs((s) => ({ ...s, corrosion_rate_mm_year: e.target.value }))}
                  className="w-full bg-app-deep border border-app-line rounded-lg px-3 py-2 text-app-text text-sm"
                />
              </div>
              <div>
                <label className="text-xs text-app-text3 block mb-1">К_з (запас) или класс ОПО</label>
                <input
                  type="text"
                  inputMode="decimal"
                  value={calcInputs.safety_factor}
                  onChange={(e) => setCalcInputs((s) => ({ ...s, safety_factor: e.target.value }))}
                  className="w-full bg-app-deep border border-app-line rounded-lg px-3 py-2 text-app-text text-sm mb-2"
                />
                <select
                  value={calcInputs.opo_hazard_class}
                  onChange={(e) => setCalcInputs((s) => ({ ...s, opo_hazard_class: e.target.value }))}
                  className="w-full bg-app-deep border border-app-line rounded-lg px-3 py-2 text-app-text text-sm"
                >
                  <option value="">Класс ОПО не задан (K_з из поля выше)</option>
                  <option value="I">I — K_з = 1,5</option>
                  <option value="II">II — K_з = 1,3</option>
                  <option value="III">III — K_з = 1,1</option>
                  <option value="IV">IV — K_з = 1,0</option>
                </select>
              </div>
            </div>
            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                onClick={runResidualLifeCalc}
                disabled={calcLoading}
                className="px-4 py-2 rounded-lg bg-accent text-white text-sm font-medium hover:bg-accent/90 disabled:opacity-50"
              >
                {calcLoading ? 'Считаем…' : 'Рассчитать'}
              </button>
              {calcResult && (
                <button
                  type="button"
                  onClick={applyCalcToForm}
                  className="px-4 py-2 rounded-lg bg-app-soft text-app-text text-sm font-medium hover:bg-app-softer border border-app-line"
                >
                  Перенести в форму добавления
                </button>
              )}
            </div>
            {calcError && <p className="text-sm text-red-400">{calcError}</p>}
            {calcResult && (
              <div className="rounded-lg border border-app-line bg-app-deep/50 p-4 space-y-2">
                <div className="flex flex-wrap items-baseline gap-3">
                  <span className="text-sm text-app-text3">Остаточный ресурс:</span>
                  <span className="text-lg font-bold text-app-text">{calcResult.residual_years} лет</span>
                  <span className={`text-sm font-semibold ${statusColor(calcResult.status)}`}>
                    {calcResult.status}
                  </span>
                </div>
                <p className="text-xs text-app-text3">{calcResult.methodology}</p>
                <pre className="text-xs text-app-text2 overflow-x-auto max-h-40 whitespace-pre-wrap">
                  {JSON.stringify(calcResult.details, null, 2)}
                </pre>
                <p className="text-xs text-app-text3">
                  Расчёт рекомендательный; итоговое заключение оформляет ответственный специалист.
                </p>
              </div>
            )}
          </div>
        )}
      </div>

      {showAddForm && (
        <div className="bg-app-panel p-6 rounded-xl border border-app-line">
          <h2 className="text-xl font-bold text-app-text mb-4">Добавить ресурс оборудования</h2>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-sm text-app-text3 block mb-1">Оборудование *</label>
                <select
                  required
                  value={formData.equipment_id}
                  onChange={(e) => setFormData({ ...formData, equipment_id: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                >
                  <option value="">Выберите оборудование</option>
                  {equipment.map((eq) => (
                    <option key={eq.id} value={eq.id}>
                      {eq.name}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Остаточный ресурс (лет)</label>
                <input
                  type="number"
                  step="0.01"
                  value={formData.remaining_resource_years}
                  onChange={(e) => setFormData({ ...formData, remaining_resource_years: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Дата окончания ресурса</label>
                <input
                  type="date"
                  value={formData.resource_end_date}
                  onChange={(e) => setFormData({ ...formData, resource_end_date: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Продление (лет)</label>
                <input
                  type="number"
                  step="0.1"
                  value={formData.extension_years}
                  onChange={(e) => setFormData({ ...formData, extension_years: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Дата продления</label>
                <input
                  type="date"
                  value={formData.extension_date}
                  onChange={(e) => setFormData({ ...formData, extension_date: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Методика расчёта</label>
                <input
                  type="text"
                  value={formData.calculation_method}
                  onChange={(e) => setFormData({ ...formData, calculation_method: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                  placeholder="Например: РД 09-539-03"
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Номер документа</label>
                <input
                  type="text"
                  value={formData.document_number}
                  onChange={(e) => setFormData({ ...formData, document_number: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                />
              </div>
            </div>
            {formData.calculation_data && (
              <div className="rounded-lg border border-app-line bg-app-deep/40 p-3">
                <p className="text-xs text-app-text3 mb-2">В БД будут сохранены параметры расчёта (JSON)</p>
                <pre className="text-xs text-app-text2 max-h-32 overflow-auto whitespace-pre-wrap">
                  {JSON.stringify(formData.calculation_data, null, 2)}
                </pre>
              </div>
            )}
            <div className="flex gap-2">
              <button
                type="submit"
                className="bg-accent px-4 py-2 rounded-lg text-white font-bold hover:bg-accent/80"
              >
                Сохранить
              </button>
              <button
                type="button"
                onClick={() => setShowAddForm(false)}
                className="bg-app-soft px-4 py-2 rounded-lg text-app-text font-bold hover:bg-app-softer"
              >
                Отмена
              </button>
            </div>
          </form>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {equipment.map((eq) => {
          const resource = getEquipmentResource(eq.id);
          const daysUntilExpiry = resource ? calculateDaysUntilExpiry(resource.resource_end_date) : null;
          const isExpiringSoon = daysUntilExpiry !== null && daysUntilExpiry < 365 && daysUntilExpiry > 0;
          const isExpired = daysUntilExpiry !== null && daysUntilExpiry <= 0;

          return (
            <div
              key={eq.id}
              className={`bg-app-panel p-4 rounded-xl border transition-colors cursor-pointer ${
                isExpired
                  ? 'border-red-500/50'
                  : isExpiringSoon
                    ? 'border-yellow-500/50'
                    : 'border-app-line hover:border-accent/50'
              }`}
              onClick={() => setSelectedEquipment(eq)}
            >
              <div className="flex justify-between items-start mb-2">
                <h3 className="text-lg font-bold text-app-text">{eq.name}</h3>
                {isExpired && <AlertTriangle className="text-red-400" size={20} />}
                {isExpiringSoon && <AlertTriangle className="text-yellow-400" size={20} />}
              </div>

              {eq.location && <p className="text-sm text-app-text3 mb-3">{eq.location}</p>}

              {resource ? (
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-app-text3">Остаточный ресурс:</span>
                    <span className="text-sm font-bold text-white">
                      {resource.remaining_resource_years != null
                        ? Number(resource.remaining_resource_years).toFixed(2)
                        : '—'}{' '}
                      лет
                    </span>
                  </div>
                  {resource.calculation_method && (
                    <p className="text-xs text-app-text3 line-clamp-2">{resource.calculation_method}</p>
                  )}
                  {resource.resource_end_date && (
                    <div className="flex items-center justify-between">
                      <span className="text-sm text-app-text3">Окончание ресурса:</span>
                      <span
                        className={`text-sm font-bold ${
                          isExpired ? 'text-red-400' : isExpiringSoon ? 'text-yellow-400' : 'text-white'
                        }`}
                      >
                        {new Date(resource.resource_end_date).toLocaleDateString('ru-RU')}
                      </span>
                    </div>
                  )}
                  {daysUntilExpiry !== null && (
                    <div className="text-xs text-app-text3 mt-2">
                      {isExpired
                        ? 'Ресурс истёк'
                        : isExpiringSoon
                          ? `Осталось ${daysUntilExpiry} дней`
                          : `Осталось ${daysUntilExpiry} дней`}
                    </div>
                  )}
                  {resource.extension_years != null && (
                    <div className="flex items-center gap-2 text-accent mt-2">
                      <TrendingUp size={14} />
                      <span className="text-sm">Продлен на {resource.extension_years} лет</span>
                    </div>
                  )}
                </div>
              ) : (
                <p className="text-sm text-app-text3">Ресурс не указан</p>
              )}
            </div>
          );
        })}
      </div>

      {selectedEquipment && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
          onClick={() => setSelectedEquipment(null)}
        >
          <div
            className="bg-app-panel rounded-xl p-6 max-w-2xl w-full mx-4 max-h-[85vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-app-text">{selectedEquipment.name}</h2>
              <button
                type="button"
                onClick={() => setSelectedEquipment(null)}
                className="text-app-text3 hover:text-app-text"
              >
                ✕
              </button>
            </div>

            {getEquipmentResource(selectedEquipment.id) ? (
              <div className="space-y-4">
                {Object.entries(getEquipmentResource(selectedEquipment.id)!).map(([key, value]) => {
                  if (key === 'id' || value === null || value === undefined) return null;
                  if (key === 'calculation_data' && typeof value === 'object') {
                    return (
                      <div key={key}>
                        <p className="text-sm text-app-text3 mb-1">Данные расчёта</p>
                        <pre className="text-xs text-app-text2 whitespace-pre-wrap bg-app-deep rounded p-2 border border-app-line">
                          {JSON.stringify(value, null, 2)}
                        </pre>
                      </div>
                    );
                  }
                  return (
                    <div key={key}>
                      <p className="text-sm text-app-text3 mb-1">{key.replace(/_/g, ' ')}</p>
                      <p className="text-white">{String(value)}</p>
                    </div>
                  );
                })}
              </div>
            ) : (
              <p className="text-app-text3">Ресурс не указан</p>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default ResourceManagement;
