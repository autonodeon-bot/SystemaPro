import type { ReactNode } from 'react';
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
  FilePlus,
  ClipboardList,
  Shield,
  Wrench,
} from 'lucide-react';
import type { GroupedItem, Inspection, Report } from './types';

export interface InspectionReports {
  technical?: Report;
  expertise?: Report;
}

interface GroupedReportListProps {
  groupedItems: GroupedItem[];
  expandedGroups: Record<string, boolean>;
  onToggleGroup: (key: string) => void;
  getGroupDisplayName: (group: GroupedItem) => string;
  formatDateRu: (value?: string | null) => string;
  getEquipmentName: (equipmentId: string) => string;
  getInspectionReports: (inspectionId: string) => InspectionReports;
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

const iconBtnBase =
  'p-2 rounded-lg border transition-colors disabled:opacity-40 disabled:cursor-not-allowed flex items-center justify-center';

const IconAction = ({
  title,
  onClick,
  disabled,
  className,
  children,
}: {
  title: string;
  onClick: () => void;
  disabled?: boolean;
  className: string;
  children: ReactNode;
}) => (
  <button
    type="button"
    title={title}
    aria-label={title}
    onClick={onClick}
    disabled={disabled}
    className={`${iconBtnBase} ${className}`}
  >
    {children}
  </button>
);

const ReportActionGroup = ({
  label,
  icon: Icon,
  accentClass,
  inspectionId,
  generatingId,
  loadingPreview,
  canUseExpertise,
  technicalReady,
  existingReport,
  onLoadPreview,
  onGenerateDirectly,
  onDownloadReport,
  reportType,
}: {
  label: string;
  icon: typeof Wrench;
  accentClass: string;
  inspectionId: string;
  generatingId: string | null;
  loadingPreview: boolean;
  technicalReady?: boolean;
  existingReport?: Report;
  onLoadPreview: (inspectionId: string, reportType: string) => void;
  onGenerateDirectly: (inspectionId: string, reportType: string, format?: string) => void;
  onDownloadReport: (reportId: string, format?: 'pdf' | 'docx') => void;
  reportType: 'TECHNICAL_REPORT' | 'EXPERTISE';
}) => {
  const blocked = reportType === 'EXPERTISE' && !technicalReady;
  const disabled = generatingId === inspectionId || loadingPreview || blocked;
  const expertiseHint = blocked ? 'Сначала сгенерируйте технический отчёт' : label;

  return (
    <div
      className={`flex items-center gap-1 rounded-lg border px-2 py-1.5 ${accentClass} ${blocked ? 'opacity-50' : ''}`}
    >
      <span className="hidden sm:flex items-center gap-1 text-[10px] font-bold uppercase tracking-wide mr-1 min-w-[2.5rem]">
        <Icon size={12} aria-hidden />
        {reportType === 'TECHNICAL_REPORT' ? 'ТО' : 'ЭПБ'}
      </span>
      <IconAction
        title={reportType === 'EXPERTISE' ? expertiseHint : `Предпросмотр: ${label}`}
        onClick={() => onLoadPreview(inspectionId, reportType)}
        disabled={disabled}
        className="text-purple-400 border-purple-500/20 bg-purple-500/10 hover:bg-purple-500/20"
      >
        <Eye size={16} />
      </IconAction>
      <IconAction
        title={blocked ? expertiseHint : `Сгенерировать PDF: ${label}`}
        onClick={() => onGenerateDirectly(inspectionId, reportType, 'pdf')}
        disabled={disabled}
        className="text-blue-400 border-blue-500/20 bg-blue-500/10 hover:bg-blue-500/20"
      >
        <FilePlus size={16} />
      </IconAction>
      <IconAction
        title={blocked ? expertiseHint : `Сгенерировать DOCX: ${label}`}
        onClick={() => onGenerateDirectly(inspectionId, reportType, 'docx')}
        disabled={disabled}
        className="text-green-400 border-green-500/20 bg-green-500/10 hover:bg-green-500/20"
      >
        <FileCode size={16} />
      </IconAction>
      {existingReport && (
        <>
          <IconAction
            title={`Скачать PDF: ${label}`}
            onClick={() => onDownloadReport(existingReport.id, 'pdf')}
            disabled={generatingId === inspectionId}
            className="text-amber-300 border-amber-500/20 bg-amber-500/10 hover:bg-amber-500/20"
          >
            <Download size={16} />
          </IconAction>
          {existingReport.word_file_path && (
            <IconAction
              title={`Скачать DOCX: ${label}`}
              onClick={() => onDownloadReport(existingReport.id, 'docx')}
              disabled={generatingId === inspectionId}
              className="text-teal-400 border-teal-500/20 bg-teal-500/10 hover:bg-teal-500/20"
            >
              <FileText size={16} />
            </IconAction>
          )}
        </>
      )}
    </div>
  );
};

const GroupedReportList = ({
  groupedItems,
  expandedGroups,
  onToggleGroup,
  getGroupDisplayName,
  formatDateRu,
  getEquipmentName,
  getInspectionReports,
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
                        const { technical: technicalReport, expertise: expertiseReport } = getInspectionReports(
                          inspection.id,
                        );
                        const eqName = getEquipmentName(inspection.equipment_id);
                        const hasAnyReport = Boolean(technicalReport || expertiseReport);

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
                                {technicalReport && (
                                  <span className="text-xs text-blue-400 bg-blue-500/10 px-2 py-1 rounded border border-blue-500/20">
                                    ТО готов
                                  </span>
                                )}
                                {expertiseReport && (
                                  <span className="text-xs text-indigo-400 bg-indigo-500/10 px-2 py-1 rounded border border-indigo-500/20">
                                    ЭПБ готов
                                  </span>
                                )}
                                {!hasAnyReport && (
                                  <span className="text-xs text-app-text3 bg-app-panel px-2 py-1 rounded border border-app-line">
                                    Без отчёта
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

                            <div className="flex flex-col gap-2">
                              <ReportActionGroup
                                label="Технический отчёт"
                                icon={Wrench}
                                accentClass="border-blue-500/20 bg-blue-500/5"
                                inspectionId={inspection.id}
                                generatingId={generatingId}
                                loadingPreview={loadingPreview}
                                existingReport={technicalReport}
                                onLoadPreview={onLoadPreview}
                                onGenerateDirectly={onGenerateDirectly}
                                onDownloadReport={onDownloadReport}
                                reportType="TECHNICAL_REPORT"
                              />
                              <ReportActionGroup
                                label="Экспертиза ПБ"
                                icon={Shield}
                                accentClass="border-indigo-500/20 bg-indigo-500/5"
                                inspectionId={inspection.id}
                                generatingId={generatingId}
                                loadingPreview={loadingPreview}
                                technicalReady={Boolean(technicalReport)}
                                existingReport={expertiseReport}
                                onLoadPreview={onLoadPreview}
                                onGenerateDirectly={onGenerateDirectly}
                                onDownloadReport={onDownloadReport}
                                reportType="EXPERTISE"
                              />
                              <div className="flex items-center gap-1 rounded-lg border border-amber-500/20 bg-amber-500/5 px-2 py-1.5 w-fit">
                                <span className="hidden sm:flex items-center gap-1 text-[10px] font-bold uppercase tracking-wide mr-1 text-amber-300">
                                  <ClipboardList size={12} aria-hidden />
                                  Диагн.
                                </span>
                                <IconAction
                                  title="Диагностический отчёт (DOCX)"
                                  onClick={() => onGenerateDirectly(inspection.id, 'DIAGNOSTICS', 'docx')}
                                  disabled={generatingId === inspection.id}
                                  className="text-amber-300 border-amber-500/20 bg-amber-500/10 hover:bg-amber-500/20"
                                >
                                  <FilePlus size={16} />
                                </IconAction>
                              </div>
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
                          className="bg-app-deep p-3 rounded-lg border border-app-line flex justify-between items-center gap-2"
                        >
                          <div className="flex-1 min-w-0">
                            <p className="text-white font-bold truncate">{report.title}</p>
                            {report.equipment_name && (
                              <p className="text-sm text-app-text3 truncate">Оборудование: {report.equipment_name}</p>
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
                          <div className="flex items-center gap-1 shrink-0">
                            {report.file_path && (
                              <IconAction
                                title="Просмотр PDF"
                                onClick={() => onPreviewReport(report.id, 'pdf')}
                                className="text-app-text border-app-text3/30 bg-app-text3/10 hover:bg-app-text3/20"
                              >
                                <Eye size={16} />
                              </IconAction>
                            )}
                            {report.file_path && (
                              <IconAction
                                title="Скачать PDF"
                                onClick={() => onDownloadReport(report.id, 'pdf')}
                                className="text-red-400 border-red-500/30 bg-red-500/10 hover:bg-red-500/20"
                              >
                                <Download size={16} />
                              </IconAction>
                            )}
                            {report.word_file_path && (
                              <IconAction
                                title="Просмотр DOCX"
                                onClick={() => onPreviewReport(report.id, 'docx')}
                                className="text-app-text border-app-text3/30 bg-app-text3/10 hover:bg-app-text3/20"
                              >
                                <FileCode size={16} />
                              </IconAction>
                            )}
                            {report.word_file_path && (
                              <IconAction
                                title="Скачать DOCX"
                                onClick={() => onDownloadReport(report.id, 'docx')}
                                className="text-blue-400 border-blue-500/30 bg-blue-500/10 hover:bg-blue-500/20"
                              >
                                <Download size={16} />
                              </IconAction>
                            )}
                            {!report.file_path && !report.word_file_path && (
                              <span className="text-app-text3 text-sm px-2">Нет файла</span>
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
