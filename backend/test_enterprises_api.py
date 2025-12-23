import asyncio
import sys
import requests

API_BASE = "http://localhost:8000"

def test_enterprises_api():
    sys.stdout.reconfigure(encoding='utf-8')
    print("Тестирование API предприятий...")
    
    # Сначала получаем токен
    login_data = {
        "username": "admin",
        "password": "admin123"
    }
    
    try:
        response = requests.post(f"{API_BASE}/api/auth/login", data=login_data)
        if response.status_code == 200:
            token = response.json().get("access_token")
            print(f"✅ Токен получен: {token[:20]}...")
            
            # Теперь запрашиваем предприятия
            headers = {"Authorization": f"Bearer {token}"}
            response = requests.get(f"{API_BASE}/api/hierarchy/enterprises", headers=headers)
            
            if response.status_code == 200:
                data = response.json()
                print(f"✅ Предприятия получены: {len(data.get('items', []))} шт.")
                for item in data.get('items', []):
                    print(f"  - {item.get('name')} (id: {item.get('id')})")
            else:
                print(f"❌ Ошибка получения предприятий: {response.status_code}")
                print(f"   Ответ: {response.text}")
        else:
            print(f"❌ Ошибка авторизации: {response.status_code}")
            print(f"   Ответ: {response.text}")
    except Exception as e:
        print(f"❌ Ошибка: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_enterprises_api()











