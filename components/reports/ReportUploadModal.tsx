import React from 'react';
import { Download, FileText, Upload, X, Image as ImageIcon } from 'lucide-react';
import { API_BASE } from '../../constants';
import type { DocumentFile, Questionnaire } from './types';
import { formatFileSize, getDocumentName } from './reportUtils';

const DOCUMENT_NUMBERS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17] as const;

export interface ReportUploadModalProps {
  questionnaire: Questionnaire;
  documentFiles: DocumentFile[] | undefined;
  uploadingFile: string | null;
  onClose: () => void;
  onUpload: (questionnaireId: string, documentNumber: string, file: File | undefined) => void;
  onDelete: (questionnaireId: string, documentNumber: string) => void;
}

const ReportUploadModal: React.FC<ReportUploadModalProps> = ({
  questionnaire,
  documentFiles,
  uploadingFile,
  onClose,
  onUpload,
  onDelete,
}) => {
  return (
    <div className="fixed inset-0 bg-black/70 z-50 flex items-center justify-center p-4">
      <div className="bg-app-panel rounded-xl border border-app-line w-full max-w-3xl max-h-[90vh] overflow-hidden flex flex-col">
        <div className="flex items-center justify-between p-6 border-b border-app-line">
          <h2 className="text-xl font-bold text-app-text">
            Файлы документов: {questionnaire.equipment_name}
          </h2>
          <button type="button" onClick={onClose} className="text-app-text3 hover:text-app-text">
            <X size={24} />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-6">
          <div className="space-y-4">
            {DOCUMENT_NUMBERS.map((docNum) => {
              const docFile = documentFiles?.find((f) => f.document_number === String(docNum));
              const docName = getDocumentName(docNum);
              const uploadKey = `${questionnaire.id}-${docNum}`;

              return (
                <div key={docNum} className="bg-app-deep rounded-lg p-4 border border-app-line">
                  <div className="flex items-center justify-between mb-2">
                    <div className="flex-1">
                      <h4 className="text-white font-semibold">
                        {docNum}. {docName}
                      </h4>
                    </div>
                    <div className="flex items-center gap-2">
                      {docFile ? (
                        <>
                          <a
                            href={`${API_BASE}/api/questionnaires/${questionnaire.id}/documents/${docNum}/view`}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="px-3 py-1.5 bg-blue-600 hover:bg-blue-700 text-white text-sm rounded-lg flex items-center gap-2"
                          >
                            <Download size={14} />
                            Просмотр
                          </a>
                          <button
                            type="button"
                            onClick={() => onDelete(questionnaire.id, String(docNum))}
                            className="px-3 py-1.5 bg-red-600 hover:bg-red-700 text-white text-sm rounded-lg flex items-center gap-2"
                          >
                            <X size={14} />
                            Удалить
                          </button>
                        </>
                      ) : (
                        <label className="px-3 py-1.5 bg-green-600 hover:bg-green-700 text-white text-sm rounded-lg cursor-pointer flex items-center gap-2">
                          <Upload size={14} />
                          Загрузить
                          <input
                            type="file"
                            accept="image/*,.pdf"
                            className="hidden"
                            onChange={(e) =>
                              onUpload(questionnaire.id, String(docNum), e.target.files?.[0])
                            }
                            disabled={uploadingFile === uploadKey}
                          />
                        </label>
                      )}
                    </div>
                  </div>
                  {docFile && (
                    <div className="mt-2 text-sm text-app-text3">
                      <div className="flex items-center gap-2">
                        {docFile.file_type === 'image' ? (
                          <ImageIcon size={14} className="text-green-400" />
                        ) : (
                          <FileText size={14} className="text-red-400" />
                        )}
                        <span>{docFile.file_name}</span>
                        <span className="text-app-text3">({formatFileSize(docFile.file_size)})</span>
                      </div>
                    </div>
                  )}
                  {uploadingFile === uploadKey && (
                    <div className="mt-2 text-sm text-blue-400">Загрузка...</div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
};

export default ReportUploadModal;
