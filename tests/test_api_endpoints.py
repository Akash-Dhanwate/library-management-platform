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
