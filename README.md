# Geofixer

Projeto pessoal para tratar arquivos de endereços que uso nas minhas entregas de
pacotes. É um web app: você **envia um `.xlsx` pelo celular** e baixa de volta um
`.csv` corrigido e padronizado, pronto pro roteirizador, junto de um log com os
endereços/ruas de maior volume.

## 🚚 O que ele faz?

- Recebe um `.xlsx` de endereços por upload (de qualquer lugar, pelo navegador).
- Corrige nomes de ruas com base no CEP usando a API do **ViaCEP**.
- Obtém a **geolocalização (latitude e longitude)** via API do **Google Maps**.
- Separa o complemento do endereço principal (ex: "apto", "fundos").
- Gera um `.csv` pronto para sistemas de rota.
- Gera um **log** com os endereços, ruas e travessas/passagens de maior volume,
  que ajuda a priorizar entregas e organizar os pacotes no veículo.

O processamento é **assíncrono**: o upload entra numa fila, uma thread interna
processa um arquivo por vez, e a página de status atualiza sozinha até os
downloads ficarem prontos.

## 💡 Por que isso existe?

Os arquivos chegavam com nomes de ruas abreviados, CEPs errados ou dados
incompletos, o que fazia o roteirizador me levar a lugares errados ou gerar
rotas ineficientes. O Geofixer corrige e padroniza isso, e os logs me ajudam a
economizar tempo, combustível e retrabalho.

## 🧭 Como funciona (fluxo)

Da entrada do usuário até a saída, passo a passo:

```
Usuário                Web (Sinatra)            Fila/Worker            APIs externas
  │ GET / (Basic Auth)  │                        │                        │
  │────────────────────>│  formulário .xlsx      │                        │
  │ POST /upload ──────>│ valida, salva input,   │                        │
  │                     │ cria job, enfileira ───┼──> [job_id, dir]       │
  │ <─ redirect /jobs/:id                        │ converte xlsx→csv      │
  │ GET /jobs/:id ─────>│ lê status (poll 2s)    │ processa linha a linha ┼──> ViaCEP
  │                     │                        │   corrige rua          │    Google Geocode
  │                     │                        │   geocodifica          │
  │                     │                        │   separa complemento   │
  │ status :done ──────>│ links de download      │ gera CSV + log         │
  │ GET .../download/csv│                        │                        │
  │<──── send_file ─────│                        │                        │
```

**No boot** (`config.ru`): cria um `JobRegistry` (mapa em memória de `id → Job`,
sem persistência) e uma `JobQueue` que sobe **uma thread de background**. Todas as
rotas ficam atrás de Basic Auth (realm "Geofixer").

1. **Upload** (`web/app.rb`, `POST /upload`): valida que é `.xlsx`, varre jobs com
   mais de 1h, gera um UUID, salva o arquivo em `tmp/jobs/<id>/input.xlsx`, cria o
   job (`:queued`), enfileira e **redireciona** para `/jobs/<id>`. Nada é processado
   de forma síncrona.
2. **Fila** (`web/job_queue.rb`): a thread processa **um job por vez** (FIFO) —
   `:running` → executa → `:done` (com os caminhos do CSV/log) ou `:failed` (com a
   mensagem). O single-thread mantém o cache global livre de corrida e segura o uso
   de recursos no free tier.
3. **Execução** (`web/job_runner.rb`): converte a 1ª aba do `.xlsx` para CSV UTF-8
   (`roo`) e chama o núcleo, gerando `DD-MM-YYYY ROTA.csv` e
   `DD-MM-YYYY log_enderecos.txt`.
4. **Núcleo** (`app/address_processor.rb`), para cada linha com CEP:
   - corrige a rua pelo CEP via **ViaCEP** (compara o nome digitado com o oficial,
     ignorando prefixos/acentos/conectores; se não casar, faz busca reversa por nome);
   - obtém **latitude/longitude** via **Google Geocoding**;
   - separa o complemento (`apto`, `fundos`, …) numa coluna própria;
   - contabiliza volumes por endereço e por rua; escreve a linha no CSV.
   - Cada CEP/geocodificação passa por um cache em memória (`CacheManager`); as
     chamadas HTTP têm timeout e retry e retornam `nil` em falha (a linha só perde o
     enriquecimento, nunca trava). Ao final reporta o progresso e gera o log Top 10
     de endereços, ruas e travessas/passagens.
5. **Saída** (`web/views/job.erb`): a página faz auto-refresh a cada 2s mostrando a
   barra de progresso (`processado/total`); quando `:done`, exibe os links de
   download (`GET /jobs/:id/download/csv|log` → `send_file` como anexo).

> Como tudo é em memória, reiniciar o processo (ex.: o dyno free dormindo) **descarta
> os jobs e arquivos** em andamento; jobs antigos são varridos no próximo upload.

## 🔧 Rodando localmente

```bash
cp .env.example .env        # preencha as variáveis
bundle install
bundle exec puma -C config/puma.rb config.ru
```

Abra `http://localhost:3000`, faça login (Basic Auth) e envie o `.xlsx`.

### Variáveis de ambiente

| Variável | Para quê |
|----------|----------|
| `GOOGLE_API_KEY` | Geocodificação no Google Maps |
| `BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD` | Login do app (obrigatórios — o app não sobe sem eles) |
| `PORT` | Porta do servidor (o Render injeta automaticamente) |

## ☁️ Deploy (Render, free)

O app roda como **um único Render Web Service gratuito** via Docker — sem
Background Worker, cron, banco ou Redis.

1. Conecte o repositório no Render (ou use o `render.yaml` como blueprint).
2. Tipo de serviço: **Docker**, plano **Free**.
3. Configure os secrets: `GOOGLE_API_KEY`, `BASIC_AUTH_USER`,
   `BASIC_AUTH_PASSWORD` (e opcionalmente `OUTPUT_LABEL`).

A instância dorme quando ociosa; o primeiro acesso depois de um tempo tem um
cold start de ~30–60s e depois normaliza. Por ser uso ocasional, não precisa de
pinger mantendo-a acordada.

## 🧪 Testes

```bash
bundle exec rspec
```
