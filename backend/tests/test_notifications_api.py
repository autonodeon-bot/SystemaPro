"""Тесты API уведомлений — структура роутера, Pydantic-схемы, логика"""
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
import uuid

from notifications_api import (
    router,
    NotificationResponse,
    DeviceRegistrationRequest,
    send_push_notification,
)


class TestNotificationSchemas:
    """Тесты Pydantic-схем уведомлений"""

    def test_notification_response_fields(self):
        resp = NotificationResponse(
            id='abc-123',
            type='new_assignment',
            title='Новое задание',
            message='Вам назначено задание',
            is_read=False,
            created_at='2025-01-01T00:00:00',
            data={'assignment_id': '123'},
        )
        assert resp.id == 'abc-123'
        assert resp.type == 'new_assignment'
        assert resp.title == 'Новое задание'
        assert resp.message == 'Вам назначено задание'
        assert resp.is_read is False
        assert resp.data == {'assignment_id': '123'}

    def test_notification_response_optional_data(self):
        resp = NotificationResponse(
            id='1',
            type='info',
            title='t',
            message='m',
            is_read=True,
            created_at='2025-01-01T00:00:00',
        )
        assert resp.data is None

    def test_device_registration_defaults(self):
        req = DeviceRegistrationRequest(fcm_token='some-token')
        assert req.fcm_token == 'some-token'
        assert req.platform == 'android'

    def test_device_registration_custom_platform(self):
        req = DeviceRegistrationRequest(fcm_token='token', platform='ios')
        assert req.platform == 'ios'


class TestNotificationRouter:
    """Тесты структуры роутера"""

    def test_router_prefix(self):
        assert router.prefix == '/api/notifications'

    def test_router_tags(self):
        assert 'notifications' in router.tags

    def test_router_has_get_notifications(self):
        paths = [r.path for r in router.routes]
        assert any('/api/notifications' == p for p in paths)

    def test_router_has_count_endpoint(self):
        paths = [r.path for r in router.routes]
        assert any(p.endswith('/count') for p in paths)

    def test_router_has_register_device(self):
        paths = [r.path for r in router.routes]
        assert any(p.endswith('/register-device') for p in paths)


class TestSendPushNotification:
    """Тесты функции отправки push-уведомлений"""

    @pytest.mark.asyncio
    async def test_send_push_no_devices(self):
        """Функция не падает, если у пользователя нет устройств"""
        mock_db = AsyncMock()
        mock_result = MagicMock()
        mock_result.scalars.return_value.all.return_value = []
        mock_db.execute = AsyncMock(return_value=mock_result)

        await send_push_notification(
            db=mock_db,
            user_id=uuid.uuid4(),
            title='Тест',
            body='Тестовое уведомление',
        )

    @pytest.mark.asyncio
    async def test_send_push_with_device(self):
        """Функция обрабатывает устройство без ошибок"""
        mock_device = MagicMock()
        mock_device.fcm_token = 'fcm_test_token_123456789012345'

        mock_db = AsyncMock()
        mock_result = MagicMock()
        mock_result.scalars.return_value.all.return_value = [mock_device]
        mock_db.execute = AsyncMock(return_value=mock_result)

        await send_push_notification(
            db=mock_db,
            user_id=uuid.uuid4(),
            title='Новое задание',
            body='Вам назначено обследование',
            data={'assignment_id': str(uuid.uuid4())},
        )

    @pytest.mark.asyncio
    async def test_send_push_handles_exception(self):
        """Функция не пробрасывает исключение, если FCM недоступен"""
        mock_device = MagicMock()
        mock_device.fcm_token = property(lambda self: (_ for _ in ()).throw(Exception('boom')))

        mock_db = AsyncMock()
        mock_result = MagicMock()
        mock_result.scalars.return_value.all.return_value = []
        mock_db.execute = AsyncMock(return_value=mock_result)

        await send_push_notification(
            db=mock_db,
            user_id=uuid.uuid4(),
            title='t',
            body='b',
        )
