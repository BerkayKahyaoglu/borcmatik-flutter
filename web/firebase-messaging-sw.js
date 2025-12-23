importScripts("https://www.gstatic.com/firebasejs/8.10.0/firebase-app.js");
importScripts("https://www.gstatic.com/firebasejs/8.10.0/firebase-messaging.js");

// Senin firebase_options.dart dosyanın 'web' kısmından alınan bilgiler:
firebase.initializeApp({
  apiKey: "AIzaSyAnPaJGNigRNTXZURzgS_PW4KkqbXKqaBg",
  appId: "1:668408981680:web:2e5a0ef9f04856ee7cf375",
  messagingSenderId: "668408981680",
  projectId: "borcmatik-v2",
  authDomain: "borcmatik-v2.firebaseapp.com",
  storageBucket: "borcmatik-v2.firebasestorage.app"
});

const messaging = firebase.messaging();

// Uygulama kapalıyken veya arka plandayken bildirim gelirse burası çalışır
messaging.onBackgroundMessage(function(payload) {
  console.log('[firebase-messaging-sw.js] Arka plan mesajı alındı: ', payload);

  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/icons/Icon-192.png' // Varsayılan ikon
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});