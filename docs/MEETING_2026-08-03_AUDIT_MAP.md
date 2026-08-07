# Карта зависимостей — встреча 03.08.2026

| П | Область | Mobile | Web | Backend / PDF |
|---|---|---|---|---|
| 1,7 | Шрифты таблиц | — | — | `form_template_filler._shrink_table_font` |
| 2 | Portrait/landscape | — | — | `form_template_filler` (секции DOCX) |
| 3 | Заказчик / орг. ТД | general info | `ReportOrgSettings.tsx` | org_settings → filler `customer_*`/`contractor_*` |
| 4 | Пустые строки | — | — | `_strip_empty_rows` |
| 5 | Листы документов | `documents_info.pages` | DynamicInspection | filler `_doc_ident_and_pages`; `report_generator._doc_meta` |
| 6 | Ориентация | `constructionType` | equipment profiles | filler / EPB |
| 8 | Материалы | `VesselElement` + passport dialog | DynamicInspection | `_fill_materials` |
| 9 | Схема подключения | passport / files | assignment tech card | `form_media_helpers` |
| 10–12 | Базовая схема + слои | drawing_annotation, UztScheme | DrawingTemplates | `drawing_templates_api`, schemes in filler |
| 13 | Точка ≠ элемент | ThicknessMeasurement | — | `_fill_uzt_results` |
| 14 | Термообработка | HeatTreatmentRecord | — | `_fill_heat_treatment` |
| 15 | Прочность | HydraulicTestRecord | — | `_fill_strength_tests`, technical_report_builder |
| 16 | Формулировки | `report_formulation_options.dart` | — | conclusion_templates |
| 17 | Приборы | instrument park | InstrumentRegistry | instruments_api + `_fill_instrument_table` |
| 18 | Твердометрия | HardnessTest | — | `_fill_hardness_*` |
| 19–20 | УЗК | add_ndt_method_screen | — | `_fill_uzk_results` |
