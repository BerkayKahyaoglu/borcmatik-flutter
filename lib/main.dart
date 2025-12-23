import 'package:borcmatik/pages/home_page.dart';
import 'package:borcmatik/pages/login_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
import 'package:borcmatik/services/notification_service.dart';
import 'package:flutter/foundation.dart'; // Web kontrolü için (kIsWeb)

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // "Spy Mode" (Hata Yakalayıcı) ile başlatıyoruz
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // 🔥 GÜVENLİ BİLDİRİM BAŞLATMA.
    try {
      // Web'de bazen NotificationService farklı davranabilir, hata verirse yutuyoruz.
      await NotificationService.initialize();
      print("✅ Bildirim servisi başarıyla başlatıldı.");
    } catch (e) {
      print("⚠️ Bildirim servisi başlatılamadı (Sorun değil, uygulama devam ediyor): $e");
    }

    runApp(const ProviderScope(child: MyApp()));

  } catch (e) {
    // Eğer Firebase'in kendisi çökerse yine kırmızı ekran göster
    runApp(ErrorApp(errorMsg: e.toString()));
  }
}

// Hata durumunda çıkacak basit ekran (Widget olarak ayırdık)
class ErrorApp extends StatelessWidget {
  final String errorMsg;
  const ErrorApp({super.key, required this.errorMsg});
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: Colors.white,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 60),
            const SizedBox(height: 20),
            const Text("Bir şeyler ters gitti ama...", style: TextStyle(color: Colors.black, fontSize: 18, decoration: TextDecoration.none)),
            const SizedBox(height: 10),
            Text(errorMsg, style: const TextStyle(color: Colors.grey, fontSize: 12, decoration: TextDecoration.none), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BorçMatik',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          primary: Colors.teal,
          secondary: Colors.tealAccent,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const AuthCheck(),
    );
  }
}

class AuthCheck extends StatefulWidget {
  const AuthCheck({super.key});

  @override
  State<AuthCheck> createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {

  @override
  void initState() {
    super.initState();
    _printFcmToken();
  }

  void _printFcmToken() async {
    try {
      // Eğer Web ise ve VapidKey yoksa hata verebilir, o yüzden catch'e düşer ve uygulama çökmez.
      String? token = await FirebaseMessaging.instance.getToken();
      print("🚀 [FCM TOKEN]: $token");
    } catch (e) {
      print("❌ Token alınırken hata oluştu (Önemli değil): $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return const HomePage();
        }
        return const LoginPage();
      },
    );
  }
}