import os
import sys

import psycopg2


def main() -> int:
    host = os.getenv("DB_HOST")
    port = int(os.getenv("DB_PORT", "5432"))
    db = os.getenv("DB_NAME")
    user = os.getenv("DB_USER")
    password = os.getenv("DB_PASS")
    sslmode = os.getenv("DB_SSLMODE", "require")

    print("DB_HOST=", host)
    print("DB_PORT=", port)
    print("DB_NAME=", db)
    print("DB_USER=", user)
    print("DB_SSLMODE=", sslmode)

    conn = psycopg2.connect(
        host=host,
        port=port,
        dbname=db,
        user=user,
        password=password,
        sslmode=sslmode,
    )
    cur = conn.cursor()

    def scalar(sql: str) -> int:
        cur.execute(sql)
        return int(cur.fetchone()[0])

    print("equipment=", scalar("select count(1) from equipment"))
    print("assignments=", scalar("select count(1) from assignments"))
    print("inspections=", scalar("select count(1) from inspections"))
    print("reports=", scalar("select count(1) from reports"))
    print("enterprises=", scalar("select count(1) from enterprises"))
    print("branches=", scalar("select count(1) from branches"))
    print("workshops=", scalar("select count(1) from workshops"))

    cur.execute(
        """
        select id, equipment_code, name, is_active, workshop_id
        from equipment
        order by created_at desc nulls last
        limit 10
        """
    )
    rows = cur.fetchall()
    print("equipment_last10=")
    for r in rows:
        print("  ", r)

    cur.execute(
        """
        select id, assigned_to, status, equipment_id, created_at
        from assignments
        order by created_at desc nulls last
        limit 10
        """
    )
    rows = cur.fetchall()
    print("assignments_last10=")
    for r in rows:
        print("  ", r)

    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

