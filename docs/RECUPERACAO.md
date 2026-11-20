# Runbook de diagnóstico e recuperação

## Método (o que explicar ao professor)

Seguir o caminho da requisição **de fora para dentro** e parar na primeira camada que falhar:

```
IP/rede (Security Group + UFW) → servidor → Docker → Traefik → container app → aplicação
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
curl -kI https://3.142.172.36            # testa de fora (-k: certificado autoassinado)
curl -k https://localhost/health         # testa direto no servidor
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

### 4. IP público mudou
- **Sintoma**: https://3.142.172.36 não responde (timeout), o deploy falha no SSH, mas a instância aparece *running* no console da AWS.
- **Investigar**: no console **EC2 → Instances**, conferir o *Public IPv4 address*. Ao parar e iniciar uma instância sem **Elastic IP**, a AWS atribui um IP novo. Pelo CloudShell: `aws ec2 describe-instances --query "Reservations[].Instances[].PublicIpAddress"`.
- **Corrigir**: atualizar o novo IP no secret `SSH_HOST`, no `ansible/inventory.ini` e na documentação. Para não acontecer de novo: associar um **Elastic IP** à instância.
- **Explicar**: como não usamos domínio, não há DNS para atualizar; o IP é o endereço da aplicação.

### 5. Problema de HTTPS
- **Comportamento esperado**: o navegador mostra "Não seguro" / `NET::ERR_CERT_AUTHORITY_INVALID`. Isso é **normal**: sem domínio, o Traefik usa o próprio certificado **autoassinado** ("TRAEFIK DEFAULT CERT"). A conexão é criptografada, só não é reconhecida por uma autoridade.
- **Sintoma de problema real**: a porta 443 não responde, `ERR_CONNECTION_REFUSED`, ou o Uptime Kuma acusa `self-signed certificate`.
- **Investigar**:
  ```bash
  echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -subject -dates
  docker logs traefik 2>&1 | grep -i -E "tls|certificate|error"
  sudo ss -tlnp | grep ':443'
  ```
- **Corrigir**: Traefik parado → `docker compose up -d traefik`. Porta fechada → ver o cenário 6. Kuma acusando `self-signed certificate` → no monitor, marcar **Avançado → Ignorar erro TLS/SSL**.
- **Evolução**: com um domínio apontando para o IP, dá para usar Let's Encrypt e ter certificado válido.

### 6. Porta bloqueada
- **Sintoma**: timeout ao acessar; no servidor `curl localhost` funciona.
- **Investigar**: `sudo ufw status` (regra removida?) e o **Security Group** `launch-wizard-1` no console da AWS. `sudo ss -tlnp | grep -E ':80|:443|:3001'` para ver se o Traefik está escutando.
- **Corrigir**: `sudo ufw allow 443/tcp` (ou 80/3001) e/ou reabrir a regra no Security Group. Rodar o playbook do Ansible de novo também recria as regras do UFW.

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
  - **Deploy** → SSH (secret `SSH_PRIVATE_KEY` vazio ou errado, IP mudou, porta 22 fechada), `git pull` com conflito ou histórico divergente (`fatal: Not possible to fast-forward` → na VM: `git fetch origin && git reset --hard origin/main`), `.env` sem permissão (`sudo chown ubuntu:ubuntu .env`), imagem não encontrada (pacote GHCR privado), disco cheio.
  - **Verificação** → container subiu mas `/health` não respondeu com o commit novo.
- **Corrigir** conforme a causa e reexecutar (**Re-run jobs**). Produção não fica quebrada porque os testes e o smoke test rodam **antes** do deploy.

### Servidor parou / VM perdida
1. VM só parada: iniciar pelo console da AWS. Os containers voltam sozinhos (`restart: unless-stopped` + Docker habilitado no boot). Conferir se o IP mudou (cenário 4).
2. VM perdida: criar nova EC2 (portas 22/80/443/3001) → trocar o IP no `ansible/inventory.ini` → `ansible-playbook playbook.yml` (prepara o servidor e sobe tudo) → restaurar o backup do `kuma-data`, se tiver → atualizar o secret `SSH_HOST` com o novo IP.
   Restaurar backup:
   ```bash
   docker compose up -d && docker compose stop
   tar xzf backup-XXXX.tar.gz -C /tmp
   docker run --rm -v projeto-cloud-devops_kuma-data:/kuma -v /tmp/kuma:/src alpine cp -a /src/. /kuma/
   docker compose up -d
   ```
   Tudo o que define o ambiente está no Git (inclusive a automação com Ansible) — só os segredos e os dados ficam fora.
