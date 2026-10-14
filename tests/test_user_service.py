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
