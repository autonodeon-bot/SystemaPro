import React from 'react';
import { ARCHITECTURE_SPECS } from '../constants';
import { Code, Terminal, Database } from 'lucide-react';

const TechSpecs = () => {
  return (
    <div className="max-w-5xl mx-auto space-y-8">
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-white mb-2">Техническая документация платформы</h1>
        <p className="text-slate-400">Версия архитектуры: 2.1.0 (2025-Q1)</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
         <div className="bg-slate-800 p-4 rounded-lg border border-slate-700 flex items-center gap-4">
            <div className="p-3 bg-blue-500/10 rounded-lg text-blue-400"><Code size={24}/></div>
            <div>
               <p className="text-xs text-slate-500">Frontend</p>
               <p className="font-bold text-white">React 18 + TS</p>
            </div>
         </div>
         <div className="bg-slate-800 p-4 rounded-lg border border-slate-700 flex items-center gap-4">
            <div className="p-3 bg-green-500/10 rounded-lg text-green-400"><Database size={24}/></div>
            <div>
               <p className="text-xs text-slate-500">Database</p>
               <p className="font-bold text-white">PostgreSQL 16</p>
            </div>
         </div>
         <div className="bg-slate-800 p-4 rounded-lg border border-slate-700 flex items-center gap-4">
            <div className="p-3 bg-orange-500/10 rounded-lg text-orange-400"><Terminal size={24}/></div>
            <div>
               <p className="text-xs text-slate-500">Backend</p>
               <p className="font-bold text-white">FastAPI 0.115+</p>
            </div>
         </div>
      </div>

      {ARCHITECTURE_SPECS.map((spec) => (
        <section key={spec.id} className="bg-secondary rounded-xl overflow-hidden border border-slate-700 shadow-lg">
          <div className="px-6 py-4 border-b border-slate-700 bg-slate-800/50">
            <h2 className="text-xl font-bold text-white">{spec.title}</h2>
          </div>
          <div className="p-6">
            <p className="text-slate-300 mb-4 whitespace-pre-line leading-relaxed">
              {spec.content}
            </p>
            
            {spec.codeBlock && (
              <div className="relative group">
                <div className="absolute top-0 right-0 px-3 py-1 bg-slate-700 rounded-bl text-xs text-slate-300 font-mono">
                  {spec.language}
                </div>
                <pre className="bg-[#0f172a] p-4 rounded-lg overflow-x-auto text-sm font-mono text-slate-200 border border-slate-700">
                  <code>{spec.codeBlock}</code>
                </pre>
              </div>
            )}
          </div>
        </section>
      ))}
    </div>
  );
};

export default TechSpecs;