#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$HOME/library-management-platform"
SCHEMA_FILE="$PROJECT_DIR/database/migrations/001_initial_schema.sql"
TEST_DB="library_management_test"
ENV_FILE="/etc/library-management/database.env"

step() {
    echo
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

fail() {
    echo
    echo "ERROR: $1"
    exit 1
}

step "STEP 1: Verify required files"

[[ -f "$SCHEMA_FILE" ]] || fail "Schema file not found: $SCHEMA_FILE"
[[ -r "$ENV_FILE" ]] || fail "Cannot read $ENV_FILE"
[[ -x "$PROJECT_DIR/venv/bin/python" ]] || fail "Project virtual environment not found"

echo "Schema file found."
echo "Database environment file readable."
echo "Python virtual environment found."

step "STEP 2: Verify PostgreSQL service"

sudo systemctl is-active --quiet postgresql \
    || fail "PostgreSQL is not running."

echo "PostgreSQL service is active."

step "STEP 3: Load database configuration"

set -a
source "$ENV_FILE"
set +a

[[ -n "${DB_NAME:-}" ]] || fail "Production DB_NAME is missing."
[[ -n "${DB_USER:-}" ]] || fail "DB_USER is missing."
[[ -n "${DB_PASSWORD:-}" ]] || fail "DB_PASSWORD is missing."

if [[ "$DB_NAME" == "$TEST_DB" ]]; then
    fail "Production database name unexpectedly matches test database name."
fi

echo "Production database: $DB_NAME"
echo "Test database: $TEST_DB"
echo "Database password will not be displayed."

step "STEP 4: Verify production database exists"

if ! sudo -u postgres psql \
    -d postgres \
    -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" \
    | grep -qx '1'; then
    fail "Production database '$DB_NAME' was not found."
fi

echo "Production database exists."

step "STEP 5: Create the isolated test database if needed"

if sudo -u postgres psql \
    -d postgres \
    -tAc "SELECT 1 FROM pg_database WHERE datname = '$TEST_DB'" \
    | grep -qx '1'; then

    echo "Test database already exists; leaving its existing data intact."
else
    sudo -u postgres createdb --owner="$DB_USER" "$TEST_DB"
    echo "Created test database: $TEST_DB"
fi

step "STEP 6: Apply schema to the test database"

PGPASSWORD="$DB_PASSWORD" psql \
    -h "$DB_HOST" \
    -p "${DB_PORT:-5432}" \
    -U "$DB_USER" \
    -d "$TEST_DB" \
    -v ON_ERROR_STOP=1 \
    -f "$SCHEMA_FILE"

step "STEP 7: Verify test database tables"

TABLES="$(
    PGPASSWORD="$DB_PASSWORD" psql \
        -h "$DB_HOST" \
        -p "${DB_PORT:-5432}" \
        -U "$DB_USER" \
        -d "$TEST_DB" \
        -Atc "
            SELECT tablename
            FROM pg_tables
            WHERE schemaname = 'public'
            ORDER BY tablename;
        "
)"

printf '%s\n' "$TABLES"

for table in books loans users; do
    printf '%s\n' "$TABLES" | grep -qx "$table" \
        || fail "Required test table '$table' is missing."
done

step "SUCCESS"

echo "Isolated test database is ready."
echo "Production database was not modified."
echo "Existing test database data, if any, was preserved."
