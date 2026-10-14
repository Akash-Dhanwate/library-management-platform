#!/usr/bin/env bash

set -Eeuo pipefail

cd "$HOME/library-management-platform"

TEST_DB="library_management_test"
ENV_FILE="/etc/library-management/database.env"

echo "=================================================="
echo "PostgreSQL Test Runner"
echo "=================================================="

# Confirm the test database exists.
EXISTS="$(
    sudo -u postgres psql -d postgres -tAc \
        "SELECT EXISTS (
            SELECT 1 FROM pg_database
            WHERE datname = '$TEST_DB'
        );"
)"

if [[ "$EXISTS" != "t" ]]; then
    echo "ERROR: Test database does not exist."
    exit 1
fi

# Load credentials without printing the password.
set -a
source "$ENV_FILE"
set +a

if [[ "${DB_NAME:-}" == "$TEST_DB" ]]; then
    echo "ERROR: The configured production database matches the test database."
    exit 1
fi

# Force all pytest database connections to use the isolated test database.
export DB_NAME="$TEST_DB"

echo "Target database: $DB_NAME"
echo "Production database will not be used."
echo

echo "STEP 1: Verify PostgreSQL connectivity"

venv/bin/python - <<'PY'
import os
import psycopg

expected = "library_management_test"

if os.environ.get("DB_NAME") != expected:
    raise SystemExit("SAFETY ERROR: DB_NAME is not the test database.")

with psycopg.connect(
    host=os.environ["DB_HOST"],
    port=os.environ.get("DB_PORT", "5432"),
    dbname=os.environ["DB_NAME"],
    user=os.environ["DB_USER"],
    password=os.environ["DB_PASSWORD"],
    connect_timeout=5,
) as connection:
    with connection.cursor() as cursor:
        cursor.execute("SELECT current_database()")
        actual = cursor.fetchone()[0]

if actual != expected:
    raise SystemExit(
        f"SAFETY ERROR: Connected to {actual}, expected {expected}."
    )

print(f"Connected successfully to {actual}.")
PY

echo
echo "STEP 2: Compile application and test files"

venv/bin/python -m py_compile \
    database/db.py \
    app/services/library_service.py \
    app/routes/api.py \
    tests/conftest.py \
    tests/test_api_endpoints.py \
    tests/test_borrow_return.py \
    tests/test_user_service.py

echo "Compilation passed."

echo
echo "STEP 3: Run pytest"

venv/bin/pytest -v tests

RESULT=$?

echo
echo "=================================================="

if [[ "$RESULT" -eq 0 ]]; then
    echo "ALL TESTS PASSED"
else
    echo "TESTS FAILED (exit code $RESULT)"
fi

echo "=================================================="

exit "$RESULT"
