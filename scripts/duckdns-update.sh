#!/usr/bin/env bash
# Atualiza o IP no DuckDNS (só necessário se o IP público da VM puder mudar).
# Agendar no cron:  */5 * * * * /opt/projeto-cloud-devops/scripts/duckdns-update.sh >/dev/null 2>&1
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

SUB="${DOMAIN%%.duckdns.org}"
curl -fsS "https://www.duckdns.org/update?domains=${SUB}&token=${DUCKDNS_TOKEN}&ip="
echo
