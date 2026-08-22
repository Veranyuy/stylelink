// Firebase Cloud Messaging Service Worker for web push notifications.
// This file enables FCM to display notifications when the web app is in
// the background or closed.
//
// For more info: https://firebase.google.com/docs/cloud-messaging/js/receive

importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBB8JZHSH4jqYIYWImFWNMmXVMovia24I0',
  authDomain: 'stylelink-505716.firebaseapp.com',
  projectId: 'stylelink-505716',
  storageBucket: 'stylelink-505716.firebasestorage.app',
  messagingSenderId: '246740680949',
  appId: '1:246740680949:web:3fb6126d1004a110db45bc',
});

const messaging = firebase.messaging();

// Handle background messages.
messaging.onBackgroundMessage(function (payload) {
  console.log('[firebase-messaging-sw.js] Background message:', payload);

  const notificationTitle = payload.notification?.title || 'StyleLink';
  const notificationOptions = {
    body: payload.notification?.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data,
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});

// Handle notification click — open the app.
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (clientList) {
      // If the app is already open, focus it.
      for (const client of clientList) {
        if (client.url.includes('/') && 'focus' in client) {
          return client.focus();
        }
      }
      // Otherwise open a new window.
      if (clients.openWindow) {
        return clients.openWindow('/');
      }
    })
  );
});
