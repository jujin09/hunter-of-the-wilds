// Hunter of the Wilds 서비스 워커
// 업데이트할 때 VERSION 숫자를 올리면 예전 캐시가 정리돼요. (안 올려도 온라인이면 최신 파일을 받아요)
const VERSION = "hotw-v17";
const CORE = ["./", "./index.html", "./config.js", "./manifest.webmanifest", "./icon-192.png", "./icon-512.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(VERSION).then(c => Promise.all(CORE.map(u => c.add(new Request(u, { cache: "reload" })).catch(() => {})))));
  self.skipWaiting();
});

self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  // 로그인·세이브 서버 요청은 캐시하지 않음
  if (url.hostname.endsWith("supabase.co") || url.hostname.endsWith("supabase.in")) return;
  if (url.origin === location.origin) {
    // 게임 파일: 네트워크 우선 → 실패하면 캐시 (온라인이면 항상 최신 버전)
    e.respondWith(fetch(req).then(res => {
      if (res.ok) { const cp = res.clone(); caches.open(VERSION).then(c => c.put(req, cp)); }
      return res;
    }).catch(() => caches.match(req).then(r => r || caches.match("./index.html"))));
  } else {
    // 글꼴·라이브러리: 캐시 우선, 뒤에서 갱신
    e.respondWith(caches.match(req).then(hit => {
      const net = fetch(req).then(res => { if (res.ok || res.type === "opaque") { const cp = res.clone(); caches.open(VERSION).then(c => c.put(req, cp)); } return res; }).catch(() => hit);
      return hit || net;
    }));
  }
});
