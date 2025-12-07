"""
Модуль шифрования для offline-пакетов
Использует AES-256-GCM с ключом, полученным из PBKDF2 хэша офлайн-PIN пользователя
"""
import os
import base64
import hashlib
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.backends import default_backend
from typing import Optional

# Константы для PBKDF2
PBKDF2_ITERATIONS = 100000  # Рекомендуемое количество итераций для безопасности
SALT_LENGTH = 16  # 128 бит
NONCE_LENGTH = 12  # 96 бит для GCM
KEY_LENGTH = 32  # 256 бит для AES-256


def derive_key_from_pin(offline_pin: str, salt: Optional[bytes] = None) -> tuple[bytes, bytes]:
    """
    Получить ключ шифрования из офлайн-PIN пользователя через PBKDF2
    
    Args:
        offline_pin: Офлайн-PIN пользователя (6-8 цифр)
        salt: Соль для PBKDF2 (если None - генерируется новая)
    
    Returns:
        tuple: (ключ, соль)
    """
    if salt is None:
        salt = os.urandom(SALT_LENGTH)
    
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=KEY_LENGTH,
        salt=salt,
        iterations=PBKDF2_ITERATIONS,
        backend=default_backend()
    )
    
    # Преобразуем PIN в байты
    pin_bytes = offline_pin.encode('utf-8')
    key = kdf.derive(pin_bytes)
    
    return key, salt


def encrypt_offline_package(data: bytes, offline_pin: str, salt: Optional[bytes] = None) -> dict:
    """
    Зашифровать offline-пакет с использованием AES-256-GCM
    
    Args:
        data: Данные для шифрования (JSON в байтах)
        offline_pin: Офлайн-PIN пользователя
        salt: Соль (если None - генерируется новая)
    
    Returns:
        dict: {
            'encrypted_data': base64-encoded зашифрованные данные,
            'salt': base64-encoded соль,
            'nonce': base64-encoded nonce
        }
    """
    # Получаем ключ из PIN
    key, salt = derive_key_from_pin(offline_pin, salt)
    
    # Генерируем nonce для GCM
    nonce = os.urandom(NONCE_LENGTH)
    
    # Шифруем данные
    aesgcm = AESGCM(key)
    encrypted_data = aesgcm.encrypt(nonce, data, None)  # None = без дополнительных данных (AAD)
    
    return {
        'encrypted_data': base64.b64encode(encrypted_data).decode('utf-8'),
        'salt': base64.b64encode(salt).decode('utf-8'),
        'nonce': base64.b64encode(nonce).decode('utf-8')
    }


def decrypt_offline_package(encrypted_package: dict, offline_pin: str) -> bytes:
    """
    Расшифровать offline-пакет
    
    Args:
        encrypted_package: {
            'encrypted_data': base64-encoded зашифрованные данные,
            'salt': base64-encoded соль,
            'nonce': base64-encoded nonce
        }
        offline_pin: Офлайн-PIN пользователя
    
    Returns:
        bytes: Расшифрованные данные
    
    Raises:
        ValueError: Если PIN неверный или данные повреждены
    """
    try:
        # Декодируем из base64
        encrypted_data = base64.b64decode(encrypted_package['encrypted_data'])
        salt = base64.b64decode(encrypted_package['salt'])
        nonce = base64.b64decode(encrypted_package['nonce'])
        
        # Получаем ключ из PIN
        key, _ = derive_key_from_pin(offline_pin, salt)
        
        # Расшифровываем данные
        aesgcm = AESGCM(key)
        decrypted_data = aesgcm.decrypt(nonce, encrypted_data, None)
        
        return decrypted_data
    except Exception as e:
        raise ValueError(f"Не удалось расшифровать пакет: {str(e)}. Возможно, неверный PIN.")


def hash_offline_pin(offline_pin: str) -> str:
    """
    Хешировать офлайн-PIN для хранения на сервере (для проверки при синхронизации)
    Используется SHA-256, так как PIN уже является секретом
    
    Args:
        offline_pin: Офлайн-PIN пользователя
    
    Returns:
        str: Hex-строка хеша
    """
    return hashlib.sha256(offline_pin.encode('utf-8')).hexdigest()

