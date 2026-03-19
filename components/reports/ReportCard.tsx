import React from 'react';
import {
  Download,
  FileText,
  Calendar,
  User,
  AlertCircle,
  Upload,
  File,
  Image as ImageIcon,
  Trash2,
  CheckCircle2,
} from 'lucide-react';
import { API_BASE } from '../../constants';
import type { DocumentFile, NDTMethod, Questionnaire, UnifiedListItem } from './types';
import {
  formatDate,
  formatFileSize,
  getDocumentName,
  getReportTypeLabel,
  getStatusColor,
  getStatusLabel,
} from './reportUtils';

export interface ReportCardProps {
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

const ReportCard: React.FC<ReportCardProps> = ({
  item,
  selected,
  onToggleSelect,
  documentFiles,
  canApprove,
  onNavigateReportViewer,
  onApproveReport,
  onDeleteReport,
  onGenerateQuestionnairePdf,
  onGenerateQuestionnaireWord,
  onOpenFileManager,
}) => {
  return (
    <div className="bg-slate-900 border border-slate-700 rounded-lg p-4 sm:p-6 hover:border-slate-600 transition-colors">
      <div className="flex items-start gap-3 mb-3">
        <input
          type="checkbox"
          checked={selected}
          onChange={(e) => onToggleSelect(item.id, e.target.checked)}
          className="mt-1 accent-blue-500"
        />
        <FileText className="text-accent mt-1 flex-shrink-0" size={24} />
        <div className="flex-1 min-w-0">
          <h3 className="text-lg font-bold text-white mb-2 break-words">{item.title}</h3>
          <div className="flex flex-wrap gap-2 mb-2">
            <span
              className={`px-2 py-1 rounded text-xs font-semibold border ${getStatusColor(item.status)}`}
            >
              {getStatusLabel(item.status)}
            </span>
            <span className="px-2 py-1 rounded text-xs font-semibold bg-blue-500/20 text-blue-400 border border-blue-500/30">
              {getReportTypeLabel(item.report_type)}
            </span>
          </div>
        </div>
      </div>

      <div className="space-y-2 text-sm text-slate-300 ml-9">
        <div className="flex items-center gap-2">
          <span className="text-slate-400">Оборудование:</span>
          <span className="font-medium">{item.equipment_name || 'Не указано'}</span>
        </div>
        {item.equipment_location && (
          <div className="flex items-center gap-2">
            <span className="text-slate-400">Местоположение:</span>
            <span>{item.equipment_location}</span>
          </div>
        )}
        {item.enterprise_name && (
          <div className="flex items-center gap-2">
            <span className="text-slate-400">Предприятие:</span>
            <span>{item.enterprise_name}</span>
          </div>
        )}
        {item.branch_name && (
          <div className="flex items-center gap-2">
            <span className="text-slate-400">Филиал:</span>
            <span>{item.branch_name}</span>
          </div>
        )}
        {item.workshop_name && (
          <div className="flex items-center gap-2">
            <span className="text-slate-400">Цех:</span>
            <span>{item.workshop_name}</span>
          </div>
        )}
        {item.opo_name && (
          <div className="flex items-center gap-2">
            <span className="text-slate-400">ОПО:</span>
            <span>
              {item.opo_name}
              {item.opo_code ? ` (${item.opo_code})` : ''}
            </span>
          </div>
        )}
        {(item.itemType === 'questionnaire' || item.itemType === 'report') && item.inspector_name && (
          <div className="flex items-center gap-2">
            <User size={16} className="text-slate-400" />
            <span className="text-slate-400">Инженер:</span>
            <span className="font-medium">{item.inspector_name}</span>
            {item.inspector_position && (
              <span className="text-slate-500">({item.inspector_position})</span>
            )}
          </div>
        )}
        {item.itemType === 'questionnaire' && item.inspection_date && (
          <div className="flex items-center gap-2">
            <Calendar size={16} className="text-slate-400" />
            <span className="text-slate-400">Дата обследования:</span>
            <span>{formatDate(item.inspection_date)}</span>
          </div>
        )}
        {item.created_at && (
          <div className="flex items-center gap-2">
            <span className="text-slate-400">Создан:</span>
            <span>{formatDate(item.created_at)}</span>
          </div>
        )}
        {item.file_size !== undefined && (
          <div className="flex items-center gap-2">
            <span className="text-slate-400">Размер PDF:</span>
            <span>{formatFileSize(item.file_size)}</span>
            {item.file_size === 0 && item.itemType === 'questionnaire' && (
              <span className="text-yellow-400 text-xs flex items-center gap-1">
                <AlertCircle size={14} />
                PDF не сгенерирован
              </span>
            )}
          </div>
        )}
        {item.itemType === 'questionnaire' && item.word_file_size !== undefined && (
          <div className="flex items-center gap-2">
            <span className="text-slate-400">Размер Word:</span>
            <span>{formatFileSize(item.word_file_size || 0)}</span>
            {item.word_file_size === 0 && (
              <span className="text-yellow-400 text-xs flex items-center gap-1">
                <AlertCircle size={14} />
                Word не сгенерирован
              </span>
            )}
          </div>
        )}
        {item.itemType === 'questionnaire' && item.ndt_methods && item.ndt_methods.length > 0 && (
          <div className="mt-3 pt-3 border-t border-slate-700">
            <div className="text-slate-400 text-sm mb-2">Методы неразрушающего контроля:</div>
            <div className="flex flex-wrap gap-2">
              {item.ndt_methods.map((method: NDTMethod) => (
                <span
                  key={method.id}
                  className="px-2 py-1 rounded text-xs bg-purple-500/20 text-purple-400 border border-purple-500/30"
                  title={`${method.method_name}${method.standard ? ` (${method.standard})` : ''}`}
                >
                  {method.method_code}
                </span>
              ))}
            </div>
          </div>
        )}
        {item.itemType === 'questionnaire' && documentFiles && documentFiles.length > 0 && (
          <div className="mt-3 pt-3 border-t border-slate-700">
            <div className="flex items-center gap-2 mb-2">
              <File size={16} className="text-slate-400" />
              <span className="text-slate-400 font-semibold">Прикрепленные документы:</span>
            </div>
            <div className="flex flex-wrap gap-2">
              {documentFiles.map((file) => (
                <a
                  key={file.id}
                  href={`${API_BASE}/api/questionnaires/${item.id}/documents/${file.document_number}/view`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-2 px-3 py-1.5 bg-slate-800 hover:bg-slate-700 rounded-lg text-sm text-white transition-colors"
                >
                  {file.file_type === 'image' ? (
                    <ImageIcon size={14} className="text-green-400" />
                  ) : (
                    <FileText size={14} className="text-red-400" />
                  )}
                  <span
                    className="max-w-[200px] truncate"
                    title={getDocumentName(Number(file.document_number))}
                  >
                    {getDocumentName(Number(file.document_number))}
                  </span>
                  <span className="text-slate-400 text-xs">({formatFileSize(file.file_size)})</span>
                </a>
              ))}
            </div>
          </div>
        )}
      </div>

      <div className="flex flex-col gap-2 flex-shrink-0 ml-9 mt-4">
        {item.itemType === 'questionnaire' ? (
          <>
            <div className="flex gap-2">
              {item.file_size === 0 || !item.file_path ? (
                <button
                  type="button"
                  onClick={() => onGenerateQuestionnairePdf(item.id)}
                  className="px-3 py-2 bg-accent hover:bg-accent/80 text-white font-semibold rounded-lg transition-colors flex items-center gap-2 text-sm"
                >
                  <FileText size={16} />
                  <span className="hidden sm:inline">PDF</span>
                </button>
              ) : (
                <a
                  href={`${API_BASE}/api/questionnaires/${item.id}/download`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="px-3 py-2 bg-green-600 hover:bg-green-700 text-white font-semibold rounded-lg transition-colors flex items-center gap-2 text-sm"
                >
                  <Download size={16} />
                  <span className="hidden sm:inline">PDF</span>
                </a>
              )}
              {item.word_file_size === 0 || !item.word_file_path ? (
                <button
                  type="button"
                  onClick={() => onGenerateQuestionnaireWord(item.id)}
                  className="px-3 py-2 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-lg transition-colors flex items-center gap-2 text-sm"
                >
                  <FileText size={16} />
                  <span className="hidden sm:inline">Word</span>
                </button>
              ) : (
                <a
                  href={`${API_BASE}/api/questionnaires/${item.id}/download-word`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="px-3 py-2 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-lg transition-colors flex items-center gap-2 text-sm"
                >
                  <Download size={16} />
                  <span className="hidden sm:inline">Word</span>
                </a>
              )}
              <button
                type="button"
                onClick={() => onOpenFileManager(item as Questionnaire)}
                className="px-3 py-2 bg-green-600 hover:bg-green-700 text-white font-semibold rounded-lg transition-colors flex items-center gap-2 text-sm"
              >
                <Upload size={16} />
                <span className="hidden sm:inline">Управление файлами</span>
                <span className="sm:hidden">Файлы</span>
              </button>
            </div>
          </>
        ) : (
          item.file_path && (
            <div className="flex items-center gap-2">
              <a
                href={`${API_BASE}/api/reports/${item.id}/download`}
                target="_blank"
                rel="noopener noreferrer"
                className="px-4 py-2 bg-accent hover:bg-accent/80 text-white font-semibold rounded-lg transition-colors flex items-center gap-2"
              >
                <Download size={18} />
                <span className="hidden sm:inline">Скачать</span>
                <span className="sm:hidden">PDF</span>
              </a>
              {item.inspection_id && (
                <button
                  type="button"
                  onClick={() => onNavigateReportViewer(item.inspection_id!)}
                  className="px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white font-semibold rounded-lg transition-colors flex items-center gap-2"
                  title="Полный просмотр"
                >
                  <FileText size={18} />
                  <span className="hidden sm:inline">Просмотр</span>
                </button>
              )}
              {canApprove && item.inspection_id && item.status !== 'APPROVED' && (
                <button
                  type="button"
                  onClick={() => onApproveReport(item.inspection_id)}
                  className="px-4 py-2 bg-green-600 hover:bg-green-700 text-white font-semibold rounded-lg transition-colors flex items-center gap-2"
                  title="Утвердить отчет"
                >
                  <CheckCircle2 size={18} />
                  <span className="hidden sm:inline">Утвердить</span>
                </button>
              )}
              <button
                type="button"
                onClick={() => onDeleteReport(item.id)}
                className="px-4 py-2 bg-red-600 hover:bg-red-700 text-white font-semibold rounded-lg transition-colors flex items-center gap-2"
                title="Удалить отчет"
              >
                <Trash2 size={18} />
                <span className="hidden sm:inline">Удалить</span>
              </button>
            </div>
          )
        )}
      </div>
    </div>
  );
};

export default ReportCard;
