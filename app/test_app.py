"""Unit tests executed by the local and Jenkins pipelines."""
import pytest

from app import create_app


@pytest.fixture
def client():
    application = create_app(
        {
            "TESTING": True,
            "DATABASE_URL": "sqlite+pysqlite:///:memory:",
            "APP_VERSION": "test-version",
            "APP_ENV": "test",
        }
    )
    with application.test_client() as test_client:
        yield test_client


def test_home_returns_200(client):
    response = client.get("/")
    assert response.status_code == 200
    assert b"DevOps Deployment Tracker" in response.data


def test_health_endpoint(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_readiness_checks_database(client):
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.get_json()["database"] == "connected"


def test_create_and_list_deployment(client):
    create_response = client.post(
        "/api/deployments",
        json={
            "service_name": "starter-api",
            "environment": "test",
            "status": "success",
        },
    )
    assert create_response.status_code == 201
    assert create_response.get_json()["status"] == "SUCCESS"

    list_response = client.get("/api/deployments")
    data = list_response.get_json()
    assert list_response.status_code == 200
    assert len(data) == 1
    assert data[0]["service_name"] == "starter-api"


def test_rejects_invalid_payload(client):
    response = client.post("/api/deployments", json={"service_name": "api"})
    assert response.status_code == 400
