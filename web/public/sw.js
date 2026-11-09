// Service worker do Geofixer.
// As páginas são dinâmicas (upload, status do job, downloads) e ficam atrás de
// Basic Auth, então passam direto pela rede. Só os assets estáticos (ícones,
// manifesto, CSS) são cacheados, em stale-while-revalidate.

const VERSAO = "geofixer-v1";

const PUBLICOS = [
  "/manifest.webmanifest",
  "/icons/icon-192.png",
  "/icons/icon-512.png",
  "/icons/apple-touch-icon.png",
  "/icons/favicon-32.png",
];

const ESTATICO = /^\/(manifest\.webmanifest|style\.css|icons\/[\w.-]+\.png)$/;

self.addEventListener("install", (evento) => {
  evento.waitUntil(
    caches.open(VERSAO)
      .then((cache) => cache.addAll(PUBLICOS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (evento) => {
  evento.waitUntil(
    caches.keys()
      .then((chaves) => Promise.all(
        chaves.filter((chave) => chave !== VERSAO).map((chave) => caches.delete(chave))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (evento) => {
  const req = evento.request;
  if (req.method !== "GET") return;

  const url = new URL(req.url);
  if (url.origin !== self.location.origin || !ESTATICO.test(url.pathname)) return;

  evento.respondWith(
    caches.open(VERSAO).then(async (cache) => {
      const cacheado = await cache.match(req, { ignoreSearch: true });
      const rede = fetch(req)
        .then((resposta) => {
          if (resposta && resposta.ok) cache.put(req, resposta.clone());
          return resposta;
        })
        .catch(() => cacheado);
      return cacheado || rede;
    })
  );
});
