# Arquitetura

## Diagrama

```
                    ┌─────────────┐
                    │   Usuário   │  https://SEUDOMINIO.duckdns.org
                    └──────┬──────┘
                           │ 1. "Qual o IP de SEUDOMINIO.duckdns.org?"
                    ┌──────▼──────┐
                    │  DNS        │  registro A → 123.45.67.89
                    │  (DuckDNS)  │
                    └──────┬──────┘
                           │ 2. conexão TCP em 123.45.67.89:443
┌──────────────────────────▼───────────────────────────────────────────┐
│  Provedor de nuvem — regras de rede (Security List / Security Group) │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ VM Ubuntu — firewall UFW: 22, 80, 443                           │ │
│  │                                                                 │ │
│  │   ┌──────────────────────────┐  3. TLS termina aqui (cert LE)   │ │
│  │   │ Traefik  :80 :443        │  4. lê o Host da requisição      │ │
│  │   └─────┬──────────────┬─────┘                                  │ │
│  │         │ rede "web"   │                                        │ │
│  │   ┌─────▼──────┐  ┌────▼───────────┐                            │ │
│  │   │ app :8000  │  │ uptime-kuma    │                            │ │
│  │   │ Flask +    │  │ :3001          │──► monitora app, cert,     │ │
│  │   │ Gunicorn   │  │                │    containers (docker.sock)│ │
│  │   └────────────┘  └────────────────┘                            │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘

CI/CD:
 dev ─git push─► GitHub ─► Actions: testes → build → push GHCR → SSH deploy → verificação HTTPS
                                                       │                 │
                                                  ghcr.io/...      VM: docker compose pull + up -d
```

## Caminho de uma requisição

1. O navegador pergunta ao **DNS** o IP de `SEUDOMINIO.duckdns.org` → recebe o IP público da VM.
2. Abre conexão na porta **443** desse IP. A regra de rede do provedor e o **UFW** permitem a 443.
3. O Docker encaminha a porta 443 do host para o container do **Traefik**.
4. O Traefik faz o **handshake TLS** com o certificado Let's Encrypt daquele domínio.
5. O Traefik olha o cabeçalho `Host`: `SEUDOMINIO...` → serviço `app`; `status.SEUDOMINIO...` → `uptime-kuma`.
6. Encaminha para `app:8000` pela rede interna `web` (o nome `app` é resolvido pelo DNS interno do Docker).
7. O **Gunicorn** recebe e o **Flask** gera o HTML. A resposta faz o caminho inverso.

## Componentes

| Componente | Papel | Por que |
|---|---|---|
| **DNS (DuckDNS)** | Traduz nome → IP | Gratuito, aceita subdomínios (`status.`) e permite atualizar o IP por API |
| **VM na nuvem** | Hospeda tudo | Controle total do SO, rede e Docker — permite demonstrar e diagnosticar cada camada |
| **UFW + regras do provedor** | Firewall em duas camadas | Só 22/80/443 alcançam a máquina |
| **Traefik** | Reverse proxy, HTTPS, redirecionamento | Descobre os containers pelas labels e emite/renova certificados sozinho |
| **app** | A aplicação | Imagem pequena, sem root, com HEALTHCHECK |
| **Uptime Kuma** | Monitoramento e alertas | Interface simples, monitora HTTP, certificado, palavra-chave e containers |
| **GitHub Actions** | CI/CD | Integrado ao repositório, gratuito para repositório público |
| **GHCR** | Registry das imagens | Guarda cada versão por SHA → rollback rápido |

## Portas

| Porta | Onde | Exposta à internet? |
|---|---|---|
| 22 | SSH no host | Sim (só chave). Ideal: restringir ao seu IP na regra do provedor |
| 80 | Traefik | Sim — só redireciona para HTTPS e responde o desafio do Let's Encrypt |
| 443 | Traefik | Sim |
| 8000 | app (interna) | **Não** |
| 3001 | uptime-kuma (interna) | **Não** (acessado via Traefik/HTTPS) |

> Observação: o Docker cria regras de iptables próprias e uma porta publicada com `ports:` **ignora o UFW**. Por isso a regra é: só o Traefik usa `ports:`; os demais serviços ficam apenas na rede interna.

## Ponto único de falha e como evoluir

**Pontos únicos de falha**: a VM (uma só máquina, uma zona), o Traefik (toda requisição passa por ele) e o disco da VM (certificados e dados do Kuma). O próprio monitoramento roda na mesma VM — se ela cair, o Kuma cai junto.

**Para ficar mais resiliente:**
- 2+ VMs em zonas diferentes atrás de um load balancer do provedor (ou Docker Swarm / Kubernetes).
- Monitoramento externo (UptimeRobot, ou o Kuma em outra máquina) para detectar queda da VM inteira.
- Backups automáticos fora da VM (`scripts/backup.sh` + cron + armazenamento de objetos).
- Infraestrutura como código (Terraform) para recriar a VM em minutos.
- Cloudflare na frente (DNS com proxy, cache, proteção DDoS).
