import React from 'react';
import { ClipboardList, Download, Calendar, User, Building2, MapPin, Settings, FileText, Eye, Archive, Trash, Pencil } from 'lucide-react';

export interface AssignmentServerSummary {
  has_history: boolean;
  has_inspection: boolean;
  has_report: boolean;
  inspection_id?: string | null;
  report_id?: string | null;
  report_file_path?: string | null;
}

export interface Assignment {
  id: string;
  equipment_id: string;
  equipment_code: string;
  equipment_name: string;
  assignment_type: string;
  assigned_by: string | null;
  assigned_to: string;
  assigned_to_name: string | null;
  status: string;
  priority: string;
  due_date: string | null;
  description: string | null;
  created_at: string;
  updated_at: string | null;
  completed_at: string | null;
  enterprise_id?: string | null;
  enterprise_name?: string | null;
  branch_id?: string | null;
  branch_name?: string | null;
  workshop_id?: string | null;
  workshop_name?: string | null;
  /** Обязательный шаблон из конструктора протоколов (мобильное приложение) */
  protocol_template_id?: string | null;
  protocol_template_name?: string | null;
  report_form_id?: string | null;
  report_form_title?: string | null;
  contract_number?: string | null;
  contract_date?: string | null;
  work_period_from?: string | null;
  work_period_to?: string | null;
  work_basis?: string | null;
  tech_card_number?: string | null;
  tech_card_file_name?: string | null;
  has_tech_card_file?: boolean;
}

export interface AssignmentCardProps {
  assignment: Assignment;
  isSelected: boolean;
  onSelect: (id: string) => void;
  getStatusIcon: (status: string) => React.ReactNode;
  getStatusLabel: (status: string) => string;
  getTypeLabel: (type: string) => string;
  getPriorityColor: (priority: string) => string;
  onViewChecklist?: (assignmentId: string) => void;
  onGenerateReport?: (assignmentId: string) => void;
  onDownloadReport?: (assignmentId: string) => void;
  onArchive?: (assignmentId: string) => void;
  onDelete?: (assignmentId: string) => void;
  onEdit?: (assignment: Assignment) => void;
  generatingReport?: string | null;
  serverSummary?: AssignmentServerSummary;
  userRole?: string;
}

const AssignmentCard: React.FC<AssignmentCardProps> = ({
  assignment, isSelected, onSelect, getStatusIcon, getStatusLabel, getTypeLabel, getPriorityColor,
  onViewChecklist, onGenerateReport, onDownloadReport, onArchive, onDelete, onEdit, generatingReport, serverSummary, userRole
}) => {
  const isOverdue = assignment.due_date && new Date(assignment.due_date) < new Date() && assignment.status !== 'COMPLETED';
  const isCompleted = assignment.status === 'COMPLETED';
  const server = serverSummary;
  
  return (
    <div
      className={`bg-app-panel rounded-xl border-2 p-4 hover:border-accent/50 transition-colors ${
        isSelected ? 'border-accent' : 'border-app-line'
      } ${isOverdue ? 'border-red-500/50' : ''} ${!isCompleted ? 'cursor-pointer' : ''}`}
      onClick={() => !isCompleted && onSelect(assignment.id)}
    >
      <div className="flex items-start justify-between mb-3">
        <div className="flex-1">
          <div className="flex items-center gap-3 mb-2">
            <input
              type="checkbox"
              checked={isSelected}
              onChange={() => onSelect(assignment.id)}
              onClick={(e) => e.stopPropagation()}
              className="rounded"
            />
            <span className="px-2 py-1 bg-app-soft rounded text-xs font-mono text-accent">
              {assignment.equipment_code}
            </span>
            <h3 className="text-lg font-bold text-app-text flex-1">{assignment.equipment_name}</h3>
            <span className={`px-2 py-1 rounded text-xs font-semibold ${getPriorityColor(assignment.priority)} text-white`}>
              {assignment.priority}
            </span>
          </div>
          <div className="flex flex-wrap items-center gap-3 text-xs text-app-text3 ml-7">
            {assignment.enterprise_name && (
              <span className="flex items-center gap-1">
                <Building2 size={14} />
                {assignment.enterprise_name}
              </span>
            )}
            {assignment.branch_name && (
              <span className="flex items-center gap-1">
                <MapPin size={14} />
                {assignment.branch_name}
              </span>
            )}
            {assignment.workshop_name && (
              <span className="flex items-center gap-1">
                <Settings size={14} />
                {assignment.workshop_name}
              </span>
            )}
          </div>
          <div className="flex flex-wrap items-center gap-4 text-sm text-app-text3 ml-7 mt-2">
            <span className="flex items-center gap-1">
              <ClipboardList size={14} />
              {getTypeLabel(assignment.assignment_type)}
            </span>
            <span className="flex items-center gap-1">
              <User size={14} />
              {assignment.assigned_to_name || 'N/A'}
            </span>
            {assignment.due_date && (
              <span className={`flex items-center gap-1 ${isOverdue ? 'text-red-400 font-semibold' : ''}`}>
                <Calendar size={14} />
                {new Date(assignment.due_date).toLocaleDateString('ru-RU')}
                {isOverdue && ' (Просрочено!)'}
              </span>
            )}
            {assignment.protocol_template_id && (
              <span className="flex items-center gap-1 px-2 py-0.5 rounded-md bg-amber-500/15 text-amber-200 border border-amber-500/35" title="Шаблон для мобильного протокола">
                <FileText size={14} />
                {assignment.protocol_template_name?.trim()
                  ? assignment.protocol_template_name
                  : `Шаблон ${assignment.protocol_template_id.slice(0, 8)}…`}
              </span>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2">
          {getStatusIcon(assignment.status)}
          <span className="text-sm font-semibold text-app-text2">
            {getStatusLabel(assignment.status)}
          </span>
        </div>
      </div>
      
      {assignment.description && (
        <p className="text-app-text2 text-sm mb-3 ml-7">{assignment.description}</p>
      )}
      
      <div className="flex items-center justify-between text-xs text-app-text3 ml-7">
        <span>Создано: {new Date(assignment.created_at).toLocaleDateString('ru-RU')}</span>
        {assignment.completed_at && (
          <span className="text-green-400">Завершено: {new Date(assignment.completed_at).toLocaleDateString('ru-RU')}</span>
        )}
      </div>

      {(server?.has_history || server?.has_report || (isCompleted && server && !server.has_history)) && (
        <div className="flex flex-wrap items-center gap-2 mt-2 ml-7">
          {server?.has_history && (
            <span className="px-2 py-1 rounded text-xs bg-green-500/20 text-green-300 border border-green-500/30">
              Данные на сервере
            </span>
          )}
          {server?.has_report && (
            <span className="px-2 py-1 rounded text-xs bg-purple-500/20 text-purple-300 border border-purple-500/30">
              Отчет готов
            </span>
          )}
          {isCompleted && server && !server.has_history && (
            <span className="px-2 py-1 rounded text-xs bg-red-500/20 text-red-300 border border-red-500/30">
              Нет данных на сервере
            </span>
          )}
        </div>
      )}
      
      <div className="flex flex-wrap items-center gap-2 mt-3 ml-7 pt-3 border-t border-app-line">
        {onEdit && (userRole === 'admin' || userRole === 'chief_operator' || userRole === 'operator') && (
          <button
            onClick={(e) => {
              e.stopPropagation();
              onEdit(assignment);
            }}
            className="flex items-center gap-2 px-3 py-1.5 bg-accent/80 hover:bg-accent text-white text-sm rounded transition-colors"
            title="Редактировать задание"
          >
            <Pencil size={16} />
            Редактировать
          </button>
        )}
        {assignment.status !== 'CANCELLED' && onArchive && (
          <button
            onClick={(e) => {
              e.stopPropagation();
              onArchive(assignment.id);
            }}
            className="flex items-center gap-2 px-3 py-1.5 bg-app-softer hover:bg-app-soft text-app-text text-sm rounded transition-colors"
            title="Перенести в архив"
          >
            <Archive size={16} />
            В архив
          </button>
        )}
        {onDelete && (
          <button
            onClick={(e) => {
              e.stopPropagation();
              onDelete(assignment.id);
            }}
            className="flex items-center gap-2 px-3 py-1.5 bg-red-600/80 hover:bg-red-600 text-white text-sm rounded transition-colors"
            title="Удалить задание"
          >
            <Trash size={16} />
            Удалить
          </button>
        )}
      {isCompleted && (
        <>
          <button
            onClick={(e) => {
              e.stopPropagation();
              onViewChecklist?.(assignment.id);
            }}
            className="flex items-center gap-2 px-3 py-1.5 bg-blue-600 hover:bg-blue-700 text-white text-sm rounded transition-colors"
          >
            <Eye size={16} />
            Просмотреть чек-лист
          </button>
          <button
            onClick={(e) => {
              e.stopPropagation();
              onGenerateReport?.(assignment.id);
            }}
            disabled={generatingReport === assignment.id}
            className="flex items-center gap-2 px-3 py-1.5 bg-green-600 hover:bg-green-700 disabled:bg-green-800 disabled:opacity-50 text-white text-sm rounded transition-colors"
          >
            {generatingReport === assignment.id ? (
              <>
                <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
                Генерация...
              </>
            ) : (
              <>
                <FileText size={16} />
                Сгенерировать отчет
              </>
            )}
          </button>
          {serverSummary?.has_report && serverSummary?.report_id && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onDownloadReport?.(assignment.id);
              }}
              className="flex items-center gap-2 px-3 py-1.5 bg-app-soft hover:bg-app-softer text-app-text text-sm rounded transition-colors"
              title="Скачать отчет"
            >
              <Download size={16} />
              Скачать
            </button>
          )}
        </>
        )}
      </div>
    </div>
  );
};

export default AssignmentCard;
