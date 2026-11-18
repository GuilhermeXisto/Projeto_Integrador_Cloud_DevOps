# Roteiro da apresentação (N2)

## Ordem sugerida da demonstração (~15 min)

1. **Abrir a URL** no navegador → mostrar cadeado, disciplina, integrantes, versão no rodapé.
2. **Arquitetura** → diagrama do `docs/ARQUITETURA.md`, seguindo o caminho de uma requisição.
3. **Cloud** → painel do provedor (VM, IP, regras de rede) e `ssh` no servidor.
4. **Docker** → `cat Dockerfile`, `docker images`, `docker compose ps`, `docker logs app`.
5. **DNS e HTTPS** → `nslookup DOMINIO`, cadeado no navegador (emissor Let's Encrypt), labels no compose.
6. **CI/CD ao vivo** → alterar algo visível (ex.: cor ou texto do `index.html`), `git commit`, `git push`, mostrar a aba Actions, recarregar a página → versão/commit novos no rodapé.
7. **Monitoramento** → painel do Kuma; `docker stop app` → monitor fica vermelho e chega alerta → `docker compose up -d` → volta verde.
8. **Diagnóstico** → `bash scripts/diagnostico.sh`.

> Dica: ensaiem o passo 6 e 7 antes. Mantenham um terminal SSH já aberto.

## Respostas às perguntas técnicas

**Por que vocês utilizaram Docker?**
Para empacotar a aplicação com tudo que ela precisa (Python, bibliotecas, configuração). A mesma imagem roda igual no meu computador, no runner da pipeline e no servidor — acaba o "na minha máquina funciona". Também facilita atualizar e voltar versões.

**Qual a diferença entre imagem e container?**
Imagem é o modelo, somente leitura, construído a partir do Dockerfile (como uma classe ou um ISO). Container é uma instância em execução dessa imagem, com uma camada gravável por cima (como um objeto, ou uma VM ligada). De uma imagem posso criar vários containers.

**O que acontece quando o container é removido?**
Some o container e tudo o que foi gravado dentro dele fora de volumes. A imagem continua lá, então `docker compose up -d` recria igual. Os dados que precisam sobreviver (certificados, dados do Kuma) estão em **volumes**, que não são apagados com o container.

**Como o domínio chega até o servidor?**
O navegador consulta o DNS, que tem um registro A apontando o domínio para o IP público da VM. Com o IP, ele conecta na porta 443; o firewall libera, o Docker entrega ao Traefik, que pelo nome do host encaminha ao container da aplicação.

**Onde está configurado o HTTPS?**
No Traefik, dentro do `docker-compose.yml`: o `certificatesresolver` "le" usa Let's Encrypt com desafio HTTP na porta 80. A label `tls.certresolver=le` no serviço app pede o certificado. Ele fica salvo em `acme.json` no volume `letsencrypt` e é renovado automaticamente. HTTP é redirecionado para HTTPS.

**Como funciona o pipeline? / O que acontece quando fazemos git push?**
O GitHub dispara o workflow do GitHub Actions: (1) roda os testes com pytest; (2) constrói a imagem Docker com o SHA do commit, sobe um container de teste e checa `/health`; (3) publica a imagem no GHCR; (4) conecta por SSH no servidor, atualiza a tag no `.env`, faz `docker compose pull` e `up -d`; (5) acessa o site por HTTPS e confirma que o commit novo está no ar. Se qualquer etapa falha, as seguintes não rodam e a produção continua na versão anterior.

**Onde estão armazenadas as credenciais?**
Na pipeline: GitHub Secrets (chave SSH, IP, domínio) — criptografados e mascarados nos logs. No servidor: arquivo `.env` com permissão 600, listado no `.gitignore`. O token para publicar a imagem é o `GITHUB_TOKEN` temporário gerado a cada execução. Nada de senha no código.

**Quais portas estão abertas?**
22 (SSH, só com chave), 80 (só redireciona e valida certificado) e 443 (HTTPS). As portas 8000 do app e 3001 do Kuma ficam apenas na rede interna do Docker.

**Como identificariam uma aplicação fora do ar?**
O Uptime Kuma verifica o `/health` a cada minuto e manda alerta. No servidor, `docker compose ps` mostra o status e o health, e o `diagnostico.sh` verifica cada camada. Depois, os logs (`docker logs`) mostram a causa.

**Se o servidor parar, como recuperar o ambiente?**
Se só desligou: ligar no painel — Docker inicia no boot e os containers têm `restart: unless-stopped`. Se a VM foi perdida: nova VM, rodar `setup-server.sh`, restaurar o `.env` e o backup, apontar o DNS para o novo IP, atualizar o secret `SSH_HOST` e `docker compose up -d`. Toda a configuração está no Git.

**Qual é o ponto único de falha da arquitetura?**
A própria VM: uma única máquina numa única zona. Também o Traefik (toda requisição passa por ele) e o disco (certificados e dados). E o monitoramento está na mesma VM, então não avisaria se ela inteira caísse.

**O que fariam para tornar o ambiente mais resiliente?**
Duas ou mais VMs em zonas diferentes atrás de um load balancer; orquestrador (Docker Swarm/Kubernetes); monitoramento externo; backups automáticos fora da VM; Terraform para recriar a infraestrutura; Cloudflare na frente; banco/armazenamento gerenciado se a aplicação tivesse dados.

## Outras perguntas prováveis

- **O que é reverse proxy?** Servidor que recebe as requisições dos clientes e as repassa ao serviço certo internamente. Centraliza HTTPS, roteamento por domínio e esconde os serviços internos.
- **Diferença entre CI e CD?** CI = integrar e validar cada alteração automaticamente (testes, build). CD = entregar/implantar automaticamente o que passou na CI.
- **O que é um volume?** Armazenamento gerenciado pelo Docker fora do ciclo de vida do container.
- **Por que `restart: unless-stopped`?** O Docker reinicia o container se ele cair ou se o servidor reiniciar, a menos que alguém o tenha parado manualmente.
- **Por que a imagem tem duas tags?** `latest` é conveniência; a tag com SHA é imutável e identifica exatamente o código em produção — permite rollback.
- **O que é o HEALTHCHECK?** Comando que o Docker executa periodicamente dentro do container para marcar `healthy`/`unhealthy` — o processo pode estar rodando mas a aplicação travada.
- **Por que o container não roda como root?** Se alguém explorar uma falha na aplicação, fica com um usuário sem privilégios, limitando o estrago.
