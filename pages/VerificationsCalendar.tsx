import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ChevronLeft, ChevronRight, ArrowLeft } from 'lucide-react';
import { API_BASE } from '../constants';

interface VerificationEquipment {
  id: string;
  name: string;
  equipment_type: string;
  serial_number: string;
  next_verification_date: string;
  days_until_expiry: number | null;
  is_expired: boolean;
}

const VerificationsCalendar: React.FC = () => {
  const navigate = useNavigate();
  const [equipment, setEquipment] = useState<VerificationEquipment[]>([]);
  const [currentMonth, setCurrentMonth] = useState(new Date());
  const [selectedDate, setSelectedDate] = useState<Date | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadEquipment();
  }, []);

  const loadEquipment = async () => {
    try {
      const token = localStorage.getItem('token');
      const response = await fetch(`${API_BASE}/api/verification-equipment?is_active=true`, {
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });
      if (response.ok) {
        const data = await response.json();
        setEquipment(data);
      }
    } catch (error) {
      console.error('Ошибка загрузки оборудования:', error);
    } finally {
      setLoading(false);
    }
  };

  /** Ключ даты YYYY-MM-DD в локальном календаре (без UTC-сдвига). */
  const localDateKey = (d: Date) => {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
  };

  const getDaysInMonth = (date: Date) => {
    const year = date.getFullYear();
    const month = date.getMonth();
    const firstDay = new Date(year, month, 1);
    const lastDay = new Date(year, month + 1, 0);
    const daysInMonth = lastDay.getDate();
    // Понедельник = первый столбец: JS getDay() 0=Вс → сдвиг
    const startingDayOfWeek = (firstDay.getDay() + 6) % 7;

    const days: (Date | null)[] = [];
    // Пустые ячейки для дней предыдущего месяца
    for (let i = 0; i < startingDayOfWeek; i++) {
      days.push(null);
    }
    // Дни текущего месяца
    for (let day = 1; day <= daysInMonth; day++) {
      days.push(new Date(year, month, day));
    }
    return days;
  };

  const getEquipmentForDate = (date: Date) => {
    const dateStr = localDateKey(date);
    return equipment.filter(eq => {
      if (!eq.next_verification_date) return false;
      const eqKey = eq.next_verification_date.slice(0, 10);
      return eqKey === dateStr;
    });
  };

  const getEquipmentForMonth = () => {
    const year = currentMonth.getFullYear();
    const month = currentMonth.getMonth();
    const startDate = new Date(year, month, 1);
    const endDate = new Date(year, month + 1, 0);

    return equipment.filter(eq => {
      if (!eq.next_verification_date) return false;
      const raw = eq.next_verification_date.slice(0, 10);
      const [y, mo, d] = raw.split('-').map(Number);
      const eqDate = new Date(y, mo - 1, d);
      return eqDate >= startDate && eqDate <= endDate;
    });
  };

  const getDateColor = (date: Date | null) => {
    if (!date) return '';
    const eqForDate = getEquipmentForDate(date);
    if (eqForDate.length === 0) return '';

    const hasExpired = eqForDate.some(eq => eq.is_expired);
    const hasUrgent = eqForDate.some(
      eq => !eq.is_expired && eq.days_until_expiry !== null && eq.days_until_expiry <= 7
    );
    const hasMonth = eqForDate.some(
      eq =>
        !eq.is_expired &&
        eq.days_until_expiry !== null &&
        eq.days_until_expiry > 7 &&
        eq.days_until_expiry <= 30
    );

    if (hasExpired) return 'bg-red-500/20 border-red-500';
    if (hasUrgent) return 'bg-orange-500/20 border-orange-500';
    if (hasMonth) return 'bg-yellow-500/20 border-yellow-500';
    return 'bg-emerald-500/10 border-emerald-600';
  };

  const monthNames = [
    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
  ];

  const weekDays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  const prevMonth = () => {
    setCurrentMonth(new Date(currentMonth.getFullYear(), currentMonth.getMonth() - 1, 1));
  };

  const nextMonth = () => {
    setCurrentMonth(new Date(currentMonth.getFullYear(), currentMonth.getMonth() + 1, 1));
  };

  if (loading) {
    return <div className="text-center text-app-text3 mt-20">Загрузка...</div>;
  }

  const days = getDaysInMonth(currentMonth);
  const monthEquipment = getEquipmentForMonth();

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4">
          <button
            onClick={() => navigate('/verifications')}
            className="p-2 text-app-text3 hover:text-app-text transition rounded-lg hover:bg-app-panel"
            title="Вернуться к поверкам"
          >
            <ArrowLeft size={20} />
          </button>
          <h1 className="text-2xl font-bold text-white">Календарь поверок</h1>
        </div>
        <div className="flex items-center gap-4">
          <button
            onClick={prevMonth}
            className="p-2 text-app-text3 hover:text-app-text transition"
          >
            <ChevronLeft size={20} />
          </button>
          <span className="text-white font-semibold">
            {monthNames[currentMonth.getMonth()]} {currentMonth.getFullYear()}
          </span>
          <button
            onClick={nextMonth}
            className="p-2 text-app-text3 hover:text-app-text transition"
          >
            <ChevronRight size={20} />
          </button>
        </div>
      </div>

      {/* Легенда */}
      <div className="bg-secondary/50 rounded-lg p-4 border border-app-line">
        <div className="flex items-center gap-6 flex-wrap">
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 bg-red-500/20 border border-red-500 rounded"></div>
            <span className="text-sm text-app-text2">Просрочено</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 bg-orange-500/20 border border-orange-500 rounded"></div>
            <span className="text-sm text-app-text2">Истекает ≤7 дней</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 bg-yellow-500/20 border border-yellow-500 rounded"></div>
            <span className="text-sm text-app-text2">Истекает 8–30 дней</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 bg-emerald-500/10 border border-emerald-600 rounded"></div>
            <span className="text-sm text-app-text2">Срок &gt; 30 дней</span>
          </div>
        </div>
      </div>

      {/* Календарь */}
      <div className="bg-secondary/50 rounded-lg border border-app-line overflow-hidden">
        <div className="grid grid-cols-7 gap-px bg-app-soft">
          {weekDays.map(day => (
            <div key={day} className="bg-app-panel p-2 text-center text-sm font-semibold text-app-text2">
              {day}
            </div>
          ))}
          {days.map((date, idx) => (
            <div
              key={idx}
              className={`bg-app-deep min-h-[100px] p-2 border-2 ${getDateColor(date)} ${
                selectedDate && date && selectedDate.getTime() === date.getTime() ? 'ring-2 ring-blue-500' : ''
              } ${date ? 'cursor-pointer hover:bg-app-panel' : 'bg-app-deep'}`}
              onClick={() => date && setSelectedDate(date)}
            >
              {date && (
                <>
                  <div className="text-sm font-semibold text-white mb-1">
                    {date.getDate()}
                  </div>
                  {getEquipmentForDate(date).slice(0, 2).map(eq => (
                    <div
                      key={eq.id}
                      className="text-xs text-app-text2 truncate mb-1"
                      title={eq.name}
                    >
                      {eq.equipment_type}: {(eq.name || '').length > 15 ? `${(eq.name || '').slice(0, 15)}…` : (eq.name || '—')}
                    </div>
                  ))}
                  {getEquipmentForDate(date).length > 2 && (
                    <div className="text-xs text-app-text3">
                      +{getEquipmentForDate(date).length - 2} еще
                    </div>
                  )}
                </>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Детали выбранной даты */}
      {selectedDate && (
        <div className="bg-secondary/50 rounded-lg p-4 border border-app-line">
          <h3 className="text-lg font-semibold text-white mb-4">
            Оборудование с поверкой {selectedDate.toLocaleDateString('ru-RU')}
          </h3>
          <div className="space-y-2">
            {getEquipmentForDate(selectedDate).length === 0 ? (
              <p className="text-app-text3">Нет оборудования с поверкой на эту дату</p>
            ) : (
              getEquipmentForDate(selectedDate).map(eq => (
                <div
                  key={eq.id}
                  className="bg-app-panel rounded-lg p-3 border border-app-line"
                >
                  <div className="flex items-center justify-between">
                    <div>
                      <div className="font-semibold text-white">{eq.name}</div>
                      <div className="text-sm text-app-text3">
                        {eq.equipment_type} • {eq.serial_number}
                      </div>
                    </div>
                    {eq.is_expired ? (
                      <span className="px-2 py-1 bg-red-500/20 text-red-400 rounded text-xs">
                        Просрочено
                      </span>
                    ) : eq.days_until_expiry !== null && eq.days_until_expiry <= 7 ? (
                      <span className="px-2 py-1 bg-orange-500/20 text-orange-400 rounded text-xs">
                        Истекает через {eq.days_until_expiry} дн.
                      </span>
                    ) : eq.days_until_expiry !== null && eq.days_until_expiry <= 30 ? (
                      <span className="px-2 py-1 bg-yellow-500/20 text-yellow-400 rounded text-xs">
                        Истекает через {eq.days_until_expiry} дн.
                      </span>
                    ) : !eq.is_expired && eq.days_until_expiry !== null ? (
                      <span className="px-2 py-1 bg-emerald-500/10 text-emerald-400 rounded text-xs">
                        Через {eq.days_until_expiry} дн.
                      </span>
                    ) : null}
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      )}

      {/* Статистика месяца */}
      <div className="bg-secondary/50 rounded-lg p-4 border border-app-line">
        <h3 className="text-lg font-semibold text-white mb-4">Статистика за месяц</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div>
            <div className="text-app-text3 text-sm">Всего поверок</div>
            <div className="text-2xl font-bold text-white mt-1">{monthEquipment.length}</div>
          </div>
          <div>
            <div className="text-app-text3 text-sm">Просрочено</div>
            <div className="text-2xl font-bold text-red-400 mt-1">
              {monthEquipment.filter(eq => eq.is_expired).length}
            </div>
          </div>
          <div>
            <div className="text-app-text3 text-sm">Требуют внимания</div>
            <div className="text-2xl font-bold text-yellow-400 mt-1">
              {monthEquipment.filter(eq => !eq.is_expired && eq.days_until_expiry !== null && eq.days_until_expiry <= 30).length}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default VerificationsCalendar;

