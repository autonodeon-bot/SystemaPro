import {
  FileText,
  FileCode,
  Download,
  Eye,
  Archive,
  ArchiveRestore,
  ChevronDown,
  ChevronRight,
  Building2,
  Factory,
  Trash2,
} from 'lucide-react';
import type { GroupedItem, Inspection, Report } from './types';

interface GroupedReportListProps {
  groupedItems: GroupedItem[];
  expandedGroups: Record<string, boolean>;
  onToggleGroup: (key: string) => void;
  getGroupDisplayName: (group: GroupedItem) => string;
  formatDateRu: (value?: string | null) => string;
  getEquipmentName: (equipmentId: string) => string;
  getInspectionReport: (inspectionId: string) => Report | undefined;
  loadingPreview: boolean;
  generatingId: string | null;
  onLoadPreview: (inspectionId: string, reportType: string) => void;
  onGenerateDirectly: (inspectionId: string, reportType: string, format?: string) => void;
  onDownloadReport: (reportId: string, format?: 'pdf' | 'docx') => void;
  onPreviewReport: (reportId: string, format?: 'pdf' | 'docx') => void;
  onArchiveInspection: (inspectionId: string, archive: boolean) => void;
  onDeleteInspection: (inspectionId: string) => void;
  onArchiveReport: (reportId: string, archive: boolean) => void;
  onDeleteReport: (reportId: string) => void;
  showArchived: boolean;
}

const GroupedReportList = ({
  groupedItems,
  expandedGroups,
  onToggleGroup,
  getGroupDisplayName,
  formatDateRu,
  getEquipmentName,
  getInspectionReport,
  loadingPreview,
  generatingId,
  onLoadPreview,
  onGenerateDirectly,
  onDownloadReport,
  onPreviewReport,
  onArchiveInspection,
  onDeleteInspection,
  onArchiveReport,
  onDeleteReport,
  showArchived,
}: GroupedReportListProps) => (
  <>
    <div className="space-y-2">
      {groupedItems.map((group) => {
        const isExpanded = expandedGroups[group.key] ?? true;
        const totalItems = group.inspections.length + group.reports.length;

        return (
          <div key={group.key} className="sp-card-soft rounded-xl">
            <button
              type="button"
              onClick={() => onToggleGroup(group.key)}
              className="w-full p-4 flex items-center justify-between hover:bg-app-soft/50 transition-colors rounded-t-xl"
            >
              <div className="flex items-center gap-3">
                {isExpanded ? (
                  <ChevronDown className="text-app-text3" size={20} />
                ) : (
                  <ChevronRight className="text-app-text3" size={20} />
                )}
                {group.enterprise_name && <Building2 className="text-app-text3" size={18} />}
                {group.workshop_name && <Factory className="text-app-text3" size={18} />}
                <span className="text-white font-bold">{getGroupDisplayName(group)}</span>
                <span className="text-sm text-app-text3">
                  ({totalItems} {totalItems === 1 ? 'элемент' : totalItems < 5 ? 'элемента' : 'элементов'})
                </span>
              </div>
            </button>

            {isExpanded && (
              <div className="p-4 space-y-4 border-t border-app-line">
                {group.inspections.length > 0 && (
                  <div>
                    <h3 className="text-sm font-bold text-app-text3 mb-2">Чек-листы ({group.inspections.length})</h3>
                    <div className="space-y-3">
                      {group.inspections.map((inspection: Inspection) => {
                        const existingReport = getInspectionReport(inspection.id);
                        const eqName = getEquipmentName(inspection.equipment_id);

                        return (
                          <div key={inspection.id} className="sp-card">
                            <div className="flex justify-between items-start mb-4">
                              <div className="flex-1">
                                <h3 className="text-lg font-bold text-app-text mb-1">{eqName}</h3>
                                <p className="text-sm text-app-text3">
                                  {inspection.date_performed
                                    ? formatDateRu(inspection.date_performed)
                                    : 'Дата не указана'}
                                  {' • '}
                                  Статус: {inspection.status}
                                </p>
                              </div>
                              <div className="flex items-center gap-2">
                                {existingReport && (
                                  <span className="text-xs text-green-400 bg-green-500/10 px-2 py-1 rounded border border-green-500/20">
                                    Отчет создан
                                  </span>
                                )}
                                <button
                                  type="button"
                                  onClick={() => onArchiveInspection(inspection.id, !inspection.is_archived)}
                                  className="p-2 text-app-text3 hover:text-yellow-400 hover:bg-app-panel rounded"
                                  title={inspection.is_archived ? 'Восстановить из архива' : 'Переместить в архив'}
                                >
                                  {inspection.is_archived ? <ArchiveRestore size={16} /> : <Archive size={16} />}
                                </button>
                                <button
                                  type="button"
                                  onClick={() => onDeleteInspection(inspection.id)}
                                  className="p-2 text-app-text3 hover:text-red-400 hover:bg-app-panel rounded"
                                  title="Удалить"
                                >
                                  <Trash2 size={16} />
                                </button>
                              </div>
                            </div>

                            {inspection.conclusion && (
                              <p className="text-sm text-app-text2 mb-4 line-clamp-2">{inspection.conclusion}</p>
                            )}

                            <div className="flex flex-col sm:flex-row gap-2 flex-wrap">
                              <button
                                type="button"
                                onClick={() => onLoadPreview(inspection.id, 'TECHNICAL_REPORT')}
                                disabled={loadingPreview || generatingId === inspection.id}
                                className="bg-purple-500/10 text-purple-400 border border-purple-500/20 px-3 md:px-4 py-2 rounded-lg text-xs md:text-sm font-bold flex items-center justify-center gap-2 hover:bg-purple-500/20 disabled:opacity-50"
                              >
                                <Eye size={14} className="md:w-4 md:h-4" />
                                <span className="hidden sm:inline">Предпросмотр технического отчета</span>
                                <span className="sm:hidden">Предпросмотр (PDF)</span>
                              </button>
                              <button
                                type="button"
                                onClick={() => onLoadPreview(inspection.id, 'EXPERTISE')}
                                disabled={loadingPreview || generatingId === inspection.id}
                                className="bg-indigo-500/10 text-indigo-400 border border-indigo-500/20 px-3 md:px-4 py-2 rounded-lg text-xs md:text-sm font-bold flex items-center justify-center gap-2 hover:bg-indigo-500/20 disabled:opacity-50"
                              >
                                <Eye size={14} className="md:w-4 md:h-4" />
                                <span className="hidden sm:inline">Предпросмотр экспертизы ПБ</span>
                                <span className="sm:hidden">Предпросмотр (ЭПБ)</span>
                              </button>
                              <button
                                type="button"
                                onClick={() => onGenerateDirectly(inspection.id, 'DIAGNOSTICS', 'docx')}
                                disabled={generatingId === inspection.id}
                                className="bg-amber-500/10 text-amber-300 border border-amber-500/20 px-3 md:px-4 py-2 rounded-lg text-xs md:text-sm font-bold flex items-center justify-center gap-2 hover:bg-amber-500/20 disabled:opacity-50"
                              >
                                <FileText size={14} className="md:w-4 md:h-4" />
                                <span className="hidden sm:inline">Диагностический отчет (DOCX)</span>
                                <span className="sm:hidden">Диагн. DOCX</span>
                              </button>
                              <button
                                type="button"
                                onClick={() => onGenerateDirectly(inspection.id, 'TECHNICAL_REPORT', 'pdf')}
                                disabled={generatingId === inspection.id}
                                className="bg-blue-500/10 text-blue-400 border border-blue-500/20 px-3 md:px-4 py-2 rounded-lg text-xs md:text-sm font-bold flex items-center justify-center gap-2 hover:bg-blue-500/20 disabled:opacity-50"
                              >
                                <FileText size={14} className="md:w-4 md:h-4" />
                                <span className="hidden sm:inline">Сгенерировать новый отчет (PDF)</span>
                                <span className="sm:hidden">PDF</span>
                              </button>
                              <button
                                type="button"
                                onClick={() => onGenerateDirectly(inspection.id, 'TECHNICAL_REPORT', 'docx')}
                                disabled={generatingId === inspection.id}
                                className="bg-green-500/10 text-green-400 border border-green-500/20 px-3 md:px-4 py-2 rounded-lg text-xs md:text-sm font-bold flex items-center justify-center gap-2 hover:bg-green-500/20 disabled:opacity-50"
                              >
                                <FileText size={14} className="md:w-4 md:h-4" />
                                <span className="hidden sm:inline">Сгенерировать новый отчет (DOCX)</span>
                                <span className="sm:hidden">DOCX</span>
                              </button>
                              {existingReport && (
                                <button
                                  type="button"
                                  onClick={() => onDownloadReport(existingReport.id, 'pdf')}
                                  className="bg-green-500/10 text-green-400 border border-green-500/20 px-3 md:px-4 py-2 rounded-lg text-xs md:text-sm font-bold flex items-center justify-center gap-2 hover:bg-green-500/20"
                                >
                                  <Download size={14} className="md:w-4 md:h-4" />
                                  <span className="hidden sm:inline">
                                    Скачать {existingReport.report_type === 'TECHNICAL_REPORT' ? 'отчет' : 'экспертизу'}
                                  </span>
                                  <span className="sm:hidden">Скачать</span>
                                </button>
                              )}
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}

                {group.reports.length > 0 && (
                  <div>
                    <h3 className="text-sm font-bold text-app-text3 mb-2">Отчеты ({group.reports.length})</h3>
                    <div className="space-y-2">
                      {group.reports.map((report: Report) => (
                        <div
                          key={report.id}
                          className="bg-app-deep p-3 rounded-lg border border-app-line flex justify-between items-center"
                        >
                          <div className="flex-1">
                            <p className="text-white font-bold">{report.title}</p>
                            {report.equipment_name && (
                              <p className="text-sm text-app-text3">Оборудование: {report.equipment_name}</p>
                            )}
                            <p className="text-sm text-app-text3">
                              {report.report_type === 'TECHNICAL_REPORT'
                                ? 'Технический отчет'
                                : report.report_type === 'EXPERTISE'
                                  ? 'Экспертиза ПБ'
                                  : 'Отчет'}
                              {' • '}
                              {formatDateRu(report.created_at)}
                              {' • '}
                              Статус: {report.status}
                            </p>
                          </div>
                          <div className="flex items-center gap-2">
                            {report.file_path && (
                              <button
                                type="button"
                                onClick={() => onPreviewReport(report.id, 'pdf')}
                                className="bg-app-text3/10 text-app-text border border-app-text3/30 px-3 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-app-text3/20"
                                title="Открыть PDF в браузере"
                              >
                                <Eye size={16} />
                                Просмотр
                              </button>
                            )}
                            {report.file_path && (
                              <button
                                type="button"
                                onClick={() => onDownloadReport(report.id, 'pdf')}
                                className="bg-red-500/10 text-red-400 border border-red-500/30 px-3 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-red-500/20"
                                title="Скачать PDF"
                              >
                                <FileText size={16} />
                                PDF
                              </button>
                            )}
                            {report.word_file_path && (
                              <button
                                type="button"
                                onClick={() => onPreviewReport(report.id, 'docx')}
                                className="bg-app-text3/10 text-app-text border border-app-text3/30 px-3 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-app-text3/20"
                                title="Открыть DOCX в браузере"
                              >
                                <Eye size={16} />
                                DOCX
                              </button>
                            )}
                            {report.word_file_path && (
                              <button
                                type="button"
                                onClick={() => onDownloadReport(report.id, 'docx')}
                                className="bg-blue-500/10 text-blue-400 border border-blue-500/30 px-3 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-blue-500/20"
                                title="Скачать DOCX"
                              >
                                <FileCode size={16} />
                                DOCX
                              </button>
                            )}
                            {!report.file_path && !report.word_file_path && (
                              <span className="text-app-text3 text-sm">Файл не сгенерирован</span>
                            )}
                            <button
                              type="button"
                              onClick={() => onArchiveReport(report.id, !report.is_archived)}
                              className="p-2 text-app-text3 hover:text-yellow-400 hover:bg-app-panel rounded"
                              title={report.is_archived ? 'Восстановить из архива' : 'Переместить в архив'}
                            >
                              {report.is_archived ? <ArchiveRestore size={16} /> : <Archive size={16} />}
                            </button>
                            <button
                              type="button"
                              onClick={() => onDeleteReport(report.id)}
                              className="p-2 text-app-text3 hover:text-red-400 hover:bg-app-panel rounded"
                              title="Удалить"
                            >
                              <Trash2 size={16} />
                            </button>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>
        );
      })}
    </div>

    {groupedItems.length === 0 && (
      <div className="text-center text-app-text3 py-20">
        {showArchived ? 'Архивные элементы не найдены' : 'Диагностики не найдены'}
      </div>
    )}
  </>
);

export default GroupedReportList;
