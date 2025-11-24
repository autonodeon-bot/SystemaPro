
import React, { useState, useEffect, useRef } from 'react';
import { PIPELINES_DATA, MOCK_INSPECTORS, MOCK_CADASTRAL } from '../constants';
import { Layers, Zap, Info, Wind, Navigation, Users, Hexagon, Triangle, MapPin, Gauge, Globe, Map as MapIcon } from 'lucide-react';
import { WeatherState, Inspector } from '../types';

// Declare Leaflet global
declare const L: any;

const PipelineMap = () => {
  const mapContainerRef = useRef<HTMLDivElement>(null);
  const mapInstanceRef = useRef<any>(null);
  const layerGroupsRef = useRef<{
    pipelines: any;
    cadastral: any;
    inspectors: any;
    toxiRisk: any;
  }>({ pipelines: null, cadastral: null, inspectors: null, toxiRisk: null });
  
  const [activeLayers, setActiveLayers] = useState({
    PIPELINES: true,
    CADASTRAL: false,
    INSPECTORS: true,
    TOXI_RISK: false,
  });

  const [baseLayer, setBaseLayer] = useState<'OSM' | 'SATELLITE'>('OSM');
  
  const [selectedSegment, setSelectedSegment] = useState<string | null>(null);
  const [weather, setWeather] = useState<WeatherState>({ temp: -12, windSpeed: 5, windDeg: 45, condition: 'Снег' });
  const [inspectors, setInspectors] = useState<Inspector[]>(MOCK_INSPECTORS);
  const [scadaData, setScadaData] = useState({ pressure: 5.5, temp: 42 });

  // --- INITIALIZE MAP ---
  useEffect(() => {
    if (!mapContainerRef.current || mapInstanceRef.current) return;

    // 1. Init Leaflet
    const map = L.map(mapContainerRef.current, {
        center: [61.26, 73.41], // Surgut center
        zoom: 13,
        zoomControl: false,
        attributionControl: false
    });
    
    // Add Zoom Control at bottom right
    L.control.zoom({ position: 'bottomright' }).addTo(map);

    mapInstanceRef.current = map;

    // Initialize Layer Groups
    layerGroupsRef.current.pipelines = L.layerGroup().addTo(map);
    layerGroupsRef.current.cadastral = L.layerGroup().addTo(map);
    layerGroupsRef.current.inspectors = L.layerGroup().addTo(map);
    layerGroupsRef.current.toxiRisk = L.layerGroup().addTo(map);

    return () => {
        if(mapInstanceRef.current) {
            mapInstanceRef.current.remove();
            mapInstanceRef.current = null;
        }
    }
  }, []);

  // --- BASE LAYER SWITCHING ---
  useEffect(() => {
    const map = mapInstanceRef.current;
    if (!map) return;

    // Remove existing tiles
    map.eachLayer((layer: any) => {
        if (layer._url) map.removeLayer(layer);
    });

    if (baseLayer === 'OSM') {
        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
            maxZoom: 19,
            opacity: 0.6 // Darker mood
        }).addTo(map);
    } else {
        // Esri Satellite (Closest free alternative to Yandex Satellite without API key)
        L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
            maxZoom: 18,
        }).addTo(map);
    }
  }, [baseLayer]);

  // --- RENDER PIPELINES ---
  useEffect(() => {
    const lg = layerGroupsRef.current.pipelines;
    if (!lg) return;
    lg.clearLayers();

    if (activeLayers.PIPELINES) {
        PIPELINES_DATA.forEach(pipe => {
            const latlngs = pipe.coordinates.map(c => [c.lat, c.lng]);
            const color = pipe.type === 'UNDERGROUND' ? '#f59e0b' : '#3b82f6';
            const isSelected = selectedSegment === pipe.id;

            // 1. Buffer Zone (Transparent)
            L.polyline(latlngs, {
                color: color,
                weight: 40,
                opacity: 0.1,
                lineCap: 'round'
            }).addTo(lg);

            // 2. The Pipe
            const line = L.polyline(latlngs, {
                color: isSelected ? '#fff' : color,
                weight: isSelected ? 6 : 4,
                opacity: 1,
                dashArray: pipe.type === 'UNDERGROUND' ? '10, 10' : null
            }).addTo(lg);

            line.on('click', () => {
                setSelectedSegment(pipe.id);
                // Center map on click slightly
                // mapInstanceRef.current.panTo(latlngs[0]);
            });

            // Label
            // L.tooltip({permanent: true, direction: 'center', className: 'bg-transparent border-0 text-white font-bold'}).setContent(pipe.name).setLatLng(latlngs[0]).addTo(lg);
        });
    }
  }, [activeLayers.PIPELINES, selectedSegment]);

  // --- RENDER CADASTRAL ---
  useEffect(() => {
    const lg = layerGroupsRef.current.cadastral;
    if (!lg) return;
    lg.clearLayers();

    if (activeLayers.CADASTRAL) {
        MOCK_CADASTRAL.forEach(cad => {
            const latlngs = cad.coordinates.map(c => [c.lat, c.lng]);
            L.polygon(latlngs, {
                color: 'orange',
                fillColor: 'orange',
                fillOpacity: 0.2,
                weight: 1,
                dashArray: '5,5'
            }).bindTooltip(`Участок: ${cad.owner}`).addTo(lg);
        });
    }
  }, [activeLayers.CADASTRAL]);

  // --- RENDER INSPECTORS & LIVE MOVEMENT ---
  useEffect(() => {
    const lg = layerGroupsRef.current.inspectors;
    if (!lg) return;
    lg.clearLayers();

    if (activeLayers.INSPECTORS) {
        inspectors.forEach(insp => {
            const icon = L.divIcon({
                className: 'custom-icon',
                html: `<div class="w-4 h-4 bg-green-500 rounded-full border-2 border-white shadow-lg animate-pulse relative">
                        <div class="absolute -top-6 left-1/2 -translate-x-1/2 whitespace-nowrap bg-black/70 text-white text-[10px] px-1 rounded">${insp.name}</div>
                       </div>`,
                iconSize: [16, 16],
                iconAnchor: [8, 8]
            });

            L.marker([insp.lat, insp.lng], { icon }).addTo(lg);
        });
    }
  }, [activeLayers.INSPECTORS, inspectors]);

  // --- RENDER TOXI RISK ---
  useEffect(() => {
     const lg = layerGroupsRef.current.toxiRisk;
     if (!lg) return;
     lg.clearLayers();

     if (activeLayers.TOXI_RISK && selectedSegment) {
        const pipe = PIPELINES_DATA.find(p => p.id === selectedSegment);
        if (pipe) {
            const start = pipe.coordinates[0];
            const startPt = L.latLng(start.lat, start.lng);
            
            // Simple logic: Create a triangle polygon based on wind direction
            // In a real app, this would use complex math converting LatLng to meters and back
            const dist = 0.015; // roughly 1.5km
            const angleRad = (weather.windDeg - 90) * (Math.PI / 180);
            
            const destLat = start.lat + dist * Math.sin(angleRad); // Approximation
            const destLng = start.lng + dist * Math.cos(angleRad) * 2; // correction for longitude at this latitude

            // Spread
            const spread = 0.005;

            const p1 = [start.lat, start.lng];
            const p2 = [destLat + spread, destLng + spread];
            const p3 = [destLat - spread, destLng - spread];

            L.polygon([p1, p2, p3], {
                color: 'red',
                fillColor: 'red',
                fillOpacity: 0.4,
                weight: 0
            }).addTo(lg);
        }
     }
  }, [activeLayers.TOXI_RISK, selectedSegment, weather.windDeg]);


  // --- SIMULATION LOOPS ---
  useEffect(() => {
    const interval = setInterval(() => {
      // 1. Weather Changes
      setWeather(prev => ({
        ...prev,
        windDeg: (prev.windDeg + (Math.random() - 0.5) * 5) % 360, 
        windSpeed: Math.max(0, prev.windSpeed + (Math.random() - 0.5))
      }));

      // 2. Inspectors Movement
      setInspectors(prev => prev.map(insp => ({
        ...insp,
        lat: insp.lat + (Math.random() - 0.5) * 0.0002,
        lng: insp.lng + (Math.random() - 0.5) * 0.0002,
      })));

      // 3. SCADA Live Data
      if (selectedSegment) {
        setScadaData(prev => ({
           pressure: Number((prev.pressure + (Math.random() - 0.5) * 0.1).toFixed(2)),
           temp: Number((prev.temp + (Math.random() - 0.5) * 0.5).toFixed(1))
        }));
      }
    }, 2000);
    return () => clearInterval(interval);
  }, [selectedSegment]);

  const toggleLayer = (key: keyof typeof activeLayers) => {
    setActiveLayers(prev => ({ ...prev, [key]: !prev[key] }));
  };

  return (
    <div className="h-full flex flex-col md:flex-row gap-4 relative">
      
      {/* MAP AREA */}
      <div className="flex-1 bg-slate-900 rounded-xl overflow-hidden relative border border-slate-700 shadow-2xl">
        
        {/* LEAFLET MAP CONTAINER */}
        <div ref={mapContainerRef} className="w-full h-full z-0 bg-[#0f172a]" id="map"></div>

        {/* OVERLAYS */}
        
        {/* TOP LEFT: WEATHER */}
        <div className="absolute top-4 left-4 z-[500] bg-secondary/90 backdrop-blur p-3 rounded-lg border border-slate-600 shadow-lg w-48">
           <h4 className="text-xs font-bold text-slate-400 mb-2 flex items-center gap-1"><Wind size={12}/> МЕТЕОСТАНЦИЯ</h4>
           <div className="flex items-center gap-4">
              <div className="relative w-12 h-12 border-2 border-slate-600 rounded-full flex items-center justify-center bg-slate-800">
                 <Navigation 
                    size={24} 
                    className="text-accent transition-transform duration-1000" 
                    style={{ transform: `rotate(${weather.windDeg}deg)` }} 
                    fill="currentColor"
                 />
                 <span className="absolute text-[8px] top-1 text-slate-500">N</span>
              </div>
              <div>
                 <p className="text-2xl font-bold text-white">{weather.windSpeed.toFixed(1)} <span className="text-xs text-slate-400">м/с</span></p>
                 <p className="text-xs text-slate-300">{weather.temp}°C, {weather.condition}</p>
              </div>
           </div>
        </div>

        {/* TOP RIGHT: LAYERS */}
        <div className="absolute top-4 right-4 z-[500] bg-secondary/90 backdrop-blur p-2 rounded-lg border border-slate-600 shadow-lg">
           <h3 className="text-sm font-bold text-white mb-2 flex items-center gap-2 px-2">
             <Layers size={16} className="text-accent" /> Управление картой
           </h3>
           
           {/* BASEMAP SWITCHER */}
           <div className="flex gap-1 mb-3 bg-slate-800 p-1 rounded">
              <button onClick={() => setBaseLayer('OSM')} className={`flex-1 text-xs py-1 px-2 rounded ${baseLayer === 'OSM' ? 'bg-slate-600 text-white' : 'text-slate-400 hover:text-white'}`}>Схема</button>
              <button onClick={() => setBaseLayer('SATELLITE')} className={`flex-1 text-xs py-1 px-2 rounded ${baseLayer === 'SATELLITE' ? 'bg-slate-600 text-white' : 'text-slate-400 hover:text-white'}`}>Спутник</button>
           </div>

           <div className="flex flex-col gap-1">
             <button onClick={() => toggleLayer('PIPELINES')} className={`text-xs px-3 py-1.5 rounded text-left flex items-center justify-between gap-2 ${activeLayers.PIPELINES ? 'bg-blue-600 text-white' : 'text-slate-300 hover:bg-slate-700'}`}>
               <span>Трубопроводы</span> {activeLayers.PIPELINES && <Zap size={10}/>}
             </button>
             <button onClick={() => toggleLayer('CADASTRAL')} className={`text-xs px-3 py-1.5 rounded text-left flex items-center justify-between gap-2 ${activeLayers.CADASTRAL ? 'bg-orange-600 text-white' : 'text-slate-300 hover:bg-slate-700'}`}>
               <span>Кадастр (Земля)</span> {activeLayers.CADASTRAL && <Hexagon size={10}/>}
             </button>
             <button onClick={() => toggleLayer('INSPECTORS')} className={`text-xs px-3 py-1.5 rounded text-left flex items-center justify-between gap-2 ${activeLayers.INSPECTORS ? 'bg-green-600 text-white' : 'text-slate-300 hover:bg-slate-700'}`}>
               <span>Персонал (GPS)</span> {activeLayers.INSPECTORS && <Users size={10}/>}
             </button>
             {selectedSegment && (
               <button onClick={() => toggleLayer('TOXI_RISK')} className={`text-xs px-3 py-1.5 rounded text-left flex items-center justify-between gap-2 border border-dashed ${activeLayers.TOXI_RISK ? 'bg-red-900/80 text-red-200 border-red-500' : 'text-red-400 border-red-800 hover:bg-red-900/30'}`}>
                  <span>Toxi-Risk (Симуляция)</span> <Triangle size={10}/>
               </button>
             )}
           </div>
        </div>

      </div>

      {/* RIGHT SIDEBAR: INFO PANEL */}
      {selectedSegment ? (
        <div className="w-full md:w-80 bg-secondary rounded-xl p-5 border border-slate-700 animate-in slide-in-from-right duration-300 flex flex-col gap-4">
           {(() => {
             const seg = PIPELINES_DATA.find(s => s.id === selectedSegment);
             if(!seg) return null;
             return (
               <>
                 <div className="flex justify-between items-start">
                    <h3 className="text-lg font-bold text-white">{seg.id}</h3>
                    <button onClick={() => { setSelectedSegment(null); setActiveLayers(l => ({...l, TOXI_RISK: false})); }} className="text-slate-400 hover:text-white"><Zap size={18}/></button>
                 </div>
                 <p className="text-slate-300 text-sm">{seg.name}</p>
                 
                 {/* LIVE SCADA BLOCK */}
                 <div className="bg-slate-900 p-4 rounded-lg border border-slate-700 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-2 opacity-10"><Gauge size={48} className="text-accent"/></div>
                    <h4 className="text-xs font-bold text-slate-400 mb-3 flex items-center gap-2">
                       <span className="w-2 h-2 rounded-full bg-green-500 animate-pulse"></span> SCADA ТЕЛЕМЕТРИЯ
                    </h4>
                    <div className="grid grid-cols-2 gap-4">
                       <div>
                          <p className="text-[10px] text-slate-500">ДАВЛЕНИЕ (P1)</p>
                          <p className="text-xl font-mono font-bold text-accent">{scadaData.pressure} <span className="text-xs">МПа</span></p>
                       </div>
                       <div>
                          <p className="text-[10px] text-slate-500">ТЕМПЕРАТУРА (T1)</p>
                          <p className="text-xl font-mono font-bold text-orange-400">{scadaData.temp} <span className="text-xs">°C</span></p>
                       </div>
                    </div>
                 </div>

                 {/* TOXI RISK ACTIONS */}
                 <div className="space-y-2">
                    <button 
                       onClick={() => toggleLayer('TOXI_RISK')}
                       className={`w-full py-3 rounded-lg font-bold text-sm flex items-center justify-center gap-2 border transition ${activeLayers.TOXI_RISK ? 'bg-red-500 text-white border-red-600' : 'bg-slate-800 text-red-400 border-red-900/50 hover:bg-slate-700'}`}
                    >
                       <Triangle size={16} className={activeLayers.TOXI_RISK ? "fill-white" : ""} />
                       {activeLayers.TOXI_RISK ? 'Остановить симуляцию' : 'Смоделировать разрыв (Toxi)'}
                    </button>
                    {activeLayers.TOXI_RISK && (
                       <div className="p-3 bg-red-900/20 border border-red-900/50 rounded text-xs text-red-200">
                          <p>⚠ Внимание: Направление облака рассчитано на основе текущего ветра ({weather.windDeg.toFixed(0)}°).</p>
                       </div>
                    )}
                 </div>

                 {/* STATIC INFO */}
                 <div className="space-y-3 pt-4 border-t border-slate-700">
                     <div className="flex justify-between text-sm">
                        <span className="text-slate-400">Толщина стенки:</span>
                        <span className="text-white">{seg.thickness} мм</span>
                     </div>
                     <div className="flex justify-between text-sm">
                        <span className="text-slate-400">Коррозия:</span>
                        <span className="text-danger">{seg.corrosionRate} мм/год</span>
                     </div>
                     <div className="flex justify-between text-sm">
                        <span className="text-slate-400">Прогноз ресурса:</span>
                        <span className="text-success">{seg.remainingLife} лет</span>
                     </div>
                 </div>

               </>
             )
           })()}
        </div>
      ) : (
         <div className="hidden md:flex w-80 bg-secondary rounded-xl p-5 border border-slate-700 items-center justify-center text-center">
            <div>
               <MapIcon className="mx-auto text-slate-600 mb-2" size={32} />
               <p className="text-slate-500">Выберите объект на карте для доступа к телеметрии и функциям анализа</p>
            </div>
         </div>
      )}
    </div>
  );
};

export default PipelineMap;
