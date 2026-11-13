// Hunter of the Wilds service worker
const VERSION="hotw-v23";
const CORE=["./","./index.html"];
self.addEventListener("install",e=>{self.skipWaiting();e.waitUntil(caches.open(VERSION).then(c=>c.addAll(CORE)).catch(()=>{}))});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==VERSION).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener("message",e=>{if(e.data==="skip")self.skipWaiting()});
const put=(r,res)=>{if(res&&(res.ok||res.type==="opaque")){const cp=res.clone();caches.open(VERSION).then(c=>c.put(r,cp))}return res};
self.addEventListener("fetch",e=>{const r=e.request;if(r.method!=="GET")return;const u=new URL(r.url);
  if(u.origin!==location.origin){
    if(/fonts\.(googleapis|gstatic)\.com$|cdn\.jsdelivr\.net$/.test(u.host))e.respondWith(caches.match(r).then(h=>h||fetch(r).then(res=>put(r,res))));
    return}
  if(r.mode==="navigate"||/\.html$|config\.js$|\/$/.test(u.pathname)){
    e.respondWith(fetch(r).then(res=>put(r,res)).catch(()=>caches.match(r).then(h=>h||caches.match("./index.html"))));return}
  e.respondWith(caches.match(r).then(h=>h||fetch(r).then(res=>put(r,res))))});
