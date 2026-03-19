import pathlib
import ssl

import database as db_module


class TestDatabaseUrl:
    def test_database_url_should_match_module_constants(self):
        expected = (
            f"postgresql+asyncpg://{db_module.DB_USER}:{db_module.DB_PASS}"
            f"@{db_module.DB_HOST}:{db_module.DB_PORT}/{db_module.DB_NAME}"
        )
        assert db_module.DATABASE_URL == expected


class TestSslContext:
    def test_get_ssl_context_should_disable_hostname_check(self):
        ctx = db_module.get_ssl_context()
        assert ctx.check_hostname is False
        assert ctx.verify_mode == ssl.CERT_NONE


class TestEngineAndConnect:
    def test_engine_should_expose_async_session_api(self):
        assert hasattr(db_module.engine, "begin")
        assert hasattr(db_module.engine, "dispose")

    def test_connect_args_should_define_ssl(self):
        assert "ssl" in db_module.connect_args


class TestPoolSettingsInSource:
    def test_database_module_should_configure_queue_pool_in_create_engine(self):
        src = pathlib.Path(db_module.__file__).read_text(encoding="utf-8")
        assert "AsyncAdaptedQueuePool" in src
        assert "pool_size=10" in src
        assert "max_overflow=20" in src
        assert "pool_timeout=30" in src
        assert "pool_recycle=1800" in src
        assert "pool_pre_ping=True" in src
