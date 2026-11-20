# Deploy do zero

Ordem: **VM na AWS → Ansible (prepara e implanta) → secrets do GitHub → pipeline → monitoramento**.

O acesso é feito direto pelo **IP público** da VM (sem domínio). Ambiente atual:

| Item | Valor |
|---|---|
| Provedor | AWS EC2 — região us-east-2 (Ohio) |
| Instância | `i-094900e790207c84f` |
| IP público | **3.142.172.36** |
| Usuário SSH | `ubuntu` |
| Par de chaves | `keys-lab-castelo` (arquivo `keys-lab-castelo.pem`, nunca vai para o Git) |
| Security Group | `launch-wizard-1` |

## 1. Criar a VM na AWS

No console da AWS: **EC2 → Launch instance**.

| Campo | Valor |
|---|---|
| Imagem (AMI) | Ubuntu Server 24.04 LTS (ou 22.04) |
| Tipo | t2.micro / t3.micro (1 vCPU, 1 GB RAM) já funciona |
| Par de chaves | `keys-lab-castelo` (ou crie um e baixe o `.pem`) |
| Disco | 20–30 GB |
| Security Group — entrada | TCP **22** (SSH), **80** (HTTP), **443** (HTTPS), **3001** (Uptime Kuma), origem `0.0.0.0/0` |

> A porta 22 precisa estar aberta para `0.0.0.0/0` (e não "My IP"): o GitHub Actions faz o deploy por SSH a partir de IPs que mudam a cada execução. O acesso continua protegido porque o servidor só aceita login com chave.
>
> Anote o **IP público** da instância. Se a instância for parada e iniciada, o IP pode mudar; para fixá-lo, associe um **Elastic IP**.
>
> Com 1 GB de RAM, é recomendável criar swap: `sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile && echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab`

## 2. Preparar o servidor e implantar com Ansible (N2)

O Ansible roda na **máquina de controle** e configura a VM por SSH. Ele não roda direto no Windows: use o **AWS CloudShell** (ícone `>_` no console), o WSL ou Linux/macOS.

```bash
# 1. Chave SSH (no CloudShell: Actions → Upload file → keys-lab-castelo.pem)
mkdir -p ~/.ssh && mv ~/keys-lab-castelo.pem ~/.ssh/ && chmod 400 ~/.ssh/keys-lab-castelo.pem

# 2. Ansible
pip3 install ansible

# 3. Projeto
git clone https://github.com/GuilhermeXisto/Projeto_Integrador_Cloud_DevOps.git
cd Projeto_Integrador_Cloud_DevOps/ansible
ansible-galaxy collection install -r requirements.yml

# 4. Conferir o inventário (IP, usuário e caminho da chave)
cat inventory.ini

# 5. Testar a conexão e rodar
ansible webservers -m ping
ansible-playbook playbook.yml
```

Para uma **VM nova**, basta trocar o IP na linha do `inventory.ini`:

```ini
[webservers]
NOVO_IP ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/keys-lab-castelo.pem
```

O playbook instala Docker + Compose, configura firewall e SSH, clona o repositório em `/opt/projeto-cloud-devops`, gera o `.env`, sobe Traefik + app + Uptime Kuma e verifica `https://localhost/health`. Detalhes no [README](../README.md#61-automático-com-ansible-n2--recomendado).

**Alternativa manual (sem Ansible):** `scripts/setup-server.sh` faz a preparação do servidor; depois `cd /opt/projeto-cloud-devops && docker compose up -d`.

## 3. Conferir no navegador

| Serviço | Endereço |
|---|---|
| Aplicação | https://3.142.172.36 (`http://3.142.172.36` redireciona para HTTPS) |
| Health check | https://3.142.172.36/health |
| Uptime Kuma | https://3.142.172.36:3001 |

O HTTPS usa um certificado **autoassinado** gerado pelo Traefik (sem domínio, o Let's Encrypt não emite certificado). O navegador mostra "Não seguro": clique em **Avançado → Continuar**.

## 4. Secrets da pipeline

No GitHub: **Settings → Secrets and variables → Actions → New repository secret** (aba *Secrets*, não *Variables*):

| Secret | Valor |
|---|---|
| `SSH_HOST` | `3.142.172.36` |
| `SSH_USER` | `ubuntu` |
| `SSH_PRIVATE_KEY` | conteúdo inteiro do `keys-lab-castelo.pem`, de `-----BEGIN` até `-----END ... KEY-----` |

Crie também o environment **producao** em **Settings → Environments** (o job de deploy usa ele).

## 5. Deploy pela pipeline

Todo `git push` na `main` dispara:

1. **1 - CI (Testes)**: pytest, validação do `docker-compose.yml` e do Ansible (syntax-check + ansible-lint).
2. **2 - Build e Push**: constrói a imagem, testa `/health` num container no runner e publica no GHCR (`ghcr.io/guilhermexisto/projeto_integrador_cloud_devops`, tags `latest` e SHA).
3. **3 - Deploy e Monitoramento**: SSH na VM → `git pull` → grava a tag no `.env` → `docker compose pull` e `up -d` → confere em `https://3.142.172.36/health` que o commit novo está no ar.

Se o deploy falhar com `unauthorized`/`denied` ao baixar a imagem, deixe o pacote público: perfil → **Packages** → `projeto_integrador_cloud_devops` → **Package settings** → **Change visibility → Public**.

O rodapé da página mostra a versão e o commit em execução.

## 6. Monitoramento (Uptime Kuma)

1. Acesse https://3.142.172.36:3001 e **crie o usuário admin** imediatamente (antes disso, qualquer um pode criar).
2. Adicione os monitores:

| Tipo | Configuração | Detecta |
|---|---|---|
| HTTP(s) – Palavra-chave | `https://3.142.172.36/health`, palavra `ok`, **Avançado → Ignorar erro TLS/SSL** marcado | App fora do ar, erro 5xx, problema no proxy |
| HTTP(s) | `http://app:8000/health` (rede interna do Docker, sem passar pelo Traefik) | App travado mesmo com o proxy no ar |
| Docker Container | Docker Host via socket `/var/run/docker.sock`; containers `app`, `traefik`, `uptime-kuma` | Container parado ou reiniciando |

> Sem a opção **Ignorar erro TLS/SSL**, o monitor fica vermelho com o erro `self-signed certificate`.

3. **Configurações → Notificações**: configure Telegram, Discord ou e-mail e associe aos monitores.

## 7. Backups

```bash
cd /opt/projeto-cloud-devops && bash scripts/backup.sh
# cron diário às 3h:
(crontab -l 2>/dev/null; echo "0 3 * * * cd /opt/projeto-cloud-devops && bash scripts/backup.sh") | crontab -
```

O backup guarda o `.env` e os dados do Uptime Kuma. Copie periodicamente para fora da VM:

```bash
scp -i keys-lab-castelo.pem ubuntu@3.142.172.36:~/backups/backup-*.tar.gz .
```
