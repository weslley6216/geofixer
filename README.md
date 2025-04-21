# Geofixer

Este é um projeto pessoal criado para automatizar o tratamento de arquivos de endereços que uso nas minhas entregas de pacotes. Ele facilita bastante a organização dos dados, corrigindo informações e padronizando os arquivos que recebo.

## 🚚 O que ele faz?

- Lê arquivos `.xlsx` com endereços enviados para uma pasta no Google Drive.
- Corrige nomes de ruas com base no CEP usando a API do ViaCEP.
- Obtém a **geolocalização (latitude e longitude)** usando a API do Google Maps.
- Separa o complemento do endereço principal (ex: "apto", "fundos", etc).
- Gera um novo arquivo `.csv` pronto para ser usado em sistemas de rota.
- Envia o `.csv` de volta para o Google Drive e remove os arquivos locais.
- Tudo isso acontece automaticamente graças a uma **cron job** que roda a cada 5 minutos e verifica se há novos arquivos na pasta do Google Drive.

## 💡 Por que isso existe?

Criei esse script porque comecei a lidar com muitos arquivos de endereços inconsistentes — nomes de ruas abreviados, CEPs incorretos ou informações incompletas. Isso causava problemas no roteirizador, que muitas vezes me levava para os lugares errados ou gerava rotas ineficientes.

Além de corrigir e padronizar os dados, o script também gera arquivos de log que me ajudam a tomar decisões melhores no dia a dia. Com essas informações, por exemplo, consigo:

- Priorizar entregas em regiões com maior volume de pedidos.
- Organizar os pacotes no veículo de forma mais lógica.
- Economizar tempo, combustível e reduzir o retrabalho.

No fim, tudo isso deixa o processo de entrega mais eficiente, confiável e menos estressante.

