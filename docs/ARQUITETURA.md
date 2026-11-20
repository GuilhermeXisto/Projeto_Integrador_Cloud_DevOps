# Arquitetura

## Diagrama

```
                    ┌─────────────┐
                    │   Usuário   │  https://3.142.172.36
                    └──────┬──────┘
                           │ 1. conexão TCP direto no IP 3.142.172.36:443 (sem DNS)
┌──────────────────────────▼───────────────────────────────────────────┐
│  AWS — Security Group launch-wizard-1: 22, 80, 443, 3001             │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ EC2 Ubuntu — firewall UFW: 22, 80, 443, 3001                    │ │
│  │                                                                 │ │
│  │   ┌──────────────────────────┐  2. TLS termina aqui             │ │
│  │   │ Traefik  :80 :443 :3001  │     (certificado autoassinado)   │ │
│  │   └─────┬──────────────┬─────┘  3. roteia pela porta de entrada │ │
│  │    :443 │ rede "web"   │ :3001                                  │ │
│  │   ┌─────▼──────┐  ┌────▼───────────┐                            │ │
│  │   │ app :8000  │  │ uptime-kuma    │                            │ │
│  │   │ Flask +    │  │ :3001          │──► monitora app e          │ │
│  │   │ Gunicorn   │  │                │    containers (docker.sock)│ │
│  │   └────────────┘  └────────────────┘                            │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘

Provisionamento (N2):
 Ansible (CloudShell/WSL) ─SSH─► EC2: instala Docker, firewall, clona o repo, gera .env, docker compose up -d

CI/CD (N1):
 dev ─git push─► GitHub ─► Actions: testes → build → push GHCR → SSH deploy → verificação HTTPS
                                                       │                 │
                                                  ghcr.io/...      EC2: docker compose pull + up -d
```

## Caminho de uma requisição

1. O navegador conecta direto no IP público **3.142.172.36**, porta **443**. Não há domínio, então não há consulta DNS.
2. O **Security Group** da AWS e o **UFW** da VM permitem a porta 443.
3. O Docker encaminha a porta 443 do host para o container do **Traefik**.
4. O Traefik faz o **handshake TLS** com o certificado **autoassinado** que ele mesmo gera (o navegador mostra o aviso "Não seguro" porque o certificado não é de uma autoridade reconhecida).
5. O Traefik escolhe o serviço pela **porta de entrada**: `:443` → `app`; `:3001` → `uptime-kuma`. Na porta `:80`, ele só redireciona para HTTPS.
6. Encaminha para `app:8000` pela rede interna `web` (o nome `app` é resolvido pelo DNS interno do Docker).
7. O **Gunicorn** recebe e o **Flask** gera o HTML. A resposta faz o caminho inverso.

## Componentes

| Componente | Papel | Por que |
|---|---|---|
| **EC2 na AWS** (`3.142.172.36`) | Hospeda tudo | Controle total do SO, rede e Docker — permite demonstrar e diagnosticar cada camada |
| **UFW + Security Group** | Firewall em duas camadas | Só 22/80/443/3001 alcançam a máquina |
| **Traefik** | Reverse proxy, HTTPS, redirecionamento | Descobre os containers pelas labels; gera o certificado autoassinado sozinho |
| **app** | A aplicação | Imagem pequena, sem root, com HEALTHCHECK |
| **Uptime Kuma** | Monitoramento e alertas | Interface simples, monitora HTTP, palavra-chave e containers |
| **GitHub Actions** | CI/CD | Integrado ao repositório, gratuito para repositório público |
| **GHCR** | Registry das imagens | Guarda cada versão por SHA → rollback rápido |
| **Ansible** | Automação da infraestrutura (N2) | Prepara um servidor novo e implanta a stack com um comando, de forma repetível e idempotente |

## Portas

| Porta | Onde | Exposta à internet? |
|---|---|---|
| 22 | SSH no host | Sim (só chave). Ideal: restringir ao seu IP na regra do provedor |
| 80 | Traefik | Sim — só redireciona para HTTPS |
| 443 | Traefik | Sim |
| 8000 | app (interna) | **Não** |
| 3001 | Traefik → uptime-kuma | Sim, via Traefik com HTTPS (o container do Kuma em si não publica porta) |

> Observação: o Docker cria regras de iptables próprias e uma porta publicada com `ports:` **ignora o UFW**. Por isso a regra é: só o Traefik usa `ports:`; os demais serviços ficam apenas na rede interna.

## Ponto único de falha e como evoluir

**Pontos únicos de falha**: a VM (uma só máquina, uma zona), o IP público (se a instância for recriada sem Elastic IP, o IP muda), o Traefik (toda requisição passa por ele) e o disco da VM (dados do Kuma). O próprio monitoramento roda na mesma VM — se ela cair, o Kuma cai junto.

**Para ficar mais resiliente:**
- 2+ VMs em zonas diferentes atrás de um load balancer do provedor (ou Docker Swarm / Kubernetes).
- Monitoramento externo (UptimeRobot, ou o Kuma em outra máquina) para detectar queda da VM inteira.
- Backups automáticos fora da VM (`scripts/backup.sh` + cron + armazenamento de objetos).
- **Elastic IP** na AWS para o IP não mudar ao recriar a instância.
- Domínio + Let's Encrypt para ter certificado válido (sem aviso no navegador).
- Infraestrutura como código (Terraform) criando a EC2 + o Ansible configurando = ambiente recriado em minutos.
