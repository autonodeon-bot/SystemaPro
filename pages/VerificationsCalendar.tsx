import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Calendar, ChevronLeft, ChevronRight, AlertTriangle, ArrowLeft } from 'lucide-react';
import { API_BASE } from '../constants';

interface VerificationEquipment {
  id: string;
  name: string;
  equipment_type: string;
  serial_number: string;
  next_verification_date: string;
  days_until_expiry?: number;
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

  const getDaysInMonth = (date: Date) => {
    const year = date.getFullYear();
    const month = date.getMonth();
    const firstDay = new Date(year, month, 1);
    const lastDay = new Date(year, month + 1, 0);
    const daysInMonth = lastDay.getDate();
    const startingDayOfWeek = firstDay.getDay();
    
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
    const dateStr = date.toISOString().split('T')[0];
    return equipment.filter(eq => {
      if (!eq.next_verification_date) return false;
      const eqDate = new Date(eq.next_verification_date).toISOString().split('T')[0];
      return eqDate === dateStr;
    });
  };

  const getEquipmentForMonth = () => {
    const year = currentMonth.getFullYear();
    const month = currentMonth.getMonth();
    const startDate = new Date(year, month, 1);
    const endDate = new Date(year, month + 1, 0);
    
    return equipment.filter(eq => {
      if (!eq.next_verification_date) return false;
      const eqDate = new Date(eq.next_verification_date);
      return eqDate >= startDate && eqDate <= endDate;
    });
  };

  const getDateColor = (date: Date | null) => {
    if (!date) return '';
    const eqForDate = getEquipmentForDate(date);
    if (eqForDate.length === 0) return '';
    
    const hasExpired = eqForDate.some(eq => eq.is_expired);
    const hasWarning = eqForDate.some(eq => !eq.is_expired && eq.days_until_expiry !== null && eq.days_until_expiry <= 7);
    
    if (hasExpired) return 'bg-red-500/20 border-red-500';
    if (hasWarning) return 'bg-orange-500/20 border-orange-500';
    return 'bg-yellow-500/20 border-yellow-500';
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
    return <div className="text-center text-slate-400 mt-20">Загрузка...</div>;
  }

  const days = getDaysInMonth(currentMonth);
  const monthEquipment = getEquipmentForMonth();

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4">
          <button
            onClick={() => navigate('/verifications')}
            className="p-2 text-slate-400 hover:text-white transition rounded-lg hover:bg-slate-800"
            title="Вернуться к поверкам"
          >
            <ArrowLeft size={20} />
          </button>
          <h1 className="text-2xl font-bold text-white">Календарь поверок</h1>
        </div>
        <div className="flex items-center gap-4">
          <button
            onClick={prevMonth}
            className="p-2 text-slate-400 hover:text-white transition"
          >
            <ChevronLeft size={20} />
          </button>
          <span className="text-white font-semibold">
            {monthNames[currentMonth.getMonth()]} {currentMonth.getFullYear()}
          </span>
          <button
            onClick={nextMonth}
            className="p-2 text-slate-400 hover:text-white transition"
          >
            <ChevronRight size={20} />
          </button>
        </div>
      </div>

      {/* Легенда */}
      <div className="bg-secondary/50 rounded-lg p-4 border border-slate-700">
        <div className="flex items-center gap-6 flex-wrap">
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 bg-red-500/20 border border-red-500 rounded"></div>
            <span className="text-sm text-slate-300">Просрочено</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 bg-orange-500/20 border border-orange-500 rounded"></div>
            <span className="text-sm text-slate-300">Истекает ≤7 дней</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 bg-yellow-500/20 border border-yellow-500 rounded"></div>
            <span className="text-sm text-slate-300">Истекает ≤30 дней</span>
          </div>
        </div>
      </div>

      {/* Календарь */}
      <div className="bg-secondary/50 rounded-lg border border-slate-700 overflow-hidden">
        <div className="grid grid-cols-7 gap-px bg-slate-700">
          {weekDays.map(day => (
            <div key={day} className="bg-slate-800 p-2 text-center text-sm font-semibold text-slate-300">
              {day}
            </div>
          ))}
          {days.map((date, idx) => (
            <div
              key={idx}
              className={`bg-slate-900 min-h-[100px] p-2 border-2 ${getDateColor(date)} ${
                selectedDate && date && selectedDate.getTime() === date.getTime() ? 'ring-2 ring-blue-500' : ''
              } ${date ? 'cursor-pointer hover:bg-slate-800' : 'bg-slate-950'}`}
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
                      className="text-xs text-slate-300 truncate mb-1"
                      title={eq.name}
                    >
                      {eq.equipment_type}: {eq.name.substring(0, 15)}...
                    </div>
                  ))}
                  {getEquipmentForDate(date).length > 2 && (
                    <div className="text-xs text-slate-500">
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
        <div className="bg-secondary/50 rounded-lg p-4 border border-slate-700">
          <h3 className="text-lg font-semibold text-white mb-4">
            Оборудование с поверкой {selectedDate.toLocaleDateString('ru-RU')}
          </h3>
          <div className="space-y-2">
            {getEquipmentForDate(selectedDate).length === 0 ? (
              <p className="text-slate-400">Нет оборудования с поверкой на эту дату</p>
            ) : (
              getEquipmentForDate(selectedDate).map(eq => (
                <div
                  key={eq.id}
                  className="bg-slate-800 rounded-lg p-3 border border-slate-700"
                >
                  <div className="flex items-center justify-between">
                    <div>
                      <div className="font-semibold text-white">{eq.name}</div>
                      <div className="text-sm text-slate-400">
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
                    ) : null}
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      )}

      {/* Статистика месяца */}
      <div className="bg-secondary/50 rounded-lg p-4 border border-slate-700">
        <h3 className="text-lg font-semibold text-white mb-4">Статистика за месяц</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div>
            <div className="text-slate-400 text-sm">Всего поверок</div>
            <div className="text-2xl font-bold text-white mt-1">{monthEquipment.length}</div>
          </div>
          <div>
            <div className="text-slate-400 text-sm">Просрочено</div>
            <div className="text-2xl font-bold text-red-400 mt-1">
              {monthEquipment.filter(eq => eq.is_expired).length}
            </div>
          </div>
          <div>
            <div className="text-slate-400 text-sm">Требуют внимания</div>
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

