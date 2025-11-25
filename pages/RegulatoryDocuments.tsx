import React, { useState, useEffect } from 'react';
import { FileText, Search, Filter, BookOpen, Download } from 'lucide-react';

interface RegulatoryDocument {
  id: string;
  document_type: string;
  number: string;
  name: string;
  description?: string;
  equipment_types?: string[];
  effective_date?: string;
  expiry_date?: string;
}

const RegulatoryDocuments = () => {
  const [documents, setDocuments] = useState<RegulatoryDocument[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [typeFilter, setTypeFilter] = useState<string>('ALL');
  const [selectedDoc, setSelectedDoc] = useState<RegulatoryDocument | null>(null);

  const API_BASE = 'http://5.129.203.182:8000';

  useEffect(() => {
    loadDocuments();
  }, []);

  const loadDocuments = async () => {
    try {
      const response = await fetch(`${API_BASE}/api/regulatory-documents`);
      const data = await response.json();
      setDocuments(data.items || []);
    } catch (error) {
      console.error('Ошибка загрузки документов:', error);
    } finally {
      setLoading(false);
    }
  };

  const getDocumentTypeLabel = (type: string) => {
    const types: Record<string, string> = {
      'GOST': 'ГОСТ',
      'RD': 'РД',
      'FNP': 'ФНП',
      'SNIP': 'СНиП',
      'OTHER': 'Другое'
    };
    return types[type] || type;
  };

  const filteredDocuments = documents.filter(doc => {
    const matchesSearch = 
      doc.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      doc.number.toLowerCase().includes(searchTerm.toLowerCase()) ||
      (doc.description && doc.description.toLowerCase().includes(searchTerm.toLowerCase()));
    const matchesType = typeFilter === 'ALL' || doc.document_type === typeFilter;
    return matchesSearch && matchesType;
  });

  const documentTypes = Array.from(new Set(documents.map(d => d.document_type)));

  if (loading) {
    return <div className="text-center text-slate-400 mt-20">Загрузка...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-white">Нормативные документы</h1>
      </div>

      {/* Поиск и фильтры */}
      <div className="flex gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400" size={20} />
          <input
            type="text"
            placeholder="Поиск по названию, номеру, описанию..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full bg-slate-800 border border-slate-700 rounded-lg pl-10 pr-4 py-2 text-white placeholder-slate-500"
          />
        </div>
        <select
          value={typeFilter}
          onChange={(e) => setTypeFilter(e.target.value)}
          className="bg-slate-800 border border-slate-700 rounded-lg px-4 py-2 text-white"
        >
          <option value="ALL">Все типы</option>
          {documentTypes.map(type => (
            <option key={type} value={type}>{getDocumentTypeLabel(type)}</option>
          ))}
        </select>
      </div>

      {/* Список документов */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {filteredDocuments.map((doc) => (
          <div
            key={doc.id}
            className="bg-slate-800 p-4 rounded-xl border border-slate-700 hover:border-accent/50 transition-colors cursor-pointer"
            onClick={() => setSelectedDoc(doc)}
          >
            <div className="flex items-start gap-3 mb-2">
              <div className="bg-accent/10 p-2 rounded-lg">
                <BookOpen className="text-accent" size={20} />
              </div>
              <div className="flex-1">
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-xs text-accent bg-accent/10 px-2 py-1 rounded">
                    {getDocumentTypeLabel(doc.document_type)}
                  </span>
                  <span className="text-xs text-slate-400">{doc.number}</span>
                </div>
                <h3 className="text-lg font-bold text-white">{doc.name}</h3>
              </div>
            </div>
            
            {doc.description && (
              <p className="text-sm text-slate-400 line-clamp-2 mb-3">{doc.description}</p>
            )}

            {doc.effective_date && (
              <p className="text-xs text-slate-500">
                Действует с: {new Date(doc.effective_date).toLocaleDateString('ru-RU')}
              </p>
            )}
          </div>
        ))}
      </div>

      {filteredDocuments.length === 0 && (
        <div className="text-center text-slate-400 py-20">
          Документы не найдены
        </div>
      )}

      {/* Модальное окно с деталями */}
      {selectedDoc && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setSelectedDoc(null)}>
          <div className="bg-slate-800 rounded-xl p-6 max-w-3xl w-full mx-4 max-h-[80vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-between items-start mb-4">
              <div>
                <div className="flex items-center gap-2 mb-2">
                  <span className="text-sm text-accent bg-accent/10 px-2 py-1 rounded">
                    {getDocumentTypeLabel(selectedDoc.document_type)}
                  </span>
                  <span className="text-sm text-slate-400">{selectedDoc.number}</span>
                </div>
                <h2 className="text-xl font-bold text-white">{selectedDoc.name}</h2>
              </div>
              <button onClick={() => setSelectedDoc(null)} className="text-slate-400 hover:text-white">✕</button>
            </div>

            {selectedDoc.description && (
              <div className="mb-4">
                <p className="text-sm text-slate-400 mb-1">Описание</p>
                <p className="text-white">{selectedDoc.description}</p>
              </div>
            )}

            <div className="grid grid-cols-2 gap-4 mb-4">
              {selectedDoc.effective_date && (
                <div>
                  <p className="text-sm text-slate-400 mb-1">Дата вступления в силу</p>
                  <p className="text-white">{new Date(selectedDoc.effective_date).toLocaleDateString('ru-RU')}</p>
                </div>
              )}
              {selectedDoc.expiry_date && (
                <div>
                  <p className="text-sm text-slate-400 mb-1">Дата окончания действия</p>
                  <p className="text-white">{new Date(selectedDoc.expiry_date).toLocaleDateString('ru-RU')}</p>
                </div>
              )}
            </div>

            {selectedDoc.equipment_types && selectedDoc.equipment_types.length > 0 && (
              <div>
                <p className="text-sm text-slate-400 mb-2">Применимо к типам оборудования:</p>
                <div className="flex flex-wrap gap-2">
                  {selectedDoc.equipment_types.map((type, idx) => (
                    <span key={idx} className="text-xs bg-slate-700 text-slate-300 px-2 py-1 rounded">
                      {type}
                    </span>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default RegulatoryDocuments;



