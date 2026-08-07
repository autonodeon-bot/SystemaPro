import {
  FileText,
  FileCode,
  X,
  CheckCircle,
  AlertCircle,
  Sparkles,
  Factory,
  FilePlus,
  Download,
} from 'lucide-react';
import type { NavigateFunction } from 'react-router-dom';
import { API_BASE } from '../../constants';
import type { PreviewData, ReportValidationResult } from './types';

interface ReportPreviewModalProps {
  previewData: PreviewData;
  previewType: string;
  validationResult: ReportValidationResult | null;
  validatingPreview: boolean;
  generatingId: string | null;
  onClose: () => void;
  formatDateRu: (value?: string | null) => string;
  onRefreshValidation: (inspectionId: string) => Promise<void>;
  navigate: NavigateFunction;
  onGenerateFromPreview: (format?: string) => void;
  onExportExcel: () => Promise<void>;
  hasTechnicalReport?: boolean;
}

const isImageDoc = (mime?: string) => (mime || '').toLowerCase().startsWith('image/');
const isPdfDoc = (mime?: string) => (mime || '').toLowerCase().includes('pdf');

const ReportPreviewModal = ({
  previewData,
  previewType,
  validationResult,
  validatingPreview,
  generatingId,
  onClose,
  formatDateRu,
  onRefreshValidation,
  navigate,
  onGenerateFromPreview,
  onExportExcel,
  hasTechnicalReport = false,
}: ReportPreviewModalProps) => {
  const previewDocs = previewData.document_files ?? [];
  const questionnaireId = previewData.questionnaire?.id;

  const buildDocUrl = (docNumber: string): string | null => {
    if (!questionnaireId) return null;
    return `${API_BASE}/api/questionnaires/${encodeURIComponent(questionnaireId)}/documents/${encodeURIComponent(docNumber)}/view`;
  };

  const isGenerating = generatingId === previewData.inspection.id;
  const expertiseBlocked = previewType === 'EXPERTISE' && !hasTechnicalReport;

  return (
    <div className="fixed inset-0 bg-black/70 z-50 flex items-center justify-center p-2 md:p-4">
      <div className="sp-card-soft rounded-xl w-full max-w-4xl max-h-[95vh] md:max-h-[90vh] overflow-hidden flex flex-col">
        <div className="flex items-center justify-between p-6 border-b border-app-line">
          <h2 className="text-xl font-bold text-app-text">
            Предпросмотр {previewType === 'TECHNICAL_REPORT' ? 'технического отчета' : 'экспертизы ПБ'}
          </h2>
          <button type="button" onClick={onClose} className="text-app-text3 hover:text-app-text">
            <X size={24} />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-4 md:p-6 space-y-4 md:space-y-6">
          <div className="bg-app-deep p-3 md:p-4 rounded-lg">
            <h3 className="sp-section-title text-base md:text-lg mb-3 flex items-center gap-2">
              <CheckCircle size={18} className="md:w-5 md:h-5 text-green-400" />
              Оборудование
            </h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
              <div>
                <span className="text-app-text3">Название:</span>
                <p className="text-white font-bold">{previewData.equipment.name}</p>
              </div>
              {previewData.equipment.serial_number && (
                <div>
                  <span className="text-app-text3">Серийный номер:</span>
                  <p className="text-white">{previewData.equipment.serial_number}</p>
                </div>
              )}
              {previewData.equipment.location && (
                <div>
                  <span className="text-app-text3">Местоположение:</span>
                  <p className="text-white">{previewData.equipment.location}</p>
                </div>
              )}
              {previewData.equipment.commissioning_date && (
                <div>
                  <span className="text-app-text3">Дата ввода в эксплуатацию:</span>
                  <p className="text-white">{formatDateRu(previewData.equipment.commissioning_date)}</p>
                </div>
              )}
            </div>
          </div>

          <div className="sp-card">
            <h3 className="sp-section-title text-lg mb-3 flex items-center gap-2">
              <CheckCircle size={20} className="text-green-400" />
              Данные диагностики
            </h3>
            <div className="space-y-2 text-sm">
              {previewData.inspection.date_performed && (
                <div>
                  <span className="text-app-text3">Дата проведения:</span>
                  <p className="text-white">{formatDateRu(previewData.inspection.date_performed)}</p>
                </div>
              )}
              <div>
                <span className="text-app-text3">Статус:</span>
                <p className="text-white">{previewData.inspection.status}</p>
              </div>
              {previewData.inspection.conclusion && (
                <div>
                  <span className="text-app-text3">Заключение:</span>
                  <p className="text-white">{previewData.inspection.conclusion}</p>
                </div>
              )}
            </div>
          </div>

          {validationResult && (
            <div className="sp-card">
              <div className="flex items-center justify-between mb-3">
                <h3 className="text-lg font-bold text-app-text">Проверка полноты</h3>
                <span
                  className={`px-2 py-1 rounded text-xs font-semibold ${
                    validationResult.is_complete
                      ? 'bg-green-500/20 text-green-300'
                      : 'bg-yellow-500/20 text-yellow-300'
                  }`}
                >
                  {validationResult.is_complete ? 'Готово к генерации' : 'Требуется заполнение'}
                </span>
              </div>
              {validationResult.missing_fields.length > 0 && (
                <div className="mb-3">
                  <p className="text-red-300 text-sm mb-1">Обязательные поля:</p>
                  <ul className="text-sm text-red-200 space-y-1">
                    {validationResult.missing_fields.map((item, idx) => (
                      <li key={`missing-${idx}`}>• {item}</li>
                    ))}
                  </ul>
                </div>
              )}
              {validationResult.warnings.length > 0 && (
                <div>
                  <p className="text-amber-300 text-sm mb-1">Предупреждения:</p>
                  <ul className="text-sm text-amber-200 space-y-1">
                    {validationResult.warnings.map((item, idx) => (
                      <li key={`warning-${idx}`}>• {item}</li>
                    ))}
                  </ul>
                </div>
              )}
              {validationResult.missing_fields.length === 0 && validationResult.warnings.length === 0 && (
                <p className="text-sm text-green-300">Критичных замечаний не найдено.</p>
              )}
            </div>
          )}

          {previewData.opo && (
            <div className="sp-card">
              <h3 className="sp-section-title text-lg mb-3 flex items-center gap-2">
                <Factory size={20} className="text-blue-400" />
                Сведения об ОПО
              </h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
                {previewData.opo.name && (
                  <div>
                    <span className="text-app-text3">Наименование:</span>
                    <p className="text-white">{previewData.opo.name}</p>
                  </div>
                )}
                {previewData.opo.code && (
                  <div>
                    <span className="text-app-text3">Код:</span>
                    <p className="text-white">{previewData.opo.code}</p>
                  </div>
                )}
                {previewData.opo.enterprise_name && (
                  <div>
                    <span className="text-app-text3">Предприятие:</span>
                    <p className="text-white">{previewData.opo.enterprise_name}</p>
                  </div>
                )}
                {previewData.opo.branch_name && (
                  <div>
                    <span className="text-app-text3">Филиал:</span>
                    <p className="text-white">{previewData.opo.branch_name}</p>
                  </div>
                )}
                {previewData.opo.workshop_name && (
                  <div>
                    <span className="text-app-text3">Цех:</span>
                    <p className="text-white">{previewData.opo.workshop_name}</p>
                  </div>
                )}
                {previewData.opo.description && (
                  <div className="sm:col-span-2">
                    <span className="text-app-text3">Описание:</span>
                    <p className="text-white">{previewData.opo.description}</p>
                  </div>
                )}
                {previewData.opo.survey_data?.organization && (
                  <div>
                    <span className="text-app-text3">Организация (опросный лист):</span>
                    <p className="text-white">{previewData.opo.survey_data.organization}</p>
                  </div>
                )}
                {previewData.opo.survey_data?.executors && (
                  <div>
                    <span className="text-app-text3">Исполнители (опросный лист):</span>
                    <p className="text-white">{previewData.opo.survey_data.executors}</p>
                  </div>
                )}
              </div>
            </div>
          )}

          {previewDocs.length > 0 && (
            <div className="sp-card">
              <h3 className="sp-section-title text-lg mb-3 flex items-center gap-2">
                <FileText size={20} className="text-purple-400" />
                Фото, чертежи и документы ({previewDocs.length})
              </h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {previewDocs.map((doc, idx) => {
                  const docUrl = buildDocUrl(String(doc.document_number));
                  const label = doc.file_name || doc.document_number;
                  if (isImageDoc(doc.mime_type)) {
                    return (
                      <div key={`${doc.document_number}-${idx}`} className="sp-card-soft p-3">
                        <p className="text-xs text-app-text3 mb-2">{label}</p>
                        {docUrl ? (
                          <a href={docUrl} target="_blank" rel="noreferrer">
                            <img
                              src={docUrl}
                              alt={label}
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
                    <div
                      key={`${doc.document_number}-${idx}`}
                      className="sp-card-soft p-3 flex items-center justify-between"
                    >
                      <div>
                        <p className="text-white text-sm">{label}</p>
                        {doc.mime_type && <p className="text-xs text-app-text3">{doc.mime_type}</p>}
                      </div>
                      {docUrl && (
                        <a
                          href={docUrl}
                          target="_blank"
                          rel="noreferrer"
                          className="text-xs text-accent hover:text-accent-light"
                        >
                          {isPdfDoc(doc.mime_type) ? 'Открыть PDF' : 'Открыть файл'}
                        </a>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          <div className="sp-card">
            <h3 className="sp-section-title text-lg mb-3 flex items-center gap-2">
              {previewData.ndt_methods.length > 0 ? (
                <CheckCircle size={20} className="text-green-400" />
              ) : (
                <AlertCircle size={20} className="text-yellow-400" />
              )}
              Методы неразрушающего контроля ({previewData.ndt_methods.length})
            </h3>
            {previewData.ndt_methods.length > 0 ? (
              <div className="space-y-3">
                {previewData.ndt_methods.map((method, idx) => (
                  <div key={idx} className="sp-card-soft p-3">
                    <div className="flex items-center gap-2 mb-2">
                      <span
                        className={`px-2 py-1 rounded text-xs ${
                          method.is_performed ? 'bg-green-500/20 text-green-400' : 'bg-app-soft text-app-text3'
                        }`}
                      >
                        {method.is_performed ? 'Выполнен' : 'Не выполнен'}
                      </span>
                      <span className="text-white font-bold">{method.method_name}</span>
                      {method.method_code && (
                        <span className="text-app-text3 text-xs">({method.method_code})</span>
                      )}
                    </div>
                    {method.inspector_name && (
                      <p className="text-sm text-app-text2">Инженер: {method.inspector_name}</p>
                    )}
                    {method.results && (
                      <p className="text-sm text-app-text2 mt-1">Результаты: {method.results}</p>
                    )}
                    {method.defects && (
                      <p className="text-sm text-red-300 mt-1">Дефекты: {method.defects}</p>
                    )}
                    {method.conclusion && (
                      <p className="text-sm text-app-text2 mt-1">Заключение: {method.conclusion}</p>
                    )}
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-app-text3 text-sm">Методы НК не указаны</p>
            )}
          </div>

          {previewType === 'EXPERTISE' && previewData.resource && (
            <div className="sp-card">
              <h3 className="sp-section-title text-lg mb-3 flex items-center gap-2">
                <CheckCircle size={20} className="text-green-400" />
                Данные ресурса
              </h3>
              <div className="grid grid-cols-2 gap-3 text-sm">
                {previewData.resource.remaining_resource_years != null && (
                  <div>
                    <span className="text-app-text3">Остаточный ресурс (лет):</span>
                    <p className="text-white">{previewData.resource.remaining_resource_years}</p>
                  </div>
                )}
                {previewData.resource.resource_end_date && (
                  <div>
                    <span className="text-app-text3">Дата окончания ресурса:</span>
                    <p className="text-white">{formatDateRu(previewData.resource.resource_end_date)}</p>
                  </div>
                )}
                {previewData.resource.extension_years != null && (
                  <div>
                    <span className="text-app-text3">Продление (лет):</span>
                    <p className="text-white">{previewData.resource.extension_years}</p>
                  </div>
                )}
                {previewData.resource.extension_date && (
                  <div>
                    <span className="text-app-text3">Дата продления:</span>
                    <p className="text-white">{formatDateRu(previewData.resource.extension_date)}</p>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>

        <div className="flex flex-col sm:flex-row justify-end gap-2 md:gap-3 p-4 md:p-6 border-t border-app-line">
          <button
            type="button"
            onClick={onClose}
            className="px-3 md:px-4 py-2 bg-app-soft hover:bg-app-softer text-app-text rounded-lg text-sm md:text-base"
          >
            Отмена
          </button>
          <button
            type="button"
            onClick={() => {
              const id = previewData.inspection.id;
              if (id) void onRefreshValidation(id);
            }}
            disabled={validatingPreview}
            className="px-3 md:px-4 py-2 bg-yellow-600 hover:bg-yellow-700 text-white rounded-lg text-sm md:text-base"
          >
            {validatingPreview ? 'Проверка...' : 'Проверить полноту'}
          </button>
          <button
            type="button"
            onClick={() => {
              const id = previewData.inspection.id;
              if (id) {
                onClose();
                navigate(`/report-viewer/${id}`);
              }
            }}
            className="px-3 md:px-4 py-2 bg-app-panel hover:bg-app-soft text-app-text rounded-lg text-sm md:text-base"
          >
            Полный просмотр
          </button>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => onGenerateFromPreview('pdf')}
              disabled={isGenerating || expertiseBlocked}
              title={
                expertiseBlocked
                  ? 'Сначала сгенерируйте технический отчёт'
                  : `Сгенерировать PDF (${previewType === 'TECHNICAL_REPORT' ? 'ТО' : 'ЭПБ'})`
              }
              aria-label="Сгенерировать PDF"
              className="p-2.5 bg-accent hover:bg-blue-600 text-white rounded-lg flex items-center justify-center disabled:opacity-50"
            >
              {isGenerating ? <Sparkles size={18} className="animate-spin" /> : <FilePlus size={18} />}
            </button>
            <button
              type="button"
              onClick={() => onGenerateFromPreview('docx')}
              disabled={isGenerating || expertiseBlocked}
              title={
                expertiseBlocked
                  ? 'Сначала сгенерируйте технический отчёт'
                  : `Сгенерировать DOCX (${previewType === 'TECHNICAL_REPORT' ? 'ТО' : 'ЭПБ'})`
              }
              aria-label="Сгенерировать DOCX"
              className="p-2.5 bg-green-500/10 text-green-400 border border-green-500/20 hover:bg-green-500/20 rounded-lg flex items-center justify-center disabled:opacity-50"
            >
              {isGenerating ? <Sparkles size={18} className="animate-spin" /> : <FileCode size={18} />}
            </button>
            <button
              type="button"
              onClick={() => void onExportExcel()}
              title="Экспорт в Excel"
              aria-label="Экспорт в Excel"
              className="p-2.5 bg-green-600 hover:bg-green-700 text-white rounded-lg flex items-center justify-center"
            >
              <Download size={18} />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ReportPreviewModal;
