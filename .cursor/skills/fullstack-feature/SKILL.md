# Skill: Fullstack фича (Backend + Frontend + Mobile)

## Описание
Создание полноценной фичи, затрагивающей все 3 слоя: Backend API, Web Frontend, Mobile App.

## Когда использовать
- Добавление нового модуля/раздела в систему
- Фича, требующая изменений во всех слоях

## Порядок действий

### Фаза 1: Планирование
1. Определить сущности и их поля
2. Определить API endpoints (CRUD + специальные действия)
3. Определить UI (страница, модалки, формы)
4. Определить мобильный UI (если нужен)

### Фаза 2: Backend
1. **Модель** → `backend/models.py`
   - UUID PK, created_at, updated_at, is_archived
   - Связи с существующими моделями
   
2. **Роутер** → `backend/{entity}_api.py`
   - Pydantic схемы (Create, Update, Response)
   - CRUD endpoints
   - Авторизация через `Depends(verify_token)`
   
3. **Подключение** → `backend/main.py`
   - `from entity_api import router as entity_router`
   - `app.include_router(entity_router)`
   
4. **Миграция** (если новая таблица)
   - `CREATE TABLE IF NOT EXISTS` в startup

### Фаза 3: Frontend
1. **Типы** → `types.ts`
   - Интерфейс сущности
   
2. **Страница** → `pages/EntityManagement.tsx`
   - Таблица с данными
   - Фильтры и поиск
   - CRUD модалки
   - Skeleton для загрузки
   
3. **Маршрут** → `App.tsx`
   - `<Route path="/entity" element={<ProtectedRoute><EntityManagement /></ProtectedRoute>} />`
   - Ссылка в навигации сайдбара

### Фаза 4: Mobile (если нужно)
1. **Модель** → `mobile/lib/models/entity.dart`
   - `fromJson()`, `toJson()`
   
2. **API** → `mobile/lib/services/api_service.dart`
   - Методы для CRUD
   
3. **Экран** → `mobile/lib/screens/entity_screen.dart`
   - ConsumerStatefulWidget
   - Список + детали + формы
   
4. **Навигация** → из Dashboard или меню

### Фаза 5: Проверка
- [ ] Backend: endpoints доступны, данные корректны
- [ ] Frontend: страница загружается, CRUD работает
- [ ] Mobile: экран показывает данные, формы работают
- [ ] Авторизация: доступ только для нужных ролей
- [ ] Тёмная тема: корректное отображение

## Чек-лист синхронизации
- [ ] Типы/модели совпадают во всех слоях
- [ ] Названия полей API одинаковы
- [ ] Форматы дат совпадают (ISO 8601)
- [ ] UUID используется везде как string
- [ ] Обработка ошибок во всех слоях
