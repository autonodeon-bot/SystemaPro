import sys
sys.stdout.reconfigure(encoding='utf-8')
from models import HierarchyEngineerAssignment

print("Проверка модели HierarchyEngineerAssignment:")
print(f"  granted_by: {hasattr(HierarchyEngineerAssignment, 'granted_by')}")
print(f"  granted_at: {hasattr(HierarchyEngineerAssignment, 'granted_at')}")
print(f"  assigned_by: {hasattr(HierarchyEngineerAssignment, 'assigned_by')}")
print(f"  assigned_at: {hasattr(HierarchyEngineerAssignment, 'assigned_at')}")

if hasattr(HierarchyEngineerAssignment, 'granted_by'):
    print("\n✅ Модель использует granted_by/granted_at (правильно)")
else:
    print("\n❌ Модель все еще использует assigned_by/assigned_at (неправильно)")











