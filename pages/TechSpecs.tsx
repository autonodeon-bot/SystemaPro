import { ARCHITECTURE_SPECS, APP_VERSION, RELEASE_NOTES_DATE } from '../constants';
import { Code, Terminal, Database } from 'lucide-react';

const TechSpecs = () => {
  return (
    <div className="max-w-5xl mx-auto space-y-8">
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-white mb-2">Техническая документация платформы</h1>
        <p className="text-app-text3">
          Версия системы: {APP_VERSION} ({RELEASE_NOTES_DATE})
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
         <div className="bg-app-panel p-4 rounded-lg border border-app-line flex items-center gap-4">
            <div className="p-3 bg-blue-500/10 rounded-lg text-blue-400"><Code size={24}/></div>
            <div>
               <p className="text-xs text-app-text3">Frontend</p>
               <p className="font-bold text-white">React 18 + TS</p>
            </div>
         </div>
         <div className="bg-app-panel p-4 rounded-lg border border-app-line flex items-center gap-4">
            <div className="p-3 bg-green-500/10 rounded-lg text-green-400"><Database size={24}/></div>
            <div>
               <p className="text-xs text-app-text3">Database</p>
               <p className="font-bold text-white">PostgreSQL 16</p>
            </div>
         </div>
         <div className="bg-app-panel p-4 rounded-lg border border-app-line flex items-center gap-4">
            <div className="p-3 bg-orange-500/10 rounded-lg text-orange-400"><Terminal size={24}/></div>
            <div>
               <p className="text-xs text-app-text3">Backend</p>
               <p className="font-bold text-white">FastAPI 0.115+</p>
            </div>
         </div>
      </div>

      {ARCHITECTURE_SPECS.map((spec) => (
        <section key={spec.id} className="bg-secondary rounded-xl overflow-hidden border border-app-line shadow-lg">
          <div className="px-6 py-4 border-b border-app-line bg-app-panel/50">
            <h2 className="text-xl font-bold text-white">{spec.title}</h2>
          </div>
          <div className="p-6">
            <p className="text-app-text2 mb-4 whitespace-pre-line leading-relaxed">
              {spec.content}
            </p>
            
            {spec.codeBlock && (
              <div className="relative group">
                <div className="absolute top-0 right-0 px-3 py-1 bg-app-soft rounded-bl text-xs text-app-text2 font-mono">
                  {spec.language}
                </div>
                <pre className="bg-[#0f172a] p-4 rounded-lg overflow-x-auto text-sm font-mono text-app-text border border-app-line">
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