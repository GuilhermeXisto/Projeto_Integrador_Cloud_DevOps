"""Aplicação web do Projeto Integrador — Cloud & DevOps."""
import os
import socket
from datetime import datetime, timezone

from flask import Flask, jsonify, render_template

DISCIPLINA = "Cloud Computing & DevOps"

# Nome completo de TODOS os integrantes do grupo (exibidos na página inicial).
INTEGRANTES = [
    "Guilherme Henrique Xisto da Silva",
    "Lael Cândido Batista Veiga",
    "Vinicius de Oliveira Mateus",
    "Arthur Leite",
    "João Vitor Davy",
    "João Pedro Moraes Silva",
]

app = Flask(__name__)

# Variáveis injetadas no build da imagem pela pipeline (ver Dockerfile).
VERSAO = os.getenv("APP_VERSION", "dev")
COMMIT = os.getenv("GIT_SHA", "local")
INICIO = datetime.now(timezone.utc)


@app.route("/")
def index():
    return render_template(
        "index.html",
        disciplina=DISCIPLINA,
        integrantes=INTEGRANTES,
        versao=VERSAO,
        commit=COMMIT[:7],
        host=socket.gethostname(),
    )


@app.route("/health")
def health():
    """Endpoint usado pelo Docker HEALTHCHECK, pela pipeline e pelo Uptime Kuma."""
    uptime = (datetime.now(timezone.utc) - INICIO).total_seconds()
    return jsonify(status="ok", versao=VERSAO, commit=COMMIT, uptime_s=int(uptime))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
