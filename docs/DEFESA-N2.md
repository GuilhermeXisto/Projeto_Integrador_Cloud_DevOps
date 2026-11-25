# Roteiro da apresentação (N2)

Objetivo da N2: mostrar que o grupo **automatizou com Ansible** a preparação de um servidor Linux e a implantação do projeto da N1, e que **entende** o que construiu. Não é leitura de slides: é demonstração prática.

## Divisão da apresentação

| Ordem | Integrante | Parte | Tempo |
| --- | --- | --- | --- |
| 1 | Integrante 1 | Abertura, aplicação no ar, arquitetura e HTTPS | ~3 min |
| 2 | Integrante 2 | Docker e CI/CD (GitHub Actions) | ~4 min |
| 3 | Integrante 3 | Ansible: arquivos, execução ao vivo e idempotência | ~5 min |
| 4 | Integrante 4 | Resultado no servidor novo, monitoramento, diagnóstico e encerramento | ~3–4 min |

## Antes da apresentação

- [ ] Criar uma **EC2 Ubuntu nova** (portas 22, 80, 443 e 3001 no Security Group) para demonstrar a automação do zero.
- [ ] Trocar o IP no `ansible/inventory.ini` pelo IP da VM nova (ou deixar duas linhas e usar `--limit`).
- [ ] CloudShell aberto, com a chave em `~/.ssh/keys-lab-castelo.pem` e o Ansible instalado (`pip3 install ansible`).
- [ ] Um terminal SSH já aberto na VM `3.142.172.36` (produção).
- [ ] Abas abertas: https://3.142.172.36, https://3.142.172.36:3001, aba **Actions** do GitHub.

## Ordem sugerida da demonstração (~15 min)

1. **Aplicação no ar** → abrir https://3.142.172.36: disciplina, integrantes, versão e commit no rodapé. Explicar o aviso do navegador (certificado autoassinado, sem domínio).
2. **Repositório** → mostrar que o Ansible está no **mesmo repositório da N1**: `ansible/` ao lado de `app/`, `Dockerfile`, `docker-compose.yml`.
3. **Arquivos do Ansible** → abrir e explicar:
   - `inventory.ini`: qual servidor, com qual usuário e qual chave.
   - `group_vars/all.yml`: variáveis (repositório, imagem, pacotes, portas).
   - `playbook.yml`: as 4 etapas (esperar a VM → preparar → implantar → verificar).
   - `templates/env.j2`: o `.env` gerado no servidor.
4. **Execução ao vivo na VM nova** →
   ```bash
   ansible webservers -m ping
   ansible-playbook playbook.yml
   ```
   Comentar as tarefas enquanto rodam. No final, mostrar o `PLAY RECAP` (`failed=0`) e as URLs exibidas.
5. **Idempotência** → rodar `ansible-playbook playbook.yml` de novo: quase tudo `ok`, poucas `changed`. Explicar por quê.
6. **Resultado no servidor novo** → `ssh` na VM nova: `docker --version`, `docker compose ps`, `curl -k https://localhost/health`. Abrir `https://IP_NOVO` no navegador.
7. **Arquitetura** → diagrama do `docs/ARQUITETURA.md`: IP → Security Group/UFW → Traefik → app / Uptime Kuma.
8. **CI/CD** → alterar algo visível, `git push`, mostrar a aba Actions (testes + validação do Ansible → build → deploy) e o rodapé com o commit novo.
9. **Monitoramento** → Uptime Kuma em https://3.142.172.36:3001; `docker stop app` → monitor vermelho → `docker compose up -d` → volta verde.

> Dica: a instalação do Docker pelo playbook leva alguns minutos numa VM nova. Comecem o passo 4 cedo e expliquem os arquivos enquanto ele roda.

## Perguntas sobre o Ansible

**O que é o Ansible e por que usar?**
Ferramenta de automação que configura servidores a partir de arquivos de texto (YAML). Em vez de entrar na VM e digitar comandos um a um, descrevemos o estado desejado e o Ansible aplica. O resultado é repetível: qualquer servidor Ubuntu novo fica igual, em minutos, e a configuração fica versionada no Git.

**Precisa instalar algo no servidor?**
Não. O Ansible é *agentless*: conecta por **SSH** e usa o Python que já vem no Ubuntu. Só a máquina de controle (CloudShell/WSL) precisa do Ansible.

**O que é o inventário?**
O arquivo `inventory.ini` com a lista de servidores, agrupados (`[webservers]`), e como conectar em cada um (`ansible_user`, `ansible_ssh_private_key_file`). Para outro servidor, basta trocar ou adicionar o IP.

**O que é um playbook? E uma task, um play, um módulo?**
O playbook é o arquivo YAML com a automação. Ele tem *plays* (um conjunto de tarefas para um grupo de hosts); cada *task* chama um *módulo* (`apt`, `systemd`, `git`, `template`, `uri`...), que é quem de fato executa a ação no servidor.

**O que é idempotência?**
Rodar o playbook várias vezes e ter sempre o mesmo resultado, sem quebrar nada. Os módulos verificam o estado antes de agir: se o Docker já está instalado, a task fica `ok` e não reinstala. Por isso a segunda execução mostra quase tudo `ok` e poucas `changed`.

**Para que serve o `become: true`?**
Executa as tarefas com `sudo` (root), necessário para instalar pacotes, mexer no firewall e no SSH.

**Para que servem o `group_vars` e o template?**
`group_vars/all.yml` separa os **dados** (repositório, imagem, portas, pacotes) da **lógica** (playbook). O template `env.j2` (Jinja2) gera o `.env` no servidor preenchendo essas variáveis — assim nenhum `.env` real vai para o Git.

**O que o playbook faz, passo a passo?**
1. `wait_for_connection`: espera a VM aceitar SSH.
2. Prepara: pacotes base; repositório oficial do Docker com a chave GPG (`deb822_repository`); Docker Engine + plugin Compose; serviço habilitado; usuário `ubuntu` no grupo `docker`; UFW liberando 22/80/443/3001; SSH só por chave; fail2ban.
3. Implanta: clona o repositório em `/opt/projeto-cloud-devops`, gera o `.env`, baixa as imagens e roda `docker compose up -d`.
4. Verifica: chama `https://localhost/health` até responder 200 e lista os containers.

**O que é aquele `block`/`rescue`?**
Tratamento de erro. O playbook tenta baixar a imagem da aplicação do GHCR (`block`). Se falhar — pacote privado ou imagem inexistente — o `rescue` constrói a imagem no próprio servidor a partir do `Dockerfile`. Assim a automação funciona num servidor novo mesmo sem acesso ao registry.

**Qual a diferença entre o Ansible e o GitHub Actions?**
O **Ansible** prepara a infraestrutura: transforma um servidor vazio num servidor pronto, com Docker, firewall e a stack no ar. O **GitHub Actions** cuida do ciclo do código: a cada `git push`, testa, constrói a imagem e atualiza a aplicação no servidor que já está preparado.

**E se o professor rodar num servidor novo?**
Basta criar uma EC2 Ubuntu com as portas 22/80/443/3001 abertas, colocar o IP no `inventory.ini` e rodar `ansible-playbook playbook.yml`. O playbook instala tudo e sobe a aplicação.

## Perguntas sobre a N1 (podem voltar)

**Por que vocês utilizaram Docker?**
Para empacotar a aplicação com tudo que ela precisa (Python, bibliotecas, configuração). A mesma imagem roda igual no computador, no runner da pipeline e no servidor. Também facilita atualizar e voltar versões.

**Qual a diferença entre imagem e container?**
Imagem é o modelo, somente leitura, construído a partir do Dockerfile. Container é uma instância em execução dessa imagem, com uma camada gravável por cima. De uma imagem posso criar vários containers.

**O que acontece quando o container é removido?**
Some o container e tudo o que foi gravado dentro dele fora de volumes. A imagem continua lá, então `docker compose up -d` recria igual. Os dados que precisam sobreviver (dados do Uptime Kuma) ficam no **volume** `kuma-data`.

**Como a requisição chega até a aplicação?**
O navegador conecta direto no IP público **3.142.172.36**, porta 443 (não há domínio, então não há DNS). O Security Group da AWS e o UFW liberam a porta; o Docker entrega ao Traefik, que faz o TLS e encaminha para o container `app` na porta 8000 pela rede interna `web`. A porta 3001 vai para o Uptime Kuma.

**Onde está configurado o HTTPS? Por que o navegador avisa "Não seguro"?**
No Traefik, no `docker-compose.yml`: entradas `websecure` (443) e `kuma` (3001) com `tls=true`, e redirecionamento do HTTP (80) para HTTPS. Sem domínio, o Let's Encrypt não emite certificado, então o Traefik usa um **certificado autoassinado**. A conexão é criptografada, mas o navegador não reconhece quem emitiu — por isso o aviso. Com um domínio, bastaria configurar o `certresolver` do Let's Encrypt.

**Como funciona o pipeline? / O que acontece no `git push`?**
(1) **Testes**: pytest, validação do `docker-compose.yml` e do Ansible (syntax-check + ansible-lint). (2) **Build**: constrói a imagem com o SHA do commit, sobe um container de teste, checa `/health` e publica no GHCR. (3) **Deploy**: SSH no servidor, atualiza a tag no `.env`, `docker compose pull` e `up -d`, e confere em `https://3.142.172.36/health` que o commit novo está no ar. Se uma etapa falha, as seguintes não rodam e a produção continua na versão anterior.

**Onde estão armazenadas as credenciais?**
Na pipeline: **GitHub Secrets** (`SSH_HOST`, `SSH_USER`, `SSH_PRIVATE_KEY`), criptografados e mascarados nos logs. No servidor: `.env` com permissão 600, fora do Git. A chave `.pem` fica só na máquina de controle (`*.pem` está no `.gitignore`). O token para publicar a imagem é o `GITHUB_TOKEN` temporário de cada execução.

**Quais portas estão abertas?**
22 (SSH, só com chave), 80 (só redireciona para HTTPS), 443 (aplicação) e 3001 (Uptime Kuma, via Traefik). A porta 8000 da aplicação fica só na rede interna do Docker.

**Como identificariam uma aplicação fora do ar?**
O Uptime Kuma verifica o `/health` a cada minuto e manda alerta. No servidor, `docker compose ps` mostra o status e o health, e o `scripts/diagnostico.sh` verifica cada camada. Os logs (`docker logs`) mostram a causa.

**Se o servidor parar, como recuperar o ambiente?**
Se só desligou: ligar no console da AWS — o Docker inicia no boot e os containers têm `restart: unless-stopped` (conferir se o IP mudou). Se a VM foi perdida: criar uma EC2 nova, colocar o IP no `inventory.ini`, rodar o **playbook do Ansible**, restaurar o backup do Kuma e atualizar o secret `SSH_HOST`.

**Qual é o ponto único de falha da arquitetura?**
A própria VM: uma única máquina numa única zona. Também o IP público (muda se a instância for recriada sem Elastic IP), o Traefik (toda requisição passa por ele) e o disco. O monitoramento está na mesma VM, então não avisaria se ela inteira caísse.

**O que fariam para tornar o ambiente mais resiliente?**
Elastic IP; duas ou mais VMs em zonas diferentes atrás de um load balancer (o Ansible já configura várias VMs iguais — basta listar no inventário); monitoramento externo; backups automáticos fora da VM; domínio + Let's Encrypt para certificado válido.

## Outras perguntas prováveis

- **O que é reverse proxy?** Servidor que recebe as requisições e as repassa ao serviço certo internamente. Centraliza HTTPS e roteamento e esconde os serviços internos.
- **Diferença entre CI e CD?** CI = integrar e validar cada alteração automaticamente (testes, build). CD = entregar/implantar automaticamente o que passou na CI.
- **O que é um volume?** Armazenamento gerenciado pelo Docker, fora do ciclo de vida do container.
- **Por que `restart: unless-stopped`?** O Docker reinicia o container se ele cair ou se o servidor reiniciar, a menos que alguém o tenha parado manualmente.
- **Por que a imagem tem duas tags?** `latest` é conveniência; a tag com o SHA é imutável e identifica exatamente o código em produção — permite rollback.
- **O que é o HEALTHCHECK?** Comando que o Docker executa periodicamente dentro do container para marcar `healthy`/`unhealthy` — o processo pode estar rodando com a aplicação travada.
- **Por que o container não roda como root?** Se alguém explorar uma falha na aplicação, fica com um usuário sem privilégios, limitando o estrago.
