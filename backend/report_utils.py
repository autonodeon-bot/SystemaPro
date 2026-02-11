"""Утилиты для работы с отчетами"""
from datetime import datetime
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from models import Report, Inspection, Equipment, NDTMethod


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
