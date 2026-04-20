"""Email service (SMTP).

Мини-скелет: асинхронная отправка через aiosmtplib + шаблоны на Jinja-строках.
Активируется переменными окружения:

  SMTP_HOST=smtp.yandex.ru
  SMTP_PORT=465
  SMTP_USERNAME=robot@neftcontrol.ru
  SMTP_PASSWORD=***
  SMTP_TLS=ssl         # ssl | starttls | none
  SMTP_FROM="SystemaPro <robot@neftcontrol.ru>"

Если SMTP_HOST пуст — модуль работает в "dry-run": ничего не шлёт, логирует,
возвращает успех. Это нужно для локальной разработки и для того, чтобы
приложение не падало, если email провайдер временно недоступен.

Интеграция:
  from email_service import send_email
  await send_email(to="user@example.com", subject="...", body_html="...")

Типовые use-cases:
  - Welcome: создание пользователя
  - Password reset
  - Новое задание назначено инженеру
  - Отчёт готов / подписан
  - Уведомление о предстоящем сроке ЭПБ
"""
from __future__ import annotations

import logging
import os
import ssl
from dataclasses import dataclass
from email.message import EmailMessage
from typing import Iterable, Optional

log = logging.getLogger(__name__)

try:
    import aiosmtplib  # type: ignore

    _AIOSMTPLIB_AVAILABLE = True
except Exception:  # pragma: no cover
    _AIOSMTPLIB_AVAILABLE = False


@dataclass(frozen=True)
class SmtpConfig:
    host: str
    port: int
    username: Optional[str]
    password: Optional[str]
    tls_mode: str  # ssl | starttls | none
    mail_from: str

    @property
    def enabled(self) -> bool:
        return bool(self.host)


def _load_config() -> SmtpConfig:
    return SmtpConfig(
        host=os.getenv("SMTP_HOST", "").strip(),
        port=int(os.getenv("SMTP_PORT", "465")),
        username=os.getenv("SMTP_USERNAME") or None,
        password=os.getenv("SMTP_PASSWORD") or None,
        tls_mode=os.getenv("SMTP_TLS", "ssl").lower(),
        mail_from=os.getenv("SMTP_FROM", "robot@neftcontrol.ru"),
    )


def _build_message(
    cfg: SmtpConfig,
    *,
    to: str | Iterable[str],
    subject: str,
    body_html: Optional[str] = None,
    body_text: Optional[str] = None,
    reply_to: Optional[str] = None,
) -> EmailMessage:
    recipients = [to] if isinstance(to, str) else list(to)
    msg = EmailMessage()
    msg["From"] = cfg.mail_from
    msg["To"] = ", ".join(recipients)
    msg["Subject"] = subject
    if reply_to:
        msg["Reply-To"] = reply_to

    if body_text:
        msg.set_content(body_text)
    else:
        msg.set_content(body_html or "", subtype="html")

    if body_html and body_text:
        msg.add_alternative(body_html, subtype="html")
    return msg


async def send_email(
    *,
    to: str | Iterable[str],
    subject: str,
    body_html: Optional[str] = None,
    body_text: Optional[str] = None,
    reply_to: Optional[str] = None,
) -> bool:
    """Отправить email. Возвращает True при успехе / dry-run, False при ошибке."""
    cfg = _load_config()

    if not cfg.enabled:
        log.info("SMTP dry-run: to=%s subject=%s (SMTP_HOST пуст)", to, subject)
        return True

    if not _AIOSMTPLIB_AVAILABLE:
        log.warning("aiosmtplib недоступен — email не отправлен")
        return False

    msg = _build_message(
        cfg, to=to, subject=subject, body_html=body_html, body_text=body_text, reply_to=reply_to
    )

    try:
        use_tls = cfg.tls_mode == "ssl"
        start_tls = cfg.tls_mode == "starttls"
        context = ssl.create_default_context() if use_tls or start_tls else None
        await aiosmtplib.send(
            msg,
            hostname=cfg.host,
            port=cfg.port,
            username=cfg.username,
            password=cfg.password,
            use_tls=use_tls,
            start_tls=start_tls,
            tls_context=context,
        )
        log.info("Email sent → %s subject=%s", to, subject)
        return True
    except Exception as exc:
        log.exception("Email send failed: %s", exc)
        return False


# ─── Шаблоны ──────────────────────────────────────────────────────────────────
def tpl_welcome(full_name: str, username: str, temp_password: str, login_url: str) -> tuple[str, str]:
    subject = "SystemaPro: ваша учётная запись создана"
    html = f"""
    <div style="font-family:Arial,sans-serif;color:#eaeaea;background:#0f1216;padding:24px;border-radius:8px">
      <h2 style="color:#5aa8ff">Добро пожаловать, {full_name}!</h2>
      <p>Для вас создана учётная запись в системе технической диагностики <b>SystemaPro</b>.</p>
      <table style="margin:16px 0;border-collapse:collapse">
        <tr><td style="padding:4px 12px;color:#aaa">Логин</td><td><code>{username}</code></td></tr>
        <tr><td style="padding:4px 12px;color:#aaa">Временный пароль</td><td><code>{temp_password}</code></td></tr>
      </table>
      <p>Войдите по ссылке: <a href="{login_url}" style="color:#5aa8ff">{login_url}</a></p>
      <p style="color:#aaa;font-size:12px">Рекомендуем сменить пароль сразу после первого входа и включить 2FA.</p>
    </div>
    """
    return subject, html


def tpl_report_ready(report_number: str, report_title: str, download_url: str) -> tuple[str, str]:
    subject = f"SystemaPro: отчёт {report_number} готов"
    html = f"""
    <div style="font-family:Arial,sans-serif;color:#eaeaea;background:#0f1216;padding:24px;border-radius:8px">
      <h2>Отчёт готов к согласованию</h2>
      <p><b>№ {report_number}</b> — {report_title}</p>
      <p><a href="{download_url}" style="color:#5aa8ff">Открыть в системе</a></p>
    </div>
    """
    return subject, html
