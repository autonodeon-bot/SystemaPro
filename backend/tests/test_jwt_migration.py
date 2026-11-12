"""Tokens issued before the JWT-library upgrade must remain usable."""
import jwt
import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

import auth

KEY = "compatibility-test-key-long-enough-for-hs256"
# Golden token produced by python-jose 3.3.0, using a test-only key.
LEGACY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJzdWIiOiJsZWdhY3ktdXNlciIsInJvbGUiOiJlbmdpbmVlciIsImFtciI6WyJwd2QiLCJ0b3RwIl0sImV4cCI6NDEwMjQ0NDgwMH0."
    "f9q8oVLapx4fC9DjZFJMZ7Q5-XNP-yYRS35r9T35a9s"
)


def credentials(token):
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


def test_legacy_token_and_claims_remain_valid(monkeypatch):
    monkeypatch.setattr(auth, "SECRET_KEY", KEY)
    assert auth.verify_token(credentials(LEGACY)) == "legacy-user"
    assert auth.verify_token_optional(credentials(LEGACY)) == "legacy-user"
    claims = jwt.decode(LEGACY, KEY, algorithms=["HS256"])
    assert claims["role"] == "engineer"
    assert claims["amr"] == ["pwd", "totp"]


@pytest.mark.parametrize("token", [
    jwt.encode({"sub": "alice", "exp": 1}, KEY, algorithm="HS256"),
    jwt.encode({"sub": "alice", "exp": 4102444800}, KEY + "wrong", algorithm="HS256"),
    jwt.encode({"sub": "alice", "exp": 4102444800}, KEY, algorithm="HS512"),
    jwt.encode({"sub": "alice", "exp": 4102444800}, "", algorithm="none"),
])
def test_invalid_tokens_fail_closed(monkeypatch, token):
    monkeypatch.setattr(auth, "SECRET_KEY", KEY)
    with pytest.raises(HTTPException) as exc:
        auth.verify_token(credentials(token))
    assert exc.value.status_code == 401
    assert auth.verify_token_optional(credentials(token)) is None
