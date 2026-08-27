# -*- coding: utf-8 -*-
"""Patch RegulatoryDocuments.tsx: upload PDF/DOCX + download + light theme."""
from pathlib import Path

p = Path("pages/RegulatoryDocuments.tsx")
text = p.read_text(encoding="utf-8")

text = text.replace(
    "import { Search, BookOpen, Filter, RefreshCw } from 'lucide-react';",
    "import { Search, BookOpen, Filter, RefreshCw, Upload, Download } from 'lucide-react';",
)

if "has_file?: boolean" not in text:
    text = text.replace(
        "  expiry_date?: string;\n}",
        "  expiry_date?: string;\n  has_file?: boolean;\n  file_name?: string;\n}",
    )

if "showUpload" not in text:
    text = text.replace(
        "  const [selectedDoc, setSelectedDoc] = useState<RegulatoryDocument | null>(null);",
        """  const [selectedDoc, setSelectedDoc] = useState<RegulatoryDocument | null>(null);
  const [showUpload, setShowUpload] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [uploadForm, setUploadForm] = useState({
    document_type: 'GOST',
    number: '',
    name: '',
    description: '',
    file: null as File | null,
  });
  const [uploadError, setUploadError] = useState('');""",
    )

# auth headers helper for load
if "Authorization" not in text:
    text = text.replace(
        """      const response = await fetch(
        `${API_BASE}/api/regulatory-documents${qs ? `?${qs}` : ''}`,
      );""",
        """      const headers: HeadersInit = {};
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;
      const response = await fetch(
        `${API_BASE}/api/regulatory-documents${qs ? `?${qs}` : ''}`,
        { headers },
      );""",
    )

upload_fn = '''
  const handleUpload = async () => {
    if (!uploadForm.file) {
      setUploadError('Выберите файл PDF или DOCX');
      return;
    }
    setUploading(true);
    setUploadError('');
    try {
      const fd = new FormData();
      fd.append('file', uploadForm.file);
      fd.append('document_type', uploadForm.document_type);
      fd.append('number', uploadForm.number);
      fd.append('name', uploadForm.name || uploadForm.file.name);
      fd.append('description', uploadForm.description);
      const headers: HeadersInit = {};
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;
      const res = await fetch(`${API_BASE}/api/regulatory-documents/upload`, {
        method: 'POST',
        headers,
        body: fd,
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || 'Ошибка загрузки');
      }
      setShowUpload(false);
      setUploadForm({ document_type: 'GOST', number: '', name: '', description: '', file: null });
      await loadDocuments();
    } catch (e: any) {
      setUploadError(e?.message || 'Ошибка загрузки');
    } finally {
      setUploading(false);
    }
  };

  const handleDownload = async (doc: RegulatoryDocument) => {
    try {
      const headers: HeadersInit = {};
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;
      const res = await fetch(`${API_BASE}/api/regulatory-documents/${doc.id}/download`, { headers });
      if (!res.ok) throw new Error('Не удалось скачать файл');
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = doc.file_name || `${doc.number || doc.name}.pdf`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      console.error(e);
      alert('Не удалось скачать файл документа');
    }
  };

'''

if "handleUpload" not in text:
    text = text.replace(
        "  const hasRequirements = (doc: RegulatoryDocument) =>",
        upload_fn + "  const hasRequirements = (doc: RegulatoryDocument) =>",
    )

# Upload button in header
old_header_btn = """        <button
          type="button"
          onClick={() => loadDocuments()}
          disabled={loading}
          className="inline-flex items-center justify-center gap-2 px-4 py-2 rounded-lg border border-app-line bg-app-panel text-app-text text-sm hover:border-accent/40 disabled:opacity-50"
        >
          <RefreshCw size={16} className={loading ? 'animate-spin' : ''} />
          Обновить
        </button>"""

new_header_btn = """        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => setShowUpload(true)}
            className="inline-flex items-center justify-center gap-2 px-4 py-2 rounded-lg bg-accent hover:bg-blue-600 text-white text-sm font-medium"
          >
            <Upload size={16} />
            Загрузить PDF/DOCX
          </button>
          <button
            type="button"
            onClick={() => loadDocuments()}
            disabled={loading}
            className="inline-flex items-center justify-center gap-2 px-4 py-2 rounded-lg border border-app-line bg-app-panel text-app-text text-sm hover:border-accent/40 disabled:opacity-50"
          >
            <RefreshCw size={16} className={loading ? 'animate-spin' : ''} />
            Обновить
          </button>
        </div>"""

if "Загрузить PDF/DOCX" not in text:
    text = text.replace(old_header_btn, new_header_btn)

# Badge for file on cards
if "has_file" not in text or "Скачать файл" not in text:
    needle = """            {hasRequirements(doc) && (
              <p className="text-[11px] text-accent/90 mb-1">Есть структурированные требования</p>
            )}"""
    insert = """            {doc.has_file && (
              <p className="text-[11px] text-emerald-400 mb-1">Прикреплён файл {doc.file_name || ''}</p>
            )}
            {hasRequirements(doc) && (
              <p className="text-[11px] text-accent/90 mb-1">Есть структурированные требования</p>
            )}"""
    if needle in text:
        text = text.replace(needle, insert)

# Download in modal + upload modal
upload_modal = '''
      {showUpload && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={() => !uploading && setShowUpload(false)}>
          <div className="bg-app-panel rounded-xl p-6 max-w-lg w-full border border-app-line shadow-2xl" onClick={(e) => e.stopPropagation()}>
            <h2 className="text-xl font-bold text-app-text mb-4">Загрузка нормативного документа</h2>
            <div className="space-y-3">
              <div>
                <label className="text-sm text-app-text3 block mb-1">Тип</label>
                <select
                  value={uploadForm.document_type}
                  onChange={(e) => setUploadForm({ ...uploadForm, document_type: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded-lg px-3 py-2 text-app-text"
                >
                  {DOC_TYPE_OPTIONS.filter((o) => o.value !== 'ALL').map((o) => (
                    <option key={o.value} value={o.value}>{o.label}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Номер</label>
                <input
                  value={uploadForm.number}
                  onChange={(e) => setUploadForm({ ...uploadForm, number: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded-lg px-3 py-2 text-app-text"
                  placeholder="ГОСТ 14249-89"
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Название</label>
                <input
                  value={uploadForm.name}
                  onChange={(e) => setUploadForm({ ...uploadForm, name: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded-lg px-3 py-2 text-app-text"
                  placeholder="Если пусто — из имени файла"
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Описание</label>
                <textarea
                  value={uploadForm.description}
                  onChange={(e) => setUploadForm({ ...uploadForm, description: e.target.value })}
                  className="w-full bg-app-deep border border-app-line rounded-lg px-3 py-2 text-app-text"
                  rows={2}
                />
              </div>
              <div>
                <label className="text-sm text-app-text3 block mb-1">Файл (PDF, DOC, DOCX)</label>
                <input
                  type="file"
                  accept=".pdf,.doc,.docx,application/pdf,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                  onChange={(e) => setUploadForm({ ...uploadForm, file: e.target.files?.[0] || null })}
                  className="w-full text-sm text-app-text"
                />
              </div>
              {uploadError && <p className="text-sm text-red-400">{uploadError}</p>}
              <div className="flex gap-2 pt-2">
                <button type="button" disabled={uploading} onClick={handleUpload} className="flex-1 px-4 py-2 bg-accent hover:bg-blue-600 text-white rounded-lg font-medium disabled:opacity-50">
                  {uploading ? 'Загрузка…' : 'Загрузить'}
                </button>
                <button type="button" disabled={uploading} onClick={() => setShowUpload(false)} className="px-4 py-2 bg-app-soft text-app-text rounded-lg">Отмена</button>
              </div>
            </div>
          </div>
        </div>
      )}
'''

if "showUpload &&" not in text:
    text = text.replace(
        "      {selectedDoc && (",
        upload_modal + "\n      {selectedDoc && (",
    )

# Download button in detail modal near close
if "Скачать файл" not in text:
    text = text.replace(
        """              <button
                type="button"
                onClick={() => setSelectedDoc(null)}
                className="text-app-text3 hover:text-app-text shrink-0 text-xl leading-none"
                aria-label="Закрыть"
              >
                ✕
              </button>""",
        """              <div className="flex items-center gap-2 shrink-0">
                {selectedDoc.has_file && (
                  <button
                    type="button"
                    onClick={() => handleDownload(selectedDoc)}
                    className="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg border border-app-line text-sm text-app-text hover:border-accent/40"
                  >
                    <Download size={16} />
                    Скачать файл
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => setSelectedDoc(null)}
                  className="text-app-text3 hover:text-app-text text-xl leading-none"
                  aria-label="Закрыть"
                >
                  ✕
                </button>
              </div>""",
    )

# Fix remaining text-white in this file
text = text.replace("text-2xl font-bold text-white", "text-2xl font-bold text-app-text")
text = text.replace("text-xl font-bold text-white", "text-xl font-bold text-app-text")
text = text.replace('<p className="text-white">', '<p className="text-app-text">')
text = text.replace("extracted JSON", "структурированные требования")

p.write_text(text, encoding="utf-8")
print("OK RegulatoryDocuments")
