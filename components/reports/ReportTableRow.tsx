import React from 'react';
import {
  Download,
  FileText,
  Trash2,
  CheckCircle2,
  Upload,
} from 'lucide-react';
import { API_BASE } from '../../constants';
import type { DocumentFile, Questionnaire, UnifiedListItem } from './types';
import {
  getReportTypeLabel,
  getStatusColor,
  getStatusLabel,
} from './reportUtils';

function shortDate(s?: string): string {
  if (!s) return '—';
  try {
    return new Date(s).toLocaleDateString('ru-RU');
  } catch {
    return s;
  }
}

export interface ReportTableRowProps {
  item: UnifiedListItem;
  selected: boolean;
  onToggleSelect: (id: string, checked: boolean) => void;
  documentFiles: DocumentFile[] | undefined;
  canApprove: boolean;
  onNavigateReportViewer: (inspectionId: string) => void;
  onApproveReport: (inspectionId?: string) => void;
  onDeleteReport: (reportId: string) => void;
  onGenerateQuestionnairePdf: (questionnaireId: string) => void;
  onGenerateQuestionnaireWord: (questionnaireId: string) => Promise<void>;
  onOpenFileManager: (q: Questionnaire) => void;
}

const ReportTableRow: React.FC<ReportTableRowProps> = ({
  item,
  selected,
  onToggleSelect,
  canApprove,
  onNavigateReportViewer,
  onApproveReport,
  onDeleteReport,
  onGenerateQuestionnairePdf,
  onGenerateQuestionnaireWord,
  onOpenFileManager,
}) => {
  const isQ = item.itemType === 'questionnaire';

  return (
    <tr className="border-b border-app-line/80 hover:bg-app-panel/60">
      <td className="px-2 py-2 align-middle w-10">
        <input
          type="checkbox"
          checked={selected}
          onChange={(e) => onToggleSelect(item.id, e.target.checked)}
          className="accent-blue-500"
        />
      </td>
      <td className="px-3 py-2 align-middle max-w-[220px]">
        <div className="font-medium text-white truncate" title={item.title}>
          {item.title}
        </div>
        <div className="text-xs text-app-text3 truncate">{item.equipment_name}</div>
      </td>
      <td className="px-2 py-2 align-middle whitespace-nowrap">
        <span className={`px-2 py-0.5 rounded text-xs border ${getStatusColor(item.status)}`}>
          {getStatusLabel(item.status)}
        </span>
      </td>
      <td className="px-2 py-2 align-middle text-xs text-app-text2 whitespace-nowrap">
        {getReportTypeLabel(item.report_type)}
      </td>
      <td className="px-2 py-2 align-middle text-xs text-app-text3 whitespace-nowrap">
        {shortDate(item.created_at)}
      </td>
      <td className="px-2 py-2 align-middle text-right">
        <div className="flex flex-wrap justify-end gap-1">
          {isQ ? (
            <>
              {item.file_size === 0 || !item.file_path ? (
                <button
                  type="button"
                  onClick={() => onGenerateQuestionnairePdf(item.id)}
                  className="px-2 py-1 rounded bg-accent/90 text-white text-xs font-medium"
                >
                  PDF
                </button>
              ) : (
                <a
                  href={`${API_BASE}/api/questionnaires/${item.id}/download`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1 px-2 py-1 rounded bg-green-700 text-white text-xs"
                >
                  <Download size={12} /> PDF
                </a>
              )}
              {item.word_file_size === 0 || !item.word_file_path ? (
                <button
                  type="button"
                  onClick={() => void onGenerateQuestionnaireWord(item.id)}
                  className="px-2 py-1 rounded bg-blue-700 text-white text-xs font-medium"
                >
                  Word
                </button>
              ) : (
                <a
                  href={`${API_BASE}/api/questionnaires/${item.id}/download-word`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1 px-2 py-1 rounded bg-blue-700 text-white text-xs"
                >
                  <Download size={12} /> W
                </a>
              )}
              <button
                type="button"
                onClick={() => onOpenFileManager(item as Questionnaire)}
                className="px-2 py-1 rounded bg-app-softer text-app-text text-xs"
                title="Файлы"
              >
                <Upload size={12} className="inline" />
              </button>
            </>
          ) : (
            <>
              {item.file_path && (
                <a
                  href={`${API_BASE}/api/reports/${item.id}/download`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1 px-2 py-1 rounded bg-accent/90 text-white text-xs"
                >
                  <Download size={12} />
                </a>
              )}
              {item.inspection_id && (
                <button
                  type="button"
                  onClick={() => onNavigateReportViewer(item.inspection_id!)}
                  className="px-2 py-1 rounded bg-app-softer text-app-text text-xs"
                  title="Просмотр"
                >
                  <FileText size={12} />
                </button>
              )}
              {canApprove && item.inspection_id && item.status !== 'APPROVED' && (
                <button
                  type="button"
                  onClick={() => onApproveReport(item.inspection_id)}
                  className="px-2 py-1 rounded bg-green-700 text-white text-xs"
                  title="Утвердить"
                >
                  <CheckCircle2 size={12} />
                </button>
              )}
              <button
                type="button"
                onClick={() => onDeleteReport(item.id)}
                className="px-2 py-1 rounded bg-red-900/70 text-white text-xs"
                title="Удалить"
              >
                <Trash2 size={12} />
              </button>
            </>
          )}
        </div>
      </td>
    </tr>
  );
};

export default ReportTableRow;
