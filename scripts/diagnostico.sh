#!/usr/bin/env bash
# Diagnóstico rápido do ambiente — útil no "Desafio Surpresa".
# Percorre a cadeia: Servidor → Disco/Memória → Docker → Containers → Portas → DNS → HTTPS → Aplicação
# Uso: bash scripts/diagnostico.sh   (rodar dentro de /opt/projeto-cloud-devops)

cd "$(dirname "$0")/.." || exit 1
[ -f .env ] && set -a && . ./.env && set +a
DOMAIN="${DOMAIN:-localhost}"

ok()   { printf "  \e[32m✔\e[0m %s\n" "$1"; }
fail() { printf "  \e[31m✘\e[0m %s\n" "$1"; }
sec()  { printf "\n\e[1m== %s ==\e[0m\n" "$1"; }

sec "1. Servidor"
uptime
echo "  Kernel: $(uname -r)"

sec "2. Recursos"
df -h / | awk 'NR==2 {print "  Disco /: "$3" usados de "$2" ("$5")"}'
USO_DISCO=$(df / | awk 'NR==2 {gsub("%","",$5); print $5}')
[ "$USO_DISCO" -lt 90 ] && ok "Disco abaixo de 90%" || fail "Disco quase cheio! Tente: docker system prune -af"
free -h | awk 'NR==2 {print "  Memória: "$3" usados de "$2}'

sec "3. Docker"
if systemctl is-active --quiet docker; then ok "Serviço docker ativo"; else fail "Docker parado → sudo systemctl start docker"; fi

sec "4. Containers"
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
for c in traefik app uptime-kuma; do
  estado=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "inexistente")
  saude=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "$c" 2>/dev/null || echo "-")
  reinicios=$(docker inspect -f '{{.RestartCount}}' "$c" 2>/dev/null || echo "?")
  if [ "$estado" = "running" ] && [ "$saude" != "unhealthy" ]; then
    ok "$c: $estado (health: $saude, restarts: $reinicios)"
  else
    fail "$c: $estado (health: $saude, restarts: $reinicios) → docker logs --tail 50 $c"
  fi
done

sec "5. Portas escutando no host"
ss -tlnp 2>/dev/null | awk 'NR==1 || /:80 |:443 |:22 /'
sudo -n ufw status 2>/dev/null | head -10 || echo "  (rode com sudo para ver o firewall)"

sec "6. DNS"
IP_DNS=$(getent hosts "$DOMAIN" | awk '{print $1}' | head -1)
IP_PUB=$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || echo "?")
echo "  $DOMAIN resolve para: ${IP_DNS:-NADA}   |   IP público deste servidor: $IP_PUB"
[ -n "$IP_DNS" ] && [ "$IP_DNS" = "$IP_PUB" ] && ok "DNS aponta para este servidor" || fail "DNS não aponta para este servidor"

sec "7. HTTPS / Certificado"
CERT=$(echo | timeout 5 openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -issuer -enddate 2>/dev/null)
if [ -n "$CERT" ]; then ok "Certificado encontrado"; echo "$CERT" | sed 's/^/    /'; else fail "Sem certificado válido em $DOMAIN:443"; fi

sec "8. Aplicação"
RESP=$(curl -fsS --max-time 5 "https://$DOMAIN/health" 2>&1)
if [ $? -eq 0 ]; then ok "https://$DOMAIN/health → $RESP"; else fail "Aplicação não respondeu: $RESP"; fi

echo
