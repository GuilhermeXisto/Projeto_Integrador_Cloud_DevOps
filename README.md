# Projeto Integrador — Cloud & DevOps

Aplicação web simples que exibe a disciplina e os integrantes do grupo, levada do código até a produção com Git, Docker, nuvem, HTTPS, CI/CD e monitoramento. O acesso é feito diretamente pelo **IP público** do servidor (sem domínio).

| Item | Valor |
|---|---|
| **Aplicação** | https://3.142.172.36 |
| **Status / Monitoramento** | https://3.142.172.36:3001 |
| **Health check** | https://3.142.172.36/health |
| **Repositório** | https://github.com/GuilhermeXisto/Projeto_Integrador_Cloud_DevOps |
| **Disciplina** | Cloud Computing e DevOps |
| **Integrantes** | Guilherme Henrique Xisto da Silva · Lael Cândido Batista Veiga · Vinicius de Oliveira Mateus · Arthur Leite · João Vitor Davy · João Pedro Moraes Silva |

```
Código → Git → Docker → Cloud → IP público → HTTPS → CI/CD → Produção → Monitoramento → Diagnóstico
```

---

## 1. Descrição da aplicação

Aplicação web em **Python/Flask**, servida pelo **Gunicorn**, com duas rotas:

| Rota | Função |
|---|---|
| `/` | Página inicial com a disciplina, os integrantes e, no rodapé, a versão/commit em execução (prova visual de que o deploy funcionou) |
| `/health` | Retorna JSON `{"status":"ok", "commit": ...}`. Usado pelo HEALTHCHECK do Docker, pela pipeline e pelo Uptime Kuma |

## 2. Arquitetura do ambiente

```
                         ┌──────────────────────── VM na nuvem (Ubuntu) ───────────────────────┐
                         │  Firewall: só 22, 80, 443, 3001                                      │
 Usuário ──► IP público ─┼─► :443  ┌─────────┐   rede docker "web"   ┌──────────────────┐       │
 (navegador)             │         │ Traefik │ ───────────────────►  │ app (Flask:8000) │       │
                         ├─► :3001 │  HTTPS  │ ───────────────────►  │ uptime-kuma:3001 │       │
                         │         └─────────┘                       └──────────────────┘       │
                         └──────────────────────────────────────────────────────────────────────┘
 GitHub (push) ──► GitHub Actions ──► GHCR (imagem) ──► SSH no servidor ──► docker compose up
```

Detalhes de cada componente: [docs/ARQUITETURA.md](docs/ARQUITETURA.md).

## 3. Tecnologias utilizadas

| Camada | Tecnologia |
|---|---|
| Aplicação | Python 3.12, Flask, Gunicorn |
| Testes | pytest |
| Versionamento | Git + GitHub |
| Containers | Docker, Docker Compose |
| Registry | GitHub Container Registry (ghcr.io) |
| Nuvem | AWS EC2 — Ubuntu 24.04 |
| Automação da infraestrutura | **Ansible** (prepara o servidor e implanta a stack) |
| Acesso | IP público da VM (sem domínio) |
| Reverse proxy + HTTPS | Traefik v3 (certificado autoassinado) |
| CI/CD | GitHub Actions |
| Monitoramento | Uptime Kuma + HEALTHCHECK do Docker + `scripts/diagnostico.sh` |
| Segurança | UFW, SSH só por chave, GitHub Secrets, `.env` fora do Git, container sem root |

## 4. Estrutura do projeto

```
.
├── app/
│   ├── app.py                 # aplicação Flask (rotas / e /health)
│   └── templates/index.html   # página inicial
├── tests/test_app.py          # testes automatizados (rodam na pipeline)
├── Dockerfile                 # receita da imagem
├── docker-compose.yml         # traefik + app + uptime-kuma
├── .env.example               # modelo de variáveis (o .env real NÃO vai pro Git)
├── .github/workflows/         # pipeline CI/CD (testes → build → deploy/monitoramento)
├── ansible/                   # N2: automação com Ansible
│   ├── ansible.cfg            # configuração (inventário padrão, SSH)
│   ├── inventory.ini          # servidor(es) de destino (IP + usuário + chave)
│   ├── group_vars/all.yml     # variáveis (repositório, imagem, pacotes, portas)
│   ├── templates/env.j2       # modelo do .env gerado no servidor
│   ├── requirements.yml       # coleções do Ansible usadas
│   └── playbook.yml           # prepara o servidor + implanta + verifica
├── scripts/
│   ├── setup-server.sh        # prepara a VM (Docker, firewall, SSH)
│   ├── diagnostico.sh         # checa servidor → containers → portas → HTTPS → app
│   └── backup.sh              # backup do .env e dos dados do Kuma
└── docs/
    ├── ARQUITETURA.md         # arquitetura e fluxo de cada requisição
    ├── DEPLOY.md              # instalação do zero: AWS, Ansible, secrets, monitoramento
    ├── RECUPERACAO.md         # runbook de falhas (desafio surpresa)
    ├── DEFESA-N2.md           # roteiro da apresentação + respostas às perguntas técnicas
    ├── EVIDENCIAS.md          # evidências da entrega (N1 e N2)
    └── evidencias/            # prints das evidências
```

## 5. Ambiente Cloud

| Item | Valor |
|---|---|
| Provedor | AWS (Amazon EC2) |
| Região | us-east-2 (Ohio) |
| Instância | `i-094900e790207c84f` · par de chaves `keys-lab-castelo` |
| Sistema operacional | Ubuntu Server (usuário `ubuntu`) |
| Recursos | _preencher com o tipo da instância (ex.: t2.micro — 1 vCPU, 1 GB RAM)_ |
| IP público | **3.142.172.36** |
| Security Group | `launch-wizard-1` — entrada 22, 80, 443, 3001 |
| Portas abertas | 22 (SSH), 80 (HTTP → redireciona), 443 (HTTPS — aplicação), 3001 (HTTPS — Uptime Kuma) |
| Acesso | `ssh -i keys-lab-castelo.pem ubuntu@3.142.172.36` — somente chave, senha desativada |

## 6. Processo de instalação

### 6.1 Automático com Ansible (N2 — recomendado)

Prepara um servidor Ubuntu **novo** e implanta a aplicação com um único comando. Roda a partir do seu computador (Linux, macOS ou WSL no Windows); o servidor só precisa ter SSH liberado.

**Pré-requisitos**
- VM Ubuntu 22.04/24.04 na nuvem com as portas **22, 80, 443 e 3001** liberadas no security group.
- A chave privada da VM em `~/.ssh/keys-lab-castelo.pem` (é o caminho usado no `inventory.ini`) com `chmod 400`.
- Ansible instalado na máquina de controle. O Ansible não roda direto no Windows: use o **AWS CloudShell**, o WSL ou Linux/macOS.
  ```bash
  pip3 install ansible      # no CloudShell (fora de um virtualenv: pip3 install --user ansible)
  ```

**Preparando a chave no AWS CloudShell** (envie o `.pem` em *Actions → Upload file*):
```bash
mkdir -p ~/.ssh && mv ~/keys-lab-castelo.pem ~/.ssh/ && chmod 400 ~/.ssh/keys-lab-castelo.pem
```

**Execução**
```bash
git clone https://github.com/GuilhermeXisto/Projeto_Integrador_Cloud_DevOps.git
cd Projeto_Integrador_Cloud_DevOps/ansible
cat inventory.ini                                   # 3.142.172.36, usuário ubuntu, chave ~/.ssh/keys-lab-castelo.pem
ansible-galaxy collection install -r requirements.yml
ansible webservers -m ping                          # testa a conexão
ansible-playbook playbook.yml                       # prepara o servidor e implanta
```

**O que o playbook faz**

| Etapa | Tarefas |
|---|---|
| 1. Espera a VM | `wait_for_connection` até o SSH responder |
| 2. Prepara o servidor | instala pacotes base; adiciona o repositório oficial do Docker; instala Docker Engine + plugin Compose; habilita o serviço; coloca o usuário no grupo `docker`; configura o firewall UFW (22, 80, 443, 3001); desativa login SSH por senha e de root; ativa o fail2ban |
| 3. Implanta | clona o repositório em `/opt/projeto-cloud-devops`; gera o `.env` a partir de `templates/env.j2`; baixa as imagens (se a imagem do GHCR não estiver acessível, **constrói a imagem no próprio servidor** pelo `Dockerfile`); `docker compose up -d` |
| 4. Verifica | espera `https://localhost/health` responder 200 e mostra os containers em execução e as URLs de acesso |

O playbook é **idempotente**: pode ser executado de novo sem quebrar nada (só altera o que estiver diferente).

**Acesso após a execução**
- Aplicação: http://3.142.172.36 → redireciona para https://3.142.172.36 (aceite o aviso do certificado autoassinado)
- Uptime Kuma: https://3.142.172.36:3001
- Health check: https://3.142.172.36/health

Em um servidor novo, troque `3.142.172.36` pelo IP que estiver no `inventory.ini`.

**Evidências** — ver [docs/EVIDENCIAS.md](docs/EVIDENCIAS.md#n2--ansible).

### 6.2 Manual com script (alternativa da N1)

```bash
# Na VM
curl -fsSL https://raw.githubusercontent.com/GuilhermeXisto/Projeto_Integrador_Cloud_DevOps/main/scripts/setup-server.sh -o setup.sh
sudo bash setup.sh https://github.com/GuilhermeXisto/Projeto_Integrador_Cloud_DevOps.git
# sair e entrar no SSH de novo
cd /opt/projeto-cloud-devops
nano .env              # IMAGE
docker compose up -d
```

Passo a passo completo (criação da VM, secrets do GitHub): [docs/DEPLOY.md](docs/DEPLOY.md).

**Rodar localmente** (sem nuvem):
```bash
pip install -r requirements-dev.txt && pytest          # testes
docker build -t app-local . && docker run -p 8000:8000 app-local   # http://localhost:8000
```

## 7. Configuração do Docker

- **Dockerfile**: parte de `python:3.12-slim`, instala dependências (camada em cache), copia o código, cria usuário sem privilégios, define `HEALTHCHECK` em `/health` e sobe o Gunicorn na porta 8000.
- **Imagem**: gerada pela pipeline e publicada em `ghcr.io/guilhermexisto/projeto_integrador_cloud_devops` com duas tags: o SHA do commit (versão imutável, permite rollback) e `latest`.
- **Container**: criado pelo Compose a partir da imagem; `restart: unless-stopped` faz ele voltar sozinho após falha ou reboot.
- **docker-compose.yml**: 3 serviços (traefik, app, uptime-kuma), 1 rede (`web`) e 1 volume (`kuma-data`). **Só o Traefik publica portas no host.**

`Código → (docker build) → Imagem → (docker run / compose up) → Container → Aplicação`

## 8. Acesso pelo IP público (sem domínio)

O projeto não usa domínio nem DNS: o acesso é feito direto pelo IP público da VM, **3.142.172.36**.

- Aplicação: `https://3.142.172.36` → porta 443 → Traefik → container app (8000)
- Uptime Kuma: `https://3.142.172.36:3001` → porta 3001 → Traefik → container uptime-kuma (3001)
- `http://3.142.172.36` (porta 80) redireciona para HTTPS.

No provedor de nuvem, libere as portas **22, 80, 443 e 3001** no security group / firewall da VM.

## 9. HTTPS

O HTTPS é feito pelo **Traefik**. Como não há domínio, o Let's Encrypt não emite certificado; o Traefik usa um **certificado autoassinado** gerado por ele mesmo. A conexão é criptografada, mas o navegador mostra o aviso "Sua conexão não é particular" na primeira vez (clique em *Avançado → Continuar*). Todo acesso HTTP é redirecionado para HTTPS.

Para ter um certificado válido (sem aviso) no futuro, basta apontar um domínio (ex.: DuckDNS) para o IP e configurar o `certresolver` do Let's Encrypt no Traefik.

## 10. Processo de CI/CD

Workflows em `.github/workflows/` — disparados a cada `git push` na `main`:

1. **Testes** — instala dependências, roda `pytest`, valida o `docker-compose.yml`.
2. **Build** — `docker build` com o SHA do commit embutido; sobe o container no runner e testa `/health`; publica a imagem no GHCR.
3. **Deploy** — via SSH: `git pull`, grava a nova tag no `.env`, `docker compose pull` e `up -d`.
4. **Verificação** — acessa `https://SSH_HOST/health` (o IP público, com `curl -k` por causa do certificado autoassinado) e confirma que o commit novo está no ar.

Pull requests rodam só testes + build (não fazem deploy).
**Secrets usados** (ambiente `producao`): `SSH_HOST` (IP público), `SSH_USER`, `SSH_PRIVATE_KEY`.

## 11. Monitoramento

- **Uptime Kuma** (`https://3.142.172.36:3001`): monitor HTTP da aplicação (`/health`), monitor de palavra-chave e monitor Docker de cada container. Alertas por Telegram/Discord/e-mail.
- **Docker HEALTHCHECK**: `docker ps` mostra `(healthy)` / `(unhealthy)`.
- **`scripts/diagnostico.sh`**: verifica servidor, disco, memória, Docker, containers, portas, IP público, certificado e aplicação em um comando.

## 12. Procedimentos básicos de recuperação

| Situação | Ação |
|---|---|
| Container parado | `docker compose up -d` |
| Deploy com bug | Rollback: `sed -i 's/^IMAGE_TAG=.*/IMAGE_TAG=<sha-anterior>/' .env && docker compose up -d app` (ou `git revert` + push) |
| Disco cheio | `docker system prune -af` / `journalctl --vacuum-size=100M` |
| Servidor perdido | Nova VM → `setup-server.sh` → restaurar `.env` do backup → atualizar o secret `SSH_HOST` com o novo IP → `docker compose up -d` |

Runbook completo: [docs/RECUPERACAO.md](docs/RECUPERACAO.md).

## Segurança — resumo

- Portas abertas: apenas 22, 80, 443 e 3001 (UFW + regras do provedor). Só o Traefik publica portas; app e Kuma ficam na rede interna.
- SSH só com chave; login por senha e root desativados; fail2ban ativo.
- Nenhuma senha no Git: `.env` está no `.gitignore`; credenciais da pipeline em **GitHub Secrets**.
- Container da aplicação roda com usuário sem privilégios.
- Uptime Kuma protegido por usuário/senha; dashboard do Traefik desativado.
- HTTPS obrigatório (HTTP redireciona), com certificado autoassinado.
