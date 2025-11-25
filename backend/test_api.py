"""
Скрипт для тестирования всех API endpoints
"""
import requests
import json
from datetime import datetime

API_BASE = "http://localhost:8000"

def test_endpoint(method, url, data=None, description=""):
    """Тестирование endpoint"""
    print(f"\n🧪 {description}")
    print(f"   {method} {url}")
    
    try:
        if method == "GET":
            response = requests.get(url, timeout=10)
        elif method == "POST":
            response = requests.post(url, json=data, timeout=10)
        elif method == "PUT":
            response = requests.put(url, json=data, timeout=10)
        elif method == "DELETE":
            response = requests.delete(url, timeout=10)
        
        if response.status_code in [200, 201, 204]:
            print(f"   ✅ Успешно ({response.status_code})")
            if response.content:
                try:
                    result = response.json()
                    if isinstance(result, dict) and 'items' in result:
                        print(f"   📊 Получено записей: {len(result.get('items', []))}")
                    elif isinstance(result, dict) and 'id' in result:
                        print(f"   📝 ID: {result.get('id')}")
                except:
                    pass
            return True
        else:
            print(f"   ❌ Ошибка ({response.status_code}): {response.text[:200]}")
            return False
    except Exception as e:
        print(f"   ❌ Исключение: {str(e)}")
        return False

def main():
    print("=" * 60)
    print("🧪 ТЕСТИРОВАНИЕ API ENDPOINTS")
    print("=" * 60)
    
    results = []
    
    # 1. Health check
    results.append(test_endpoint("GET", f"{API_BASE}/health", description="Health check"))
    
    # 2. Equipment
    results.append(test_endpoint("GET", f"{API_BASE}/api/equipment", description="Получить список оборудования"))
    
    # 3. Equipment Types
    results.append(test_endpoint("GET", f"{API_BASE}/api/equipment-types", description="Получить типы оборудования"))
    
    # 4. Clients
    results.append(test_endpoint("GET", f"{API_BASE}/api/clients", description="Получить список клиентов"))
    
    # 5. Projects
    results.append(test_endpoint("GET", f"{API_BASE}/api/projects", description="Получить список проектов"))
    
    # 6. Inspections
    results.append(test_endpoint("GET", f"{API_BASE}/api/inspections", description="Получить список диагностик"))
    
    # 7. Equipment Resources
    results.append(test_endpoint("GET", f"{API_BASE}/api/equipment-resources", description="Получить ресурсы оборудования"))
    
    # 8. Regulatory Documents
    results.append(test_endpoint("GET", f"{API_BASE}/api/regulatory-documents", description="Получить нормативные документы"))
    
    # 9. Engineers
    results.append(test_endpoint("GET", f"{API_BASE}/api/engineers", description="Получить список инженеров"))
    
    # 10. Certifications
    results.append(test_endpoint("GET", f"{API_BASE}/api/certifications", description="Получить сертификаты"))
    
    # 11. Reports
    results.append(test_endpoint("GET", f"{API_BASE}/api/reports", description="Получить список отчетов"))
    
    # Итоги
    print("\n" + "=" * 60)
    print("📊 РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ")
    print("=" * 60)
    passed = sum(results)
    total = len(results)
    print(f"✅ Успешно: {passed}/{total}")
    print(f"❌ Ошибок: {total - passed}/{total}")
    print(f"📈 Процент успеха: {passed/total*100:.1f}%")
    
    if passed == total:
        print("\n🎉 Все тесты пройдены успешно!")
    else:
        print("\n⚠️ Некоторые тесты не прошли. Проверьте логи выше.")

if __name__ == "__main__":
    main()



