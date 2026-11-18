# Deploy do zero

Ordem: **GitHub → VM → DNS → .env → subir containers → secrets → primeiro push → monitoramento**.

## 1. Repositório no GitHub

```bash
git init
git add .
git commit -m "feat: estrutura inicial do projeto"
git branch -M main
git remote add origin https://github.com/flacolael/projeto-cloud-devops.git
git push -u origin main
```

Deixe o repositório **público** (exigência do professor).
Edite `app/app.py` → lista `INTEGRANTES` com o nome completo de todos.

## 2. Criar a VM na nuvem

Qualquer provedor serve. Exemplo de configuração mínima:

| | |
|---|---|
| Imagem | Ubuntu Server 24.04 LTS |
| Tamanho | 1 vCPU / 1 GB RAM já funciona (Oracle Always Free, AWS t3.micro/t2.micro, Azure B1s, GCP e2-micro) |
| Disco | 20–30 GB |
| Chave SSH | gere com `ssh-keygen -t ed25519 -f ~/.ssh/projeto` e cadastre a **pública** (`projeto.pub`) |
| Regras de rede | Entrada TCP 22, 80, 443 (Oracle: Security List da VCN; AWS: Security Group; Azure: NSG; GCP: firewall rules) |

> **Oracle Cloud**: além da Security List, a imagem Ubuntu da Oracle vem com regras de iptables próprias. O `setup-server.sh` usa UFW; se 80/443 não abrirem, rode `sudo iptables -I INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT && sudo netfilter-persistent save`.
>
> Se a RAM for 1 GB, crie swap: `sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile && echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab`

Anote o **IP público**.

## 3. Preparar o servidor

```bash
ssh -i ~/.ssh/projeto ubuntu@IP_PUBLICO

curl -fsSL https://raw.githubusercontent.com/flacolael/projeto-cloud-devops/main/scripts/setup-server.sh -o setup.sh
sudo bash setup.sh https://github.com/flacolael/projeto-cloud-devops.git
exit   # sair e entrar de novo para o grupo docker valer
```

> ⚠️ O script desativa login por senha no SSH. Confirme que você está entrando **com chave** antes de rodar.

## 4. DNS (DuckDNS)

1. Entre em https://www.duckdns.org com sua conta do GitHub.
2. Crie o subdomínio, ex.: `projeto-lael` → `projeto-lael.duckdns.org`.
3. Em **current ip**, coloque o IP público da VM e clique em **update ip**.
4. Copie o **token** (vai no `.env` se for usar o `duckdns-update.sh`).
5. Teste do seu computador: `nslookup projeto-lael.duckdns.org` → deve retornar o IP da VM.

`status.projeto-lael.duckdns.org` já resolve para o mesmo IP, sem configuração extra.

> **Domínio próprio** (Registro.br, Cloudflare etc.): crie registro **A** `@ → IP` e **A** `status → IP`. Se usar Cloudflare com proxy (nuvem laranja), use modo SSL **Full (strict)**.

## 5. Configurar o `.env` e subir

```bash
ssh -i ~/.ssh/projeto ubuntu@IP_PUBLICO
cd /opt/projeto-cloud-devops
nano .env
```

```ini
DOMAIN=projeto-lael.duckdns.org
ACME_EMAIL=seu-email@exemplo.com
IMAGE=ghcr.io/flacolael/projeto-cloud-devops
IMAGE_TAG=latest
```

**Antes do primeiro push da pipeline** ainda não existe imagem no GHCR. Para subir já, faça o build no próprio servidor:

```bash
docker compose build app
docker compose up -d
docker compose ps
docker logs -f traefik     # acompanhe a emissão do certificado
```

Acesse `https://projeto-lael.duckdns.org` — deve abrir com cadeado. 🎉

## 6. Secrets da pipeline

Gere uma chave **só para o deploy** (no seu computador):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/deploy_github -N "" -C "github-actions"
ssh-copy-id -i ~/.ssh/deploy_github.pub -o "IdentityFile ~/.ssh/projeto" ubuntu@IP_PUBLICO
```

No GitHub: **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Valor |
|---|---|
| `SSH_HOST` | IP público da VM |
| `SSH_USER` | `ubuntu` (ou seu usuário) |
| `SSH_PRIVATE_KEY` | conteúdo inteiro de `~/.ssh/deploy_github` (a **privada**) |
| `DOMAIN` | `projeto-lael.duckdns.org` |

Crie também o environment **producao** em **Settings → Environments** (o job de deploy usa ele).

## 7. Primeiro deploy pela pipeline

```bash
git commit --allow-empty -m "ci: primeiro deploy automatizado"
git push
```

Acompanhe na aba **Actions**. Depois do primeiro push:

1. Vá no seu perfil → **Packages** → `projeto-cloud-devops` → **Package settings** → **Change visibility → Public**.
   (Assim o servidor faz `docker compose pull` sem precisar de login. Alternativa: `docker login ghcr.io` no servidor com um token `read:packages`.)
2. Rode novamente o workflow (**Actions → CI/CD → Re-run all jobs**).

A partir daqui, **todo push na `main` vai para produção**. O rodapé da página mostra o número da versão e o commit.

## 8. Monitoramento (Uptime Kuma)

1. Acesse `https://status.projeto-lael.duckdns.org` e **crie o usuário admin** imediatamente (senha forte — antes disso qualquer um pode criar).
2. Adicione monitores:

| Tipo | Configuração | Detecta |
|---|---|---|
| HTTP(s) | `https://projeto-lael.duckdns.org/health`, intervalo 60s | App fora do ar, erro 5xx, problema de proxy |
| HTTP(s) – Keyword | URL `/`, palavra `Cloud Computing` | Página quebrada mesmo com 200 |
| HTTP(s) | marque **Certificate Expiry Notification** | Certificado expirando/inválido |
| Docker Container | host Docker: socket `/var/run/docker.sock`; containers `app` e `traefik` | Container parado/reiniciando |
| DNS | `projeto-lael.duckdns.org`, tipo A, servidor 1.1.1.1 | DNS apontando errado |

3. **Settings → Notifications**: configure Telegram, Discord ou e-mail e associe aos monitores.
4. (Opcional) Crie uma **Status Page** pública.

## 9. Backups

```bash
bash scripts/backup.sh
# cron diário às 3h:
(crontab -l 2>/dev/null; echo "0 3 * * * cd /opt/projeto-cloud-devops && bash scripts/backup.sh") | crontab -
```

Copie periodicamente os backups para fora da VM.
