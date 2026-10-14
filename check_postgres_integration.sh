#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$HOME/library-management-platform"
cd "$PROJECT_DIR"

# Display each step and stop on the first failure.
run_step() {
    local description="$1"
    shift

    echo
    echo "=================================================="
    echo "STEP: $description"
    echo "=================================================="

    if "$@"; then
        echo "RESULT: PASS"
    else
        local exit_code=$?
        echo "RESULT: FAIL (exit code: $exit_code)"
        echo "Stopping here. Fix this error before continuing."
        exit "$exit_code"
    fi
}

echo "Library Management Platform - PostgreSQL Code Checks"
echo "Project: $PROJECT_DIR"
echo "Date: $(date)"
echo

# Step 1: Verify project files.
run_step "Verify required files exist" \
    test -f database/db.py

run_step "Verify library service exists" \
    test -f app/services/library_service.py

# Step 2: Check Python syntax.
run_step "Compile PostgreSQL database module" \
    venv/bin/python -m py_compile database/db.py

run_step "Compile PostgreSQL library service" \
    venv/bin/python -m py_compile app/services/library_service.py

# Step 3: Run the combined syntax check.
run_step "Compile both PostgreSQL modules" \
    venv/bin/python -m py_compile \
        database/db.py \
        app/services/library_service.py

# Step 4: Check for critical Python errors using Flake8.
run_step "Check database and service for critical lint errors" \
    venv/bin/flake8 \
        app/services/library_service.py \
        database/db.py \
        --count \
        --select=E9,F63,F7,F82 \
        --show-source

# Step 5: Verify the PostgreSQL driver is installed.
run_step "Verify psycopg installation" \
    venv/bin/python -c \
    'import psycopg; print("psycopg version:", psycopg.__version__)'

echo
echo "=================================================="
echo "ALL CHECKS PASSED"
echo "=================================================="
echo "Python syntax and critical lint checks passed."
echo "No database records or services were changed."
echo
echo "Next: prepare an isolated PostgreSQL test database"
echo "before running the application tests."
