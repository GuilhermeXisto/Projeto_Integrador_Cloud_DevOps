import sys
from html import escape
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))

import pytest  # noqa: E402

from app import DISCIPLINA, INTEGRANTES, app  # noqa: E402


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_pagina_inicial_responde(client):
    resp = client.get("/")
    assert resp.status_code == 200


def test_pagina_mostra_disciplina(client):
    html = client.get("/").get_data(as_text=True)
    assert escape(DISCIPLINA) in html  # "&" vira "&amp;" no HTML


def test_pagina_mostra_todos_integrantes(client):
    html = client.get("/").get_data(as_text=True)
    assert len(INTEGRANTES) >= 1
    for nome in INTEGRANTES:
        assert nome in html


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"
