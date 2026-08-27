# -*- coding: utf-8 -*-
from pathlib import Path

p = Path("pages/ReportTemplates.tsx")
text = p.read_text(encoding="utf-8")
replacements = [
    ("text-2xl font-bold text-white", "text-2xl font-bold text-app-text"),
    ("text-xl font-bold text-white", "text-xl font-bold text-app-text"),
    ("text-lg font-bold text-white", "text-lg font-bold text-app-text"),
    ('className="text-white text-sm"', 'className="text-app-text text-sm"'),
    ("роль <strong className=\"text-app-text\">admin</strong>", "роль <strong className=\"text-app-text\">администратор</strong>"),
]
for a, b in replacements:
    text = text.replace(a, b)

# Add preview modal support if not present
if "previewTemplate" not in text:
    text = text.replace(
        "const [editingTemplate, setEditingTemplate] = useState<ReportTemplate | null>(null);",
        "const [editingTemplate, setEditingTemplate] = useState<ReportTemplate | null>(null);\n"
        "  const [previewTemplate, setPreviewTemplate] = useState<ReportTemplate | null>(null);",
    )
    # Eye icon import
    if "Eye" not in text:
        text = text.replace(
            "import { Plus, Edit, Trash2, Save, X } from 'lucide-react';",
            "import { Plus, Edit, Trash2, Save, X, Eye } from 'lucide-react';",
        )

    section_labels = """
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
"""
    if "SECTION_LABELS" not in text:
        text = text.replace(
            "const ReportTemplates = () => {",
            section_labels + "\nconst ReportTemplates = () => {",
        )

    # Add preview button next to edit
    old_btns = """              <div className="flex gap-2">
                <button
                  onClick={() => {
                    setEditingTemplate(template);"""
    new_btns = """              <div className="flex gap-2">
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
                    setEditingTemplate(template);"""
    if "setPreviewTemplate(template)" not in text:
        text = text.replace(old_btns, new_btns)

    preview_modal = """
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
"""
    if "previewTemplate &&" not in text:
        text = text.replace(
            "      {templates.length === 0 && (",
            preview_modal + "\n      {templates.length === 0 && (",
        )

    # Use SECTION_LABELS in form checkboxes if still using inline ternary
    if "key === 'equipment_info' ?" in text:
        text = text.replace(
            """                    <span className="text-app-text text-sm">
                      {key === 'equipment_info' ? 'Информация об оборудовании' :
                       key === 'opo_info' ? 'Информация об ОПО' :
                       key === 'ndt_methods' ? 'Методы НК' :
                       key === 'specialists' ? 'Специалисты' :
                       key === 'verification_equipment' ? 'Поверенное оборудование' :
                       key === 'documents' ? 'Документы' :
                       key === 'photos' ? 'Фотографии' :
                       key === 'control_scheme' ? 'Схема контроля' : key}
                    </span>""",
            """                    <span className="text-app-text text-sm">
                      {SECTION_LABELS[key] || key}
                    </span>""",
        )

p.write_text(text, encoding="utf-8")
print("OK ReportTemplates")
for i, l in enumerate(text.splitlines()):
    if "previewTemplate" in l or "Шаблоны" in l:
        print(i + 1, l[:100])
