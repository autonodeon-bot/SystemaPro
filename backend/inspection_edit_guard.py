"""Checks for updating a mobile inspection without silently replacing another revision."""
from datetime import datetime, timezone
from fastapi import HTTPException


def inspection_revision(inspection):
    value = getattr(inspection, 'updated_at', None) or getattr(inspection, 'created_at', None)
    return value.isoformat() if value else None


def assert_mobile_edit_allowed(inspection, equipment_id, user, source_revision):
    if inspection is None:
        raise HTTPException(404, "Обследование не найдено; локальный черновик сохранён")
    if inspection.equipment_id != equipment_id or inspection.is_deleted or getattr(inspection, 'is_archived', False):
        raise HTTPException(409, "Обследование удалено или относится к другому оборудованию")
    # SIGNED — завершённый мобильный чек-лист. Подписанные электронной
    # подписью отчёты дополнительно защищены в endpoint до любых изменений.
    if inspection.status not in {"DRAFT", "SIGNED"}:
        raise HTTPException(409, "Утверждённое обследование нельзя перезаписывать. Создайте новую редакцию")
    if user is None or (user.role not in {"admin", "chief_operator", "operator"} and
                        not (user.role == "engineer" and user.id in {inspection.created_by, inspection.inspector_id, inspection.performed_by})):
        raise HTTPException(403, "Нет прав редактировать это обследование")
    try:
        expected = datetime.fromisoformat(str(source_revision).replace("Z", "+00:00"))
        actual = datetime.fromisoformat(inspection_revision(inspection))
        expected = expected.replace(tzinfo=timezone.utc) if expected.tzinfo is None else expected
        actual = actual.replace(tzinfo=timezone.utc) if actual.tzinfo is None else actual
    except (TypeError, ValueError):
        raise HTTPException(409, "Откройте актуальную серверную версию перед редактированием. Локальный черновик сохранён")
    if expected != actual:
        raise HTTPException(409, "Обследование уже изменено на другом устройстве. Локальный черновик сохранён")
