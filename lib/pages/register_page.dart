import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // Kontrolcüler
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController(); // Şifre tekrarı eklendi

  bool _isLoading = false;
  bool _isPasswordVisible = false;

  // --- KAYIT FONKSİYONU ---
  Future<void> _register() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    // 1. Temel Validasyonlar
    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _showSnackBar("Lütfen tüm alanları doldurun!", Colors.orange);
      return;
    }

    if (password != confirmPassword) {
      _showSnackBar("Şifreler birbiriyle eşleşmiyor!", Colors.red);
      return;
    }

    if (password.length < 6) {
      _showSnackBar("Şifre en az 6 karakter olmalıdır!", Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 2. Firebase Auth ile Kullanıcı Oluşturma
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 3. Kullanıcının Adını Auth Profiline Güncelle
      await userCredential.user!.updateDisplayName(name);

      // 4. Firestore'a Kullanıcı Bilgilerini Kaydet
      // Bu kısım arkadaş ekleme ve arama için çok kritiktir.
      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid,
        'name': name,
        'email': email,
        'searchName': name.toLowerCase(), // Arama yaparken kolaylık sağlar
        'createdAt': FieldValue.serverTimestamp(),
        'fcmToken': "", // Bildirimler için başlangıç değeri
      });

      if (mounted) {
        _showSnackBar("Hesabınız başarıyla oluşturuldu! 🎉", Colors.teal);
        Navigator.pop(context); // Giriş sayfasına geri dön
      }
    } on FirebaseAuthException catch (e) {
      // Firebase Özel Hatalarını Yönetme
      String message = "Bir hata oluştu.";
      if (e.code == 'weak-password') message = "Şifre çok zayıf.";
      else if (e.code == 'email-already-in-this-use') message = "Bu e-posta zaten kayıtlı.";
      else if (e.code == 'invalid-email') message = "Geçersiz e-posta formatı.";

      _showSnackBar(message, Colors.red);
    } catch (e) {
      _showSnackBar("Hata: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Yardımcı Mesaj Kutusu
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal.shade50,
      appBar: AppBar(
        title: const Text("Yeni Hesap Oluştur"),
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_add_rounded, size: 80, color: Colors.teal),
              const SizedBox(height: 15),
              const Text(
                "Borçmatik'e Katıl",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.teal),
              ),
              const Text(
                "Borçlar biter, dostluk kalır.",
                style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.teal),
              ),
              const SizedBox(height: 40),

              // İsim Soyisim
              _buildTextField(
                controller: _nameController,
                label: "Ad Soyad",
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 15),

              // E-posta
              _buildTextField(
                controller: _emailController,
                label: "E-posta Adresi",
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 15),

              // Şifre
              _buildTextField(
                controller: _passwordController,
                label: "Şifre",
                icon: Icons.lock_outline,
                isPassword: true,
              ),
              const SizedBox(height: 15),

              // Şifre Tekrar
              _buildTextField(
                controller: _confirmPasswordController,
                label: "Şifreyi Onayla",
                icon: Icons.lock_clock_outlined,
                isPassword: true,
              ),
              const SizedBox(height: 35),

              // Kayıt Butonu
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("KAYIT OL", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),

              const SizedBox(height: 20),

              // Giriş Sayfasına Dönüş
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Zaten bir hesabın var mı? Giriş Yap",
                  style: TextStyle(color: Colors.teal, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Ortak TextField Tasarımı
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword && !_isPasswordVisible,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.teal),
        suffixIcon: isPassword
            ? IconButton(
          icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off, color: Colors.teal),
          onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
        )
            : null,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.teal, width: 2),
        ),
      ),
    );
  }
}