"""Утилиты для работы с отчетами"""
from datetime import datetime
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from models import Report, Inspection, Equipment, NDTMethod, Questionnaire, QuestionnaireDocumentFile


def _has_value(value) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        return value.strip() != ""
    if isinstance(value, (list, dict, tuple, set)):
        return len(value) > 0
    return True


async def generate_report_number(db: AsyncSession, report_type: str = "TECHNICAL") -> str:
    """Генерирует автоматический номер отчета"""
    try:
        # Получаем последний номер отчета за текущий год
        current_year = datetime.now().year
        prefix = "ТР" if report_type == "TECHNICAL" else "ЭР"  # Технический отчет / Экспертиза
        
        # Ищем последний отчет с таким префиксом за текущий год (одна запись)
        query = select(Report).where(
            Report.report_number.like(f"{prefix}-{current_year}-%")
        ).order_by(Report.report_number.desc()).limit(1)
        
        result = await db.execute(query)
        last_report = result.scalar_one_or_none()
        
        if last_report and last_report.report_number:
            # Извлекаем номер из последнего отчета
            try:
                parts = last_report.report_number.split("-")
                if len(parts) == 3:
                    last_number = int(parts[2])
                    new_number = last_number + 1
                else:
                    new_number = 1
            except:
                new_number = 1
        else:
            new_number = 1
        
        # Форматируем номер: ТР-2026-0001
        report_number = f"{prefix}-{current_year}-{new_number:04d}"
        return report_number
    except Exception as e:
        # В случае ошибки возвращаем номер на основе timestamp
        timestamp = int(datetime.now().timestamp())
        return f"{prefix}-{current_year}-{timestamp}"


async def generate_registration_number(db: AsyncSession) -> str:
    """Генерирует регистрационный номер отчета"""
    try:
        current_year = datetime.now().year
        # Ищем последний регистрационный номер за текущий год (одна запись)
        query = select(Report).where(
            Report.registration_number.like(f"РЕГ-{current_year}-%")
        ).order_by(Report.registration_number.desc()).limit(1)
        
        result = await db.execute(query)
        last_report = result.scalar_one_or_none()
        
        if last_report and last_report.registration_number:
            try:
                parts = last_report.registration_number.split("-")
                if len(parts) == 3:
                    last_number = int(parts[2])
                    new_number = last_number + 1
                else:
                    new_number = 1
            except:
                new_number = 1
        else:
            new_number = 1
        
        registration_number = f"РЕГ-{current_year}-{new_number:04d}"
        return registration_number
    except Exception as e:
        timestamp = int(datetime.now().timestamp())
        return f"РЕГ-{datetime.now().year}-{timestamp}"


async def validate_inspection_completeness(
    db: AsyncSession,
    inspection_id: str
) -> dict:
    """Проверяет полноту данных обследования перед генерацией отчета"""
    from uuid import UUID as UUIDLib
    
    missing_fields = []
    warnings = []
    
    try:
        insp_uuid = UUIDLib(inspection_id)
        result = await db.execute(
            select(Inspection).where(Inspection.id == insp_uuid)
        )
        inspection = result.scalar_one_or_none()
        
        if not inspection:
            return {
                "is_complete": False,
                "missing_fields": ["Обследование не найдено"],
                "warnings": []
            }
        
        # Проверяем обязательные поля
        if not inspection.date_performed:
            missing_fields.append("Дата обследования")
        
        if not inspection.equipment_id:
            missing_fields.append("Оборудование")
        else:
            # Проверяем наличие данных оборудования
            eq_result = await db.execute(
                select(Equipment).where(Equipment.id == inspection.equipment_id)
            )
            equipment = eq_result.scalar_one_or_none()
            if not equipment:
                missing_fields.append("Данные оборудования")
        
        data = inspection.data if isinstance(inspection.data, dict) else {}

        # Базовые поля для шапки отчета
        organization = data.get("organization") or data.get("inspection_organization")
        executors = data.get("executors") or data.get("inspection_executors")
        if not _has_value(organization):
            missing_fields.append("Организация (карта обследования)")
        if not _has_value(executors):
            missing_fields.append("Исполнители (карта обследования)")

        # Системные вложения: фото таблички и схема контроля
        factory_plate = data.get("factory_plate_photo")
        control_scheme = data.get("control_scheme_image")

        # Дополнительно проверяем наличие этих файлов среди вложений опросного листа
        has_factory_doc = False
        has_scheme_doc = False
        try:
            q_query = (
                select(Questionnaire)
                .where(Questionnaire.equipment_id == inspection.equipment_id)
                .order_by(Questionnaire.created_at.desc())
                .limit(1)
            )
            q_result = await db.execute(q_query)
            questionnaire = q_result.scalar_one_or_none()
            if questionnaire:
                files_result = await db.execute(
                    select(QuestionnaireDocumentFile).where(
                        QuestionnaireDocumentFile.questionnaire_id == questionnaire.id
                    )
                )
                for f in files_result.scalars().all():
                    if f.document_number == "factory_plate_photo":
                        has_factory_doc = True
                    if f.document_number == "control_scheme_image":
                        has_scheme_doc = True
        except Exception:
            # Валидация не должна падать из-за ошибок чтения вложений
            pass

        if not (_has_value(factory_plate) or has_factory_doc):
            missing_fields.append("Фото заводской таблички")
        if not (_has_value(control_scheme) or has_scheme_doc):
            missing_fields.append("Схема контроля")

        # Проверяем точки замера для корректного отображения в отчете
        thickness = data.get("thickness_measurements")
        if isinstance(thickness, list) and len(thickness) > 0:
            without_coordinates = 0
            for p in thickness:
                if not isinstance(p, dict):
                    continue
                if p.get("x_percent") is None or p.get("y_percent") is None:
                    without_coordinates += 1
            if without_coordinates > 0:
                warnings.append(
                    f"Точки УЗТ без координат X/Y: {without_coordinates}. Они могут отображаться неточно на схеме."
                )

        # Проверяем наличие методов НК
        ndt_result = await db.execute(
            select(NDTMethod).where(NDTMethod.inspection_id == insp_uuid)
        )
        ndt_methods = ndt_result.scalars().all()
        
        if not ndt_methods:
            warnings.append("Не указаны методы неразрушающего контроля")
        else:
            # Проверяем, что у методов НК заполнены обязательные поля
            for method in ndt_methods:
                if not method.inspector_name:
                    warnings.append(f"Метод {method.method_code or method.method_name}: не указан инженер")
                if not method.performed_date:
                    warnings.append(f"Метод {method.method_code or method.method_name}: не указана дата выполнения")
        
        # Проверяем наличие заключения
        if not inspection.conclusion or inspection.conclusion.strip() == "":
            warnings.append("Не указано заключение")

        # Проверяем наличие приложений документов 1..17 (как рекомендованный минимум)
        # Не блокируем генерацию, но предупреждаем.
        docs = data.get("documents")
        if isinstance(docs, dict):
            present_count = 0
            for _, v in docs.items():
                if isinstance(v, dict):
                    present = v.get("present")
                    if present is True:
                        present_count += 1
                elif v is True:
                    present_count += 1
            if present_count == 0:
                warnings.append("По перечню документов 1..17 не отмечено ни одного приложенного документа")
        
        return {
            "is_complete": len(missing_fields) == 0,
            "missing_fields": missing_fields,
            "warnings": warnings,
            "can_generate": len(missing_fields) == 0
        }
    except Exception as e:
        return {
            "is_complete": False,
            "missing_fields": [f"Ошибка проверки: {str(e)}"],
            "warnings": []
        }


async def compare_inspections(
    db: AsyncSession,
    current_inspection_id: str,
    previous_inspection_id: str = None
) -> dict:
    """Сравнивает текущее обследование с предыдущим"""
    from uuid import UUID as UUIDLib
    
    try:
        curr_uuid = UUIDLib(current_inspection_id)
        curr_result = await db.execute(
            select(Inspection).where(Inspection.id == curr_uuid)
        )
        current = curr_result.scalar_one_or_none()
        
        if not current:
            return {"error": "Текущее обследование не найдено"}
        
        comparison = {
            "current_inspection_id": current_inspection_id,
            "previous_inspection_id": previous_inspection_id,
            "changes": [],
            "new_defects": [],
            "resolved_defects": [],
            "measurement_changes": []
        }
        
        if previous_inspection_id:
            prev_uuid = UUIDLib(previous_inspection_id)
            prev_result = await db.execute(
                select(Inspection).where(Inspection.id == prev_uuid)
            )
            previous = prev_result.scalar_one_or_none()
            
            if previous:
                # Сравниваем даты
                if current.date_performed and previous.date_performed:
                    days_diff = (current.date_performed - previous.date_performed).days
                    comparison["days_between"] = days_diff
                
                # Сравниваем методы НК
                curr_ndt = await db.execute(
                    select(NDTMethod).where(NDTMethod.inspection_id == curr_uuid)
                )
                prev_ndt = await db.execute(
                    select(NDTMethod).where(NDTMethod.inspection_id == prev_uuid)
                )
                
                curr_methods = {m.method_code: m for m in curr_ndt.scalars().all()}
                prev_methods = {m.method_code: m for m in prev_ndt.scalars().all()}
                
                # Находим изменения
                for code, method in curr_methods.items():
                    if code in prev_methods:
                        prev_method = prev_methods[code]
                        if method.conclusion != prev_method.conclusion:
                            comparison["changes"].append({
                                "method": code,
                                "type": "conclusion_changed",
                                "previous": prev_method.conclusion,
                                "current": method.conclusion
                            })
                    else:
                        comparison["changes"].append({
                            "method": code,
                            "type": "new_method"
                        })
        
        return comparison
    except Exception as e:
        return {"error": f"Ошибка сравнения: {str(e)}"}
