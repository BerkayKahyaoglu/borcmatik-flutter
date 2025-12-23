import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart'; // Animasyon paketi

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  // --- ARKADAŞ EKLEME FONKSİYONU ---
  Future<void> _addFriend() async {
    if (_emailController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final currentUid = FirebaseAuth.instance.currentUser!.uid;
      final emailToSearch = _emailController.text.trim().toLowerCase(); // Küçük harfe çevirerek ara

      // 1. Kendi kendini eklemeyi engelle
      if (emailToSearch == FirebaseAuth.instance.currentUser!.email) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Kendini ekleyemezsin :)"), backgroundColor: Colors.orange));
        }
        return;
      }

      // 2. Kullanıcıyı 'users' koleksiyonunda ara
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: emailToSearch)
          .get();

      if (querySnapshot.docs.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bu e-posta ile kullanıcı bulunamadı."), backgroundColor: Colors.red));
        return;
      }

      final userToAdd = querySnapshot.docs.first;

      // 3. Zaten arkadaş mı? Kontrol et.
      final friendCheck = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUid)
          .collection('friends')
          .doc(userToAdd.id)
          .get();

      if (friendCheck.exists) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bu kişi zaten arkadaş listenizde."), backgroundColor: Colors.orange));
        return;
      }

      // 4. Arkadaş listesine (Subcollection) ekle
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUid)
          .collection('friends')
          .doc(userToAdd.id) // Arkadaşın ID'si döküman ID'si olsun
          .set({
        'uid': userToAdd['uid'],
        'name': userToAdd['name'],
        'email': userToAdd['email'],
        'addedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _emailController.clear();
        Navigator.pop(context); // Diyaloğu kapat
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Arkadaş eklendi!"), backgroundColor: Colors.teal));
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- ARKADAŞ EKLEME PENCERESİ ---
  void _showAddFriendDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Arkadaş Ekle"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Arkadaşının e-posta adresini gir:"),
            const SizedBox(height: 10),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: "ornek@gmail.com",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.mail, color: Colors.teal),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.teal)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            onPressed: _isLoading ? null : _addFriend,
            child: _isLoading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text("Ekle"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Arkadaşlarım"),
        backgroundColor: Colors.teal, // Tema rengi
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddFriendDialog,
        backgroundColor: Colors.teal, // Tema rengi
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUid)
            .collection('friends')
            .orderBy('name')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.teal));
          }

          // --- BOŞ DURUM ---
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // NOT: Eğer 'assets/animations/friends_empty.json' dosyan yoksa
                    // burası hata verebilir. Yoksa Icon kullanabilirsin.
                    Lottie.asset(
                      'assets/animations/friends_empty.json',
                      width: 200,
                      height: 200,
                      fit: BoxFit.fill,
                      errorBuilder: (context, error, stackTrace) => Icon(Icons.person_off, size: 100, color: Colors.teal.shade200),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Listen bomboş! 😔",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const Text(
                      "Sağ alttaki butondan arkadaş ekle.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }

          final friends = snapshot.data!.docs;

          // --- ARKADAŞ LİSTESİ ---
          return ListView.builder(
            itemCount: friends.length,
            padding: const EdgeInsets.all(10),
            itemBuilder: (context, index) {
              final friend = friends[index].data() as Map<String, dynamic>;
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.symmetric(vertical: 5),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.teal.shade100, // Tema rengi
                    child: Text(friend['name'][0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                  ),
                  title: Text(friend['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(friend['email']),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      // Silme onayı
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("Silinsin mi?"),
                          content: Text("${friend['name']} listenizden çıkarılacak."),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("İptal")),
                            ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(currentUid)
                                      .collection('friends')
                                      .doc(friends[index].id)
                                      .delete();

                                  if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Arkadaş silindi."), duration: Duration(seconds: 1)));
                                },
                                child: const Text("Sil")
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}