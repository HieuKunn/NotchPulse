// NotchPulse Service Worker - Instant Offline & Local Cache Storage
const CACHE_NAME = 'notchpulse-local-v1';

const PRECACHE_URLS = [
  './assets/cozy_bg.webp',
  './assets/cozy_bg.jpg',
  './assets/app_icon.png',
  './assets/logo_clean.png',
  './assets/hugo_hani.png',
  './style.css?v=34',
  './main.js?v=23'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(PRECACHE_URLS);
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      );
    }).then(() => self.clients.claim())
  );
});

// Cache-First Strategy for Images & Static Assets: Serves instantly from local disk in 0ms
self.addEventListener('fetch', (event) => {
  const requestUrl = new URL(event.request.url);

  // Intercept images and static assets
  if (
    event.request.destination === 'image' ||
    requestUrl.pathname.includes('/assets/') ||
    requestUrl.pathname.endsWith('.webp') ||
    requestUrl.pathname.endsWith('.jpg') ||
    requestUrl.pathname.endsWith('.png')
  ) {
    event.respondWith(
      caches.match(event.request).then((cachedResponse) => {
        if (cachedResponse) {
          return cachedResponse;
        }
        return fetch(event.request).then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200) {
            const responseClone = networkResponse.clone();
            caches.open(CACHE_NAME).then((cache) => {
              cache.put(event.request, responseClone);
            });
          }
          return networkResponse;
        });
      })
    );
  }
});
