import os

import pytest

TEST_DATABASE_NAME = "library_management_test"


@pytest.fixture(autouse=True)
def isolated_postgres_database(monkeypatch):
    """Run each test against the dedicated test database only."""
    env_file = "/etc/library-management/database.env"

    if not os.path.isfile(env_file):
        pytest.fail("Database environment file is missing.")

    # Preserve the shell/service configuration, but load the database
    # credentials from the protected environment file.
    config = {}
    with open(env_file, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue

            key, value = line.split("=", 1)
            config[key.strip()] = value.strip().strip("'\"")

    configured_database = config.get("DB_NAME")

    if configured_database == TEST_DATABASE_NAME:
        pytest.fail(
            "The configured application database is the test database. "
            "Refusing to run tests."
        )

    for key in ("DB_HOST", "DB_PORT", "DB_USER", "DB_PASSWORD"):
        value = os.environ.get(key) or config.get(key)
        if not value:
            pytest.fail(f"Required database configuration is missing: {key}")
        monkeypatch.setenv(key, value)

    # Force the application code to connect to the isolated test database.
    monkeypatch.setenv("DB_NAME", TEST_DATABASE_NAME)

    import psycopg
    from database.db import db

    try:
        with db.connect() as connection:
            with connection.cursor() as cursor:
                # All cleanup is restricted to library_management_test.
                cursor.execute("SELECT current_database() AS database_name")
                actual_database = cursor.fetchone()["database_name"]

                if actual_database != TEST_DATABASE_NAME:
                    pytest.fail(
                        "Database safety check failed: connected to "
                        f"{actual_database!r}, not {TEST_DATABASE_NAME!r}."
                    )

                cursor.execute("DELETE FROM loans")
                cursor.execute("DELETE FROM books")
                cursor.execute("DELETE FROM users")

                cursor.execute(
                    """
                    INSERT INTO users
                        (user_id, name, email, role, active_loans)
                    VALUES
                        (%s, %s, %s, %s, 0),
                        (%s, %s, %s, %s, 0)
                    """,
                    (
                        "U101", "Alice Johnson",
                        "alice@university.edu", "Student",
                        "U102", "Dr. Robert Smith",
                        "robert.smith@university.edu", "Faculty",
                    ),
                )

                cursor.execute(
                    """
                    INSERT INTO books
                        (
                            book_id, title, author, isbn,
                            total_copies, available_copies
                        )
                    VALUES
                        (%s, %s, %s, %s, %s, %s),
                        (%s, %s, %s, %s, %s, %s)
                    """,
                    (
                        "B001", "Cloud Native DevOps Architecture",
                        "Linus Torvalds", "978-0134685991", 5, 5,
                        "B002", "Continuous Delivery Principles",
                        "Jez Humble & David Farley",
                        "978-0321601919", 3, 3,
                    ),
                )
    except psycopg.Error as exc:
        pytest.fail(
            "Unable to prepare the isolated PostgreSQL test database: "
            f"{type(exc).__name__}: {exc}"
        )

    yield
