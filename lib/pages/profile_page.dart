import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:borcmatik/pages/login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _ibanController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      final user = _auth.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await _firestore.collection('users').doc(user.uid).get();

        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          _nameController.text = data['name'] ?? user.displayName ?? "";
          _ibanController.text = data['iban'] ?? "";
        }
      }
    } catch (e) {
      _showSnackBar("Veriler yüklenirken hata oluştu: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) {
      _showSnackBar("İsim alanı boş bırakılamaz!", Colors.orange);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.updateDisplayName(_nameController.text.trim());

        await _firestore.collection('users').doc(user.uid).set({
          'name': _nameController.text.trim(),
          'iban': _ibanController.text.trim().toUpperCase(), // IBAN genelde büyük harf tutulur
          'email': user.email,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (mounted) {
          _showSnackBar("Profil başarıyla güncellendi! ✅", Colors.teal);
          FocusScope.of(context).unfocus();
        }
      }
    } catch (e) {
      _showSnackBar("Güncelleme hatası: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _copyToClipboard() {
    if (_ibanController.text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _ibanController.text));
      _showSnackBar("IBAN panoya kopyalandı!", Colors.teal);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal.shade50,
      appBar: AppBar(
        title: const Text("Profil Ayarları"),
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.teal.shade100,
                  child: const Icon(Icons.person, size: 70, color: Colors.teal),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => _showSnackBar("Profil fotoğrafı yükleme özelliği yakında! 📸", Colors.teal),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              _auth.currentUser?.email ?? "",
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 35),

            // 2. İsim Girişi
            _buildProfileField(
              controller: _nameController,
              label: "Ad Soyad",
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 20),

            _buildProfileField(
              controller: _ibanController,
              label: "IBAN Numaranız",
              icon: Icons.account_balance_wallet_outlined,
              hint: "TR00 0000...",
              suffix: IconButton(
                icon: const Icon(Icons.copy, color: Colors.teal),
                onPressed: _copyToClipboard,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Arkadaşların borç öderken bu IBAN'ı görecektir.",
              style: TextStyle(fontSize: 12, color: Colors.teal, fontStyle: FontStyle.italic),
            ),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 2,
                  backgroundColor: Colors.teal, // ✨ Buton Rengi Belirginleştirildi
                  foregroundColor: Colors.white,
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("BİLGİLERİ GÜNCELLE", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 20),

            TextButton.icon(
              onPressed: () async {
                await _auth.signOut();
                if (mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                        (route) => false,
                  );
                }
              },
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              label: const Text("Çıkış Yap", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.teal),
        suffixIcon: suffix,
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