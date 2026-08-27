import { useState } from 'react';
import { Sparkles, CheckCircle, AlertCircle, Plus, Bug, Settings, ChevronDown, ChevronUp } from 'lucide-react';

interface Version {
  version: string;
  date: string;
  type: 'major' | 'minor' | 'patch';
  changes: {
    type: 'added' | 'fixed' | 'changed' | 'improved';
    description: string;
  }[];
}

const Changelog = () => {
  /** Единственный источник для карточки «Версия системы» и списка ниже */
  const versions: Version[] = [
    {
      version: '3.7.26',
      date: '27.08.2026',
      type: 'patch',
      changes: [
        {
          type: 'fixed',
          description:
            'Мобильное приложение — удобство ввода: длинные формулировки в выпадающих списках (заключения НК, методы контроля, организации, характер дефекта, испытательная среда) больше не выходят за границы поля и обрезаются многоточием; список исполнителей и навигатор по разделам отчёта прокручиваются и не перекрывают экран; заголовок обследования не переполняется; на схеме УЗТ тап по готовой точке открывает её редактирование, а не создаёт новую поверх; нижние поля экрана «Метод НК» не перекрываются клавиатурой; кнопки «Камера/Галерея» в дефектах переносятся на узких экранах. APK 3.7.26+63.',
        },
      ],
    },
    {
      version: '3.7.25',
      date: '27.08.2026',
      type: 'patch',
      changes: [
        {
          type: 'fixed',
          description:
            'Замечания к отчёту ТО 20.08.2026 (моб. 3.7.24): выводы стр. 7 (УЗТ/УЗК/МПК, идентификаторы оборудования, расчёт и остаточный ресурс, общий вывод при ремонте), запятая «установлено,», формулировка оперативной диагностики, колонка даты, марка стали в твёрдости, параметры ВИК/МПК, поля УЗК в таблице. Схемы ВИК/УЗТ/ТК/УЗК/МПК по слоям: ориентация гориз./верт., легенда патрубков и швов, размеры, точки УЗТ до 150, участки Т/У, зоны НК, эскизы твёрдости. Конструктор — DN, ось/окружность, место патрубка. Для всех форм ТО (блоки одинаковые). APK 3.7.25+62.',
        },
      ],
    },
    {
      version: '3.7.24',
      date: '16.08.2026',
      type: 'patch',
      changes: [
        {
          type: 'fixed',
          description:
            'Замечания к отчёту ТО 14.08.2026 (моб. 3.7.23): класс/рег.№ ОПО, основания и сроки, карточки предприятий, руководитель/телефон/e-mail/ЛНК, результаты анализа документации и НК при дефектах, выводы 14–15, объём документов, направление текста элементов, метод НК, механика днища, переносы заголовков, цвет приборов, схемы УЗТ/ТК/УЗК/МПК из приложения, ориентация сосуда, легенда патрубков, дубли карт, формулировки заключений, исполнители МПК. APK 3.7.24+61.',
        },
      ],
    },
    {
      version: '3.7.23',
      date: '12.08.2026',
      type: 'patch',
      changes: [
        {
          type: 'added',
          description:
            'Все 44 формы ТО: генерация официальных отчётов (специализированные + generic filler); обследования по профилю семейства (сосуд/трубопровод/ГПМ/резервуар/котёл/машины/эл./арматура/башня/станция); конструктор схем с параметрами под тип оборудования. APK 3.7.23+60.',
        },
      ],
    },
    {
      version: '3.7.22',
      date: '12.08.2026',
      type: 'patch',
      changes: [
        {
          type: 'added',
          description:
            'Конструктор карт контроля: все 44 формы ТО (развёртка/трубопровод/резервуар/башня/эл./арматура/станция). Web и Mobile — выбор типа до параметров; продольные швы вразбежку; днища-круги; схема из конструктора → отчёт. APK 3.7.22+59.',
        },
      ],
    },
    {
      version: '3.7.21',
      date: '07.08.2026',
      type: 'patch',
      changes: [
        {
          type: 'changed',
          description:
            'Раздел «Карта трубопроводов» → «Текущие сотрудники»: на карте онлайн сотрудники с GPS; клик в списке — переход к маркеру. Mobile шлёт координаты раз в 5 мин при наличии сети. APK 3.7.21+58.',
        },
      ],
    },
    {
      version: '3.7.20',
      date: '07.08.2026',
      type: 'patch',
      changes: [
        {
          type: 'improved',
          description:
            'to-33 и to-3 доведены до глубины сосуда: полный набор приложений (ВИК/УЗТ/МПК/ВТК/твёрдость/ЭХЗ/расчёт; акт ПС и чек-листы ГПМ). Mobile — полный ввод данных. APK 3.7.20+57.',
        },
      ],
    },
    {
      version: '3.7.19',
      date: '07.08.2026',
      type: 'patch',
      changes: [
        {
          type: 'added',
          description:
            'Формы ТО to-33 (подземные трубопроводы) и to-3 (ГПМ): автовыбор по типу оборудования, заполнение Word, адаптированный ввод в mobile. Сосуды to-1 без изменений. APK 3.7.19+56.',
        },
        {
          type: 'added',
          description:
            'Типы оборудования UNDERGROUND_PIPELINE и CRANE в справочнике; PIPELINE+«подземн» → to-33.',
        },
      ],
    },
    {
      version: '3.7.18',
      date: '07.08.2026',
      type: 'patch',
      changes: [
        {
          type: 'fixed',
          description:
            'Отчёт to-1: заполнение табл. приборов (реестр + ручной ввод + НК); убраны пустые строки в перечне объектов; keep-with-next для заголовков разделов; содержание с новой страницы.',
        },
        {
          type: 'improved',
          description:
            'Mobile: явный ввод приборов для разд. 7, инвентарный № / местонахождение, договор и сроки работ. APK 3.7.18+55.',
        },
      ],
    },
    {
      version: '3.7.17',
      date: '07.08.2026',
      type: 'patch',
      changes: [
        {
          type: 'added',
          description:
            'Конструктор схем сосуда: ориентация гориз./верт., пресеты сварки, патрубки → PNG; Web + Mobile; сохранение в шаблоны чертежей. APK 3.7.17+54.',
        },
        {
          type: 'fixed',
          description:
            'УЗТ таблица результатов; Times New Roman во всём to-1; титул только portrait; параметры УЗК в to-1; файл схемы подключения.',
        },
      ],
    },
    {
      version: '3.7.16',
      date: '07.08.2026',
      type: 'patch',
      changes: [
        {
          type: 'fixed',
          description:
            'Встреча 03.08: шрифты таблиц ~12 pt + landscape для широких таблиц; объём листов в PDF; пустые строки; ориентация сосуда; режим термообработки; УЗК характер дефекта (объёмный/плоскостной); точка ≠ элемент.',
        },
        {
          type: 'added',
          description:
            'Mobile: заказчик/организация ТД, базовая схема сосуда со слоями НК, расширенные поля УЗК/твёрдости. APK 3.7.16+53.',
        },
      ],
    },
    {
      version: '3.7.15',
      date: '30.07.2026',
      type: 'patch',
      changes: [
        {
          type: 'fixed',
          description:
            'Отчёт ТО-1 по замечаниям PDF: механика материала (σт/σв/δ/ψ), техкарта с задания → схема в отчёте, УЗК/МПК маппинг, очистка пустых строк, ОПО класс/рег.№ через реестр ОПО.',
        },
        {
          type: 'added',
          description:
            'Веб: страница «Реестр ОПО» (класс опасности, рег. №). Mobile: поля механики в элементах корпуса, расширенные поля УЗК, полные поля гидро/термо/истории НК. APK 3.7.15+52.',
        },
      ],
    },
    {
      version: '3.7.14',
      date: '27.07.2026',
      type: 'patch',
      changes: [
        {
          type: 'added',
          description:
            'Мобильное: бейдж очереди на «Синхронизация», «Продолжить последнее», группировка заданий по ОПО/неделям, фильтр просроченных, свайпы Начать/Детали, поиск в реестре протоколов.',
        },
        {
          type: 'added',
          description:
            'Мобильное: голосовой ввод и чипы формулировок, дублирование протокола, липкие разделы чек-листа, крупный ввод УЗТ, разметка фото при съёмке, итоги дня после sync, светлая тема на главном экране, увеличенные touch-цели. APK 3.7.14+51.',
        },
      ],
    },
    {
      version: '3.7.13',
      date: '27.07.2026',
      type: 'patch',
      changes: [
        {
          type: 'fixed',
          description:
            'Сервер: исправлена ошибка генерации отчёта ЭПБ «Failed to generate report: too many values to unpack (expected 3)».',
        },
        {
          type: 'fixed',
          description:
            'Мобильное: реестр протоколов — завершённые и отправленные на сервер обследования/протоколы больше не отображаются как «не завершён» (черновик удаляется после отправки и при синхронизации).',
        },
        {
          type: 'added',
          description:
            'Мобильное: реестр протоколов показывает историю ранее завершённых обследований с сервера (вкладка «Все протоколы»).',
        },
        {
          type: 'added',
          description:
            'Мобильное: задания можно просматривать выпадающим списком по предприятиям (переключатель вида в шапке экрана, выбор запоминается). APK 3.7.13+50.',
        },
      ],
    },
    {
      version: '3.7.12',
      date: '27.07.2026',
      type: 'patch',
      changes: [
        {
          type: 'fixed',
          description:
            'Отчёт ТО-1: титул (класс/наименование/рег.№ ОПО, полный адрес объекта), специалисты по видам НК из мобильного (вместо статичных ФИО), области аттестации кириллицей, № удостоверения и сроки из справочника.',
        },
        {
          type: 'fixed',
          description:
            'Отчёт ТО-1: полные наименования приборов, поверка из реестра; пустые строки таблиц убраны; «Не предоставлено» → тире в объёме; унифицирован шрифт приложений; исправлено обрезание названия организации-исполнителя.',
        },
        {
          type: 'fixed',
          description:
            'ВИК/УЗТ/УЗК/твёрдость: объекты контроля, объём и дефекты из мобильных данных; параметры ВИК (шероховатость/освещённость/доп. освещение); таблицы измерений заполняются из чек-листа и методов НК.',
        },
        {
          type: 'added',
          description:
            'Мобильное: доп. данные о сосуде; стандартные формулировки заключений НК; доп. освещение ВИК; ввод точек твердометрии в методе НК; индикатор схемы/техкарты на задании.',
        },
        {
          type: 'added',
          description:
            'Веб: типы приборов (образцы шероховатости, люксметры, капиллярный контроль с реагентами); загрузка файла схемы/техкарты к заданию. APK 3.7.12+49.',
        },
      ],
    },
    {
      version: '3.7.11',
      date: '21.07.2026',
      type: 'patch',
      changes: [
        {
          type: 'fixed',
          description:
            'Мобильное приложение: сохранение введённых данных при смене страниц осмотра, блокировке экрана и перезапуске (черновик восстанавливается целиком). APK 3.7.11+48.',
        },
      ],
    },
    {
      version: '3.7.10',
      date: '20.07.2026',
      type: 'patch',
      changes: [
        {
          type: 'improved',
          description:
            'Мобильное APK обновлено до 3.7.10+47 на neftcontrol.ru/mobile/ (пересборка и выкладка актуального приложения).',
        },
      ],
    },
    {
      version: '3.7.9',
      date: '17.07.2026',
      type: 'patch',
      changes: [
        {
          type: 'added',
          description:
            'Задание: поля договора, периода работ, основания и № техкарты; выбор формы ТО при создании; данные уходят в отчёт.',
        },
        {
          type: 'added',
          description:
            'Мобильное: выпадающие формулировки разд. 14–15 и оперативной диагностики; поля класса опасности и расчётной толщины элементов.',
        },
        {
          type: 'improved',
          description:
            'Форма ТО to-1: заполнение титула/разд.1–15, «Не предоставлено», местонахождение в шапке приложений, приборы ВИК (шероховатость/освещённость).',
        },
      ],
    },
    {
      version: '3.7.8',
      date: '17.07.2026',
      type: 'patch',
      changes: [
        {
          type: 'fixed',
          description:
            'Форма ТО to-1: заполнение титула и разделов 1–15 (раньше не заполнялись из-за content control); местонахождение оборудования в шапке приложений; статус «Не предоставлено» для документов; читаемые размеры/марки стали; исправлено задвоение «Таблица № 6».',
        },
        {
          type: 'improved',
          description:
            'Мобильное: поля класса опасности / взрыво- и пожароопасности, расчётной толщины элементов, объёма контроля и формулировок разд. 14–15 для отчёта.',
        },
      ],
    },
    {
      version: '3.7.7',
      date: '10.07.2026',
      type: 'patch',
      changes: [
        {
          type: 'improved',
          description:
            'Мобильное: схема контроля на карте обследования; блокировка подписания без таблички/схемы/УЗТ/заключения; предупреждение при синхронизации неполных данных.',
        },
        {
          type: 'improved',
          description:
            'Светлая тема: заголовки и текст на панелях читаемы (вместо белого на белом).',
        },
        {
          type: 'added',
          description:
            'Нормативные документы: загрузка и скачивание PDF/DOC/DOCX.',
        },
        {
          type: 'added',
          description:
            'Шаблоны отчётов: просмотр состава разделов шаблона.',
        },
        {
          type: 'improved',
          description:
            'Русские подписи типов обследований и статусов; официальные формы ТО заполняются полями мобильного чек-листа.',
        },
      ],
    },
    {
      version: '3.7.6',
      date: '10.07.2026',
      type: 'patch',
      changes: [
        {
          type: 'added',
          description:
            'Официальные формы ТО: генерация Word по шаблону; to-1/to-13/to-25; PDF через LibreOffice.',
        },
      ],
    },
    {
      version: '3.7.5',
      date: '09.07.2026',
      type: 'patch',
      changes: [
        {
          type: 'improved',
          description:
            'Технический отчёт: все приложения 1–10 всегда в документе; данные ЗРА/СППК, УЗТ, схемы, сканы документов и фото из мобильного чек-листа.',
        },
        {
          type: 'improved',
          description:
            'Генерация отчётов: кнопки-иконки, порядок ТО → ЭПБ; экспертиза доступна только после технического отчёта.',
        },
        {
          type: 'added',
          description:
            'В отчёт включаются все фото точек УЗТ, схемы uzt_schemes, мульти-комплекты сканов документов и фото объекта.',
        },
      ],
    },
    {
      version: '3.7.4',
      date: '24.06.2026',
      type: 'patch',
      changes: [
        {
          type: 'added',
          description:
            'Отчёт ТО/ЭПБ: справочник «Данные отчёта» (основания, заказчик, организация ТД, НД, шапки приложений, шаблоны выводов).',
        },
        {
          type: 'improved',
          description:
            'Word-отчёт: титул, статическое содержание, таблицы №1–10, документы с количеством страниц, выводы, фото подписей, шапки приложений из справочника.',
        },
        {
          type: 'improved',
          description:
            'Мобильное: поле «Количество страниц» в документах, таблица предыдущих обследований, варианты заключения «Соответствует / Не соответствует / Ограниченно».',
        },
      ],
    },
    {
      version: '3.7.3',
      date: '24.06.2026',
      type: 'patch',
      changes: [
        {
          type: 'fixed',
          description:
            'Мобильное: исправлен белый экран после выбора шаблона обследования или формы технического отчёта (ошибка вызова buildProgressIndicator).',
        },
        {
          type: 'improved',
          description:
            'Мобильное: обновлены подписи разделов навигации (добавлен раздел «Паспортные данные»).',
        },
        {
          type: 'changed',
          description:
            'Системный релиз 3.7.3: web/backend 3.7.3, mobile 3.7.3+40; деплой 24.06.2026 на neftcontrol.ru.',
        },
      ],
    },
    {
      version: '3.7.2',
      date: '24.06.2026',
      type: 'minor',
      changes: [
        {
          type: 'improved',
          description:
            'Мобильное: плоский список заданий с вкладками по статусу, поиск и сортировка; навигация по разделам отчёта через кнопку вместо всплывающего меню.',
        },
        {
          type: 'improved',
          description:
            'Мобильное: выбор формы технического отчёта при старте обследования; разделы и документы соответствуют реестру форм ТО.',
        },
        {
          type: 'improved',
          description:
            'Веб: табличный вид и сортировка на странице сотрудников; поиск и сортировка инженеров в компетенциях; фильтры реестра приборов открыты по умолчанию.',
        },
        {
          type: 'improved',
          description:
            'Веб: вкладки и поиск на карточке оборудования; сортировка столбцов в журнале поверок.',
        },
        {
          type: 'changed',
          description:
            'Системный релиз 3.7.2: web/backend 3.7.2, mobile 3.7.2+39; деплой 24.06.2026 на neftcontrol.ru.',
        },
      ],
    },
    {
      version: '3.7.1',
      date: '17.06.2026',
      type: 'patch',
      changes: [
        {
          type: 'added',
          description:
            'Единый реестр профилей оборудования (`equipment_profiles.py`): отстойник, газосепаратор, ёмкость, сосуд — API `/api/equipment-profiles/resolve`.',
        },
        {
          type: 'added',
          description:
            'Заключение ЭПБ: приложение Б (таблицы Б1–Б6), протоколы №3–№6 (твердометрия, УЗТ 108 точек, МПК, УЗК), приложение Е (расчёт остаточного ресурса) — формат образца 25-3173.',
        },
        {
          type: 'added',
          description:
            'Веб: форма диагностики и карточка оборудования подключаются к `/api/equipment-profiles/resolve` — автоподстановка паспортных данных и полей ЭПБ.',
        },
        {
          type: 'improved',
          description:
            'Мобильное: страница «Паспорт (прил. Б)», точки твердометрии Т.1–Т.5, метод контроля MPK/UZK, merge шаблона с 108 точками УЗТ для отстойника.',
        },
        {
          type: 'changed',
          description:
            'Системный релиз 3.7.1: web/backend 3.7.1, mobile 3.7.1+38; деплой 17.06.2026 на neftcontrol.ru.',
        },
      ],
    },
    {
      version: '3.7.0',
      date: '02.06.2026',
      type: 'minor',
      changes: [
        {
          type: 'added',
          description:
            'Иерархия оборудования (веб): редактирование и удаление предприятий, филиалов, цехов, типов и единиц оборудования.',
        },
        {
          type: 'added',
          description:
            'CRUD сотрудников (Users API): создание, редактирование и удаление учётных записей инженеров и операторов.',
        },
        {
          type: 'improved',
          description:
            'Мобильное: автосохранение чек-листа при смене шага и восстановление черновика (документы, ОПО, схемы УЗТ).',
        },
        {
          type: 'improved',
          description:
            'Мобильное: выбор организации из справочника, мультивыбор исполнителей, несколько комплектов документов (п.15, п.17).',
        },
        {
          type: 'added',
          description:
            'Мобильное: управление иерархией (admin) — экран дерева, удаление оборудования долгим нажатием.',
        },
        {
          type: 'changed',
          description:
            'Системный релиз 3.7.0: web 3.7.0, backend 3.7.0, mobile 3.7.0+37; деплой 02.06.2026 на neftcontrol.ru.',
        },
      ],
    },
    {
      version: '3.6.0',
      date: '15.05.2026',
      type: 'minor',
      changes: [
        {
          type: 'added',
          description:
            'Матрица обследований xlsx в мастере «Новый протокол»: НиВО, ГИ (ПИ + АЭ), ТД, ЭПБ; хаб испытаний; отдельный протокол акустико-эмиссионного контроля (АЭ).',
        },
        {
          type: 'added',
          description:
            'Шаблоны обследования объектов: API `/api/inspection-object-templates`, предзаполнение чек-листа при выборе оборудования; веб-раздел «Шаблоны обследования».',
        },
        {
          type: 'added',
          description:
            'Опытная база: CRUD `/api/experience-base`, контекст по объекту, вкладки в мобильном приложении и подсказки при создании акта.',
        },
        {
          type: 'added',
          description:
            'Редактируемое меню диагностики на сервере (черновик/публикация); веб «Меню диагностики»; мобильное меню загружается с API с fallback.',
        },
        {
          type: 'added',
          description:
            'Шаблоны быстрого контроля (ВИК, УЗТ, УЗК, ПВК, ГИ, ПИ, аварийный осмотр): API `protocol-templates/by-quick-control/{code}`.',
        },
        {
          type: 'improved',
          description:
            'Мобильное: ТД открывает полный акт (чек-лист с NDT), ГИ/ПИ — выбор объекта и опрессовка; офлайн-очередь опросников и НК с фото (sync v6).',
        },
        {
          type: 'added',
          description: 'Мобильное: экран настроек, улучшенная синхронизация и профиль.',
        },
        {
          type: 'changed',
          description:
            'Системный релиз 3.6.0: web 3.6.0, backend 3.6.0, mobile 3.6.0+36; деплой на neftcontrol.ru и APK в /mobile/.',
        },
      ],
    },
    {
      version: '3.5.0',
      date: '06.05.2026',
      type: 'minor',
      changes: [
        {
          type: 'changed',
          description:
            'Системный релиз 3.5.0: web 3.5.0, backend 3.5.0, mobile 3.5.0+35; деплой на neftcontrol.ru и обновлённый APK в /mobile/.',
        },
      ],
    },
    {
      version: '3.32.0',
      date: '06.05.2026',
      type: 'patch',
      changes: [
        {
          type: 'fixed',
          description:
            'Backend: автомиграция колонок clients (phone, email и др.) — раздел управления проектами без ошибки UndefinedColumn.',
        },
        {
          type: 'fixed',
          description:
            'Отчёты PDF/DOCX: вложения и фото только из данных текущего обследования/опросника; убран глобальный поиск файла по имени.',
        },
        { type: 'changed', description: 'Системный релиз 3.32.0: web 3.32.0, backend 3.32.0, mobile 3.32.0+34.' },
      ],
    },
    {
      version: '3.31.0',
      date: '06.05.2026',
      type: 'minor',
      changes: [
        {
          type: 'added',
          description:
            'API и DOCX для «автономных» протоколов из мобильного приложения: POST/GET `/api/standalone-protocols`, скачивание `/api/standalone-protocols/{id}/download`.',
        },
        {
          type: 'improved',
          description:
            'Мобильное: нижние кнопки обследований и протоколов учитывают системную навигационную панель Android (Safe Area / отступы).',
        },
        {
          type: 'improved',
          description:
            'Мобильное: завершение быстрого контроля ВИК/УЗТ, протокола НК и шаблонного протокола отправляет запись на сервер; реестр протоколов подтягивает список с сервера.',
        },
        {
          type: 'added',
          description:
            'Веб «Генерация отчётов»: блок «Протоколы только с телефона» со списком и кнопкой «Скачать DOCX» без привязки к чек-листу.',
        },
        { type: 'changed', description: 'Системный релиз 3.31.0: web 3.31.0, backend 3.31.0, mobile 3.31.0+33.' },
      ],
    },
    {
      version: '3.30.2',
      date: '05.05.2026',
      type: 'patch',
      changes: [
        { type: 'fixed', description: 'Светлая тема: раздел «Проекты» и модалки поверочного оборудования — читаемые цвета вместо фиксированного bg-secondary.' },
        { type: 'fixed', description: 'Поверки: кнопка «Статистика» — API usage по связи обследований с поверочным оборудованием; алиас экспорта /export/csv.' },
        { type: 'added', description: 'Поверки: проверка сведений в публичном фонде ФГИС «Аршин» (прокси-запрос с бэкенда, кнопка в форме прибора).' },
        { type: 'changed', description: 'Системный релиз 3.30.2: web 3.30.2, backend 3.30.2, mobile 3.30.2+32.' },
      ],
    },
    {
      version: '3.30.1',
      date: '05.05.2026',
      type: 'patch',
      changes: [
        { type: 'added', description: 'Скрипт backend/scripts/seed_demo_data.py — идемпотентные демо-данные: клиент, предприятие, ОПО, оборудование (сосуд/трубопровод), инженеры и пользователи demo.*, поверочные приборы, реестр приборов, задания всех типов, обследование с дефектами в JSON, методы НК, сегмент трубопровода, шаблон чертежа с точками, шаблон отчёта, запись protocol_templates; встроенная verify() после загрузки.' },
        { type: 'added', description: 'Демо-пользователь demo.client с доступом к оборудованию (user_equipment_access), опросный лист, отчёт и нормативный документ для полноты стенда.' },
        { type: 'fixed', description: 'Ведомость дефектов: импорт из обследований учитывает ответ API { items }, поле data и date_performed; объединение checklist_data с data; подтягивание визуальных дефектов из visual_defects.' },
        { type: 'changed', description: 'Системный релиз 3.30.1: web 3.30.1, backend 3.30.1, mobile 3.30.1+31.' },
      ],
    },
    {
      version: '3.30.0',
      date: '19.04.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Наблюдаемость: интеграция Sentry на backend/frontend/mobile (включается переменной SENTRY_DSN), Prometheus-совместимый /metrics на FastAPI (http_requests_total, http_request_duration_seconds, report_generation_seconds, auth_login_total), structured logging через loguru (JSON в проде), новый /ready endpoint для readiness probe.' },
        { type: 'added', description: 'Безопасность: 2FA TOTP (pyotp) — новый роутер /api/auth/2fa/{setup,enable,disable,verify,status}, QR-код для Google/Yandex Authenticator, 8 одноразовых recovery-кодов; rate-limit через slowapi (10/min на /auth/login, 5/min на /auth/2fa/verify); блокировка аккаунта после 5 провалов на 15 минут (HTTP 423); единая политика паролей (минимум 10 символов, 3 класса, блок-лист).' },
        { type: 'added', description: 'RBAC: единая матрица прав в backend/security.py (PERMISSION_MATRIX), новая dependency-фабрика require_rbac("users.write") — fail-closed на неизвестные permissions; старый require_permission сохранён для совместимости.' },
        { type: 'added', description: 'Доменный движок: новый пакет backend/diagnostic_engine с расчётом остаточного ресурса по РД 09-539-03 (учёт опасности ОПО через safety_factor), конструктором заключения ЭПБ сосуда по СА 03-008-08, картой объект × метод НК → нормы (NORMS_MAP); API /api/diagnostic/residual-life, /api/diagnostic/epb-vessel, /api/diagnostic/norms; покрытие тестами.' },
        { type: 'added', description: 'Подлинность PDF-заключений: QR-штамп на последней странице со ссылкой /api/verify/report/{token}, публичная верификация (метаданные + sha256), проверка целостности загруженного PDF (POST .../check-hash), реестр report_signatures с полем revoked_at для отзыва; подготовлен hook для PAdES-T (pyhanko, включается PADES_ENABLED=1).' },
        { type: 'added', description: 'Инфраструктура: email-service (aiosmtplib, dry-run если SMTP_HOST пуст), шаблоны welcome/report-ready; очередь фоновых задач (FastAPI BackgroundTasks с ограничением параллелизма) — интерфейс готов для миграции на Celery+Redis; staging-compose (docker-compose.staging.yml) с изолированным SENTRY_ENVIRONMENT=staging.' },
        { type: 'added', description: 'Документация: новый README с архитектурной схемой, ADR-записи 0001 (observability), 0002 (RBAC+2FA), 0003 (diagnostic engine), 0004 (PDF verification/PAdES).' },
        { type: 'improved', description: 'nginx: добавлены security-заголовки HSTS (max-age=1 год, includeSubDomains), X-Content-Type-Options nosniff, X-Frame-Options SAMEORIGIN, Referrer-Policy strict-origin-when-cross-origin, Permissions-Policy для geolocation/camera.' },
        { type: 'improved', description: 'БД: новые колонки users.totp_secret, totp_enabled, totp_recovery_codes, failed_login_count, locked_until; новая таблица report_signatures с индексами по report_id, verification_token, signed_at.' },
        { type: 'changed', description: 'Системный релиз 3.30.0: web 3.30.0, backend 3.30.0, mobile 3.30.0+30. requirements.txt пополнен (sentry-sdk, prometheus-client, loguru, slowapi, pyotp, qrcode, aiosmtplib, pypdf). package.json: @sentry/react. pubspec.yaml: sentry_flutter.' },
      ],
    },
    {
      version: '3.29.0',
      date: '19.04.2026',
      type: 'minor',
      changes: [
        { type: 'improved', description: 'Mobile UI: SyncScreen полностью переработан — новый индикатор сети (онлайн/офлайн чип с glow), статистические плитки «В очереди / Черновики / Подписаны» с tabular-figures, компактный блок разбивки SIGNED (Готовы / Проверить), моно-дата последней синхронизации и прогресс-бар аплоада с МБ/сек.' },
        { type: 'improved', description: 'Mobile UI: AssignmentsScreen — новый AppBar с бейджем количества активных заданий, прозрачный фильтр-индикатор в акцентном цвете, переработанный empty-state с круглой иконкой на поверхности и подсказкой вместо плоского текста.' },
        { type: 'improved', description: 'Mobile UI: ProfileScreen — шапка с круглым avatar-инициалом (AA) в акцентном glow, pill-бейдж роли, плотные info-карточки с моноширинной версией, чистая типографика −0.2 letter-spacing и редизайн версии приложения.' },
        { type: 'improved', description: 'Mobile: унификация AppBar по тёмному indicator-стилю — backgroundDeep, без теней, заголовки 16 px / w600 / letter-spacing −0.2, иконки 20 px для стыковки с вебом.' },
        { type: 'improved', description: 'Deploy hardening: .dockerignore расширен (backend/uploads|reports|certs, mobile-apk, __pycache__, terminals) — frontend build context сжался с 1.6 GB до десятков MB, устранены OOM-обрывы по SSH при vite build на VPS.' },
        { type: 'improved', description: 'deploy-ssh.ps1 теперь копирует .dockerignore и vite-env.d.ts на сервер, чтобы локальные исключения контекста применялись и в проде.' },
        { type: 'fixed', description: 'Security: .env удалён из git-индекса (git rm --cached); файл уже был в .gitignore, но отслеживался исторически — креды БД и JWT в историю не попадали, теперь защита от случайного коммита.' },
        { type: 'changed', description: 'Системный релиз 3.29.0: синхронизированы версии web 3.29.0, backend 3.29.0, mobile 3.29.0+29.' },
      ],
    },
    {
      version: '3.28.0',
      date: '19.04.2026',
      type: 'minor',
      changes: [
        { type: 'improved', description: 'Web UI: редизайн AdminPanel и UsersManagement в индустриальной data-dense эстетике 2026 — единые стили sp-surface, sp-stat, sp-pill-nav, ind-chip с семантическими цветами и tabular-nums.' },
        { type: 'improved', description: 'Web UI: EquipmentHierarchyTree переведён на CSS-токены (var(--accent), var(--success), var(--warning)) вместо 32 hardcoded slate/blue/green цветов; вложенные уровни с пунктирными разделителями.' },
        { type: 'improved', description: 'Web UI: ReportsAndExpertise — breadcrumb и заголовок раздела переведены на дизайн-токены, добавлена плавная анимация sp-animate-in.' },
        { type: 'improved', description: 'Web CSS: добавлены алиасы ind-chip--success/--warning/--warn/--ok и sp-pill-nav__item для совместимости стилей между страницами.' },
        { type: 'improved', description: 'Mobile UI: equipment_list_screen — компактные плоские группы с ind-style border, dense type/дропдауны, chips счётчиков с AppColors.accent, 1-2 строки типографики вместо 4.' },
        { type: 'improved', description: 'Mobile UI: protocols_registry_screen — таблица реестра с 10.5px моноширинной датой, pill-статусами (success/warning с border), уплотнённая шапка и строки.' },
        { type: 'improved', description: 'Mobile UI: opo_list_screen — карточки со squircle-иконкой на warning-фоне, двухстрочное название с letter-spacing, chevron-стрелка вместо edit-кнопки.' },
        { type: 'fixed', description: 'Deploy: скрипт deploy-ssh.ps1 собирает backend и frontend последовательно без --no-cache — устранён OOM на VPS с 3–4 ГБ RAM, BUILD_REF по-прежнему инвалидирует frontend-слой.' },
        { type: 'changed', description: 'Системный релиз 3.28.0: синхронизированы версии web/backend/mobile.' },
      ],
    },
    {
      version: '3.27.0',
      date: '19.04.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Шаблоны чертежей с точками замеров: новый модуль «Шаблоны чертежей» (/drawing-templates) — загрузка растровых схем (PNG/JPG) с привязкой к конкретному оборудованию или типу оборудования, расстановка точек замеров прямо на изображении через интерактивный редактор с pan/zoom.' },
        { type: 'added', description: 'Бэкенд: новые модели DrawingTemplate и DrawingTemplatePoint, миграция Alembic 005, эндпоинты POST/GET/PATCH/DELETE /api/drawing-templates с отдачей изображений, загрузкой файлов и синхронизацией delta.' },
        { type: 'added', description: 'Мобильное: новые экраны выбора шаблона чертежа из библиотеки (drawing_template_picker) и аннотирования (drawing_annotation) с отображением предопределённых точек, перетаскиванием и добавлением новых; offline-кэш изображений и точек через sqflite.' },
        { type: 'added', description: 'Мобильное: интеграция «Шаблон из библиотеки» в экран толщинометрии (ThicknessMeasurementScreen) — точки замеров из веб-шаблона автоматически подтягиваются в форму замеров.' },
        { type: 'added', description: 'Мобильное: delta-синхронизация drawing templates в SyncService с префетчем для всех заданий инженера.' },
        { type: 'added', description: 'Карточка оборудования: новый блок «Шаблоны чертежей» показывает привязанные к объекту чертежи с переходом в редактор.' },
        { type: 'improved', description: 'Web UI: расширена индустриальная data-dense эстетика — новые CSS-токены sp-surface, sp-stat, sp-pill-nav, sp-progress, sp-skeleton, focus-visible; редизайн Dashboard, AssignmentsManagement, VerificationsManagement, EquipmentManagement с семантическими цветами и tabular-nums.' },
        { type: 'improved', description: 'Mobile UI: новая тема AppTheme 2026 — плотность −1/−1, современная типографика с отрицательным letter-spacing, плоские карточки; обновлённая карточка задания с 3px статусной полосой, pill-чипами статуса/приоритета и компактным индикатором sync.' },
        { type: 'fixed', description: 'Mobile: исправлены координаты точек на экранах ImageAnnotationScreen и WeldDefectAnnotationScreen — переход с глобальных координат на details.localPosition устранил смещение точек при тапе.' },
        { type: 'fixed', description: 'Mobile: VesselInspectionScreen — нижняя навигация страниц теперь корректно учитывает SafeArea и не перекрывается системной панелью Android.' },
        { type: 'fixed', description: 'Web: устранены все pre-existing TypeScript-ошибки (unused imports, import.meta.env, несовместимость LucideIcon) — tsc --noEmit проходит чисто, CI больше не засоряется.' },
        { type: 'changed', description: 'Системный релиз 3.27.0: синхронизированы версии web/backend/mobile.' },
      ],
    },
    {
      version: '3.26.0',
      date: '07.04.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Мобильное: меню «Создать» — пункт «Акт ТД (ЭПБ) оборудования» теперь открывает экран выбора объекта из базы (поиск, фильтр по типу) с прямым переходом к созданию акта.' },
        { type: 'added', description: 'Мобильное: новый экран «Новый протокол НК» — выбор методов контроля (ВИК, УЗТ; УЗК и ПВК/МПД — скоро), динамическая форма протокола по выбранным методам.' },
        { type: 'added', description: 'Мобильное: «Продолжить контроль» — реестр черновиков теперь открывает нужный экран (QuickControl / НК-протокол / Свой шаблон) с восстановлением всех заполненных данных.' },
        { type: 'added', description: 'Мобильное: «Ведомость дефектов» — официальный бланк результатов НК с автозаполнением из VIK-дефектов и UZT-замеров, статистикой, фильтром по степени, заключением и подписями.' },
        { type: 'added', description: 'Мобильное: PDF-экспорт ведомости дефектов с кириллическими шрифтами (NotoSans через printing/pdf), диалог печати и сохранения.' },
        { type: 'added', description: 'Мобильное: реестр протоколов/актов — переведён на единую таблицу (Дата | Объект | Вид контроля | Статус) с зелёным/красным цветом статуса, как в требованиях.' },
        { type: 'added', description: 'Мобильное: реестр приборов — переведён на компактную таблицу (№ | Наименование | Тип | Поверка до | Состояние | Специалист) с цветовой индикацией срока поверки и состояния.' },
        { type: 'added', description: 'Веб: новый раздел «Ведомость дефектов» (/defect-statement) — импорт из обследования, редактируемая таблица дефектов, автозаключение, фильтр по степени, печать/PDF через браузер.' },
        { type: 'added', description: 'Веб: конструктор протоколов/актов (/protocol-constructor) — создание и управление шаблонами протоколов с блочным редактором (секции, таблицы, поля, фото, подписи и др.).' },
        { type: 'added', description: 'Веб: корзина удалённых обследований (/inspections-trash) — просмотр мягко удалённых записей, восстановление в течение 60 дней, принудительная очистка для admin.' },
        { type: 'added', description: 'П.5.1 — Защита от случайного удаления: мягкое удаление (soft-delete) обследований с 60-дневным периодом восстановления; физическое удаление только по команде admin (purge). Все GET-запросы автоматически скрывают удалённые записи.' },
        { type: 'added', description: 'Бэкенд: новые endpoints — POST /api/inspections/{id}/restore, GET /api/inspections-trash, DELETE /api/inspections-trash/purge; миграция Alembic 004 (поля is_deleted, deleted_at, deleted_by в таблице inspections).' },
        { type: 'added', description: 'Мобильное: «Быстрый контроль ВИК/УЗТ» — реальное сохранение черновиков через AutoSaveService, восстановление всех полей, фотографий и таблиц при повторном открытии.' },
        { type: 'added', description: 'Мобильное: «Свой протокол / акт» — сохранение и восстановление черновиков шаблонных протоколов через AutoSaveService.' },
        { type: 'improved', description: 'Мобильное: AutoSaveService расширен методом saveGenericDraft с поддержкой типов экранов (quick_control, ndk_protocol, custom_protocol) для унифицированного сохранения черновиков.' },
      ],
    },
    {
      version: '3.25.0',
      date: '31.03.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Клиентский портал: фильтрация оборудования, обследований и отчётов по роли client; скачивание отчётов с Bearer; маршрут только для client; привязка через enterprises.client_id и проекты.' },
        { type: 'added', description: 'Календарь поверок: корректные локальные даты, неделя с понедельника, легенда сроков; API фильтр is_active по boolean.' },
        { type: 'added', description: 'Карта трубопроводов: GET /api/pipeline-map/segments из БД и coordinates в attributes оборудования; демо при отсутствии геоданных.' },
        { type: 'added', description: 'Миграция Alembic 003 (enterprises.client_id), загрузка .env в alembic/env.py; DB_SSLMODE=disable для локального Postgres без TLS.' },
        { type: 'changed', description: 'Имя продукта в интерфейсе: «Монитор» (кодовое имя SystemaPro / ЕС ТД НГО) — веб, мобильное приложение, OpenAPI.' },
        { type: 'added', description: 'Системный релиз 3.25.0: синхронизированы версии web/backend/mobile и обновлён раздел «Что нового».' },
        { type: 'improved', description: 'Web UI-kit (phase 1): добавлены единые классы sp-card, sp-card-soft, sp-section-title, sp-badge и sp-btn-subtle для сквозного современного интерфейса.' },
        { type: 'improved', description: 'Web отчёты: страницы ReportGeneration и ReportViewer переведены на унифицированный визуальный каркас без потери функциональности.' },
        { type: 'added', description: 'Web отчёты: предпросмотр PDF/DOCX, сохранение/сброс фильтров, фильтр по типу отчёта и единый формат дат (ДД.ММ.ГГГГ).' },
        { type: 'added', description: 'Проверка полноты отчёта в web: показ missing_fields/warnings в предпросмотре и просмотре отчёта перед генерацией.' },
        { type: 'improved', description: 'Backend валидация отчётов: обязательные поля (организация, исполнители, фото таблички, схема контроля) и предупреждения по данным толщинометрии.' },
        { type: 'improved', description: 'Backend загрузка фото НК: нормализация MIME и ограничение размера файлов для более надёжной обработки.' },
        { type: 'improved', description: 'Mobile синхронизация: ретраи отправки архивов, индикация online/offline, сводка готовности подписанных отчётов и быстрые подсказки на экране синхронизации.' },
        { type: 'improved', description: 'Mobile задания: сохранение фильтров/поиска, быстрый сброс фильтров, очистка поиска в одно нажатие и унифицированный формат дат.' },
        { type: 'fixed', description: 'Mobile фото: полностью переработан штамп метаданных — дата/время и GPS в отдельных блоках, без наложения строк.' },
        { type: 'improved', description: 'Mobile фото: размер текста для даты/GPS теперь рассчитывается пропорционально размеру изображения (~1/15) с автоподгонкой по ширине.' },
      ],
    },
    {
      version: '3.24.0',
      date: '21.02.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Релиз 3.24: полная пересборка backend/frontend контейнеров и перезапуск на сервере' },
        { type: 'added', description: 'Обновлён раздел «Что нового» с актуальной версией и детальным списком изменений' },
        { type: 'improved', description: 'Стабилизирован деплой: копирование `styles/` при публикации, чтобы дизайн-токены всегда попадали в docker-сборку' },
        { type: 'improved', description: 'Web: унифицировано отображение версии на Dashboard, Changelog и TechSpecs' },
        { type: 'improved', description: 'Mobile: версия APK обновлена до 3.24.0+24 и повторно выложена на сервер' },
      ],
    },
    {
      version: '3.23.0',
      date: '09.02.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Группировка обследований по типам (VISUAL/NDT/QUESTIONNAIRE) в API и web-интерфейсе' },
        { type: 'added', description: 'Мобильное: выбор типа обследования перед началом работы по заданию' },
        { type: 'added', description: 'Точки УЗК: координаты x_percent, y_percent на схеме, отрисовка в отчёте' },
        { type: 'added', description: 'Овальность: редактирование по сечению, улучшенные подсказки' },
        { type: 'added', description: 'Схема контроля: выбор файла / фото / встроенный шаблон / шаблон с сервера' },
        { type: 'improved', description: 'Web-редизайн: дизайн-токены, обновленные Login/Dashboard, улучшенная читаемость и навигация' },
        { type: 'improved', description: 'Mobile-редизайн: устранены перекрытия элементов в экранах аннотаций и фотофиксации' },
        { type: 'added', description: 'Чек-листы (web): сохранение фильтров между сессиями и экспорт отфильтрованных данных в CSV' },
        { type: 'fixed', description: 'Backend: устранен Windows-краш импорта (cp1251) в database.py при запуске модулей отчетов' },
      ],
    },
    {
      version: '3.22.0',
      date: '09.02.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Toast-уведомления (ToastContext) вместо alert' },
        { type: 'added', description: 'Модальные подтверждения (ConfirmModal) для критичных действий' },
        { type: 'added', description: 'Скелетоны загрузки (Skeleton, SkeletonCard, SkeletonTable)' },
        { type: 'added', description: 'Глоссарий терминов (ВИК, УЗТ, ОПО и др.) — страница /glossary' },
        { type: 'added', description: 'Панель статистики на дашборде: обследования, отчёты, задания за период (API /api/stats)' },
        { type: 'added', description: 'Подсказки (Tooltip) для сложных полей' },
        { type: 'added', description: 'Утилиты: fetchWithRetry (повтор при сетевых ошибках), cache (localStorage)' },
        { type: 'added', description: 'Мобильное: явный офлайн-статус при отсутствии сети' },
        { type: 'added', description: 'Мобильное: краткая сводка перед подписанием чек-листа' },
      ],
    },
    {
      version: '3.21.0',
      date: '09.02.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Проверка сети перед синхронизацией: перед отправкой данных проверяется доступность API (/health); при отсутствии интернета показывается «Нет интернета», синхронизация не запускается' },
        { type: 'improved', description: 'Экран «Синхронизация»: при нажатии «Синхронизировать» сначала проверка соединения, затем отправка — не тратятся попытки без сети' },
        { type: 'improved', description: 'Экран «Задания»: при нажатии кнопки синхронизации заданий — та же проверка; при отсутствии сети — сообщение без запросов к серверу' },
        { type: 'improved', description: 'Фоновая задача периодической синхронизации (Workmanager): при отсутствии доступа к API синхронизация не выполняется' },
        { type: 'added', description: 'Документ CHAT-SUMMARY.md: выжимка контекста системы, что сделано по улучшениям, приоритеты развития и следующие шаги' },
      ],
    },
    {
      version: '3.20.0',
      date: '03.02.2026',
      type: 'minor',
      changes: [
        { type: 'improved', description: 'Специалисты: API возвращает method_code как в БД (ВИК, УЗК и т.д.) — специалисты с удостоверениями корректно подходят при выборе по методу НК' },
        { type: 'improved', description: 'Отчёты: фото дефектов ВИК подставляются из загруженных document_files (ключи vd_i_j) при синхронизации с мобильного, если путь в data не разрешается' },
        { type: 'improved', description: 'Офлайн-вход: кнопка «Войти офлайн» всегда показывается при наличии сохранённого пользователя' },
        { type: 'added', description: 'Экран синхронизации: кнопка «Подключиться и синхронизировать» и сообщения при частичной синхронизации (чек отправлен, фото — повторить позже)' },
        { type: 'fixed', description: 'Мобильное приложение: фото таблички и схемы контроля сохраняются в постоянную папку приложения для корректной синхронизации' },
        { type: 'fixed', description: 'Список ожидающих синхронизации не очищается при выходе — можно повторить загрузку файлов после повторного входа' },
        { type: 'fixed', description: 'Устранён дубликат эндпоинта get_engineers — используется реализация с подтягиванием сертификатов из Certification' },
      ],
    },
    {
      version: '3.18.0',
      date: '28.01.2026',
      type: 'minor',
      changes: [
        { type: 'improved', description: 'Фото в заданиях и отчётах: корректное прикрепление фото заводской таблички и схемы контроля в опросном листе и при генерации отчётов' },
        { type: 'improved', description: 'Улучшено разрешение путей к изображениям в отчётах (questionnaire_documents) — фото надёжно подставляются в PDF и на сайте' },
        { type: 'fixed', description: 'Офлайн: при отсутствии токена открытие задания использует кэш оборудования, без ошибки «Токен авторизации не найден»' },
      ],
    },
    {
      version: '3.17.0',
      date: '30.01.2026',
      type: 'minor',
      changes: [
        { type: 'fixed', description: 'Офлайн-режим: при запуске без интернета больше не показываются ошибки — приложение запрашивает PIN и работает с сохранёнными данными' },
        { type: 'improved', description: 'При открытии задания без сети оборудование подгружается из кэша, экран обследования открывается без ошибки "Network is unreachable"' },
        { type: 'added', description: 'Возможность продолжить черновик отчёта: после "Сохранить черновик" можно снова открыть задание, отредактировать и подписать; при синхронизации отчёт отправляется на сервер' },
        { type: 'fixed', description: 'Картинки в отчётах: в отчёт и при просмотре на сайте подставляются схема УЗК с точками, фото заводской таблички и фото дефектов ВИК из базы' },
        { type: 'fixed', description: 'Исправлено создание опросного листа при отправке инспекции с сервера — картинки документов сохраняются и привязываются к отчёту' },
        { type: 'fixed', description: 'Ошибка "column questionnaires.assignment_id does not exist" при генерации отчёта устранена' },
      ],
    },
    {
      version: '3.12.0',
      date: '25.01.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Полный просмотр отчета в веб‑системе с отображением всех приложений и вложений' },
        { type: 'added', description: 'Централизованное хранение фото НК на сервере и загрузка через API' },
        { type: 'added', description: 'Миграция старых сканов поверок в новую структуру хранения' },
        { type: 'added', description: 'PIN‑вход в мобильном приложении с возможностью установки/отключения пользователем' },
      ],
    },
    {
      version: '3.11.0',
      date: '20.01.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Группировка отчетов и чек-листов по предприятиям и цехам с раскрывающимся списком' },
        { type: 'added', description: 'Архивирование и удаление отчетов и чек-листов' },
        { type: 'fixed', description: 'Исправлено дублирование отправки отчетов из мобильного приложения (черновики не отправляются автоматически)' },
        { type: 'improved', description: 'Логика "начать заново" для выполненных заданий: выбор между "пройти заново" и "внести изменения"' },
        { type: 'added', description: 'Группировка оборудования по ОПО на сервере и в мобильном приложении' },
        { type: 'added', description: 'Выбор ОПО при начале диагностики, если оно не задано на сервере' },
        { type: 'added', description: 'Автоматическая загрузка списка ОПО предприятия при синхронизации' },
        { type: 'improved', description: 'Чек-лист для ОПО: заполнение данных по ОПО (пункты 1-9) с возможностью прикрепления документов' },
        { type: 'improved', description: 'Синхронизация ОПО опросников с сервером' },
      ],
    },
    {
      version: '3.10.0',
      date: '20.01.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Новая генерация отчетов для сосудов и ресиверов по образцу технических отчетов с полной структурой разделов 1-15 и приложений' },
        { type: 'added', description: 'Автоматическое определение типа оборудования для генерации специализированных отчетов' },
        { type: 'added', description: 'Шаблоны чертежей сосудов: автоматическое использование шаблона, если не загружено фото схемы контроля' },
        { type: 'added', description: 'API для получения шаблонов чертежей с сервера в мобильном приложении' },
        { type: 'improved', description: 'Мобильное приложение: загрузка стандартных чертежей с сервера для работы с точками замера' },
        { type: 'improved', description: 'Отчеты для сосудов: добавлены все необходимые таблицы, протоколы и приложения согласно нормативной документации' },
        { type: 'improved', description: 'Структура отчетов: титульный лист, содержание, разделы 1-15, приложения с протоколами по каждому методу НК' },
        { type: 'added', description: 'Поддержка разных типов оборудования с возможностью расширения для других типов (трубопроводы, резервуары и т.д.)' },
      ],
    },
    {
      version: '3.9.0',
      date: '19.01.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Автосохранение черновиков при выходе/закрытии мобильного приложения' },
        { type: 'added', description: 'Фильтрация специалистов по методам контроля: показываются только те, у кого есть соответствующие удостоверения' },
        { type: 'added', description: 'Выбор методов контроля через галочки перед выбором специалистов' },
        { type: 'improved', description: 'Кнопки для фото таблички и схемы замеров теперь с понятными надписями' },
        { type: 'improved', description: 'Черновики отображаются в синхронизации как ожидающие синхронизации с детальной статистикой' },
        { type: 'improved', description: 'Генерация отчетов: добавлены чертежи с точками замера (координаты X, Y, толщина), фото заводской таблички в разделе ВИК' },
        { type: 'added', description: 'Отдельная вкладка ОПО для заполнения данных и привязки оборудования' },
        { type: 'added', description: 'Светлая тема для веб-системы с переключателем в боковом меню' },
        { type: 'improved', description: 'Офлайн вход: улучшена работа без интернета, вход по PIN/отпечатку' },
        { type: 'improved', description: 'Редизайн: улучшены переходы, анимации, расположение кнопок' },
      ],
    },
    {
      version: '3.8.1',
      date: '18.01.2026',
      type: 'patch',
      changes: [
        { type: 'added', description: 'Отдельные формы актов обследования по каждому методу НК в отчетах' },
        { type: 'improved', description: 'Расширена таблица технических характеристик по сосуду' },
        { type: 'improved', description: 'Опросный лист: документы и вложения прикрепляются в отчет' },
        { type: 'improved', description: 'ВИК: дефекты с фото/размерами добавлены в отчет' },
        { type: 'improved', description: 'УЗТ: схема контроля и таблицы точек измерения' },
        { type: 'improved', description: 'Синхронизация инженеров, заданий и поверок в мобильном приложении' },
        { type: 'added', description: 'Раздел "Что нового" на дашборде с переходом к истории изменений' },
      ],
    },
    {
      version: '3.8.0',
      date: '18.01.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Биометрическая аутентификация: вход по отпечатку пальца или PIN-коду в мобильном приложении' },
        { type: 'added', description: 'Привязка пользователя к устройству: безопасная локальная авторизация для офлайн-режима' },
        { type: 'improved', description: 'Офлайн-авторизация: пользователь может войти в приложение без интернета, используя биометрию или PIN' },
        { type: 'improved', description: 'Безопасность: токены и пароли хранятся в защищенном хранилище устройства' },
        { type: 'improved', description: 'UX мобильного приложения: автоматическое предложение биометрической аутентификации при первом входе' },
      ],
    },
    {
      version: '3.7.0',
      date: '13.01.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Задания (веб): для выполненных заданий добавлены действия “Просмотреть чек‑лист” и “Сгенерировать отчет”, чтобы всегда можно было открыть данные инженера и сделать диагностический отчет' },
        { type: 'added', description: 'Шаблоны отчетов: добавлен редактор макетов (визуальный + JSON), привязка шаблона к типу оборудования и загрузка логотипа для титульной страницы' },
        { type: 'improved', description: 'DOCX “Диагностический отчет”: генерация по структуре как в примере, подтягивание названия и характеристик из базы оборудования, поддержка логотипа на титуле' },
        { type: 'improved', description: 'Мобильное: сценарий “Сохранить (черновик)” и “Подписать/Завершить” (подписание готовит данные к отправке, а “выполнено” на сервере ставится только после успешной синхронизации)' },
        { type: 'improved', description: 'Мобильное: статусы по заданиям — “черновик локально / подписано локально / ожидает синхронизации”, чтобы не было путаницы' },
        { type: 'improved', description: 'Мобильное: иерархический список заданий (предприятие → филиал → цех) для удобной навигации' },
        { type: 'fixed', description: 'Версионирование и обновления: синхронизированы версии (web/backend/mobile) и улучшена автоматизация публикации APK' },
      ],
    },
    {
      version: '3.6.2',
      date: '12.01.2026',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Система аннотирования изображений для всех методов НК: возможность фотографировать чертежи и обводить дефекты стилусом/пальцем' },
        { type: 'added', description: 'Специальный экран для дефектов сварных швов: выбор типа дефекта (пористость, трещина, включение, подрез и т.д.) с характеристиками' },
        { type: 'added', description: 'Аннотированные изображения включаются в отчеты: схемы с обведенными дефектами автоматически добавляются в отчет' },
        { type: 'improved', description: 'Генерация отчетов: улучшено отображение документов специалистов и поверенного оборудования с приложенными сканами' },
        { type: 'improved', description: 'Чек-листы: улучшено отображение всех приложенных документов с размерами файлов и прямыми ссылками на просмотр' },
        { type: 'fixed', description: 'Календарь поверок: исправлена ошибка отображения' },
      ],
    },
    {
      version: '3.6.0',
      date: '23.12.2025',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Система управления поверками оборудования: полный цикл управления оборудованием для поверок' },
        { type: 'added', description: 'Календарь поверок: визуализация сроков поверок с цветовой индикацией (просрочено, истекает ≤7 дней, ≤30 дней)' },
        { type: 'added', description: 'Уведомления о сроках поверок на главной странице (Dashboard) с предупреждениями за 30, 14 и 7 дней' },
        { type: 'added', description: 'Мобильное приложение: выбор поверенного оборудования перед началом работ с валидацией' },
        { type: 'added', description: 'Мобильное приложение: автоматическое включение информации об используемом оборудовании в отчеты' },
        { type: 'added', description: 'Отчеты: автоматическое добавление раздела "Оборудование, использованное при диагностировании" с приложенными сканами поверок' },
        { type: 'added', description: 'История поверок: просмотр полной истории поверок для каждого оборудования' },
        { type: 'added', description: 'Экспорт списка оборудования для поверок в CSV с фильтрацией по срокам и типам' },
        { type: 'added', description: 'Статистика использования оборудования: анализ частоты использования оборудования в обследованиях' },
        { type: 'added', description: 'Категории оборудования: автоподстановка типов оборудования (ВИК, УЗК, ПВК, РК, МК, ВК, ТК)' },
        { type: 'improved', description: 'Валидация: нельзя начать обследование без выбора поверенного оборудования в мобильном приложении' },
        { type: 'improved', description: 'Интеграция: оборудование для поверок автоматически привязывается к обследованиям и включается в отчеты' },
      ],
    },
    {
      version: '3.5.1',
      date: '16.12.2025',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Задания: обзор назначений по объектам (предприятие/филиал/цех/оборудование) + прогресс-бар выполнено/всего' },
        { type: 'added', description: 'Чек-листы: названия документов в “Перечень рассмотренных документов” как в мобильном приложении' },
        { type: 'added', description: 'Чек-листы: просмотр прикрепленных файлов (сканы/фото) прямо в браузере (inline view)' },
        { type: 'added', description: 'Чек-листы: отображение всех “прочих вложений” (помимо стандартных документов и системных фото)' },
        { type: 'added', description: 'Отчеты/чек-листы: удаление (RBAC) — admin/operator могут удалять любые, инженер только свои' },
        { type: 'added', description: 'Очистка: массовое удаление старых отчетов и чек-листов по сроку хранения' },
        { type: 'fixed', description: 'DOCX/PDF генерация: исправлены ошибки формирования и корректные MIME/имя файла для DOCX' },
        { type: 'fixed', description: 'PDF: исправлено отображение кириллицы (шрифты с поддержкой русского языка)' },
        { type: 'improved', description: 'Генератор отчетов: структура как у реальных отчетов (общая часть, акты НК, заключение, приложения)' },
        { type: 'improved', description: 'Отчеты: подтягиваются данные из мобильного (точки замера, фото таблички, карта обследования, арматура, фото/вложения методов НК)' },
        { type: 'improved', description: 'Мобильное: синхронизация заданий + обработка 401 (автовыход и повторная авторизация)' },
        { type: 'improved', description: 'Мобильное: автозаполнение карты обследования из базы оборудования и сохранение изменений обратно в оборудование' },
        { type: 'added', description: 'Мобильное: расширены методы НК (ЗРА, СППК, овальность, прогиб, твердость по точкам, ПВК/МК/УЗК сварных соединений)' },
        { type: 'added', description: 'API: утверждение отчетов/чек-листов (APPROVED) — после утверждения отображаются в карточке оборудования и в списках' },
      ],
    },
    {
      version: '3.5.0',
      date: '12.12.2025',
      type: 'major',
      changes: [
        { type: 'added', description: 'Мобильное приложение обновлено до 3.5.0 (release APK)' },
        { type: 'fixed', description: 'Ссылка на APK приведена к единому формату /mobile/* (исключены “старые”/битые ссылки)' },
        { type: 'added', description: 'Компетенции: прикрепление скана сертификата (фото/PDF) к карточке инженера' },
        { type: 'added', description: 'Оборудование: переход в карточку оборудования по клику (страница с полной информацией, как в Диагностике)' },
        { type: 'improved', description: 'Генерация отчетов: улучшена поддержка данных из мобильного (в т.ч. толщинометрия)' },
      ],
    },
    {
      version: '3.3.0',
      date: '11.12.2025',
      type: 'major',
      changes: [
        { type: 'added', description: 'Единая база оборудования с уникальными кодами (equipment_code)' },
        { type: 'added', description: 'Система заданий на диагностику/экспертизу (assignments)' },
        { type: 'added', description: 'История обследований оборудования (inspection_history)' },
        { type: 'added', description: 'Журнал ремонта оборудования (repair_journal)' },
        { type: 'added', description: 'Операторы могут создавать задания и назначать инженеров' },
        { type: 'added', description: 'Инженеры видят только назначенные им задания в мобильном приложении' },
        { type: 'added', description: 'Офлайн-режим: синхронизация скачивает назначенное оборудование' },
        { type: 'added', description: 'Работа с заданиями в мобильном приложении без интернета' },
        { type: 'added', description: 'Автоматическое обновление статуса задания при выполнении' },
        { type: 'improved', description: 'Все обследования привязаны к оборудованию по уникальному коду' },
        { type: 'improved', description: 'Полная история обследований и ремонтов для каждого оборудования' },
      ],
    },
    {
      version: '3.2.9',
      date: '11.12.2025',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Добавлена кнопка выхода из системы в веб-приложении' },
        { type: 'added', description: 'Создан раздел "Что нового?" для отслеживания изменений версий' },
        { type: 'added', description: 'Добавлено отображение версии системы в интерфейсе (3.2.9 (10))' },
        { type: 'added', description: 'Реализовано автоматическое увеличение версии при загрузке мобильного приложения' },
        { type: 'added', description: 'Добавлено отображение версии приложения в мобильном приложении (профиль)' },
        { type: 'fixed', description: 'Исправлена ошибка загрузки списка пользователей (500 Internal Server Error)' },
        { type: 'fixed', description: 'Исправлена ошибка сравнения типа is_active в таблице users' },
        { type: 'fixed', description: 'Исправлена ошибка создания экспертизы (equipment_resources.resource_type)' },
        { type: 'fixed', description: 'Исправлена ошибка создания технического отчета (NDTMethod.inspection_id)' },
        { type: 'fixed', description: 'Исправлена проблема с пустым экраном оборудования в мобильном приложении' },
        { type: 'fixed', description: 'Исправлена ошибка загрузки leaflet.css (integrity attribute)' },
        { type: 'improved', description: 'Улучшена работа с назначением инженеров на оборудование' },
        { type: 'improved', description: 'Обновлен интерфейс управления доступом к оборудованию' },
        { type: 'improved', description: 'Обновлена версия мобильного приложения до 3.2.9 (build 10)' },
        { type: 'improved', description: 'Улучшена система версионирования APK файлов (автоматическое переименование)' },
        { type: 'improved', description: 'Оптимизирован фронтенд для работы с мобильных устройств' },
      ],
    },
    {
      version: '3.2.8',
      date: '10.12.2025',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Добавлена иерархическая структура оборудования (Предприятия → Филиалы → Цеха → Оборудование)' },
        { type: 'added', description: 'Реализовано назначение инженеров на уровни иерархии оборудования' },
        { type: 'added', description: 'Добавлена офлайн-синхронизация оборудования в мобильном приложении' },
        { type: 'added', description: 'Реализована фильтрация оборудования по назначенным инженерам' },
        { type: 'improved', description: 'Улучшена работа мобильного приложения в офлайн-режиме' },
      ],
    },
    {
      version: '3.2.7',
      date: '09.12.2025',
      type: 'patch',
      changes: [
        { type: 'fixed', description: 'Исправлена ошибка генерации отчетов в формате DOCX' },
        { type: 'fixed', description: 'Исправлена проблема с отображением русских символов в PDF отчетах' },
        { type: 'added', description: 'Добавлен предпросмотр данных перед генерацией технического отчета' },
        { type: 'improved', description: 'Улучшена генерация отчетов с поддержкой всех методов НК' },
      ],
    },
    {
      version: '3.2.6',
      date: '08.12.2025',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Добавлена генерация отчетов в формате Word (DOCX)' },
        { type: 'added', description: 'Реализована система управления доступом к оборудованию (RBAC)' },
        { type: 'added', description: 'Добавлено отображение ФИО инженера в карточках отчетов и чек-листов' },
        { type: 'improved', description: 'Улучшено отображение названий документов в чек-листах' },
        { type: 'improved', description: 'Добавлено хранение отчетов о толщинометрии и других методов НК' },
      ],
    },
    {
      version: '3.2.5',
      date: '07.12.2025',
      type: 'minor',
      changes: [
        { type: 'added', description: 'Восстановлена функция толщинометрии с указанием точек на схеме' },
        { type: 'added', description: 'Добавлена фильтрация оборудования по предприятиям и цехам в мобильном приложении' },
        { type: 'fixed', description: 'Исправлена ошибка отправки отчетов (project_id не существует)' },
        { type: 'improved', description: 'Восстановлен полный функционал мобильного приложения' },
      ],
    },
  ];

  const [expandedVersions, setExpandedVersions] = useState<Set<string>>(new Set([versions[0]?.version || '']));

  const toggleVersion = (version: string) => {
    setExpandedVersions((prev) => {
      const newSet = new Set(prev);
      if (newSet.has(version)) {
        newSet.delete(version);
      } else {
        newSet.add(version);
      }
      return newSet;
    });
  };

  const getChangeIcon = (type: string) => {
    switch (type) {
      case 'added':
        return <Plus className="text-green-400" size={16} />;
      case 'fixed':
        return <Bug className="text-red-400" size={16} />;
      case 'changed':
        return <Settings className="text-blue-400" size={16} />;
      case 'improved':
        return <CheckCircle className="text-yellow-400" size={16} />;
      default:
        return <CheckCircle className="text-app-text3" size={16} />;
    }
  };

  const getChangeLabel = (type: string) => {
    switch (type) {
      case 'added':
        return 'Добавлено';
      case 'fixed':
        return 'Исправлено';
      case 'changed':
        return 'Изменено';
      case 'improved':
        return 'Улучшено';
      default:
        return 'Изменение';
    }
  };

  const getVersionBadgeColor = (type: string) => {
    switch (type) {
      case 'major':
        return 'bg-red-500/20 text-red-400 border-red-500/30';
      case 'minor':
        return 'bg-blue-500/20 text-blue-400 border-blue-500/30';
      case 'patch':
        return 'bg-green-500/20 text-green-400 border-green-500/30';
      default:
        return 'bg-app-text3/20 text-app-text3 border-app-text3/30';
    }
  };

  const latest = versions[0];

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3 mb-6">
        <Sparkles className="text-accent" size={32} />
        <h1 className="text-3xl font-bold text-app-text">Что нового?</h1>
      </div>

      <div className="bg-app-panel rounded-xl border border-app-line p-6">
        <div className="mb-6 p-4 bg-app-deep rounded-lg border border-app-line">
          <h2 className="text-xl font-bold text-app-text mb-2">Версия системы</h2>
          <p className="text-2xl font-bold text-accent">
            {latest.version} ({latest.date})
          </p>
          <p className="text-sm text-app-text3 mt-1">Текущая версия платформы</p>
        </div>
        <p className="text-app-text2 mb-6">
          Здесь вы можете увидеть все изменения и обновления системы. Версии отсортированы от новых к старым.
        </p>

        <div className="space-y-4">
          {versions.map((version, index) => {
            const isExpanded = expandedVersions.has(version.version);
            return (
              <div
                key={index}
                className="bg-app-deep rounded-lg border border-app-line hover:border-accent/50 transition-colors overflow-hidden"
              >
                <button
                  onClick={() => toggleVersion(version.version)}
                  className="w-full flex items-center justify-between p-6 hover:bg-app-panel/50 transition-colors text-left"
                >
                  <div className="flex items-center gap-3">
                    <div className="flex items-center justify-center w-8 h-8 rounded-full bg-app-panel border border-app-line">
                      {isExpanded ? (
                        <ChevronUp className="text-accent" size={20} />
                      ) : (
                        <ChevronDown className="text-app-text3" size={20} />
                      )}
                    </div>
                    <div className="flex items-center gap-3">
                      <h2 className="text-2xl font-bold text-app-text">Версия {version.version}</h2>
                      <span
                        className={`px-3 py-1 rounded-full text-xs font-semibold border ${getVersionBadgeColor(
                          version.type
                        )}`}
                      >
                        {version.type === 'major'
                          ? 'Крупное обновление'
                          : version.type === 'minor'
                          ? 'Обновление'
                          : 'Исправление'}
                      </span>
                    </div>
                  </div>
                  <span className="text-app-text3 text-sm">{version.date}</span>
                </button>

                {isExpanded && (
                  <div className="px-6 pb-6 pt-2 space-y-2 animate-in slide-in-from-top-2 duration-200">
                    {version.changes.map((change, changeIndex) => (
                      <div
                        key={changeIndex}
                        className="flex items-start gap-3 p-3 bg-app-panel/50 rounded-lg hover:bg-app-panel transition-colors"
                      >
                        <div className="mt-0.5">{getChangeIcon(change.type)}</div>
                        <div className="flex-1">
                          <div className="flex items-center gap-2 mb-1">
                            <span className="text-xs font-semibold text-app-text3">
                              {getChangeLabel(change.type)}
                            </span>
                          </div>
                          <p className="text-app-text2 text-sm">{change.description}</p>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
        </div>

        <div className="mt-8 pt-6 border-t border-app-line">
          <div className="flex items-start gap-3">
            <AlertCircle className="text-yellow-400 mt-0.5" size={20} />
            <div>
              <h3 className="text-yellow-400 font-bold mb-2">Обратная связь</h3>
              <p className="text-sm text-app-text2">
                Если вы заметили ошибку или у вас есть предложения по улучшению системы, пожалуйста, свяжитесь с администратором.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Changelog;
