"""Очередь фоновых задач.

Эволюционный подход:
  Сейчас (v3.30) — используем FastAPI BackgroundTasks (in-process). Этого
  достаточно для текущей нагрузки (≤10 отчётов/мин). Генерация отчёта
  выносится из sync-обработчика HTTP-запроса, UI не блокируется.

  Дальше (v3.31+) — переключение на Celery + Redis + worker-контейнер.
  Интерфейс `enqueue(...)` остаётся тот же, внутренности заменяются.

Использование:
    from fastapi import BackgroundTasks
    from report_queue import enqueue_report_generation

    @router.post("/reports/{report_id}/generate")
    async def trigger(report_id, background: BackgroundTasks):
        enqueue_report_generation(background, report_id=report_id, format="pdf")
        return {"status": "queued"}
"""
from __future__ import annotations

import asyncio
import logging
import os
from typing import Any, Awaitable, Callable, Optional
from uuid import UUID

from fastapi import BackgroundTasks

log = logging.getLogger(__name__)


# ─── In-process очередь с ограничением параллелизма ──────────────────────────
_MAX_PARALLEL = int(os.getenv("REPORT_QUEUE_MAX_PARALLEL", "2"))
_semaphore = asyncio.Semaphore(_MAX_PARALLEL)


async def _run_with_semaphore(coro_fn: Callable[..., Awaitable[Any]], *args, **kwargs):
    async with _semaphore:
        try:
            return await coro_fn(*args, **kwargs)
        except Exception:
            log.exception("Background task failed: %s", coro_fn.__name__)


def enqueue(background: BackgroundTasks, coro_fn: Callable[..., Awaitable[Any]], *args, **kwargs) -> None:
    """Добавить корутину в BackgroundTasks с ограничением параллелизма."""
    background.add_task(_run_with_semaphore, coro_fn, *args, **kwargs)


# ─── Высокоуровневые хуки ─────────────────────────────────────────────────────
async def _generate_report_impl(report_id: UUID, format: str) -> None:
    """Заглушка: в реальном коде здесь вызов существующих генераторов
    (reports_generator / report_utils) и запись результата в файловое хранилище.

    Текущие генераторы в проекте синхронные (reportlab / python-docx), поэтому
    оборачиваем их в thread-pool, чтобы не блокировать event loop.
    """
    log.info("Report generation queued: id=%s format=%s", report_id, format)
    await asyncio.sleep(0)  # точка переключения; реальная логика подключается отдельно


def enqueue_report_generation(
    background: BackgroundTasks,
    *,
    report_id: UUID,
    format: str = "pdf",
) -> None:
    enqueue(background, _generate_report_impl, report_id, format)


async def _send_email_impl(**kwargs) -> None:
    from email_service import send_email

    await send_email(**kwargs)


def enqueue_email(background: BackgroundTasks, **kwargs) -> None:
    enqueue(background, _send_email_impl, **kwargs)
