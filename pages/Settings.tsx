import { useTheme } from '../contexts/ThemeContext';
import { APP_VERSION, MOBILE_APK_URL } from '../constants';

export default function Settings() {
  const { theme, setTheme } = useTheme();
  return <section className="space-y-6 max-w-3xl">
    <div><h1 className="text-2xl font-semibold text-app-text">Настройки</h1><p className="text-app-text3 mt-2">Внешний вид и сведения о системе.</p></div>
    <fieldset className="sp-surface p-5 space-y-4">
      <legend className="font-semibold px-2">Оформление</legend>
      <p className="text-sm text-app-text2">Основная тема — дневная. Выбранный режим сохраняется на этом устройстве.</p>
      {(['light', 'dark'] as const).map(value => <label key={value} className="flex items-center gap-3 min-h-12 cursor-pointer">
        <input type="radio" name="theme" value={value} checked={theme === value} onChange={() => setTheme(value)} />
        <span>{value === 'light' ? 'Дневная — светлые поверхности и контрастный текст' : 'Ночная — для работы при слабом освещении'}</span>
      </label>)}
    </fieldset>
    <div className="sp-surface p-5 space-y-3"><h2 className="font-semibold">Монитор · {APP_VERSION}</h2><a className="text-accent underline inline-flex min-h-10 items-center" href={MOBILE_APK_URL}>Скачать приложение для Android</a><p className="text-sm text-app-text3">Обследование → черновик → проверка → подпись → отчёт. Перед подписью проверьте сохранение и синхронизацию.</p></div>
  </section>;
}
