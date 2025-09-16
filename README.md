# Keycloak SSO Stack

Ambiente Docker para executar o Keycloak em modo produção com PostgreSQL e reverse proxy externo (Nginx ou Apache HTTPD) publicando o domínio `https://auth-sso.travelapi.com.br/`.

## Arquitetura

- **Keycloak** (imagem `quay.io/keycloak/keycloak:24.0.3`) executando com `kc.sh start --optimized`, health checks e métricas ativados.
- **PostgreSQL 16** endurecido, isolado em rede interna Docker e com volume persistente (`keycloak_db_data`).
- **Reverse proxy (opcional)**: arquivos de referência para **Nginx** e **Apache HTTPD** com TLS, cabeçalhos de segurança e rate limiting.

> ⚠️ Lembrete: as variáveis sensíveis devem ser armazenadas apenas em `.env` local (não versionado). Gire credenciais periodicamente e aplique o princípio do menor privilégio no banco.

## Pré-requisitos

1. Docker Engine >= 24.x.
2. Docker Compose plugin >= v2.
3. Certificado TLS válido (ex.: emitido via Let’s Encrypt) provisionado no host do proxy reverso.
4. DNS do domínio `auth-sso.travelapi.com.br` apontando para o IP público do proxy.

## Configuração

1. Copie o arquivo de exemplo e ajuste as variáveis sensíveis:
   ```bash
   cp .env.example .env
   # edite o arquivo com senhas fortes e únicas
   ```
2. Defina senhas longas (>20 caracteres) para `KEYCLOAK_ADMIN_PASSWORD` e `KC_DB_PASSWORD`.
3. Garanta que o usuário `KC_DB_USERNAME` possua apenas permissões necessárias sobre o schema `KC_DB_SCHEMA`.
4. Opcionalmente ajuste parâmetros de pool (`KC_DB_POOL_*`) conforme o volume de requisições esperado.

## Subindo o ambiente

```bash
# valida sintaxe do compose
docker compose config

# sobe a pilha em segundo plano
docker compose up -d --build

# acompanha os logs
docker compose logs -f keycloak
```

Após a inicialização, o Keycloak ficará disponível internamente em `http://127.0.0.1:8080/` e publicamente via proxy em `https://auth-sso.travelapi.com.br/`.

### Checks de saúde

```bash
# dentro do host docker
curl -f http://127.0.0.1:8080/health/ready

# via proxy reverso (TLS obrigatório)
curl -f https://auth-sso.travelapi.com.br/healthz
```

Em caso de falha, verifique os logs dos serviços `keycloak` e `db`.

## Reverse Proxy

### Nginx

Arquivo: [`reverse-proxy/nginx/keycloak.conf`](reverse-proxy/nginx/keycloak.conf)

1. Instale Nginx >= 1.20.
2. Habilite HTTP/2 e certifique-se de possuir certificados válidos em `/etc/letsencrypt/live/auth-sso.travelapi.com.br/`.
3. Copie o arquivo para `/etc/nginx/conf.d/keycloak.conf` (ou site-available) e ajuste caminhos de certificado caso necessário.
4. Teste a configuração antes de recarregar:
   ```bash
   nginx -t
   systemctl reload nginx
   ```

A configuração inclui:
- Redirecionamento 80 -> 443, HTTP/2, TLS forte, HSTS, CSP restritiva e cabeçalhos de proteção.
- Rate limiting (`10r/s`) e endpoint `/healthz` expondo o health check do Keycloak.
- Encaminhamento de cabeçalhos `X-Forwarded-*` para preservar protocolo/host originais.

### Apache HTTPD

Arquivo: [`reverse-proxy/apache/keycloak.conf`](reverse-proxy/apache/keycloak.conf)

1. Instale Apache >= 2.4 com os módulos `ssl proxy proxy_http proxy_wstunnel headers rewrite http2`.
2. Copie o arquivo para `/etc/apache2/sites-available/keycloak.conf`.
3. Atualize os caminhos de certificado conforme seu ambiente.
4. Habilite o site e recarregue:
   ```bash
   a2ensite keycloak.conf
   apachectl configtest
   systemctl reload apache2
   ```

O virtual host aplica TLS forte, preserva o host original, encaminha cabeçalhos `X-Forwarded-*`, reforça cookies com `Secure` + `HttpOnly` e publica `/healthz` apenas localmente.

## Backup e Observabilidade

- **Banco de dados**: configure `pg_dump` agendado (ex.: cron/pgBackRest) para snapshots diários e testes periódicos de restauração.
- **Volumes**: monitore o volume `keycloak_db_data` e inclua-o em rotinas de backup off-site cifradas.
- **Logs**: exporte logs de Keycloak e PostgreSQL para sua stack de observabilidade (ELK, Loki, etc.).
- **Auditoria**: habilite auditoria de eventos no Keycloak e rotacione chaves periodicamente.

## Atualizações e Manutenção

1. Para atualizar o Keycloak, ajuste a tag da imagem no `keycloak.Dockerfile`, execute `docker compose build --no-cache keycloak` e reinicie o serviço.
2. Antes de atualizar, execute backup completo do banco e valide em ambiente de homologação.
3. Utilize `docker compose pull` regularmente para aplicar correções do PostgreSQL.
4. Execute `docker system prune` (com cautela) para remover camadas antigas.

## Segurança (Checklist mínimo)

- [ ] TLS obrigatório em todos os acessos externos.
- [ ] Segregação de rede: apenas o proxy acessa o Keycloak diretamente.
- [ ] Credenciais fortes e armazenadas em cofre de segredos.
- [ ] Usuário de banco com privilégios mínimos e conexão via TLS (configure `pg_hba.conf`).
- [ ] Monitoramento de tentativas de login e alertas de anomalias.
- [ ] Rotina de atualização e patches mensais.

## Testes Rápidos

```bash
# valida estado dos containers
docker compose ps

# verifica migrações do banco (exemplo)
docker compose exec keycloak /opt/keycloak/bin/kc.sh show-config | grep db
```

Execute testes de regressão e segurança adicionais (SAST, DAST, scans de imagem) antes de promover para produção.
