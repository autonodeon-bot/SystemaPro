import { useState, useEffect, useCallback } from 'react';
import { Search, BookOpen, Filter, RefreshCw } from 'lucide-react';
import { API_BASE } from '../constants';

interface RegulatoryDocument {
  id: string;
  document_type: string;
  number: string;
  name: string;
  description?: string;
  equipment_types?: string[];
  requirements?: Record<string, unknown>;
  effective_date?: string;
  expiry_date?: string;
}

interface EquipmentTypeRow {
  id: string;
  name: string;
  code?: string;
  description?: string;
}

const DOC_TYPE_OPTIONS: { value: string; label: string }[] = [
  { value: 'ALL', label: 'Все типы документов' },
  { value: 'GOST', label: 'ГОСТ' },
  { value: 'RD', label: 'РД' },
  { value: 'FNP', label: 'ФНП' },
  { value: 'SNIP', label: 'СНиП' },
  { value: 'OTHER', label: 'Другое' },
];

const RegulatoryDocuments = () => {
  const [documents, setDocuments] = useState<RegulatoryDocument[]>([]);
  const [equipmentTypes, setEquipmentTypes] = useState<EquipmentTypeRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [listMeta, setListMeta] = useState<{ total_returned: number; limit: number } | null>(null);
  const [searchInput, setSearchInput] = useState('');
  const [debouncedQ, setDebouncedQ] = useState('');
  const [typeFilter, setTypeFilter] = useState<string>('ALL');
  const [equipmentTypeFilter, setEquipmentTypeFilter] = useState<string>('');
  const [selectedDoc, setSelectedDoc] = useState<RegulatoryDocument | null>(null);

  useEffect(() => {
    const t = window.setTimeout(() => setDebouncedQ(searchInput), 360);
    return () => window.clearTimeout(t);
  }, [searchInput]);

  const loadEquipmentTypes = useCallback(async () => {
    try {
      const res = await fetch(`${API_BASE}/api/equipment-types`);
      const data = await res.json();
      setEquipmentTypes(Array.isArray(data.items) ? data.items : []);
    } catch (e) {
      console.error('Типы оборудования:', e);
    }
  }, []);

  const loadDocuments = useCallback(async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams();
      if (debouncedQ.trim()) params.set('q', debouncedQ.trim());
      if (typeFilter !== 'ALL') params.set('document_type', typeFilter);
      if (equipmentTypeFilter.trim()) params.set('equipment_type', equipmentTypeFilter.trim());
      params.set('limit', '500');
      const qs = params.toString();
      const response = await fetch(
        `${API_BASE}/api/regulatory-documents${qs ? `?${qs}` : ''}`,
      );
      const data = await response.json();
      setDocuments(data.items || []);
      if (typeof data.total_returned === 'number' && typeof data.limit === 'number') {
        setListMeta({ total_returned: data.total_returned, limit: data.limit });
      } else {
        setListMeta(null);
      }
    } catch (error) {
      console.error('Ошибка загрузки документов:', error);
      setDocuments([]);
    } finally {
      setLoading(false);
    }
  }, [debouncedQ, typeFilter, equipmentTypeFilter]);

  useEffect(() => {
    loadEquipmentTypes();
  }, [loadEquipmentTypes]);

  useEffect(() => {
    loadDocuments();
  }, [loadDocuments]);

  const getDocumentTypeLabel = (type: string) => {
    const hit = DOC_TYPE_OPTIONS.find((o) => o.value === type);
    return hit?.label ?? type;
  };

  const hasRequirements = (doc: RegulatoryDocument) =>
    doc.requirements && Object.keys(doc.requirements).length > 0;

  if (loading && documents.length === 0) {
    return <div className="text-center text-app-text3 mt-20">Загрузка...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:justify-between sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-bold text-white">Нормативные документы</h1>
          {listMeta && (
            <p className="text-sm text-app-text3 mt-1">
              В выборке: {listMeta.total_returned}
              {listMeta.total_returned >= listMeta.limit ? ` (лимит ${listMeta.limit})` : ''}
            </p>
          )}
        </div>
        <button
          type="button"
          onClick={() => loadDocuments()}
          disabled={loading}
          className="inline-flex items-center justify-center gap-2 px-4 py-2 rounded-lg border border-app-line bg-app-panel text-app-text text-sm hover:border-accent/40 disabled:opacity-50"
        >
          <RefreshCw size={16} className={loading ? 'animate-spin' : ''} />
          Обновить
        </button>
      </div>

      <div className="flex flex-col lg:flex-row gap-4">
        <div className="relative flex-1 min-w-0">
          <Search
            className="absolute left-3 top-1/2 transform -translate-y-1/2 text-app-text3 pointer-events-none"
            size={20}
          />
          <input
            type="text"
            placeholder="Поиск по названию, номеру, описанию…"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            className="w-full bg-app-panel border border-app-line rounded-lg pl-10 pr-4 py-2.5 text-app-text placeholder-app-text3"
          />
        </div>
        <div className="flex flex-col sm:flex-row gap-3 shrink-0">
          <div className="flex items-center gap-2 text-app-text3">
            <Filter size={18} className="hidden sm:block shrink-0" />
            <select
              value={typeFilter}
              onChange={(e) => setTypeFilter(e.target.value)}
              className="bg-app-panel border border-app-line rounded-lg px-3 py-2.5 text-app-text text-sm min-w-[200px]"
              aria-label="Тип документа"
            >
              {DOC_TYPE_OPTIONS.map((opt) => (
                <option key={opt.value} value={opt.value}>
                  {opt.label}
                </option>
              ))}
            </select>
          </div>
          <select
            value={equipmentTypeFilter}
            onChange={(e) => setEquipmentTypeFilter(e.target.value)}
            className="bg-app-panel border border-app-line rounded-lg px-3 py-2.5 text-app-text text-sm min-w-[220px]"
            aria-label="Тип оборудования"
          >
            <option value="">Все типы оборудования</option>
            {equipmentTypes.map((et) => (
              <option key={et.id} value={(et.code || et.name || '').trim() || et.id}>
                {et.name}
                {et.code ? ` (${et.code})` : ''}
              </option>
            ))}
          </select>
        </div>
      </div>
      <p className="text-xs text-app-text3 -mt-2">
        Фильтр по оборудованию сопоставляет код типа (code) с массивом{' '}
        <span className="font-mono text-app-text2">equipment_types</span> в карточке НД.
      </p>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {documents.map((doc) => (
          <div
            key={doc.id}
            className="bg-app-panel p-4 rounded-xl border border-app-line hover:border-accent/50 transition-colors cursor-pointer"
            onClick={() => setSelectedDoc(doc)}
          >
            <div className="flex items-start gap-3 mb-2">
              <div className="bg-accent/10 p-2 rounded-lg shrink-0">
                <BookOpen className="text-accent" size={20} />
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex flex-wrap items-center gap-2 mb-1">
                  <span className="text-xs text-accent bg-accent/10 px-2 py-1 rounded">
                    {getDocumentTypeLabel(doc.document_type)}
                  </span>
                  <span className="text-xs text-app-text3 font-mono">{doc.number}</span>
                </div>
                <h3 className="text-lg font-bold text-app-text leading-snug">{doc.name}</h3>
              </div>
            </div>

            {doc.description && (
              <p className="text-sm text-app-text3 line-clamp-2 mb-3">{doc.description}</p>
            )}

            {doc.equipment_types && doc.equipment_types.length > 0 && (
              <div className="flex flex-wrap gap-1 mb-2">
                {doc.equipment_types.slice(0, 4).map((t, idx) => (
                  <span
                    key={`${doc.id}-et-${idx}`}
                    className="text-[11px] bg-app-deep text-app-text2 px-2 py-0.5 rounded border border-app-line"
                  >
                    {t}
                  </span>
                ))}
                {doc.equipment_types.length > 4 && (
                  <span className="text-[11px] text-app-text3">+{doc.equipment_types.length - 4}</span>
                )}
              </div>
            )}

            {hasRequirements(doc) && (
              <p className="text-[11px] text-accent/90 mb-1">Есть структурированные требования</p>
            )}

            {doc.effective_date && (
              <p className="text-xs text-app-text3">
                Действует с: {new Date(doc.effective_date).toLocaleDateString('ru-RU')}
              </p>
            )}
          </div>
        ))}
      </div>

      {documents.length === 0 && !loading && (
        <div className="text-center text-app-text3 py-20">Документы не найдены — измените фильтры или поиск</div>
      )}

      {selectedDoc && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
          onClick={() => setSelectedDoc(null)}
        >
          <div
            className="bg-app-panel rounded-xl p-6 max-w-3xl w-full max-h-[85vh] overflow-y-auto border border-app-line shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex justify-between items-start mb-4 gap-4">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2 mb-2">
                  <span className="text-sm text-accent bg-accent/10 px-2 py-1 rounded">
                    {getDocumentTypeLabel(selectedDoc.document_type)}
                  </span>
                  <span className="text-sm text-app-text3 font-mono">{selectedDoc.number}</span>
                </div>
                <h2 className="text-xl font-bold text-white leading-snug">{selectedDoc.name}</h2>
              </div>
              <button
                type="button"
                onClick={() => setSelectedDoc(null)}
                className="text-app-text3 hover:text-app-text shrink-0 text-xl leading-none"
                aria-label="Закрыть"
              >
                ✕
              </button>
            </div>

            {selectedDoc.description && (
              <div className="mb-4">
                <p className="text-sm text-app-text3 mb-1">Описание</p>
                <p className="text-app-text whitespace-pre-wrap">{selectedDoc.description}</p>
              </div>
            )}

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-4">
              {selectedDoc.effective_date && (
                <div>
                  <p className="text-sm text-app-text3 mb-1">Дата вступления в силу</p>
                  <p className="text-white">
                    {new Date(selectedDoc.effective_date).toLocaleDateString('ru-RU')}
                  </p>
                </div>
              )}
              {selectedDoc.expiry_date && (
                <div>
                  <p className="text-sm text-app-text3 mb-1">Дата окончания действия</p>
                  <p className="text-white">
                    {new Date(selectedDoc.expiry_date).toLocaleDateString('ru-RU')}
                  </p>
                </div>
              )}
            </div>

            {selectedDoc.equipment_types && selectedDoc.equipment_types.length > 0 && (
              <div className="mb-4">
                <p className="text-sm text-app-text3 mb-2">Применимо к типам оборудования (коды/метки в БД)</p>
                <div className="flex flex-wrap gap-2">
                  {selectedDoc.equipment_types.map((type, idx) => (
                    <span key={idx} className="text-xs bg-app-deep text-app-text2 px-2 py-1 rounded border border-app-line">
                      {type}
                    </span>
                  ))}
                </div>
              </div>
            )}

            {hasRequirements(selectedDoc) && (
              <div>
                <p className="text-sm text-app-text3 mb-2">Требования / extracted JSON</p>
                <pre className="text-xs text-app-text2 bg-app-deep rounded-lg p-3 border border-app-line overflow-x-auto whitespace-pre-wrap max-h-64">
                  {JSON.stringify(selectedDoc.requirements, null, 2)}
                </pre>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default RegulatoryDocuments;
