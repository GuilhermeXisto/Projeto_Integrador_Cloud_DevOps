# Runbook de diagnóstico e recuperação

## Método (o que explicar ao professor)

Seguir o caminho da requisição **de fora para dentro** e parar na primeira camada que falhar:

```
DNS → rede/firewall → servidor → Docker → Traefik → container app → aplicação
```

Primeiro comando sempre:

```bash
cd /opt/projeto-cloud-devops && bash scripts/diagnostico.sh
```

Depois: **identificar → investigar a causa (logs) → corrigir → validar → explicar**.

Comandos que resolvem 90% dos casos:

```bash
docker compose ps                        # estado e health de cada container
docker logs --tail 100 app               # logs da aplicação
docker logs --tail 100 traefik           # logs do proxy / certificados
docker inspect app --format '{{.State.ExitCode}} {{.RestartCount}} {{.State.OOMKilled}}'
curl -I https://DOMINIO                  # testa de fora
curl -s http://localhost -H "Host: DOMINIO" -k   # testa direto no servidor
df -h ; free -h ; top                    # recursos
sudo ss -tlnp                            # quem está escutando em cada porta
sudo ufw status                          # firewall
```

---

## Cenários do desafio surpresa

### 1. Aplicação fora do ar
- **Sintoma**: Kuma vermelho; navegador mostra erro ou `502 Bad Gateway` / `404 page not found` (do Traefik).
- **Investigar**: `502` → Traefik está ok mas não alcança o app. `404 page not found` → Traefik não tem rota (container app não existe ou label errada). Sem resposta → Traefik/servidor/rede.
- **Corrigir**: `docker compose up -d` ; conferir `docker compose ps`.

### 2. Container parado
- **Sintoma**: `docker compose ps` mostra `exited`.
- **Investigar**: `docker logs app` e o exit code (`137` = morto por falta de memória ou `docker kill`; `1` = erro da aplicação; `0` = parado manualmente).
- **Corrigir**: `docker compose up -d app`. Se foi OOM, criar swap / aumentar a VM.

### 3. Container reiniciando (restart loop)
- **Sintoma**: `Restarting (1) X seconds ago`, RestartCount subindo.
- **Investigar**: `docker logs --tail 50 app` → erro de import, variável faltando, porta em uso, imagem errada.
- **Corrigir**: corrigir a causa. Se veio de um deploy → **rollback**:
  ```bash
  # SHA anterior: aba Actions, ou: git log --oneline
  sed -i 's/^IMAGE_TAG=.*/IMAGE_TAG=<sha-anterior-completo>/' .env
  docker compose up -d app
  ```
  E corrigir no código com `git revert <commit> && git push`.

### 4. Problema de DNS
- **Sintoma**: navegador diz "não foi possível encontrar o servidor"; o IP direto funciona.
- **Investigar**: `nslookup DOMINIO` / `dig +short DOMINIO` → IP diferente do da VM ou nenhum.
- **Corrigir**: atualizar o IP no DuckDNS (ou `bash scripts/duckdns-update.sh`). Explicar o **TTL/cache**: pode levar alguns minutos; testar com `dig @1.1.1.1 DOMINIO`.

### 5. Problema de HTTPS
- **Sintoma**: aviso de certificado inválido / "TRAEFIK DEFAULT CERT" / `ERR_CERT_*`.
- **Investigar**:
  ```bash
  echo | openssl s_client -connect DOMINIO:443 -servername DOMINIO 2>/dev/null | openssl x509 -noout -issuer -dates
  docker logs traefik 2>&1 | grep -i -E "acme|certificate|error"
  ```
  Causas comuns: porta 80 bloqueada (Let's Encrypt não valida), DNS errado, `ACME_EMAIL`/`DOMAIN` errados no `.env`, limite de emissões do Let's Encrypt.
- **Corrigir**: liberar a 80, corrigir DNS/.env, `docker compose up -d --force-recreate traefik`. Último recurso: apagar o volume `letsencrypt` para forçar nova emissão (cuidado com o rate limit).

### 6. Porta bloqueada
- **Sintoma**: timeout ao acessar; no servidor `curl localhost` funciona.
- **Investigar**: `sudo ufw status` (regra removida?) e as regras do provedor (Security List / Security Group). `sudo ss -tlnp | grep -E ':80|:443'` para ver se o Traefik está escutando.
- **Corrigir**: `sudo ufw allow 443/tcp` (ou 80) e/ou reabrir a regra no painel do provedor.

### 7. Problema no reverse proxy
- **Sintoma**: `404 page not found`, `502`, ou Traefik parado.
- **Investigar**: `docker compose ps traefik`, `docker logs traefik`, `docker inspect app --format '{{json .Config.Labels}}'` (label alterada?), app e traefik na mesma rede? `docker network inspect web`.
- **Corrigir**: `docker compose up -d` (recria com as labels corretas do compose), `git diff docker-compose.yml` para achar alteração indevida.

### 8. Falta de espaço em disco
- **Sintoma**: deploy falha com `no space left on device`; containers não sobem; Kuma não grava.
- **Investigar**: `df -h`, `docker system df`, `sudo du -xh / --max-depth=2 | sort -h | tail`.
- **Corrigir**:
  ```bash
  docker system prune -af          # imagens/containers não usados (não apaga volumes)
  sudo journalctl --vacuum-size=100M
  sudo apt-get clean
  # encontrar arquivo gigante: sudo find / -xdev -size +500M 2>/dev/null
  ```

### 9. Falha no deploy
- **Sintoma**: job vermelho na aba Actions; produção continua na versão anterior.
- **Investigar**: qual job falhou?
  - **Testes** → bug no código; ver o log do pytest.
  - **Build** → erro no Dockerfile/dependência.
  - **Deploy** → SSH (secret errado, IP mudou, porta 22 fechada), `git pull` com conflito, imagem não encontrada (pacote GHCR privado), disco cheio.
  - **Verificação** → container subiu mas `/health` não respondeu com o commit novo.
- **Corrigir** conforme a causa e reexecutar (**Re-run jobs**). Produção não fica quebrada porque os testes e o smoke test rodam **antes** do deploy.

### Servidor parou / VM perdida
1. VM só parada: iniciar pelo painel do provedor. Os containers voltam sozinhos (`restart: unless-stopped` + Docker habilitado no boot).
2. VM perdida: criar nova VM → `setup-server.sh` → restaurar `.env` (e, se tiver, o backup de `letsencrypt` e `kuma-data`) → atualizar DNS para o novo IP → atualizar o secret `SSH_HOST` → `docker compose up -d`.
   Restaurar backup:
   ```bash
   docker compose up -d && docker compose stop
   tar xzf backup-XXXX.tar.gz -C /tmp
   docker run --rm -v projeto-cloud-devops_kuma-data:/kuma -v /tmp/kuma:/src alpine cp -a /src/. /kuma/
   docker run --rm -v projeto-cloud-devops_letsencrypt:/le -v /tmp/letsencrypt:/src alpine cp -a /src/. /le/
   docker compose up -d
   ```
   Tudo o que define o ambiente está no Git — só os segredos e os dados ficam fora.
