#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$HOME/library-management-platform"
cd "$PROJECT_DIR"

TEST_DB="library_management_test"
ENV_FILE="/etc/library-management/database.env"

echo "=================================================="
echo "PostgreSQL Test Migration"
echo "=================================================="

# 1. Verify prerequisites.
[[ -f "$ENV_FILE" ]] || {
    echo "ERROR: Database environment file not found."
    exit 1
}

[[ -f "tests/test_api_endpoints.py" ]] || {
    echo "ERROR: Existing API tests not found."
    exit 1
}

[[ -f "tests/test_borrow_return.py" ]] || {
    echo "ERROR: Existing borrowing tests not found."
    exit 1
}

[[ -f "tests/test_user_service.py" ]] || {
    echo "ERROR: Existing user tests not found."
    exit 1
}

# 2. Load the database configuration without displaying secrets.
set -a
source "$ENV_FILE"
set +a

[[ -n "${DB_PASSWORD:-}" ]] || {
    echo "ERROR: DB_PASSWORD is missing."
    exit 1
}

if [[ "${DB_NAME:-}" == "$TEST_DB" ]]; then
    echo "ERROR: Production database configuration points to the test database."
    exit 1
fi

# 3. Confirm that the isolated test database exists.
EXISTS="$(
    sudo -u postgres psql -d postgres -tAc \
        "SELECT EXISTS (
            SELECT 1
            FROM pg_database
            WHERE datname = '$TEST_DB'
        );"
)"

[[ "$EXISTS" == "t" ]] || {
    echo "ERROR: Test database does not exist. Run setup_test_database.sh first."
    exit 1
}

echo "Production database: $DB_NAME"
echo "Test database verified: $TEST_DB"

# 4. Back up the current tests.
BACKUP_DIR="$HOME/project-backups/postgresql-integration/tests-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp tests/test_api_endpoints.py "$BACKUP_DIR/"
cp tests/test_borrow_return.py "$BACKUP_DIR/"
cp tests/test_user_service.py "$BACKUP_DIR/"

echo "Existing tests backed up to: $BACKUP_DIR"

# 5. Create shared fixtures.
cat > tests/conftest.py <<'PY'
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
PY

# 6. Replace API tests.
cat > tests/test_api_endpoints.py <<'PY'
import pytest

from app import create_app


@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True

    with app.test_client() as test_client:
        yield test_client


def test_healthcheck_endpoint(client):
    response = client.get("/api/health")

    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "UP"
    assert "Enterprise Smart Library" in data["service"]


def test_api_list_books(client):
    response = client.get("/api/books")

    assert response.status_code == 200
    data = response.get_json()
    assert data["count"] >= 2


def test_api_borrow_endpoint(client):
    response = client.post(
        "/api/borrow",
        json={"user_id": "U101", "book_id": "B001"},
    )

    assert response.status_code == 200
    assert response.get_json()["message"] == "Book checked out successfully"
    assert response.get_json()["loan"]["status"] == "ACTIVE"
PY

# 7. Replace borrowing and returning tests.
cat > tests/test_borrow_return.py <<'PY'
import pytest

from app.services.library_service import LibraryService


def test_borrow_and_return_book_lifecycle():
    initial_book = LibraryService.get_book("B001")
    initial_user = LibraryService.get_user("U101")

    assert initial_book is not None
    assert initial_user is not None

    initial_available = initial_book["available_copies"]

    loan = LibraryService.borrow_book("U101", "B001")

    assert loan["status"] == "ACTIVE"

    updated_book = LibraryService.get_book("B001")
    updated_user = LibraryService.get_user("U101")

    assert updated_book["available_copies"] == initial_available - 1
    assert updated_user["active_loans"] == 1

    returned = LibraryService.return_book("U101", "B001")

    assert returned["status"] == "RETURNED"

    final_book = LibraryService.get_book("B001")
    final_user = LibraryService.get_user("U101")

    assert final_book["available_copies"] == initial_available
    assert final_user["active_loans"] == 0


def test_student_quota_enforcement():
    for book_id in ("B10", "B20", "B30", "B40"):
        LibraryService.add_book(
            book_id,
            f"Book {book_id}",
            "Test Author",
            f"ISBN-{book_id}",
            5,
        )

    for book_id in ("B10", "B20", "B30"):
        LibraryService.borrow_book("U101", book_id)

    with pytest.raises(ValueError, match="quota exceeded"):
        LibraryService.borrow_book("U101", "B40")


def test_borrow_nonexistent_book_fails():
    with pytest.raises(ValueError, match="not found"):
        LibraryService.borrow_book("U101", "MISSING")


def test_return_without_active_loan_fails():
    with pytest.raises(ValueError, match="No active loan"):
        LibraryService.return_book("U101", "B001")
PY

# 8. Replace user service tests.
cat > tests/test_user_service.py <<'PY'
import pytest

from app.services.library_service import LibraryService


def test_add_user_success():
    user = LibraryService.add_user(
        "U200",
        "Grace Hopper",
        "grace@navy.mil",
        "Faculty",
    )

    assert user["user_id"] == "U200"
    assert user["name"] == "Grace Hopper"
    assert user["active_loans"] == 0


def test_add_duplicate_user_raises_error():
    with pytest.raises(ValueError, match="already exists"):
        LibraryService.add_user(
            "U101",
            "Duplicate Alice",
            "alice2@edu.com",
        )


def test_delete_user_with_loans_fails():
    LibraryService.borrow_book("U101", "B001")

    with pytest.raises(ValueError, match="with active book loans"):
        LibraryService.delete_user("U101")


def test_get_missing_user_returns_none():
    assert LibraryService.get_user("U404") is None
PY

echo
echo "=================================================="
echo "STEP 9: Validate test files"
echo "=================================================="

venv/bin/python -m py_compile \
    tests/conftest.py \
    tests/test_api_endpoints.py \
    tests/test_borrow_return.py \
    tests/test_user_service.py

echo "Test files compile successfully."

echo
echo "=================================================="
echo "TEST MIGRATION COMPLETE"
echo "=================================================="
echo "Existing tests backed up to: $BACKUP_DIR"
echo "No production database records were changed."
echo
echo "IMPORTANT: The tests have NOT been executed yet."
echo "Run them with the test-only runner in the next step."
