import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:googleapis_auth/auth_io.dart';
// 👇 SIR DOSYASINI BURAYA ÇAĞIRIYORUZ
import 'package:borcmatik/secrets.dart';

class NotificationService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // 1. BAŞLANGIÇ AYARLARI
  static Future<void> initialize() async {
    await _firebaseMessaging.requestPermission(alert: true, badge: true, sound: true);

    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/launcher_icon');
    const DarwinInitializationSettings initializationSettingsDarwin = DarwinInitializationSettings();
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid, iOS: initializationSettingsDarwin);

    await _localNotificationsPlugin.initialize(initializationSettings);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showNotification(message);
    });

    await getToken();
  }

  // 2. BİLDİRİMİ GÖSTER
  static Future<void> _showNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'Yüksek Öncelikli Bildirimler',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    await _localNotificationsPlugin.show(
      0,
      message.notification?.title ?? "Borçmatik",
      message.notification?.body ?? "Yeni işlem.",
      platformDetails,
    );
  }

  // 3. TOKEN AL VE KAYDET
  static Future<String?> getToken() async {
    try {
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        User? user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'fcmToken': token,
            'lastActive': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
      return token;
    } catch (e) {
      print("Token hatası: $e");
      return null;
    }
  }

  // 4. (GÜVENLİ) BİLDİRİM GÖNDER
  static Future<void> sendPushNotification(String userToken, String title, String body) async {
    try {
      // 🔐 BİLGİLERİ GİZLİ DOSYADAN ALIYORUZ
      // secrets.dart içindeki 'mySecretKey' değişkenini kullanıyoruz.
      final serviceAccountCredentials = ServiceAccountCredentials.fromJson(mySecretKey);

      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final client = await clientViaServiceAccount(serviceAccountCredentials, scopes);

      final String projectId = mySecretKey['project_id'];

      final Uri url = Uri.parse('https://fcm.googleapis.com/v1/projects/$projectId/messages:send');

      final Map<String, dynamic> messageData = {
        "message": {
          "token": userToken,
          "notification": {"title": title, "body": body},
          "data": {
            "click_action": "FLUTTER_NOTIFICATION_CLICK",
            "status": "done"
          }
        }
      };

      final response = await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(messageData),
      );

      if (response.statusCode == 200) {
        print("🚀 Bildirim başarıyla gönderildi (V1 API)!");
      } else {
        print("⚠️ Hata Kodu: ${response.statusCode}");
        print("Hata Detayı: ${response.body}");
      }
      client.close();
    } catch (e) {
      print("❌ Bildirim gönderme hatası: $e");
    }
  }
}