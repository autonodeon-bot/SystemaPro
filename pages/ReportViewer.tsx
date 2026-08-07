import React, { useEffect, useMemo, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { FileText, ArrowLeft, Download, Image as ImageIcon, AlertCircle } from 'lucide-react';
import { API_BASE } from '../constants';

interface PreviewData {
  inspection: {
    id: string;
    date_performed?: string;
    status: string;
    conclusion?: string;
    data?: any;
  };
  equipment: {
    id: string;
    name: string;
    serial_number?: string;
    location?: string;
    commissioning_date?: string;
    attributes?: any;
  };
  questionnaire?: { id?: string | null };
  document_files?: Array<{
    document_number: string;
    file_name?: string;
    file_size?: number;
    file_type?: string;
    mime_type?: string;
  }>;
  opo?: {
    id?: string;
    name?: string;
    code?: string;
    description?: string;
    enterprise_name?: string;
    branch_name?: string;
    workshop_name?: string;
    survey_data?: any;
  };
  ndt_methods?: Array<{
    id?: string;
    method_code: string;
    method_name: string;
    is_performed: boolean;
    standard?: string;
    equipment?: string;
    inspector_name?: string;
    inspector_level?: string;
    results?: string;
    defects?: string;
    conclusion?: string;
    photos?: string[];
    additional_data?: any;
  }>;
}

interface ReportValidationResult {
  is_complete: boolean;
  missing_fields: string[];
  warnings: string[];
  can_generate?: boolean;
}

const ReportViewer: React.FC = () => {
  const { inspectionId } = useParams();
  const navigate = useNavigate();
  const [data, setData] = useState<PreviewData | null>(null);
  const [reportId, setReportId] = useState<string | null>(null);
  const [validation, setValidation] = useState<ReportValidationResult | null>(null);
  const [loading, setLoading] = useState(true);

  const buildDocUrl = (docNumber: string) => {
    const qId = data?.questionnaire?.id;
    if (!qId) return null;
    return `${API_BASE}/api/questionnaires/${encodeURIComponent(qId)}/documents/${encodeURIComponent(docNumber)}/view`;
  };

  const isImageDoc = (mime?: string) => (mime || '').toLowerCase().startsWith('image/');
  const buildNdtPhotoUrl = (methodId?: string, path?: string) => {
    if (!methodId || !path) return null;
    const fileName = path.split('/').pop();
    if (!fileName) return null;
    return `${API_BASE}/api/ndt-methods/${encodeURIComponent(methodId)}/photos/${encodeURIComponent(fileName)}`;
  };

  useEffect(() => {
    const load = async () => {
      if (!inspectionId) return;
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;
      try {
        setLoading(true);
        const [previewRes, reportRes, validationRes] = await Promise.all([
          fetch(`${API_BASE}/api/inspections/${inspectionId}/preview`, { headers }),
          fetch(`${API_BASE}/api/reports?inspection_id=${inspectionId}`, { headers }),
          fetch(`${API_BASE}/api/reports/validate/${inspectionId}`, { headers }),
        ]);
        if (previewRes.ok) {
          const preview = await previewRes.json();
          setData(preview);
        }
        if (reportRes.ok) {
          const reportData = await reportRes.json();
          const item = (reportData.items || [])[0];
          if (item?.id) setReportId(item.id);
        }
        if (validationRes.ok) {
          const validationData = await validationRes.json();
          setValidation(validationData);
        } else {
          setValidation(null);
        }
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [inspectionId]);

  const docFiles = useMemo(() => data?.document_files ?? [], [data]);
  const schemeDoc = useMemo(
    () => docFiles.find((doc) => doc.document_number === 'control_scheme_image'),
    [docFiles],
  );
  const documentsData = (data?.inspection?.data?.documents ?? {}) as Record<string, any>;
  const documentsInfo = (data?.inspection?.data?.documents_info ?? {}) as Record<string, any>;
  const documentKeys = useMemo(() => {
    const keys = new Set<string>();
    Object.keys(documentsData || {}).forEach((k) => keys.add(String(k)));
    Object.keys(documentsInfo || {}).forEach((k) => keys.add(String(k)));
    return Array.from(keys).sort((a, b) => {
      const ai = parseInt(a, 10);
      const bi = parseInt(b, 10);
      if (!Number.isNaN(ai) && !Number.isNaN(bi)) return ai - bi;
      return a.localeCompare(b);
    });
  }, [documentsData, documentsInfo]);

  if (loading) {
    return <div className="text-center text-app-text3 mt-20">Загрузка...</div>;
  }

  if (!data) {
    return (
      <div className="text-center text-app-text3 mt-20">
        Данные не найдены
      </div>
    );
  }

  return (
    <div className="space-y-4 md:space-y-6">
      <div className="flex items-center gap-3">
        <button
          onClick={() => navigate(-1)}
          className="px-3 py-2 rounded-lg bg-app-soft hover:bg-app-softer text-app-text text-sm"
        >
          <ArrowLeft size={16} className="inline mr-2" />
          Назад
        </button>
        <h1 className="text-xl md:text-2xl font-bold text-app-text">Полный просмотр отчета</h1>
        {reportId && (
          <a
            className="ml-auto px-3 py-2 rounded-lg bg-accent text-white text-sm"
            href={`${API_BASE}/api/reports/${reportId}/download`}
          >
            <Download size={16} className="inline mr-2" />
            Скачать отчет
          </a>
        )}
      </div>

      <div className="sp-card">
        <h3 className="sp-section-title text-lg mb-2">Оборудование</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
          <div>
            <span className="text-app-text3">Название:</span>
            <p className="text-white">{data.equipment.name}</p>
          </div>
          {data.equipment.serial_number && (
            <div>
              <span className="text-app-text3">Серийный номер:</span>
              <p className="text-white">{data.equipment.serial_number}</p>
            </div>
          )}
          {data.equipment.location && (
            <div>
              <span className="text-app-text3">Местоположение:</span>
              <p className="text-white">{data.equipment.location}</p>
            </div>
          )}
        </div>
      </div>

      {validation && (
        <div className="sp-card">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-lg font-bold text-app-text">Проверка полноты</h3>
            <span
              className={`px-2 py-1 rounded text-xs font-semibold ${
                validation.is_complete
                  ? 'bg-green-500/20 text-green-300'
                  : 'bg-yellow-500/20 text-yellow-300'
              }`}
            >
              {validation.is_complete ? 'Готово к генерации' : 'Требуется заполнение'}
            </span>
          </div>
          {validation.missing_fields.length > 0 && (
            <div className="mb-3">
              <p className="text-red-300 text-sm mb-1">Обязательные поля:</p>
              <ul className="text-sm text-red-200 space-y-1">
                {validation.missing_fields.map((item, idx) => (
                  <li key={`missing-${idx}`}>• {item}</li>
                ))}
              </ul>
            </div>
          )}
          {validation.warnings.length > 0 && (
            <div>
              <p className="text-amber-300 text-sm mb-1">Предупреждения:</p>
              <ul className="text-sm text-amber-200 space-y-1">
                {validation.warnings.map((item, idx) => (
                  <li key={`warning-${idx}`}>• {item}</li>
                ))}
              </ul>
            </div>
          )}
          {validation.missing_fields.length === 0 && validation.warnings.length === 0 && (
            <p className="text-sm text-green-300">Критичных замечаний не найдено.</p>
          )}
        </div>
      )}

      {data.opo && (
        <div className="sp-card">
          <h3 className="sp-section-title text-lg mb-2">ОПО</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
            {data.opo.name && (
              <div>
                <span className="text-app-text3">Наименование:</span>
                <p className="text-white">{data.opo.name}</p>
              </div>
            )}
            {data.opo.code && (
              <div>
                <span className="text-app-text3">Код:</span>
                <p className="text-white">{data.opo.code}</p>
              </div>
            )}
            {data.opo.enterprise_name && (
              <div>
                <span className="text-app-text3">Предприятие:</span>
                <p className="text-white">{data.opo.enterprise_name}</p>
              </div>
            )}
            {data.opo.branch_name && (
              <div>
                <span className="text-app-text3">Филиал:</span>
                <p className="text-white">{data.opo.branch_name}</p>
              </div>
            )}
            {data.opo.workshop_name && (
              <div>
                <span className="text-app-text3">Цех:</span>
                <p className="text-white">{data.opo.workshop_name}</p>
              </div>
            )}
            {data.opo.description && (
              <div className="sm:col-span-2">
                <span className="text-app-text3">Описание:</span>
                <p className="text-white">{data.opo.description}</p>
              </div>
            )}
          </div>
        </div>
      )}

      {documentKeys.length > 0 && (
        <div className="sp-card">
          <h3 className="sp-section-title text-lg mb-2">Перечень документов</h3>
          <div className="overflow-x-auto">
            <table className="w-full text-sm text-app-text border border-app-line">
              <thead className="bg-app-panel text-app-text2">
                <tr>
                  <th className="p-2 text-left">№</th>
                  <th className="p-2 text-left">Номер документа</th>
                  <th className="p-2 text-left">Дата документа</th>
                  <th className="p-2 text-left">Наличие</th>
                </tr>
              </thead>
              <tbody>
                {documentKeys.map((num) => {
                  const docVal = documentsData?.[num];
                  const info = documentsInfo?.[num] || {};
                  const present =
                    (docVal && typeof docVal === 'object' ? docVal.present ?? docVal.has ?? docVal.value : docVal) ??
                    info?.present ??
                    info?.has ??
                    info?.value;
                  const docNumber =
                    (docVal && typeof docVal === 'object' ? docVal.number ?? docVal.doc_number : '') ||
                    info?.number ||
                    info?.doc_number ||
                    '';
                  const docDate =
                    (docVal && typeof docVal === 'object' ? docVal.date ?? docVal.doc_date : '') ||
                    info?.date ||
                    info?.doc_date ||
                    '';
                  return (
                    <tr key={num} className="border-t border-app-line">
                      <td className="p-2">{num}</td>
                      <td className="p-2">{docNumber || '—'}</td>
                      <td className="p-2">{docDate || '—'}</td>
                      <td className="p-2">{present ? 'Да' : 'Нет'}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      <div className="sp-card">
        <h3 className="sp-section-title text-lg mb-2">Методы НК</h3>
        {data.ndt_methods && data.ndt_methods.length > 0 ? (
          <div className="space-y-3">
            {data.ndt_methods.map((m, idx) => (
              <div key={idx} className="sp-card-soft p-3">
                <div className="text-white font-semibold">{m.method_name}</div>
                {m.inspector_name && (
                  <div className="text-sm text-app-text2">Специалист: {m.inspector_name}</div>
                )}
                {m.standard && (
                  <div className="text-sm text-app-text3">НТД: {m.standard}</div>
                )}
                {m.results && (
                  <div className="text-sm text-app-text2">Результаты: {m.results}</div>
                )}
                {m.defects && (
                  <div className="text-sm text-rose-300">Дефекты: {m.defects}</div>
                )}
                {m.photos && m.photos.length > 0 && (
                  <div className="mt-3 grid grid-cols-2 md:grid-cols-3 gap-2">
                    {m.photos.map((p, pIdx) => {
                      const url = buildNdtPhotoUrl(m.id, p);
                      if (!url) return null;
                      return (
                        <a key={pIdx} href={url} target="_blank" rel="noreferrer">
                          <img
                            src={url}
                            alt="Фото НК"
                            className="w-full h-24 object-cover rounded bg-app-deep"
                          />
                        </a>
                      );
                    })}
                  </div>
                )}
              </div>
            ))}
          </div>
        ) : (
          <div className="text-app-text3 flex items-center gap-2">
            <AlertCircle size={16} />
            Методы НК не указаны
          </div>
        )}
      </div>

      {(schemeDoc || (data.inspection.data?.thickness_measurements || []).length > 0) && (
        <div className="sp-card">
          <h3 className="sp-section-title text-lg mb-2">Схема контроля и точки замера</h3>
          {schemeDoc ? (
            <div className="mb-3">
              {buildDocUrl(String(schemeDoc.document_number)) ? (
                <a href={buildDocUrl(String(schemeDoc.document_number))!} target="_blank" rel="noreferrer">
                  <img
                    src={buildDocUrl(String(schemeDoc.document_number))!}
                    alt="Схема контроля"
                    className="w-full max-h-80 object-contain rounded bg-app-deep"
                  />
                </a>
              ) : (
                <div className="text-app-text3 text-sm">Ссылка на схему недоступна</div>
              )}
            </div>
          ) : (
            <div className="text-app-text3 text-sm mb-3">Схема контроля не приложена</div>
          )}

          {(data.inspection.data?.thickness_measurements || []).length > 0 && (
            <div className="overflow-x-auto">
              <table className="w-full text-sm text-app-text border border-app-line">
                <thead className="bg-app-panel text-app-text2">
                  <tr>
                    <th className="p-2 text-left">№</th>
                    <th className="p-2 text-left">Местоположение</th>
                    <th className="p-2 text-left">Сечение</th>
                    <th className="p-2 text-left">Толщина</th>
                    <th className="p-2 text-left">X%</th>
                    <th className="p-2 text-left">Y%</th>
                  </tr>
                </thead>
                <tbody>
                  {(data.inspection.data?.thickness_measurements || []).map((p: any, idx: number) => (
                    <tr key={idx} className="border-t border-app-line">
                      <td className="p-2">{idx + 1}</td>
                      <td className="p-2">{p.location || '—'}</td>
                      <td className="p-2">{p.section_number || '—'}</td>
                      <td className="p-2">{p.thickness || '—'}</td>
                      <td className="p-2">{p.x_percent ?? '—'}</td>
                      <td className="p-2">{p.y_percent ?? '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      <div className="sp-card">
        <h3 className="sp-section-title text-lg mb-2 flex items-center gap-2">
          <FileText size={18} />
          Приложения ({docFiles.length})
        </h3>
        {docFiles.length === 0 ? (
          <div className="text-app-text3">Нет приложений</div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {docFiles.map((doc, idx) => {
              const docUrl = buildDocUrl(String(doc.document_number));
              if (isImageDoc(doc.mime_type)) {
                return (
                  <div key={`${doc.document_number}-${idx}`} className="sp-card-soft p-3">
                    <p className="text-xs text-app-text3 mb-2">{doc.file_name || doc.document_number}</p>
                    {docUrl ? (
                      <a href={docUrl} target="_blank" rel="noreferrer">
                        <img
                          src={docUrl}
                          alt={doc.file_name || doc.document_number}
                          className="w-full max-h-64 object-contain rounded bg-app-deep"
                        />
                      </a>
                    ) : (
                      <div className="text-app-text3 text-sm">Ссылка недоступна</div>
                    )}
                  </div>
                );
              }
              return (
                <div key={`${doc.document_number}-${idx}`} className="sp-card-soft p-3 flex items-center gap-2">
                  <ImageIcon size={16} className="text-app-text3" />
                  <a
                    href={docUrl || '#'}
                    className="text-white text-sm"
                    target="_blank"
                    rel="noreferrer"
                  >
                    {doc.file_name || doc.document_number}
                  </a>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};

export default ReportViewer;
