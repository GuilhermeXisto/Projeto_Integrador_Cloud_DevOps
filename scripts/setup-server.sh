#!/usr/bin/env bash
# Prepara um servidor Ubuntu 22.04/24.04 recém-criado na nuvem.
# Uso (no servidor):  sudo bash setup-server.sh <url-do-repositorio>
set -euo pipefail

REPO_URL="${1:-https://github.com/GuilhermeXisto/Projeto_Integrador_Cloud_DevOps.git}"
APP_DIR="/opt/projeto-cloud-devops"
DEPLOY_USER="${SUDO_USER:-ubuntu}"

echo "==> Atualizando pacotes"
apt-get update -y && apt-get upgrade -y
apt-get install -y ca-certificates curl git ufw fail2ban unattended-upgrades

echo "==> Instalando Docker Engine + Compose plugin"
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
usermod -aG docker "$DEPLOY_USER"
systemctl enable --now docker

echo "==> Firewall: só SSH, HTTP, HTTPS e 3001 (Uptime Kuma)"
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 3001/tcp
ufw --force enable

echo "==> SSH: desativando login por senha e login direto como root"
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart ssh || systemctl restart sshd

echo "==> Clonando repositório em $APP_DIR"
if [ ! -d "$APP_DIR/.git" ]; then
  git clone "$REPO_URL" "$APP_DIR"
fi
chown -R "$DEPLOY_USER":"$DEPLOY_USER" "$APP_DIR"

if [ ! -f "$APP_DIR/.env" ]; then
  cp "$APP_DIR/.env.example" "$APP_DIR/.env"
  chmod 600 "$APP_DIR/.env"
  # O deploy (via SSH, como $DEPLOY_USER) precisa ler e editar o .env
  chown "$DEPLOY_USER":"$DEPLOY_USER" "$APP_DIR/.env"
  echo "!! Edite $APP_DIR/.env (IMAGE) antes de subir os containers."
fi

echo
echo "Pronto. Próximos passos:"
echo "  1) Saia e entre de novo no SSH (para o grupo docker valer)"
echo "  2) nano $APP_DIR/.env"
echo "  3) cd $APP_DIR && docker compose up -d"
