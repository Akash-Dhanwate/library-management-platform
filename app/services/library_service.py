from datetime import datetime, timezone
from uuid import uuid4

from psycopg import errors

from database.db import db


class LibraryService:
    """Business logic for the PostgreSQL-backed library platform."""

    @staticmethod
    def _get_active_loan_count(cursor, user_id):
        cursor.execute(
            """
            SELECT COUNT(*) AS loan_count
            FROM loans
            WHERE user_id = %s AND status = 'ACTIVE'
            """,
            (user_id,),
        )
        return cursor.fetchone()["loan_count"]

    @staticmethod
    def add_user(user_id, name, email, role="Student"):
        if not user_id or not name or not email:
            raise ValueError(
                "All user fields (user_id, name, email) are mandatory."
            )

        try:
            with db.connect() as connection:
                with connection.cursor() as cursor:
                    cursor.execute(
                        """
                        INSERT INTO users
                            (user_id, name, email, role, active_loans)
                        VALUES (%s, %s, %s, %s, 0)
                        RETURNING user_id, name, email, role, active_loans
                        """,
                        (user_id, name, email, role),
                    )
                    return cursor.fetchone()

        except errors.UniqueViolation:
            raise ValueError(
                f"User with ID '{user_id}' already exists."
            ) from None

    @staticmethod
    def get_user(user_id):
        with db.connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT user_id, name, email, role, active_loans
                    FROM users
                    WHERE user_id = %s
                    """,
                    (user_id,),
                )
                return cursor.fetchone()

    @staticmethod
    def delete_user(user_id):
        with db.connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT active_loans FROM users "
                    "WHERE user_id = %s FOR UPDATE",
                    (user_id,),
                )
                user = cursor.fetchone()

                if not user:
                    raise ValueError(f"User '{user_id}' not found.")

                if user["active_loans"] > 0:
                    raise ValueError(
                        f"Cannot delete user '{user_id}' "
                        "with active book loans."
                    )

                cursor.execute(
                    "DELETE FROM users WHERE user_id = %s",
                    (user_id,),
                )

        return True

    @staticmethod
    def add_book(book_id, title, author, isbn, total_copies=1):
        if not book_id or not title or not author or not isbn:
            raise ValueError(
                "All book fields (book_id, title, author, isbn) are mandatory."
            )

        if total_copies < 1:
            raise ValueError("Total copies must be at least 1.")

        try:
            with db.connect() as connection:
                with connection.cursor() as cursor:
                    cursor.execute(
                        """
                        INSERT INTO books
                            (
                                book_id, title, author, isbn,
                                total_copies, available_copies
                            )
                        VALUES (%s, %s, %s, %s, %s, %s)
                        RETURNING
                            book_id, title, author, isbn,
                            total_copies, available_copies
                        """,
                        (
                            book_id,
                            title,
                            author,
                            isbn,
                            total_copies,
                            total_copies,
                        ),
                    )
                    return cursor.fetchone()

        except errors.UniqueViolation:
            raise ValueError(
                f"Book with ID '{book_id}' already exists."
            ) from None

    @staticmethod
    def get_book(book_id):
        with db.connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT
                        book_id, title, author, isbn,
                        total_copies, available_copies
                    FROM books
                    WHERE book_id = %s
                    """,
                    (book_id,),
                )
                return cursor.fetchone()

    @staticmethod
    def search_books(query=""):
        query = query.strip()

        with db.connect() as connection:
            with connection.cursor() as cursor:
                if not query:
                    cursor.execute(
                        """
                        SELECT
                            book_id, title, author, isbn,
                            total_copies, available_copies
                        FROM books
                        ORDER BY book_id
                        """
                    )
                else:
                    pattern = f"%{query}%"
                    cursor.execute(
                        """
                        SELECT
                            book_id, title, author, isbn,
                            total_copies, available_copies
                        FROM books
                        WHERE title ILIKE %s
                           OR author ILIKE %s
                           OR isbn ILIKE %s
                        ORDER BY book_id
                        """,
                        (pattern, pattern, pattern),
                    )

                return cursor.fetchall()

    @staticmethod
    def borrow_book(user_id, book_id):
        with db.connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT user_id, name, role, active_loans
                    FROM users
                    WHERE user_id = %s
                    FOR UPDATE
                    """,
                    (user_id,),
                )
                user = cursor.fetchone()

                if not user:
                    raise ValueError(
                        f"User '{user_id}' not registered."
                    )

                max_quota = 5 if user["role"] == "Faculty" else 3

                # Count actual active loan records rather than relying
                # only on the cached counter.
                active_loans = LibraryService._get_active_loan_count(
                    cursor, user_id
                )

                if active_loans >= max_quota:
                    raise ValueError(
                        f"User loan quota exceeded (Max: {max_quota})."
                    )

                cursor.execute(
                    """
                    UPDATE books
                    SET available_copies = available_copies - 1
                    WHERE book_id = %s AND available_copies > 0
                    RETURNING book_id, title, available_copies
                    """,
                    (book_id,),
                )
                book = cursor.fetchone()

                if not book:
                    cursor.execute(
                        "SELECT book_id, title FROM books WHERE book_id = %s",
                        (book_id,),
                    )
                    existing_book = cursor.fetchone()

                    if not existing_book:
                        raise ValueError(
                            f"Book '{book_id}' not found in catalog."
                        )

                    raise ValueError(
                        f"Book '{existing_book['title']}' "
                        "is currently out of stock."
                    )

                loan_id = f"L-{uuid4().hex[:12].upper()}"
                borrowed_at = datetime.now(timezone.utc)

                cursor.execute(
                    """
                    INSERT INTO loans
                        (loan_id, user_id, book_id, borrowed_at, status)
                    VALUES (%s, %s, %s, %s, 'ACTIVE')
                    RETURNING
                        loan_id, user_id, book_id,
                        borrowed_at, returned_at, status
                    """,
                    (loan_id, user_id, book_id, borrowed_at),
                )
                loan = cursor.fetchone()

                cursor.execute(
                    """
                    UPDATE users
                    SET active_loans = %s
                    WHERE user_id = %s
                    """,
                    (active_loans + 1, user_id),
                )

                return loan

    @staticmethod
    def return_book(user_id, book_id):
        with db.connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT user_id, active_loans
                    FROM users
                    WHERE user_id = %s
                    FOR UPDATE
                    """,
                    (user_id,),
                )
                user = cursor.fetchone()

                cursor.execute(
                    """
                    SELECT book_id, available_copies
                    FROM books
                    WHERE book_id = %s
                    FOR UPDATE
                    """,
                    (book_id,),
                )
                book = cursor.fetchone()

                if not user or not book:
                    raise ValueError("Invalid user or book ID.")

                cursor.execute(
                    """
                    SELECT
                        loan_id, user_id, book_id,
                        borrowed_at, returned_at, status
                    FROM loans
                    WHERE user_id = %s
                      AND book_id = %s
                      AND status = 'ACTIVE'
                    ORDER BY borrowed_at
                    LIMIT 1
                    FOR UPDATE
                    """,
                    (user_id, book_id),
                )
                loan = cursor.fetchone()

                if not loan:
                    raise ValueError(
                        f"No active loan found for user '{user_id}' "
                        f"and book '{book_id}'."
                    )

                returned_at = datetime.now(timezone.utc)

                cursor.execute(
                    """
                    UPDATE loans
                    SET status = 'RETURNED', returned_at = %s
                    WHERE loan_id = %s
                    RETURNING
                        loan_id, user_id, book_id,
                        borrowed_at, returned_at, status
                    """,
                    (returned_at, loan["loan_id"]),
                )
                returned_loan = cursor.fetchone()

                cursor.execute(
                    """
                    UPDATE books
                    SET available_copies = available_copies + 1
                    WHERE book_id = %s
                    """,
                    (book_id,),
                )

                cursor.execute(
                    """
                    UPDATE users
                    SET active_loans = GREATEST(active_loans - 1, 0)
                    WHERE user_id = %s
                    """,
                    (user_id,),
                )

                return returned_loan
