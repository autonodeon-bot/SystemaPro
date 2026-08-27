import { useState, useEffect, useRef, useCallback } from 'react';
import { API_BASE } from '../constants';
import { Layers, Users, MapPin, RefreshCw, Wifi } from 'lucide-react';

declare const L: any;

type OnlineEmployee = {
  user_id: string;
  username: string;
  full_name: string;
  role?: string;
  latitude: number;
  longitude: number;
  accuracy?: number | null;
  updated_at?: string | null;
  device_label?: string | null;
  online?: boolean;
};

function formatAgo(iso?: string | null): string {
  if (!iso) return '';
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return '';
  const sec = Math.max(0, Math.round((Date.now() - t) / 1000));
  if (sec < 60) return `${sec} с назад`;
  const min = Math.round(sec / 60);
  if (min < 60) return `${min} мин назад`;
  const h = Math.round(min / 60);
  return `${h} ч назад`;
}

const PipelineMap = () => {
  const mapContainerRef = useRef<HTMLDivElement>(null);
  const mapInstanceRef = useRef<any>(null);
  const markersLayerRef = useRef<any>(null);
  const markerByIdRef = useRef<Record<string, any>>({});

  const [baseLayer, setBaseLayer] = useState<'OSM' | 'SATELLITE'>('OSM');
  const [employees, setEmployees] = useState<OnlineEmployee[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastFetch, setLastFetch] = useState<Date | null>(null);

  const fetchOnline = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const token = localStorage.getItem('token');
      const res = await fetch(`${API_BASE}/api/employee-locations/online`, {
        headers: token ? { Authorization: `Bearer ${token}` } : {},
      });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      const data = await res.json();
      const list = Array.isArray(data.employees) ? (data.employees as OnlineEmployee[]) : [];
      setEmployees(list);
      setLastFetch(new Date());
    } catch (e: any) {
      setError(e?.message || 'Не удалось загрузить сотрудников');
    } finally {
      setLoading(false);
    }
  }, []);

  // Init map
  useEffect(() => {
    if (!mapContainerRef.current || mapInstanceRef.current) return;

    const map = L.map(mapContainerRef.current, {
      center: [61.26, 73.41],
      zoom: 12,
      zoomControl: false,
      attributionControl: false,
    });
    L.control.zoom({ position: 'bottomright' }).addTo(map);
    mapInstanceRef.current = map;
    markersLayerRef.current = L.layerGroup().addTo(map);

    return () => {
      if (mapInstanceRef.current) {
        mapInstanceRef.current.remove();
        mapInstanceRef.current = null;
      }
    };
  }, []);

  // Base tiles
  useEffect(() => {
    const map = mapInstanceRef.current;
    if (!map) return;
    map.eachLayer((layer: any) => {
      if (layer._url) map.removeLayer(layer);
    });
    if (markersLayerRef.current) {
      markersLayerRef.current.addTo(map);
    }
    if (baseLayer === 'OSM') {
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19,
        opacity: 0.85,
      }).addTo(map);
    } else {
      L.tileLayer(
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        { maxZoom: 18 },
      ).addTo(map);
    }
  }, [baseLayer]);

  // Markers from employees
  useEffect(() => {
    const lg = markersLayerRef.current;
    const map = mapInstanceRef.current;
    if (!lg || !map) return;
    lg.clearLayers();
    markerByIdRef.current = {};

    employees.forEach((emp) => {
      const isSelected = emp.user_id === selectedId;
      const icon = L.divIcon({
        className: '',
        html: `<div style="
          background:${isSelected ? '#2563eb' : '#16a34a'};
          color:#fff;
          border:2px solid #fff;
          border-radius:9999px;
          width:36px;height:36px;
          display:flex;align-items:center;justify-content:center;
          font-size:12px;font-weight:700;
          box-shadow:0 2px 8px rgba(0,0,0,.35);
        ">${(emp.full_name || emp.username || '?').trim().charAt(0).toUpperCase()}</div>`,
        iconSize: [36, 36],
        iconAnchor: [18, 18],
      });
      const m = L.marker([emp.latitude, emp.longitude], { icon })
        .bindPopup(
          `<b>${emp.full_name || emp.username}</b><br/>${formatAgo(emp.updated_at)}`,
        )
        .on('click', () => setSelectedId(emp.user_id));
      m.addTo(lg);
      markerByIdRef.current[emp.user_id] = m;
    });

    if (employees.length > 0 && !selectedId) {
      const bounds = L.latLngBounds(employees.map((e) => [e.latitude, e.longitude]));
      if (bounds.isValid()) {
        map.fitBounds(bounds.pad(0.35), { maxZoom: 14 });
      }
    }
  }, [employees, selectedId]);

  // Poll every 30s
  useEffect(() => {
    fetchOnline();
    const id = setInterval(fetchOnline, 30000);
    return () => clearInterval(id);
  }, [fetchOnline]);

  const focusEmployee = (emp: OnlineEmployee) => {
    setSelectedId(emp.user_id);
    const map = mapInstanceRef.current;
    if (!map) return;
    map.flyTo([emp.latitude, emp.longitude], 15, { duration: 0.8 });
    const marker = markerByIdRef.current[emp.user_id];
    if (marker) {
      setTimeout(() => marker.openPopup(), 400);
    }
  };

  return (
    <div className="h-full flex flex-col md:flex-row gap-4 relative">
      <div className="flex-1 bg-app-deep rounded-xl overflow-hidden relative border border-app-line shadow-2xl min-h-[420px]">
        <div ref={mapContainerRef} className="w-full h-full z-0 bg-[#0f172a]" id="staff-map" />

        <div className="absolute top-4 left-4 z-[500] bg-secondary/95 backdrop-blur p-3 rounded-lg border border-app-line shadow-lg max-w-xs">
          <h4 className="text-xs font-bold text-app-text3 mb-1 flex items-center gap-1">
            <Wifi size={12} /> ТЕКУЩИЕ СОТРУДНИКИ
          </h4>
          <p className="text-sm text-app-text">
            Онлайн: <span className="font-bold text-green-400">{employees.length}</span>
          </p>
          <p className="text-[11px] text-app-text3 mt-1">
            Пинг с телефона раз в 5 мин. Окно онлайн — 15 мин.
            {lastFetch ? ` Обновлено ${lastFetch.toLocaleTimeString('ru-RU')}` : ''}
          </p>
        </div>

        <div className="absolute top-4 right-4 z-[500] bg-secondary/95 backdrop-blur p-2 rounded-lg border border-app-line shadow-lg">
          <h3 className="text-sm font-bold text-white mb-2 flex items-center gap-2 px-2">
            <Layers size={16} className="text-accent" /> Карта
          </h3>
          <div className="flex gap-1 mb-2 bg-app-panel p-1 rounded">
            <button
              type="button"
              onClick={() => setBaseLayer('OSM')}
              className={`flex-1 text-xs py-1 px-2 rounded ${
                baseLayer === 'OSM' ? 'bg-app-softer text-app-text' : 'text-app-text3 hover:text-app-text'
              }`}
            >
              Схема
            </button>
            <button
              type="button"
              onClick={() => setBaseLayer('SATELLITE')}
              className={`flex-1 text-xs py-1 px-2 rounded ${
                baseLayer === 'SATELLITE' ? 'bg-app-softer text-app-text' : 'text-app-text3 hover:text-app-text'
              }`}
            >
              Спутник
            </button>
          </div>
          <button
            type="button"
            onClick={() => fetchOnline()}
            disabled={loading}
            className="w-full text-xs px-3 py-1.5 rounded text-left flex items-center gap-2 text-app-text2 hover:bg-app-soft"
          >
            <RefreshCw size={12} className={loading ? 'animate-spin' : ''} />
            Обновить
          </button>
        </div>
      </div>

      <div className="w-full md:w-80 bg-secondary rounded-xl p-4 border border-app-line flex flex-col gap-3 max-h-[70vh] md:max-h-none overflow-hidden">
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-bold text-app-text flex items-center gap-2">
            <Users size={18} className="text-accent" />
            Онлайн
          </h3>
          <span className="text-xs text-app-text3">{employees.length}</span>
        </div>

        {error && (
          <div className="text-xs text-red-300 bg-red-950/40 border border-red-900/50 rounded p-2">{error}</div>
        )}

        <div className="flex-1 overflow-y-auto space-y-1 pr-1">
          {employees.length === 0 && !loading && (
            <div className="text-sm text-app-text3 py-8 text-center px-2">
              Нет сотрудников онлайн. Откройте мобильное приложение с доступом к геолокации и интернету —
              координаты уйдут в течение 5 минут.
            </div>
          )}
          {employees.map((emp) => {
            const selected = emp.user_id === selectedId;
            return (
              <button
                key={emp.user_id}
                type="button"
                onClick={() => focusEmployee(emp)}
                className={`w-full text-left p-3 rounded-lg border transition ${
                  selected
                    ? 'bg-blue-600/30 border-blue-500 text-white'
                    : 'bg-app-panel border-app-line hover:bg-app-soft text-app-text'
                }`}
              >
                <div className="flex items-start gap-2">
                  <div
                    className={`mt-0.5 w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold ${
                      selected ? 'bg-blue-500 text-white' : 'bg-green-700 text-white'
                    }`}
                  >
                    {(emp.full_name || emp.username || '?').trim().charAt(0).toUpperCase()}
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="font-semibold text-sm truncate">{emp.full_name || emp.username}</p>
                    <p className="text-[11px] text-app-text3 truncate">
                      @{emp.username}
                      {emp.role ? ` · ${emp.role}` : ''}
                    </p>
                    <p className="text-[11px] text-green-400/90 mt-0.5 flex items-center gap-1">
                      <MapPin size={10} />
                      {formatAgo(emp.updated_at) || 'сейчас'}
                      {emp.accuracy != null ? ` · ±${Math.round(emp.accuracy)} м` : ''}
                    </p>
                  </div>
                </div>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
};

export default PipelineMap;
