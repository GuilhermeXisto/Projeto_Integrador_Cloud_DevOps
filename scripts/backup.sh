#!/usr/bin/env bash
# Backup dos dados que NÃO estão no Git: .env, certificados e dados do Uptime Kuma.
# Uso: bash scripts/backup.sh   → gera ~/backups/backup-AAAAMMDD-HHMM.tar.gz
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="$HOME/backups"
mkdir -p "$DEST"
STAMP=$(date +%Y%m%d-%H%M)

docker run --rm \
  -v projeto-cloud-devops_letsencrypt:/letsencrypt:ro \
  -v projeto-cloud-devops_kuma-data:/kuma:ro \
  -v "$PWD/.env:/env/.env:ro" \
  -v "$DEST:/backup" \
  alpine tar czf "/backup/backup-$STAMP.tar.gz" /letsencrypt /kuma /env

echo "Backup salvo em $DEST/backup-$STAMP.tar.gz"
echo "Copie para fora do servidor:  scp usuario@servidor:$DEST/backup-$STAMP.tar.gz ."
