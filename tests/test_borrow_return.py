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
