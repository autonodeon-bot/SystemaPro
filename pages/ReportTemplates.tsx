import { useState, useEffect } from 'react';
import { Plus, Edit, Trash2, Save, X, Eye } from 'lucide-react';
import { API_BASE } from '../constants';

interface ReportTemplate {
  id: string;
  name: string;
  description?: string;
  template_type: string;
  client_id?: string;
  client_name?: string;
  template_config: any;
  is_default: boolean;
  is_active: number;
}


  const SECTION_LABELS: Record<string, string> = {
    equipment_info: 'Информация об оборудовании',
    opo_info: 'Информация об ОПО',
    ndt_methods: 'Методы НК',
    specialists: 'Специалисты',
    verification_equipment: 'Поверенное оборудование',
    documents: 'Документы',
    photos: 'Фотографии',
    control_scheme: 'Схема контроля',
  };

const ReportTemplates = () => {
  const [templates, setTemplates] = useState<ReportTemplate[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editingTemplate, setEditingTemplate] = useState<ReportTemplate | null>(null);
  const [previewTemplate, setPreviewTemplate] = useState<ReportTemplate | null>(null);
  const [formData, setFormData] = useState({
    name: '',
    description: '',
    template_type: 'TECHNICAL',
    client_id: '',
    template_config: {
      include_sections: {
        equipment_info: true,
        opo_info: true,
        ndt_methods: true,
        specialists: true,
        verification_equipment: true,
        documents: true,
        photos: true,
        control_scheme: true,
      },
      styles: {
        font_family: 'Arial',
        font_size: 11,
        header_color: '#1e40af',
      }
    },
    is_default: false,
  });

  useEffect(() => {
    loadTemplates();
  }, []);

  const loadTemplates = async () => {
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;
      
      const response = await fetch(`${API_BASE}/api/report-templates-db`, { headers });
      if (response.ok) {
        const data = await response.json();
        setTemplates(data.items || []);
      }
    } catch (error) {
      console.error('Ошибка загрузки шаблонов:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async () => {
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;
      
      const url = editingTemplate
        ? `${API_BASE}/api/report-templates-db/${editingTemplate.id}`
        : `${API_BASE}/api/report-templates-db`;
      
      const method = editingTemplate ? 'PUT' : 'POST';
      
      const response = await fetch(url, {
        method,
        headers,
        body: JSON.stringify(formData)
      });

      if (response.ok) {
        await loadTemplates();
        setShowForm(false);
        setEditingTemplate(null);
        setFormData({
          name: '',
          description: '',
          template_type: 'TECHNICAL',
          client_id: '',
          template_config: {
            include_sections: {
              equipment_info: true,
              opo_info: true,
              ndt_methods: true,
              specialists: true,
              verification_equipment: true,
              documents: true,
              photos: true,
              control_scheme: true,
            },
            styles: {
              font_family: 'Arial',
              font_size: 11,
              header_color: '#1e40af',
            }
          },
          is_default: false,
        });
      } else {
        const error = await response.json();
        alert(`Ошибка: ${error.detail || 'Не удалось сохранить шаблон'}`);
      }
    } catch (error) {
      console.error('Ошибка сохранения шаблона:', error);
      alert('Ошибка сохранения шаблона');
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Удалить шаблон?')) return;
    
    try {
      const headers: HeadersInit = { 'Content-Type': 'application/json' };
      const token = localStorage.getItem('token');
      if (token) headers['Authorization'] = `Bearer ${token}`;
      
      const response = await fetch(`${API_BASE}/api/report-templates-db/${id}`, {
        method: 'DELETE',
        headers
      });

      if (response.ok) {
        await loadTemplates();
      }
    } catch (error) {
      console.error('Ошибка удаления шаблона:', error);
    }
  };

  if (loading) {
    return <div className="text-center text-app-text3 mt-20">Загрузка...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-app-text">Шаблоны отчетов</h1>
        <button
          onClick={() => {
            setEditingTemplate(null);
            setShowForm(true);
          }}
          className="px-4 py-2 bg-accent hover:bg-blue-600 text-white rounded-lg font-bold flex items-center gap-2"
        >
          <Plus size={20} />
          Создать шаблон
        </button>
      </div>

      <div className="bg-app-panel rounded-xl p-4 border border-app-line text-sm text-app-text2 space-y-2">
        <p className="font-semibold text-app-text">Как пользоваться шаблонами отчётов</p>
        <ul className="list-disc list-inside space-y-1 text-app-text3">
          <li>
            Раздел доступен роли <strong className="text-app-text">admin</strong>: здесь вносятся записи в базу
            (название, тип отчёта, какие разделы включать, флаг «по умолчанию» для данного типа).
          </li>
          <li>
            Нажмите «Создать шаблон», заполните поля, отметьте нужные блоки отчёта и сохраните. Один шаблон на тип
            отчёта можно пометить «по умолчанию» — при создании новой записи система снимает флаг с остальных того же типа.
          </li>
          <li>
            Кнопка перехода к настройке шаблонов есть в панели генерации отчёта (иконка / ссылка на этот раздел).
          </li>
          <li className="text-app-text3">
            Текущая генерация Word/PDF на сервере подбирает <strong className="text-app-text">макет документа</strong> из
            файла <code className="text-xs bg-app-deep px-1 rounded">reports/report_templates.json</code> по типу
            оборудования и виду отчёта. Настройки из этой страницы (галки разделов) хранятся в БД и предназначены для
            учёта и дальнейшей связки с генератором; при необходимости изменить внешний вид готового файла согласуйте с
            администратором правки JSON-макетов на сервере.
          </li>
        </ul>
      </div>

      {showForm && (
        <div className="bg-app-panel rounded-xl p-6 border border-app-line">
          <div className="flex justify-between items-center mb-4">
            <h2 className="text-xl font-bold text-app-text">
              {editingTemplate ? 'Редактировать шаблон' : 'Создать шаблон'}
            </h2>
            <button
              onClick={() => {
                setShowForm(false);
                setEditingTemplate(null);
              }}
              className="text-app-text3 hover:text-app-text"
            >
              <X size={24} />
            </button>
          </div>

          <div className="space-y-4">
            <div>
              <label className="text-sm text-app-text3 block mb-1">Название *</label>
              <input
                type="text"
                value={formData.name}
                onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                placeholder="Название шаблона"
              />
            </div>

            <div>
              <label className="text-sm text-app-text3 block mb-1">Тип отчета</label>
              <select
                value={formData.template_type}
                onChange={(e) => setFormData({ ...formData, template_type: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
              >
                <option value="TECHNICAL">Технический отчет</option>
                <option value="EXPERTISE">Экспертиза</option>
              </select>
            </div>

            <div>
              <label className="text-sm text-app-text3 block mb-1">Описание</label>
              <textarea
                value={formData.description}
                onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                className="w-full bg-app-deep border border-app-line rounded p-2 text-app-text"
                rows={3}
                placeholder="Описание шаблона"
              />
            </div>

            <div>
              <label className="text-sm text-app-text3 block mb-2">Включаемые разделы</label>
              <div className="grid grid-cols-2 gap-2 bg-app-deep p-4 rounded border border-app-line">
                {Object.entries(formData.template_config.include_sections).map(([key, value]) => (
                  <label key={key} className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={value as boolean}
                      onChange={(e) => {
                        setFormData({
                          ...formData,
                          template_config: {
                            ...formData.template_config,
                            include_sections: {
                              ...formData.template_config.include_sections,
                              [key]: e.target.checked
                            }
                          }
                        });
                      }}
                      className="accent-blue-500"
                    />
                    <span className="text-app-text text-sm">
                      {SECTION_LABELS[key] || key}
                    </span>
                  </label>
                ))}
              </div>
            </div>

            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={formData.is_default}
                onChange={(e) => setFormData({ ...formData, is_default: e.target.checked })}
                className="accent-blue-500"
              />
              <label className="text-sm text-app-text2">Использовать по умолчанию</label>
            </div>

            <div className="flex gap-2">
              <button
                onClick={handleSave}
                className="flex-1 px-4 py-2 bg-accent hover:bg-blue-600 text-white rounded-lg font-bold flex items-center justify-center gap-2"
              >
                <Save size={18} />
                Сохранить
              </button>
              <button
                onClick={() => {
                  setShowForm(false);
                  setEditingTemplate(null);
                }}
                className="px-4 py-2 bg-app-soft hover:bg-app-softer text-app-text rounded-lg font-bold"
              >
                Отмена
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {templates.map((template) => (
          <div
            key={template.id}
            className="bg-app-panel rounded-xl p-6 border border-app-line"
          >
            <div className="flex justify-between items-start mb-4">
              <div>
                <h3 className="text-lg font-bold text-app-text">{template.name}</h3>
                {template.is_default && (
                  <span className="inline-block mt-1 px-2 py-1 bg-blue-600 text-white text-xs rounded">
                    По умолчанию
                  </span>
                )}
              </div>
              <div className="flex gap-2">
                <button
                  type="button"
                  title="Просмотр шаблона"
                  onClick={() => setPreviewTemplate(template)}
                  className="text-emerald-400 hover:text-emerald-300"
                >
                  <Eye size={18} />
                </button>
                <button
                  onClick={() => {
                    setEditingTemplate(template);
                    setFormData({
                      name: template.name,
                      description: template.description || '',
                      template_type: template.template_type,
                      client_id: template.client_id || '',
                      template_config: template.template_config,
                      is_default: template.is_default,
                    });
                    setShowForm(true);
                  }}
                  className="text-blue-400 hover:text-blue-300"
                >
                  <Edit size={18} />
                </button>
                <button
                  onClick={() => handleDelete(template.id)}
                  className="text-red-400 hover:text-red-300"
                >
                  <Trash2 size={18} />
                </button>
              </div>
            </div>
            
            <p className="text-app-text3 text-sm mb-4">{template.description || 'Без описания'}</p>
            
            <div className="text-xs text-app-text3">
              Тип: {template.template_type === 'TECHNICAL' ? 'Технический отчет' : 'Экспертиза'}
            </div>
          </div>
        ))}
      </div>


      {previewTemplate && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={() => setPreviewTemplate(null)}>
          <div className="bg-app-panel rounded-xl p-6 max-w-2xl w-full max-h-[85vh] overflow-y-auto border border-app-line" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-between items-start gap-4 mb-4">
              <div>
                <h2 className="text-xl font-bold text-app-text">{previewTemplate.name}</h2>
                <p className="text-sm text-app-text3 mt-1">
                  Тип: {previewTemplate.template_type === 'TECHNICAL' ? 'Технический отчёт' : previewTemplate.template_type === 'EXPERTISE' ? 'Экспертиза' : previewTemplate.template_type}
                  {previewTemplate.is_default ? ' · по умолчанию' : ''}
                </p>
              </div>
              <button type="button" onClick={() => setPreviewTemplate(null)} className="text-app-text3 hover:text-app-text" aria-label="Закрыть">✕</button>
            </div>
            {previewTemplate.description && (
              <p className="text-app-text2 mb-4 whitespace-pre-wrap">{previewTemplate.description}</p>
            )}
            <p className="text-sm font-semibold text-app-text mb-2">Разделы шаблона</p>
            <ul className="space-y-2 mb-4">
              {Object.entries(previewTemplate.template_config?.include_sections || {}).map(([key, enabled]) => (
                <li key={key} className="flex items-center justify-between text-sm border border-app-line rounded-lg px-3 py-2 bg-app-deep/40">
                  <span className="text-app-text">{SECTION_LABELS[key] || key}</span>
                  <span className={enabled ? 'text-emerald-400' : 'text-app-text3'}>{enabled ? 'Включён' : 'Выключен'}</span>
                </li>
              ))}
            </ul>
            {previewTemplate.template_config?.styles && (
              <div className="text-sm text-app-text3">
                Шрифт: {previewTemplate.template_config.styles.font_family || '—'},
                размер: {previewTemplate.template_config.styles.font_size || '—'},
                цвет заголовка: {previewTemplate.template_config.styles.header_color || '—'}
              </div>
            )}
          </div>
        </div>
      )}

      {templates.length === 0 && (
        <div className="text-center text-app-text3 py-20">
          Шаблоны не найдены. Создайте первый шаблон.
        </div>
      )}
    </div>
  );
};

export default ReportTemplates;
