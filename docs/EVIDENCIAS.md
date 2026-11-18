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
