# Отчёт: встреча 03.08.2026 — реализация в 3.7.16

## Изменено

1. **Шрифты PDF** — минимум ~12 pt (было 8.5); очень широкие таблицы — умеренно 10 pt.
2. **Landscape** — широкие таблицы (≥7 колонок) выносятся в landscape-секцию с возвратом к portrait.
3. **Пустые строки** — `_strip_empty_rows` для УЗТ/твёрдости/УЗК/МПК и основных таблиц.
4. **Заказчик / организация ТД** — mobile: поля + загрузка из `/api/report-org-settings`; filler учитывает `customer_info`/`contractor_info`.
5. **Объём листов** — колонка в reportlab PDF (`report_generator`); mobile уже писал `pages`.
6. **Ориентация** — `orientation: horizontal|vertical` + UI в паспорте; маппинг из `construction_type`.
7. **Материалы** — mobile полный набор; web DynamicInspection — ГОСТ/σт/σв/δ/ориентация.
8. **Термообработка** — поле `mode` (режим); filler/tech report.
9. **Испытания** — select вид (гидр./пневм.) и среда; температура; ключ `hydraulic_test_history` в technical_report_builder.
10. **Формулировки** — расширен `docAnalysis` (без выдуманных юр. текстов).
11. **Приборы** — реестр без изменений структуры; filler defaults по методам сохранены.
12. **Твердометрия** — элемент / № точки / марка стали (авто из корпуса в filler).
13. **УЗК** — тип соединения, толщина, Sдоп; характер дефекта select объёмный|плоскостной; номер стыка/дефекта.
14. **Точка ≠ элемент** — раздельные ключи в ThicknessMeasurement / Hardness / SchemeControlPoint.
15. **Схемы** — `BaseVesselScheme` + слои точек УЗТ/твёрдости; connection_scheme file в collect_scheme_paths.

## Файлы (основные)

- `backend/form_template_filler.py`, `form_media_helpers.py`, `report_generator.py`, `technical_report_builder.py`
- `mobile/lib/models/vessel_checklist.dart`
- `mobile/lib/widgets/inspection/inspection_passport_section.dart`
- `mobile/lib/widgets/inspection/inspection_general_info_section.dart`
- `mobile/lib/screens/add_ndt_method_screen.dart`
- `mobile/lib/constants/report_formulation_options.dart`
- `pages/DynamicInspection.tsx`, `pages/Changelog.tsx`
- версии: package.json, pubspec, main.py, constants.ts, mobile_stats_api.py

## Database

Изменений схемы БД нет (данные в `Inspection.data` JSONB).

## API

Без новых endpoint; используется существующий `/api/report-org-settings`.

## PDF

Типографика + landscape + pages + маппинг УЗК/термо/прочность/твёрдость.

## Схемы

Базовая схема: `control_scheme_image` / `base_vessel_scheme`; точки методов пишутся в `points[]` при сериализации чек-листа. Параметрический CAD-конструктор корпуса — не реализован (вне минимального расширения DrawingTemplates).

## Тестирование

Локально: правки моделей/filler. Полный E2E на проде (создать сосуд → заполнить → PDF) — после деплоя 3.7.16 / APK +53.

## Осталось (нужны данные специалиста)

- Юридически утверждённые формулировки выводов (TODO в константах).
- Полноценный параметрический CAD-конструктор сосуда (корпус/днища/патрубки с размерами) — отдельный этап.
- Реальные паспортные данные приборов в реестре — заполняет оператор.
