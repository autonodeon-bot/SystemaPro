
import React, { useState } from 'react';
import { VESSEL_SCHEMA, HIERARCHY_TREE } from '../constants';
import { FormField, ModuleSchema, HierarchyNode, NodeType, EquipmentType, MaintenanceEvent, AttachedDocument, DocCategory, EquipmentAttributes } from '../types';
import { 
  Camera, Save, Calculator, PenTool, Check, 
  ChevronRight, ChevronDown, 
  Building2, Network, Factory, Box, FileText, Tag, FolderOpen, Folder,
  ClipboardList, History, FileBadge, Info, Download, AlertTriangle, Calendar,
  User, ShieldCheck, Printer, Search, Plus, Edit2, Upload, Target, X
} from 'lucide-react';

// --- WIDGETS ---

// Complex Thickness Widget
interface ThicknessPoint {
   id: number;
   x: number; // % from left
   y: number; // % from top
   value: string;
   min: string;
   comment: string;
}

const ThicknessMeasurementWidget = () => {
   const [points, setPoints] = useState<ThicknessPoint[]>([]);
   const [image, setImage] = useState<string | null>(null);

   const handleImageUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (file) {
         // Create a fake URL for demo
         const reader = new FileReader();
         reader.onload = (ev) => setImage(ev.target?.result as string);
         reader.readAsDataURL(file);
      }
   };

   const handleImageClick = (e: React.MouseEvent<HTMLDivElement>) => {
      if (!image) return;
      const rect = e.currentTarget.getBoundingClientRect();
      const x = ((e.clientX - rect.left) / rect.width) * 100;
      const y = ((e.clientY - rect.top) / rect.height) * 100;

      const newPoint: ThicknessPoint = {
         id: points.length + 1,
         x,
         y,
         value: '',
         min: '',
         comment: ''
      };
      setPoints([...points, newPoint]);
   };

   const updatePoint = (id: number, field: keyof ThicknessPoint, value: string) => {
      setPoints(points.map(p => p.id === id ? { ...p, [field]: value } : p));
   };

   return (
      <div className="space-y-4">
         {/* Drawing Area */}
         <div className="relative border-2 border-dashed border-slate-600 rounded-lg min-h-[300px] bg-slate-900/50 flex items-center justify-center overflow-hidden group">
            {image ? (
               <div className="relative w-full h-full cursor-crosshair" onClick={handleImageClick}>
                  <img src={image} alt="Scheme" className="w-full h-auto object-contain select-none pointer-events-none" />
                  {points.map(p => {
                     const isCritical = p.value && p.min && parseFloat(p.value) < parseFloat(p.min);
                     return (
                        <div 
                           key={p.id}
                           className={`absolute w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold border-2 shadow-lg transform -translate-x-1/2 -translate-y-1/2 ${isCritical ? 'bg-red-500 border-white text-white' : 'bg-accent border-white text-white'}`}
                           style={{ left: `${p.x}%`, top: `${p.y}%` }}
                        >
                           {p.id}
                        </div>
                     )
                  })}
               </div>
            ) : (
               <div className="text-center p-8">
                  <Upload className="mx-auto text-slate-500 mb-2" size={32} />
                  <p className="text-slate-400 text-sm mb-4">Загрузите схему/чертеж для нанесения точек замера</p>
                  <label className="px-4 py-2 bg-slate-700 hover:bg-slate-600 rounded cursor-pointer text-white text-sm">
                     Выбрать файл
                     <input type="file" className="hidden" accept="image/*" onChange={handleImageUpload} />
                  </label>
               </div>
            )}
         </div>
         
         {/* Points Table */}
         {points.length > 0 && (
            <div className="overflow-x-auto border border-slate-700 rounded-lg">
               <table className="w-full text-sm text-left">
                  <thead className="bg-slate-800 text-slate-300 uppercase text-xs">
                     <tr>
                        <th className="px-4 py-3 w-16">№</th>
                        <th className="px-4 py-3">T min (мм)</th>
                        <th className="px-4 py-3">T факт (мм)</th>
                        <th className="px-4 py-3">Примечание</th>
                        <th className="px-4 py-3 w-10"></th>
                     </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-700 bg-slate-900/30">
                     {points.map(p => {
                         const isCritical = p.value && p.min && parseFloat(p.value) < parseFloat(p.min);
                         return (
                           <tr key={p.id} className={isCritical ? 'bg-red-900/20' : ''}>
                              <td className="px-4 py-2 font-bold text-center">{p.id}</td>
                              <td className="px-4 py-2">
                                 <input 
                                    type="number" 
                                    className="bg-slate-800 border border-slate-600 rounded px-2 py-1 w-24 text-white focus:border-accent outline-none" 
                                    placeholder="0.0"
                                    value={p.min}
                                    onChange={(e) => updatePoint(p.id, 'min', e.target.value)}
                                 />
                              </td>
                              <td className="px-4 py-2">
                                 <input 
                                    type="number" 
                                    className={`bg-slate-800 border rounded px-2 py-1 w-24 text-white focus:border-accent outline-none ${isCritical ? 'border-red-500 text-red-200' : 'border-slate-600'}`} 
                                    placeholder="0.0"
                                    value={p.value}
                                    onChange={(e) => updatePoint(p.id, 'value', e.target.value)}
                                 />
                              </td>
                              <td className="px-4 py-2">
                                 <input 
                                    type="text" 
                                    className="bg-slate-800 border border-slate-600 rounded px-2 py-1 w-full text-white focus:border-accent outline-none"
                                    placeholder="..." 
                                    value={p.comment}
                                    onChange={(e) => updatePoint(p.id, 'comment', e.target.value)}
                                 />
                              </td>
                              <td className="px-4 py-2 text-center">
                                 <button onClick={() => setPoints(points.filter(pt => pt.id !== p.id))} className="text-slate-500 hover:text-red-400">
                                    <X size={16} />
                                 </button>
                              </td>
                           </tr>
                        );
                     })}
                  </tbody>
               </table>
            </div>
         )}
      </div>
   );
};

// --- FORM RENDERER ---

interface FormFieldRendererProps {
  field: FormField;
}

const FormFieldRenderer: React.FC<FormFieldRendererProps> = ({ field }) => {
  return (
    <div className="mb-6">
      <label className="block text-sm font-medium text-slate-300 mb-2">
        {field.label} {field.required && <span className="text-danger">*</span>}
      </label>
      
      {field.type === 'text' && (
        <input type="text" className="w-full bg-slate-800 border border-slate-600 rounded px-3 py-2 text-white focus:ring-2 focus:ring-accent outline-none" placeholder="..." />
      )}
      
      {field.type === 'select' && (
        <select className="w-full bg-slate-800 border border-slate-600 rounded px-3 py-2 text-white focus:ring-2 focus:ring-accent outline-none">
          {field.options?.map(opt => <option key={opt}>{opt}</option>)}
        </select>
      )}

      {field.type === 'number' && (
        <div className="relative">
           <input type="number" className="w-full bg-slate-800 border border-slate-600 rounded px-3 py-2 text-white focus:ring-2 focus:ring-accent outline-none pr-10" placeholder="0.00" />
           {field.unit && <span className="absolute right-3 top-2 text-slate-500 text-sm">{field.unit}</span>}
        </div>
      )}
      
      {field.type === 'boolean' && (
         <div className="flex gap-4">
            <label className="flex items-center gap-2 cursor-pointer">
               <input type="radio" name={field.id} className="w-4 h-4 text-accent" /> <span className="text-white">Да</span>
            </label>
            <label className="flex items-center gap-2 cursor-pointer">
               <input type="radio" name={field.id} className="w-4 h-4 text-accent" /> <span className="text-white">Нет</span>
            </label>
         </div>
      )}

      {field.type === 'photo' && (
        <div className="border-2 border-dashed border-slate-600 rounded-lg p-6 flex flex-col items-center justify-center cursor-pointer hover:bg-slate-800 transition">
           <Camera className="text-slate-400 mb-2" />
           <p className="text-xs text-slate-400">Нажмите для загрузки фото</p>
           <button className="mt-2 text-xs text-accent flex items-center gap-1">
             <PenTool size={12}/> Gemini Vision Analysis
           </button>
        </div>
      )}

      {field.type === 'drawing_thickness' && (
         <ThicknessMeasurementWidget />
      )}
    </div>
  );
};

// --- TREE VIEW ---

const StatusIndicator = ({ status }: { status?: string }) => {
   if (!status) return null;
   const colors = {
     'OK': 'bg-success',
     'WARNING': 'bg-warning',
     'CRITICAL': 'bg-danger'
   };
   // @ts-ignore
   return <div className={`w-2.5 h-2.5 border border-slate-900 rounded-full ${colors[status] || 'bg-slate-500'}`} />;
};

const NodeIcon = ({ type, isOpen }: { type: NodeType, isOpen: boolean }) => {
  switch (type) {
    case NodeType.ROOT: return <Network size={16} className="text-blue-400" />;
    case NodeType.COMPANY: return <Building2 size={16} className="text-indigo-400" />;
    case NodeType.BRANCH: return <Network size={16} className="text-violet-400" />;
    case NodeType.DEPARTMENT: return <Factory size={16} className="text-slate-400" />;
    case NodeType.DIVISION: return <Box size={16} className="text-slate-400" />;
    case NodeType.GROUP: return isOpen ? <FolderOpen size={16} className="text-yellow-500" /> : <Folder size={16} className="text-yellow-500" />;
    case NodeType.EQUIPMENT: return <Tag size={16} className="text-green-400" />;
    default: return <FileText size={16} />;
  }
};

interface TreeNodeProps {
  node: HierarchyNode;
  level: number;
  expandedNodes: Set<string>;
  toggleNode: (id: string) => void;
  selectedNodeId: string | null;
  onSelect: (node: HierarchyNode) => void;
}

const TreeNodeItem: React.FC<TreeNodeProps> = ({ node, level, expandedNodes, toggleNode, selectedNodeId, onSelect }) => {
  const hasChildren = node.children && node.children.length > 0;
  const isExpanded = expandedNodes.has(node.id);
  const isSelected = selectedNodeId === node.id;

  const handleExpand = (e: React.MouseEvent) => {
    e.stopPropagation();
    toggleNode(node.id);
  };

  const handleClick = () => {
     onSelect(node);
     if (hasChildren && !isExpanded) {
        toggleNode(node.id);
     }
  };

  return (
    <div className="min-w-max">
      <div 
        className={`
           flex items-center gap-2 py-1.5 px-2 cursor-pointer transition-colors select-none text-sm
           ${isSelected ? 'bg-accent/20 text-white border-r-2 border-accent' : 'text-slate-400 hover:text-white hover:bg-slate-800'}
        `}
        style={{ paddingLeft: `${level * 16 + 8}px` }}
        onClick={handleClick}
      >
         <div onClick={hasChildren ? handleExpand : undefined} className={`p-0.5 rounded hover:bg-white/10 ${hasChildren ? 'visible' : 'invisible'}`}>
            {isExpanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
         </div>
         <NodeIcon type={node.type} isOpen={isExpanded} />
         <span className="truncate flex-1">{node.name}</span>
         <StatusIndicator status={node.status} />
      </div>

      {isExpanded && hasChildren && node.children!.map(child => (
        <TreeNodeItem 
          key={child.id} 
          node={child} 
          level={level + 1} 
          expandedNodes={expandedNodes}
          toggleNode={toggleNode}
          selectedNodeId={selectedNodeId}
          onSelect={onSelect}
        />
      ))}
    </div>
  );
};

// --- EQUIPMENT TABS ---

interface PassportTabProps {
   node: HierarchyNode;
   onUpdate: (updatedAttributes: EquipmentAttributes, changeLog: MaintenanceEvent) => void;
}

const PassportTab: React.FC<PassportTabProps> = ({ node, onUpdate }) => {
  const [isEditing, setIsEditing] = useState(false);
  const [formData, setFormData] = useState<EquipmentAttributes>(node.attributes || {});

  const handleSave = () => {
     // Compare and generate log
     const changes: string[] = [];
     const oldAttrs = node.attributes || {};
     
     (Object.keys(formData) as Array<keyof EquipmentAttributes>).forEach(key => {
        if (formData[key] != oldAttrs[key]) {
           changes.push(`${key}: ${oldAttrs[key] || '-'} -> ${formData[key]}`);
        }
     });

     if (changes.length > 0) {
        const logEvent: MaintenanceEvent = {
           id: `evt-${Date.now()}`,
           date: new Date().toISOString().split('T')[0],
           type: 'ATTRIBUTE_CHANGE',
           title: 'Изменение паспортных данных',
           description: `Изменены поля: ${changes.join(', ')}`,
           performer: 'Иванов И.И. (Администратор)'
        };
        onUpdate(formData, logEvent);
     }
     
     setIsEditing(false);
  };

  const renderField = (key: keyof EquipmentAttributes, label: string, unit?: string) => {
     if (isEditing) {
        return (
           <div className="flex justify-between items-center py-2 border-b border-slate-700/50">
              <span className="text-slate-400 text-sm">{label}</span>
              <input 
                  type="text" 
                  value={formData[key] || ''} 
                  onChange={(e) => setFormData({...formData, [key]: e.target.value})}
                  className="bg-slate-900 border border-slate-600 rounded px-2 py-1 text-sm text-white w-1/2 text-right focus:border-accent outline-none"
              />
           </div>
        )
     }
     return (
       <div className="flex justify-between py-2 border-b border-slate-700/50 last:border-0 hover:bg-slate-800/30 px-2 rounded">
         <span className="text-slate-400 text-sm">{label}</span>
         <span className="text-white font-medium text-sm text-right">{formData[key]} <span className="text-slate-500 text-xs">{unit}</span></span>
       </div>
     );
  };

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 animate-in fade-in duration-300 relative">
      <div className="absolute top-0 right-0 z-10">
         {isEditing ? (
            <div className="flex gap-2">
               <button onClick={() => setIsEditing(false)} className="bg-slate-700 text-white px-3 py-1.5 rounded text-sm hover:bg-slate-600">Отмена</button>
               <button onClick={handleSave} className="bg-green-600 text-white px-3 py-1.5 rounded text-sm hover:bg-green-500 flex items-center gap-2"><Save size={14}/> Сохранить</button>
            </div>
         ) : (
            <button onClick={() => setIsEditing(true)} className="bg-slate-700 text-accent px-3 py-1.5 rounded text-sm hover:bg-slate-600 flex items-center gap-2 border border-slate-600">
               <Edit2 size={14}/> Редактировать
            </button>
         )}
      </div>

      <div className="bg-slate-800/50 rounded-xl p-5 border border-slate-700">
         <h4 className="text-white font-bold mb-4 flex items-center gap-2"><Info size={18} className="text-accent"/> Основные сведения</h4>
         <div className="space-y-1">
            {renderField('serialNumber', 'Заводской номер')}
            {renderField('regNumber', 'Рег. номер (Ростехнадзор)')}
            {renderField('manufacturer', 'Изготовитель')}
            {renderField('manufactureYear', 'Год выпуска')}
            {renderField('commissioningDate', 'Дата ввода в эксплуатацию')}
            {renderField('designLife', 'Расчетный срок службы', 'лет')}
         </div>
      </div>

      <div className="bg-slate-800/50 rounded-xl p-5 border border-slate-700">
         <h4 className="text-white font-bold mb-4 flex items-center gap-2"><Calculator size={18} className="text-accent"/> Технические параметры</h4>
         <div className="space-y-1">
            {renderField('volume', 'Объем', 'м³')}
            {renderField('pressureDesign', 'Расчетное давление', 'МПа')}
            {renderField('pressureWork', 'Рабочее давление', 'МПа')}
            {renderField('tempDesign', 'Расчетная температура', '°C')}
            {renderField('tempWork', 'Рабочая температура', '°C')}
            {renderField('medium', 'Рабочая среда')}
            {renderField('material', 'Марка стали')}
         </div>
      </div>
    </div>
  );
};

const HistoryTab = ({ events, onAddEvent }: { events?: MaintenanceEvent[], onAddEvent: (evt: MaintenanceEvent) => void }) => {
   const [showAddForm, setShowAddForm] = useState(false);
   const [newEvent, setNewEvent] = useState<Partial<MaintenanceEvent>>({ type: 'MAINTENANCE' });

   const handleAdd = () => {
      if (newEvent.title && newEvent.description) {
         onAddEvent({
            id: `manual-${Date.now()}`,
            date: newEvent.date || new Date().toISOString().split('T')[0],
            type: newEvent.type as any,
            title: newEvent.title,
            description: newEvent.description,
            performer: newEvent.performer || 'Иванов И.И.',
            documentRef: newEvent.documentRef
         });
         setShowAddForm(false);
         setNewEvent({ type: 'MAINTENANCE' });
      }
   };

  return (
    <div className="space-y-6 pl-4 py-4 animate-in fade-in duration-300">
       <div className="flex justify-end">
          <button onClick={() => setShowAddForm(true)} className="bg-accent/10 text-accent border border-accent/20 px-4 py-2 rounded-lg text-sm font-bold flex items-center gap-2 hover:bg-accent/20">
             <Plus size={16}/> Добавить запись
          </button>
       </div>

       {showAddForm && (
          <div className="bg-slate-800 p-4 rounded-xl border border-slate-600 shadow-xl mb-6">
             <h4 className="text-white font-bold mb-4">Новая запись в журнале</h4>
             <div className="grid grid-cols-2 gap-4 mb-4">
                <div>
                   <label className="text-xs text-slate-400 block mb-1">Дата</label>
                   <input type="date" className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white" 
                     value={newEvent.date} onChange={e => setNewEvent({...newEvent, date: e.target.value})}
                   />
                </div>
                <div>
                   <label className="text-xs text-slate-400 block mb-1">Тип работ</label>
                   <select className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white"
                     value={newEvent.type} onChange={e => setNewEvent({...newEvent, type: e.target.value as any})}
                   >
                      <option value="MAINTENANCE">ТО и Ремонт</option>
                      <option value="INSPECTION">Диагностика</option>
                      <option value="INCIDENT">Инцидент</option>
                   </select>
                </div>
                <div className="col-span-2">
                   <label className="text-xs text-slate-400 block mb-1">Заголовок</label>
                   <input type="text" className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white" placeholder="Например: Замена манометра"
                      value={newEvent.title} onChange={e => setNewEvent({...newEvent, title: e.target.value})}
                   />
                </div>
                <div className="col-span-2">
                   <label className="text-xs text-slate-400 block mb-1">Описание</label>
                   <textarea className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-white h-20" placeholder="Подробное описание..."
                      value={newEvent.description} onChange={e => setNewEvent({...newEvent, description: e.target.value})}
                   />
                </div>
             </div>
             <div className="flex justify-end gap-2">
                <button onClick={() => setShowAddForm(false)} className="text-slate-400 px-4 py-2 text-sm hover:text-white">Отмена</button>
                <button onClick={handleAdd} className="bg-success text-white px-4 py-2 rounded text-sm font-bold hover:bg-green-600">Сохранить запись</button>
             </div>
          </div>
       )}

       {(!events || events.length === 0) ? <div className="text-center text-slate-500 py-10">История эксплуатации пуста</div> :
       events.map((event, idx) => (
         <div key={event.id} className="relative pl-8 border-l border-slate-700 last:border-0">
            {/* Dot */}
            <div className={`absolute -left-2 top-0 w-4 h-4 rounded-full border-2 border-slate-900 ${
               event.type === 'INCIDENT' ? 'bg-danger' : 
               event.type === 'INSPECTION' ? 'bg-accent' : 
               event.type === 'ATTRIBUTE_CHANGE' ? 'bg-indigo-500' :
               'bg-success'
            }`}></div>
            
            <div className="bg-slate-800/50 p-4 rounded-lg border border-slate-700 hover:border-slate-600 transition -mt-1">
               <div className="flex justify-between items-start mb-2">
                  <div>
                    <span className={`text-xs font-bold px-2 py-0.5 rounded mr-2 ${
                       event.type === 'INCIDENT' ? 'bg-danger/20 text-danger' : 
                       event.type === 'INSPECTION' ? 'bg-accent/20 text-accent' : 
                       event.type === 'ATTRIBUTE_CHANGE' ? 'bg-indigo-500/20 text-indigo-300' :
                       'bg-success/20 text-success'
                    }`}>
                      {event.type === 'INSPECTION' ? 'Диагностика' : event.type === 'MAINTENANCE' ? 'ТО и Ремонт' : event.type === 'ATTRIBUTE_CHANGE' ? 'Изменение паспорта' : 'Инцидент'}
                    </span>
                    <span className="text-sm font-bold text-white">{event.title}</span>
                  </div>
                  <span className="text-xs text-slate-400 font-mono">{event.date}</span>
               </div>
               <p className="text-slate-300 text-sm mb-2 whitespace-pre-line">{event.description}</p>
               <div className="flex justify-between items-center pt-2 border-t border-slate-700/50">
                  <span className="text-xs text-slate-500 flex items-center gap-1"><User size={12}/> {event.performer}</span>
                  {event.documentRef && (
                     <span className="text-xs text-accent cursor-pointer hover:underline flex items-center gap-1">
                        <FileText size={12}/> {event.documentRef}
                     </span>
                  )}
               </div>
            </div>
         </div>
       ))}
    </div>
  );
};

const DocsTab = ({ docs }: { docs?: AttachedDocument[] }) => {
   if (!docs || docs.length === 0) return <div className="text-center text-slate-500 py-10">Нет прикрепленных документов</div>;
   
   // Group docs by category excluding EPB Reports (they have their own tab)
   const categories = [
     { id: DocCategory.PASSPORT, label: 'Паспорта и формуляры' },
     { id: DocCategory.DRAWING, label: 'Чертежи и схемы' },
     { id: DocCategory.PROTOCOL, label: 'Акты и протоколы' },
     { id: DocCategory.CERTIFICATE, label: 'Сертификаты' },
   ];

   const relevantDocs = docs.filter(d => d.category !== DocCategory.EPB_REPORT);

   return (
     <div className="space-y-8 animate-in fade-in duration-300">
        {categories.map(cat => {
           const catDocs = relevantDocs.filter(d => d.category === cat.id);
           if (catDocs.length === 0) return null;

           return (
             <div key={cat.id}>
                <h4 className="text-sm font-bold text-slate-400 uppercase tracking-wider mb-3 border-b border-slate-700 pb-1">{cat.label}</h4>
                <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
                   {catDocs.map(doc => (
                      <div key={doc.id} className="p-4 bg-slate-800 border border-slate-700 rounded-lg hover:border-slate-500 transition group relative">
                         <div className="flex items-start justify-between mb-3">
                            <div className="flex items-center gap-3">
                               <div className="p-2 bg-slate-700 rounded text-slate-300">
                                  <FileText size={20} />
                               </div>
                               <div>
                                  <p className="font-medium text-white line-clamp-1 text-sm">{doc.name}</p>
                                  <p className="text-xs text-slate-500">{doc.size} • {doc.extension.toUpperCase()}</p>
                               </div>
                            </div>
                         </div>
                         
                         <div className="mt-2 pt-2 border-t border-slate-700/50 flex justify-between items-center">
                            <div className="flex items-center gap-1.5 text-xs text-slate-400" title={doc.uploadedBy.role}>
                               <div className="w-5 h-5 rounded-full bg-slate-600 flex items-center justify-center text-[10px] text-white">
                                 {doc.uploadedBy.avatar}
                               </div>
                               <span>{doc.uploadedBy.name}</span>
                            </div>
                            <span className="text-xs text-slate-500">{doc.uploadDate}</span>
                         </div>
                      </div>
                   ))}
                </div>
             </div>
           )
        })}
        
        <div className="border-2 border-dashed border-slate-700 rounded-lg flex flex-col items-center justify-center text-slate-500 hover:text-white hover:border-slate-500 transition cursor-pointer h-32 mt-4">
           <Download size={24} className="mb-2" />
           <p className="text-sm">Загрузить новый документ</p>
        </div>
     </div>
   );
};

// --- EXPERTISE REPORT GENERATOR (EPB) ---

const ExpertiseTab = ({ node }: { node: HierarchyNode }) => {
   const [isGenerating, setIsGenerating] = useState(false);
   const [reportPreview, setReportPreview] = useState<boolean>(false);
   
   const epbDocs = node.documents?.filter(d => d.category === DocCategory.EPB_REPORT) || [];
   const attrs = node.attributes || {};

   const generateReport = () => {
      setIsGenerating(true);
      setTimeout(() => {
         setIsGenerating(false);
         setReportPreview(true);
      }, 1500);
   };

   if (reportPreview) {
      return (
         <div className="animate-in fade-in zoom-in-95 duration-300 h-full flex flex-col">
            <div className="flex items-center justify-between mb-4 pb-4 border-b border-slate-700">
               <h3 className="text-lg font-bold text-white flex items-center gap-2">
                  <FileText className="text-accent" /> Предварительный просмотр заключения ЭПБ
               </h3>
               <div className="flex gap-2">
                  <button onClick={() => setReportPreview(false)} className="px-3 py-1.5 text-sm text-slate-400 hover:text-white">Закрыть</button>
                  <button className="px-3 py-1.5 bg-accent hover:bg-blue-600 text-white rounded text-sm flex items-center gap-2">
                     <Printer size={16} /> Печать / PDF
                  </button>
               </div>
            </div>
            
            <div className="flex-1 bg-white text-black p-8 rounded shadow-xl overflow-y-auto font-serif leading-relaxed max-w-4xl mx-auto w-full">
               <div className="text-center mb-8">
                  <p className="uppercase font-bold text-sm">Федеральная служба по экологическому, технологическому и атомному надзору</p>
                  <h1 className="text-xl font-bold mt-4 mb-2">ЗАКЛЮЧЕНИЕ ЭКСПЕРТИЗЫ ПРОМЫШЛЕННОЙ БЕЗОПАСНОСТИ</h1>
                  <p className="text-sm">№ 00-00-00000-2025</p>
               </div>
               
               <p className="font-bold mb-2">1. Вводная часть</p>
               <p className="mb-4 text-sm">
                  Экспертиза проведена на основании договора № 123/25 от 10.01.2025. 
                  Объект экспертизы: {node.name}, регистрационный номер {attrs.regNumber}.
                  Владелец: ООО "Газпром переработка".
               </p>

               <p className="font-bold mb-2">2. Характеристика объекта</p>
               <table className="w-full text-sm border-collapse border border-black mb-4">
                  <tbody>
                     <tr><td className="border border-black p-1">Наименование</td><td className="border border-black p-1">{node.name}</td></tr>
                     <tr><td className="border border-black p-1">Заводской номер</td><td className="border border-black p-1">{attrs.serialNumber}</td></tr>
                     <tr><td className="border border-black p-1">Год изготовления</td><td className="border border-black p-1">{attrs.manufactureYear} г.</td></tr>
                     <tr><td className="border border-black p-1">Рабочее давление</td><td className="border border-black p-1">{attrs.pressureWork} МПа</td></tr>
                     <tr><td className="border border-black p-1">Материал</td><td className="border border-black p-1">{attrs.material}</td></tr>
                  </tbody>
               </table>

               <p className="font-bold mb-2">3. Результаты диагностирования</p>
               <p className="mb-4 text-sm">
                  Проведен визуально-измерительный контроль, ультразвуковая толщинометрия и контроль твердости. 
                  Толщина стенки находится в пределах допусков (минимум {attrs.wallThickness ? attrs.wallThickness * 0.9 : 'N/A'} мм).
                  Дефектов, препятствующих дальнейшей эксплуатации, не выявлено.
                  Расчетная скорость коррозии не превышает 0.1 мм/год.
               </p>

               <p className="font-bold mb-2">4. Выводы</p>
               <p className="mb-8 text-sm">
                  Объект экспертизы <strong>СООТВЕТСТВУЕТ</strong> требованиям промышленной безопасности.
                  Срок дальнейшей безопасной эксплуатации установлен на <strong>5 лет</strong> (до 2030 года).
               </p>
               
               <div className="flex justify-between mt-10 pt-4 border-t border-black">
                  <div>Эксперт (удостоверение ЭП-001)</div>
                  <div>____________ / Смирнов А.А. /</div>
               </div>
            </div>
         </div>
      );
   }

   return (
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 h-full animate-in fade-in duration-300">
         {/* List of existing reports */}
         <div className="lg:col-span-2">
            <div className="flex justify-between items-center mb-4">
               <h3 className="text-white font-bold">Реестр заключений ЭПБ</h3>
            </div>
            
            {epbDocs.length > 0 ? (
               <div className="space-y-3">
                  {epbDocs.map(doc => (
                     <div key={doc.id} className="bg-slate-800 p-4 rounded-lg border border-slate-700 flex items-center justify-between group">
                        <div className="flex items-center gap-4">
                           <div className="p-2 bg-green-500/10 text-green-500 rounded"><ShieldCheck size={24}/></div>
                           <div>
                              <p className="text-white font-medium">{doc.name}</p>
                              <p className="text-xs text-slate-400">Внесен в реестр РТН: {doc.uploadDate}</p>
                           </div>
                        </div>
                        <button className="px-3 py-1.5 bg-slate-700 text-slate-300 text-sm rounded hover:bg-slate-600">Открыть</button>
                     </div>
                  ))}
               </div>
            ) : (
               <div className="bg-slate-800/50 p-8 rounded-lg border border-slate-700 text-center text-slate-500">
                  <ShieldCheck size={48} className="mx-auto mb-3 opacity-20" />
                  <p>Действующих заключений не найдено</p>
               </div>
            )}
            
            <div className="mt-8">
               <h3 className="text-white font-bold mb-4">Требования ФНиП</h3>
               <div className="bg-slate-800/30 p-4 rounded text-sm text-slate-400 border border-slate-700">
                  <p className="mb-2">Согласно Приказу Ростехнадзора № 420, экспертиза проводится в случаях:</p>
                  <ul className="list-disc pl-5 space-y-1">
                     <li>Истечения срока службы (20 лет)</li>
                     <li>Отсутствия технической документации</li>
                     <li>После аварий или восстановительного ремонта</li>
                  </ul>
               </div>
            </div>
         </div>

         {/* Generator Action Panel */}
         <div className="bg-secondary p-6 rounded-xl border border-slate-700 h-fit">
            <h3 className="text-lg font-bold text-white mb-2">Генератор Заключения</h3>
            <p className="text-sm text-slate-400 mb-6">Автоматическое формирование проекта заключения на основе данных паспорта и последней диагностики.</p>
            
            <div className="space-y-4 mb-6">
               <div className="flex items-center gap-2 text-sm text-slate-300">
                  <Check size={16} className="text-green-500" /> Паспортные данные валидны
               </div>
               <div className="flex items-center gap-2 text-sm text-slate-300">
                  <Check size={16} className="text-green-500" /> Диагностика проведена
               </div>
               <div className="flex items-center gap-2 text-sm text-slate-300">
                  <Check size={16} className="text-green-500" /> Дефекты устранены
               </div>
            </div>

            <button 
               onClick={generateReport}
               disabled={isGenerating}
               className="w-full py-3 bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-500 hover:to-indigo-500 text-white font-bold rounded-lg shadow-lg flex items-center justify-center gap-2 transition-all disabled:opacity-50"
            >
               {isGenerating ? (
                  <>Генерация...</>
               ) : (
                  <><PenTool size={18} /> Сформировать проект</>
               )}
            </button>
         </div>
      </div>
   );
};

// --- MAIN INSPECTION LOGIC (Existing Form) ---

const InspectionForm = ({ schema }: { schema: ModuleSchema }) => {
  const [activeSection, setActiveSection] = useState(0);

  return (
    <div className="flex gap-6 h-full min-h-0 animate-in fade-in duration-300">
      <div className="w-64 hidden xl:block overflow-y-auto pr-2 shrink-0">
        <div className="bg-slate-900/50 rounded-xl p-4 border border-slate-700">
            <nav className="space-y-1">
              {schema.sections.map((section, idx) => (
                  <button 
                    key={idx}
                    onClick={() => setActiveSection(idx)}
                    className={`w-full text-left px-3 py-2 rounded-lg text-xs font-medium transition-colors flex items-center gap-3 ${activeSection === idx ? 'bg-accent/10 text-accent' : 'text-slate-400 hover:text-white hover:bg-slate-800'}`}
                  >
                    <div className={`w-5 h-5 rounded-full flex items-center justify-center text-[10px] border shrink-0 ${activeSection === idx ? 'border-accent bg-accent text-white' : 'border-slate-600'}`}>
                      {activeSection > idx ? <Check size={10}/> : idx + 1}
                    </div>
                    <span className="line-clamp-2">{section.title}</span>
                  </button>
              ))}
            </nav>
        </div>
      </div>

      <div className="flex-1 bg-slate-800/30 rounded-xl border border-slate-700 p-6 overflow-y-auto">
          <h3 className="text-lg font-bold text-white mb-6 pb-2 border-b border-slate-700 sticky top-0 bg-[#151e32] z-10">
            {schema.sections[activeSection].title}
          </h3>
          
          <div className="space-y-6">
              {schema.sections[activeSection].fields.map(field => (
                <FormFieldRenderer key={field.id} field={field} />
              ))}
          </div>

          <div className="mt-8 pt-6 border-t border-slate-700 flex justify-between">
              <button 
                disabled={activeSection === 0}
                onClick={() => setActiveSection(p => p - 1)}
                className="px-4 py-2 text-slate-400 hover:text-white disabled:opacity-50 text-sm"
              >
                Назад
              </button>
              <button 
                onClick={() => setActiveSection(p => Math.min(schema.sections.length - 1, p + 1))}
                className="px-6 py-2 bg-white text-slate-900 font-bold rounded hover:bg-slate-200 transition text-sm"
              >
                {activeSection === schema.sections.length - 1 ? 'Подписать ЭЦП' : 'Далее'}
              </button>
          </div>
      </div>
    </div>
  );
}

// --- MAIN PAGE LAYOUT ---

const DynamicInspection = () => {
  const [selectedNode, setSelectedNode] = useState<HierarchyNode | null>(null);
  const [expandedNodes, setExpandedNodes] = useState<Set<string>>(new Set(['root', 'cmp-1']));
  const [activeTab, setActiveTab] = useState<'INFO' | 'HISTORY' | 'DOCS' | 'EXPERT' | 'INSPECTION'>('INFO');

  const toggleNode = (id: string) => {
    const newSet = new Set(expandedNodes);
    if (newSet.has(id)) newSet.delete(id); else newSet.add(id);
    setExpandedNodes(newSet);
  };

  const handleSelectNode = (node: HierarchyNode) => {
    setSelectedNode(node);
    // Reset tab to info when changing equipment
    if (node.type === NodeType.EQUIPMENT) {
      setActiveTab('INFO');
    }
  };
  
  // Handler for Passport updates
  const handleAttributesUpdate = (newAttrs: EquipmentAttributes, log: MaintenanceEvent) => {
     if (selectedNode) {
        // Deep clone logic would go here in a real app (Immer/Redux)
        const updatedNode = {
           ...selectedNode,
           attributes: newAttrs,
           history: [log, ...(selectedNode.history || [])]
        };
        setSelectedNode(updatedNode);
     }
  };

  // Handler for Manual History Add
  const handleAddHistoryEvent = (evt: MaintenanceEvent) => {
     if (selectedNode) {
        const updatedNode = {
           ...selectedNode,
           history: [evt, ...(selectedNode.history || [])]
        };
        setSelectedNode(updatedNode);
     }
  };

  const renderContent = () => {
     if (!selectedNode) {
        return (
           <div className="h-full flex flex-col items-center justify-center text-slate-500">
              <Network size={64} className="mb-4 opacity-20" />
              <p>Выберите объект или оборудование в дереве навигации</p>
           </div>
        );
     }

     if (selectedNode.type !== NodeType.EQUIPMENT) {
        // Folder View
        return (
           <div className="p-8">
              <div className="flex items-center gap-3 mb-6">
                 <div className="p-3 bg-slate-800 rounded-lg">
                    <NodeIcon type={selectedNode.type} isOpen={true} />
                 </div>
                 <div>
                    <h2 className="text-2xl font-bold text-white">{selectedNode.name}</h2>
                    <p className="text-sm text-slate-400">Уровень иерархии: {selectedNode.type}</p>
                 </div>
              </div>
               {selectedNode.children && selectedNode.children.length > 0 ? (
                 <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                    {selectedNode.children.map(child => (
                       <div 
                         key={child.id} 
                         onClick={() => { setSelectedNode(child); toggleNode(selectedNode.id); }}
                         className="p-4 bg-secondary border border-slate-700 rounded-lg hover:border-slate-500 cursor-pointer transition group"
                       >
                          <div className="flex justify-between items-start mb-2">
                             <NodeIcon type={child.type} isOpen={false} />
                             <StatusIndicator status={child.status} />
                          </div>
                          <p className="font-medium text-white group-hover:text-accent transition">{child.name}</p>
                       </div>
                    ))}
                 </div>
              ) : ( <p className="text-slate-500 italic">Нет объектов</p> )}
           </div>
        );
     }

     // --- EQUIPMENT DIGITAL TWIN VIEW ---
     
     const today = new Date();
     const nextDate = selectedNode.nextInspectionDate ? new Date(selectedNode.nextInspectionDate) : null;
     const daysLeft = nextDate ? Math.ceil((nextDate.getTime() - today.getTime()) / (1000 * 60 * 60 * 24)) : null;
     
     const isOverdue = daysLeft !== null && daysLeft < 0;
     const isUrgent = daysLeft !== null && daysLeft < 30;

     return (
        <div className="h-full flex flex-col">
           {/* Equipment Header */}
           <div className="bg-secondary border-b border-slate-700 px-6 py-4 shrink-0">
              <div className="flex justify-between items-start mb-4">
                 <div>
                    <div className="flex items-center gap-2 text-xs text-slate-400 mb-1 uppercase tracking-wider">
                       <span>{selectedNode.equipmentType}</span>
                       <span>•</span>
                       <span className={selectedNode.status === 'OK' ? 'text-success' : selectedNode.status === 'WARNING' ? 'text-warning' : 'text-danger'}>
                          {selectedNode.status === 'OK' ? 'В работе' : 'Требует внимания'}
                       </span>
                    </div>
                    <h2 className="text-2xl font-bold text-white leading-tight">{selectedNode.name}</h2>
                 </div>
                 
                 {/* Next Inspection Alert */}
                 {selectedNode.nextInspectionDate && (
                    <div className={`px-4 py-2 rounded-lg border flex items-center gap-3 ${isOverdue ? 'bg-danger/10 border-danger/30' : isUrgent ? 'bg-warning/10 border-warning/30' : 'bg-slate-800 border-slate-700'}`}>
                       <Calendar size={20} className={isOverdue ? 'text-danger' : isUrgent ? 'text-warning' : 'text-slate-400'} />
                       <div className="text-right">
                          <p className="text-xs text-slate-400">Следующая диагностика</p>
                          <p className={`font-bold ${isOverdue ? 'text-danger' : 'text-white'}`}>
                             {selectedNode.nextInspectionDate} 
                             <span className="text-xs font-normal ml-1 opacity-70">
                                ({isOverdue ? `просрочено на ${Math.abs(daysLeft!)} дн.` : `через ${daysLeft} дн.`})
                             </span>
                          </p>
                       </div>
                    </div>
                 )}
              </div>

              {/* Tabs */}
              <div className="flex gap-1 overflow-x-auto">
                 {[
                   { id: 'INFO', label: 'Паспорт', icon: Info },
                   { id: 'HISTORY', label: 'Журнал', icon: History },
                   { id: 'DOCS', label: 'Документы', icon: FileBadge },
                   { id: 'EXPERT', label: 'Экспертиза (ЭПБ)', icon: ShieldCheck },
                   { id: 'INSPECTION', label: 'Диагностика', icon: ClipboardList },
                 ].map(tab => (
                    <button
                      key={tab.id}
                      onClick={() => setActiveTab(tab.id as any)}
                      className={`flex items-center gap-2 px-4 py-2 rounded-t-lg text-sm font-medium transition-colors border-t border-x whitespace-nowrap ${
                         activeTab === tab.id 
                         ? 'bg-primary border-slate-700 text-white translate-y-[1px] border-b-primary z-10' 
                         : 'bg-transparent border-transparent text-slate-400 hover:text-white hover:bg-slate-800/50'
                      }`}
                    >
                       <tab.icon size={16} /> {tab.label}
                    </button>
                 ))}
              </div>
           </div>

           {/* Tab Content */}
           <div className="flex-1 overflow-auto p-6 bg-primary relative">
              {activeTab === 'INFO' && <PassportTab node={selectedNode} onUpdate={handleAttributesUpdate} />}
              {activeTab === 'HISTORY' && <HistoryTab events={selectedNode.history} onAddEvent={handleAddHistoryEvent} />}
              {activeTab === 'DOCS' && <DocsTab docs={selectedNode.documents} />}
              {activeTab === 'EXPERT' && <ExpertiseTab node={selectedNode} />}
              {activeTab === 'INSPECTION' && <InspectionForm schema={VESSEL_SCHEMA} />}
           </div>
        </div>
     );
  };

  return (
    <div className="h-[calc(100vh-6rem)] flex -m-6">
      {/* Sidebar Tree */}
      <div className="w-80 bg-[#0b1120] border-r border-slate-800 flex flex-col shrink-0 pt-4">
         <div className="px-4 pb-4 border-b border-slate-800 bg-[#0b1120] sticky top-0 z-10">
            <h3 className="text-sm font-bold text-slate-300 uppercase tracking-wider mb-2">Навигатор объектов</h3>
            <div className="relative">
               <input 
                  type="text" 
                  placeholder="Поиск по шифру/имени..." 
                  className="w-full bg-slate-800 text-xs text-white px-3 py-2 rounded border border-slate-700 focus:border-accent outline-none pl-8"
               />
               <Search size={14} className="absolute left-2.5 top-2.5 text-slate-500" />
            </div>
         </div>
         <div className="flex-1 overflow-y-auto overflow-x-auto p-2 custom-scrollbar">
            <TreeNodeItem 
               node={HIERARCHY_TREE} 
               level={0} 
               expandedNodes={expandedNodes} 
               toggleNode={toggleNode}
               selectedNodeId={selectedNode ? selectedNode.id : null}
               onSelect={handleSelectNode}
            />
         </div>
      </div>

      {/* Main Content Area */}
      <div className="flex-1 min-w-0 bg-primary overflow-hidden relative">
         {renderContent()}
      </div>
    </div>
  );
};

export default DynamicInspection;
