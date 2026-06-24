import React from 'react';
import { Package, Droplets, Wrench, Gauge } from 'lucide-react';

interface Props {
  displayName: string;
  defaultData: Record<string, unknown>;
  loading?: boolean;
  error?: string | null;
}

function countList(data: Record<string, unknown>, key: string): number {
  const v = data[key];
  return Array.isArray(v) ? v.length : 0;
}

const EquipmentProfilePassportPanel: React.FC<Props> = ({
  displayName,
  defaultData,
  loading,
  error,
}) => {
  if (loading) {
    return (
      <div className="mb-6 p-4 rounded-xl border border-app-line bg-app-deep/40 text-app-text3 text-sm">
        Загрузка профиля оборудования…
      </div>
    );
  }
  if (error) {
    return (
      <div className="mb-6 p-4 rounded-xl border border-danger/30 bg-danger/10 text-danger text-sm">
        {error}
      </div>
    );
  }

  const elements = countList(defaultData, 'vessel_elements');
  const uzt = countList(defaultData, 'thickness_measurements');
  const fittings = countList(defaultData, 'fittings_and_instruments');

  return (
    <div className="mb-6 p-4 rounded-xl border border-accent/30 bg-accent/5">
      <div className="flex flex-wrap items-center gap-2 mb-3">
        <Package size={18} className="text-accent" />
        <span className="font-semibold text-white">Профиль: {displayName}</span>
        {defaultData.scheme_index != null && (
          <span className="text-xs px-2 py-0.5 rounded bg-app-panel text-app-text2">
            {String(defaultData.scheme_index)}
          </span>
        )}
        {defaultData.inspection_type === 'EXPERTISE' && (
          <span className="text-xs px-2 py-0.5 rounded bg-indigo-900/50 text-indigo-200">
            ЭПБ
          </span>
        )}
      </div>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
        <div className="flex items-center gap-2 text-app-text2">
          <Wrench size={14} />
          <span>Б1 элементы: {elements}</span>
        </div>
        <div className="flex items-center gap-2 text-app-text2">
          <Droplets size={14} />
          <span>Гидроиспытания: {countList(defaultData, 'hydraulic_test_history')}</span>
        </div>
        <div className="flex items-center gap-2 text-app-text2">
          <Gauge size={14} />
          <span>Точки УЗТ: {uzt}</span>
        </div>
        <div className="flex items-center gap-2 text-app-text2">
          <Package size={14} />
          <span>Б6 арматура: {fittings}</span>
        </div>
      </div>
      {defaultData.purpose != null && (
        <p className="mt-3 text-xs text-app-text3 line-clamp-2">
          Назначение: {String(defaultData.purpose)}
        </p>
      )}
    </div>
  );
};

export default EquipmentProfilePassportPanel;
