import React, { useMemo } from 'react';
import { FileText, Package, MapPin, Calendar, Download } from 'lucide-react';
import { checklistDocumentNames } from '../../pages/checklistDocumentNames';
import { API_BASE } from '../../constants';
import type { DocumentFile, Inspection, InspectionQuestionnaireInfo } from './types';
import InspectionStatusBadge from './InspectionStatusBadge';
import { formatInspectionDate } from './inspectionUtils';

const ATTACHMENT_LABELS: Record<string, string> = {
  factory_plate_photo: 'Фото заводской таблички',
  control_scheme_image: 'Схема контроля / карта обследования',
};

interface InspectionDetailModalProps {
  inspection: Inspection;
  questionnaireInfo: Record<string, InspectionQuestionnaireInfo>;
  loadingQuestionnaire: boolean;
  onClose: () => void;
}

const InspectionDetailModal: React.FC<InspectionDetailModalProps> = ({
  inspection: insp,
  questionnaireInfo,
  loadingQuestionnaire,
  onClose,
}) => {
  const data = (insp.data ?? {}) as Record<string, unknown>;
  const docsInfo = questionnaireInfo[insp.id];

  const { docsFilesByNumber, attachmentKeys, otherAttachmentKeys } = useMemo(() => {
    const byNum: Record<string, DocumentFile[]> = {};
    if (docsInfo?.document_files) {
      for (const f of docsInfo.document_files) {
        const k = String(f.document_number);
        if (!byNum[k]) byNum[k] = [];
        byNum[k].push(f);
      }
    }
    const attKeys = Object.keys(byNum).filter((k) => k in ATTACHMENT_LABELS);
    const otherKeys = Object.keys(byNum)
      .filter((k) => {
        if (k in ATTACHMENT_LABELS) return false;
        const n = Number(k);
        if (!Number.isNaN(n) && Number.isFinite(n) && n >= 1 && n <= 17) return false;
        return true;
      })
      .sort((a, b) => a.localeCompare(b, 'en'));
    return {
      docsFilesByNumber: byNum,
      attachmentKeys: attKeys,
      otherAttachmentKeys: otherKeys,
    };
  }, [docsInfo]);

  const documents = data.documents;
  const hasDocuments =
    documents !== null &&
    documents !== undefined &&
    typeof documents === 'object' &&
    !Array.isArray(documents);

  return (
    <div
      className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
      onClick={onClose}
      role="presentation"
    >
      <div
        className="bg-app-panel rounded-lg max-w-4xl w-full max-h-[90vh] overflow-y-auto border border-app-line"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="inspection-detail-title"
      >
        <div className="sticky top-0 bg-app-soft border-b border-app-line p-6 flex items-center justify-between">
          <h2 id="inspection-detail-title" className="text-xl font-bold text-app-text flex items-center gap-2">
            <FileText className="text-accent" size={24} />
            Детали чек-листа
          </h2>
          <button
            type="button"
            onClick={onClose}
            className="text-app-text3 hover:text-app-text transition-colors"
          >
            ✕
          </button>
        </div>
        <div className="p-6 space-y-6">
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="text-xs text-app-text3 mb-1 block">Оборудование</label>
              <div className="flex items-center gap-2">
                <Package size={16} className="text-accent" />
                <span className="font-medium">{insp.equipment_name || 'Не указано'}</span>
              </div>
            </div>
            <div>
              <label className="text-xs text-app-text3 mb-1 block">Местоположение</label>
              <div className="flex items-center gap-2">
                <MapPin size={16} className="text-accent" />
                <span>{insp.equipment_location || 'Не указано'}</span>
              </div>
            </div>
            <div>
              <label className="text-xs text-app-text3 mb-1 block">Дата обследования</label>
              <div className="flex items-center gap-2">
                <Calendar size={16} className="text-accent" />
                <span>{formatInspectionDate(insp.date_performed)}</span>
              </div>
            </div>
            <div>
              <label className="text-xs text-app-text3 mb-1 block">Статус</label>
              <InspectionStatusBadge status={insp.status} />
            </div>
          </div>

          {typeof data.executors === 'string' && data.executors && (
            <div>
              <label className="text-xs text-app-text3 mb-1 block">Исполнители</label>
              <p className="text-app-text">{data.executors}</p>
            </div>
          )}

          {typeof data.organization === 'string' && data.organization && (
            <div>
              <label className="text-xs text-app-text3 mb-1 block">Организация</label>
              <p className="text-app-text">{data.organization}</p>
            </div>
          )}

          {hasDocuments && (
            <div>
              <label className="text-xs text-app-text3 mb-2 block">Перечень рассмотренных документов</label>
              <div className="space-y-2">
                {Object.entries(documents as Record<string, unknown>).map(([key, value]) => (
                  <div key={key} className="flex items-center justify-between p-2 bg-app-soft border border-app-line rounded">
                    <div className="flex-1 pr-3">
                      <div className="text-sm text-app-text2">
                        {checklistDocumentNames[String(key)] ?? `Документ ${key}`}
                      </div>
                      {docsFilesByNumber[String(key)]?.length ? (
                        <div className="mt-1 flex flex-wrap gap-2">
                          {docsFilesByNumber[String(key)].map((f) => (
                            <a
                              key={f.id}
                              className="text-xs text-accent hover:underline inline-flex items-center gap-1 px-2 py-1 bg-accent/10 hover:bg-accent/20 rounded"
                              href={`${API_BASE}/api/questionnaires/${docsInfo?.questionnaire_id}/documents/${String(key)}/view`}
                              target="_blank"
                              rel="noreferrer"
                              title={f.file_name}
                            >
                              <Download size={14} />
                              {f.file_name || 'Открыть файл'}
                              {f.file_size ? ` (${(f.file_size / 1024).toFixed(1)} КБ)` : ''}
                            </a>
                          ))}
                        </div>
                      ) : (
                        <div className="mt-1 text-xs text-app-text3">Файл не приложен</div>
                      )}
                    </div>

                    <span
                      className={`px-2 py-1 rounded text-xs ${
                        value ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'
                      }`}
                    >
                      {value ? 'Да' : 'Нет'}
                    </span>
                  </div>
                ))}
              </div>
              {loadingQuestionnaire && (
                <div className="text-xs text-app-text3 mt-2">Загрузка вложений документов...</div>
              )}
              {docsInfo?.questionnaire_id &&
                Object.keys(docsFilesByNumber).length === 0 &&
                !loadingQuestionnaire && (
                  <div className="text-xs text-app-text3 mt-2">Документы не загружены</div>
                )}
            </div>
          )}

          {typeof data.vesselName === 'string' && data.vesselName && (
            <div>
              <label className="text-xs text-app-text3 mb-2 block">Карта обследования</label>
              <div className="grid grid-cols-2 gap-4 p-4 bg-app-soft border border-app-line rounded">
                <div>
                  <span className="text-xs text-app-text3">Наименование сосуда</span>
                  <p className="text-app-text font-medium">{data.vesselName}</p>
                </div>
                {typeof data.serialNumber === 'string' && data.serialNumber && (
                  <div>
                    <span className="text-xs text-app-text3">Заводской номер</span>
                    <p className="text-app-text font-medium">{data.serialNumber}</p>
                  </div>
                )}
                {typeof data.regNumber === 'string' && data.regNumber && (
                  <div>
                    <span className="text-xs text-app-text3">Регистрационный номер</span>
                    <p className="text-app-text font-medium">{data.regNumber}</p>
                  </div>
                )}
              </div>
            </div>
          )}

          {docsInfo?.questionnaire_id && attachmentKeys.length > 0 && (
            <div>
              <label className="text-xs text-app-text3 mb-2 block">Приложенные файлы</label>
              <div className="space-y-2">
                {attachmentKeys.map((k) => (
                  <div key={k} className="flex items-center justify-between p-2 bg-app-soft border border-app-line rounded">
                    <div className="flex-1 pr-3">
                      <div className="text-sm text-app-text2 font-medium">{ATTACHMENT_LABELS[k] || k}</div>
                      <div className="mt-1 flex flex-wrap gap-2">
                        {(docsFilesByNumber[k] || []).map((f) => (
                          <a
                            key={f.id}
                            className="text-xs text-accent hover:underline inline-flex items-center gap-1 px-2 py-1 bg-accent/10 hover:bg-accent/20 rounded"
                            href={`${API_BASE}/api/questionnaires/${docsInfo.questionnaire_id}/documents/${k}/view`}
                            target="_blank"
                            rel="noreferrer"
                            title={f.file_name}
                          >
                            <Download size={14} />
                            {f.file_name || 'Открыть'}
                            {f.file_size ? ` (${(f.file_size / 1024).toFixed(1)} КБ)` : ''}
                          </a>
                        ))}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {docsInfo?.questionnaire_id && otherAttachmentKeys.length > 0 && (
            <div>
              <label className="text-xs text-app-text3 mb-2 block">Прочие вложения</label>
              <div className="space-y-2">
                {otherAttachmentKeys.map((k) => (
                  <div key={k} className="flex items-center justify-between p-2 bg-app-soft border border-app-line rounded">
                    <div className="flex-1 pr-3">
                      <div className="text-sm text-app-text2 font-medium">{k}</div>
                      <div className="mt-1 flex flex-wrap gap-2">
                        {(docsFilesByNumber[k] || []).map((f) => (
                          <a
                            key={f.id}
                            className="text-xs text-accent hover:underline inline-flex items-center gap-1 px-2 py-1 bg-accent/10 hover:bg-accent/20 rounded"
                            href={`${API_BASE}/api/questionnaires/${docsInfo.questionnaire_id}/documents/${k}/view`}
                            target="_blank"
                            rel="noreferrer"
                            title={f.file_name}
                          >
                            <Download size={14} />
                            {f.file_name || 'Открыть'}
                            {f.file_size ? ` (${(f.file_size / 1024).toFixed(1)} КБ)` : ''}
                          </a>
                        ))}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {!docsInfo?.questionnaire_id && (
            <div className="p-3 bg-yellow-500/10 border border-yellow-500/20 rounded">
              <p className="text-xs text-yellow-400">
                Документы привязаны к опросному листу. Для просмотра документов необходимо наличие опросного листа для
                данного оборудования.
              </p>
            </div>
          )}

          {insp.conclusion && (
            <div>
              <label className="text-xs text-app-text3 mb-1 block">Заключение</label>
              <div className="p-4 bg-app-soft border border-app-line rounded">
                <p className="text-app-text whitespace-pre-wrap">{insp.conclusion}</p>
              </div>
            </div>
          )}

          {Object.keys(data).length > 0 && (
            <details className="mt-4">
              <summary className="cursor-pointer text-sm text-app-text3 hover:text-app-text">
                Показать все данные
              </summary>
              <pre className="mt-2 p-4 bg-app-soft rounded text-xs overflow-auto text-app-text2 border border-app-line">
                {JSON.stringify(data, null, 2)}
              </pre>
            </details>
          )}
        </div>
      </div>
    </div>
  );
};

export default InspectionDetailModal;
