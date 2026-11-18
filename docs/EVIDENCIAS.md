# Evidências da entrega (N1)

Salvar os prints em `docs/evidencias/` e referenciar aqui. Lembrando: o ambiente precisa estar **funcionando** — prints são complemento.

## Links
- [ ] URL da aplicação: https://...
- [ ] Repositório: https://github.com/flacolael/projeto-cloud-devops
- [ ] Monitoramento: https://status....
- [ ] E-mail enviado para claudio.castelo@afya.com.br com URL + repositório

## Cloud
- [ ] Painel do provedor mostrando a VM (nome, região, tamanho, IP)
- [ ] Regras de rede (Security List / Security Group) com 22/80/443
- [ ] Terminal: `ssh ...` conectado + `lsb_release -a`, `nproc`, `free -h`, `df -h`
- [ ] `sudo ufw status verbose`

## Docker
- [ ] `docker images`
- [ ] `docker compose ps` (todos `Up`, app `healthy`)
- [ ] `docker logs --tail 20 app`

## DNS + HTTPS
- [ ] `nslookup DOMINIO` mostrando o IP da VM
- [ ] Navegador com cadeado + detalhes do certificado (emitido por Let's Encrypt, validade)
- [ ] `curl -I http://DOMINIO` mostrando redirecionamento 301/308 para https

## CI/CD
- [ ] Aba Actions com execução verde (os 3 jobs)
- [ ] Log do job de deploy e da verificação "✅ Nova versão no ar"
- [ ] Antes/depois de uma alteração (rodapé com versão/commit diferentes)
- [ ] Página do pacote no GHCR com as tags

## Monitoramento
- [ ] Painel do Uptime Kuma com os monitores verdes
- [ ] Simulação: `docker stop app` → monitor vermelho + notificação recebida → recuperação
- [ ] Saída do `scripts/diagnostico.sh`

## Git
- [ ] `git log --oneline --graph` mostrando histórico organizado

## N2 — Ansible

Comandos para gerar as evidências da N2 (rodar na sua máquina, dentro de `ansible/`, e na VM):

| Evidência | Comando | Print |
|---|---|---|
| Conexão do Ansible com o servidor | `ansible webservers -m ping` | _colar_ |
| Execução do playbook (servidor novo) | `ansible-playbook playbook.yml` — mostrar o `PLAY RECAP` com `failed=0` | _colar_ |
| Idempotência (2ª execução) | `ansible-playbook playbook.yml` de novo — `changed` baixo, `failed=0` | _colar_ |
| Docker instalado pelo Ansible | na VM: `docker --version && docker compose version` | _colar_ |
| Stacks em funcionamento | na VM: `cd /opt/projeto-cloud-devops && docker compose ps` | _colar_ |
| Aplicação respondendo | `curl -k https://IP_DA_VM/health` e print do navegador em `http://IP_DA_VM` | _colar_ |
| Monitoramento | print do Uptime Kuma em `https://IP_DA_VM:3001` | _colar_ |

