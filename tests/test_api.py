import importlib

import pytest
from fastapi.testclient import TestClient

from app import main


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("APP_VERSION", "test-release-123")
    importlib.reload(main)
    with TestClient(main.app) as client:
        yield client
    monkeypatch.delenv("APP_VERSION")
    importlib.reload(main)


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_version_identifies_release(client):
    response = client.get("/version")
    assert response.status_code == 200
    assert response.json() == {"version": "test-release-123"}


def test_unknown_route(client):
    assert client.get("/missing").status_code == 404


def test_default_development_version(monkeypatch):
    monkeypatch.delenv("APP_VERSION", raising=False)
    importlib.reload(main)
    with TestClient(main.app) as client:
        assert client.get("/version").json() == {"version": "dev"}
