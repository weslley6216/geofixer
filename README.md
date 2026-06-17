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
