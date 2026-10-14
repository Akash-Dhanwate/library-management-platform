CREATE TABLE IF NOT EXISTS users (
    user_id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    email VARCHAR(255) NOT NULL,
    role VARCHAR(30) NOT NULL DEFAULT 'Student',
    active_loans INTEGER NOT NULL DEFAULT 0
        CHECK (active_loans >= 0)
);

CREATE TABLE IF NOT EXISTS books (
    book_id VARCHAR(50) PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    author VARCHAR(150) NOT NULL,
    isbn VARCHAR(30) NOT NULL,
    total_copies INTEGER NOT NULL CHECK (total_copies >= 1),
    available_copies INTEGER NOT NULL
        CHECK (
            available_copies >= 0
            AND available_copies <= total_copies
        )
);

CREATE TABLE IF NOT EXISTS loans (
    loan_id VARCHAR(50) PRIMARY KEY,
    user_id VARCHAR(50) NOT NULL
        REFERENCES users(user_id),
    book_id VARCHAR(50) NOT NULL
        REFERENCES books(book_id),
    borrowed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    returned_at TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'RETURNED')),
    CHECK (
        (status = 'ACTIVE' AND returned_at IS NULL)
        OR
        (status = 'RETURNED' AND returned_at IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_loans_user_status
    ON loans(user_id, status);

CREATE INDEX IF NOT EXISTS idx_loans_book_status
    ON loans(book_id, status);
