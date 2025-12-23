import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final TextEditingController _groupNameController = TextEditingController();
  bool _isLoading = false;

  // --- GRUP OLUŞTURMA FONKSİYONU ---
  Future<void> _createGroup() async {
    final groupName = _groupNameController.text.trim();

    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lütfen bir grup adı girin."), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser != null) {
        await FirebaseFirestore.instance.collection('groups').add({
          'name': groupName,
          'members': [currentUser.uid],
          'memberEmails': [currentUser.email],
          'createdBy': currentUser.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Grup başarıyla oluşturuldu! 🚀"),
              backgroundColor: Colors.teal, // ✨ Turkuaz Bildirim
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Hata oluştu: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal.shade50, // ✨ Hafif turkuaz arka plan
      appBar: AppBar(
        title: const Text("Yeni Grup Oluştur"),
        centerTitle: true,
        elevation: 0, // Sade görünüm
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Icon(
              Icons.groups_rounded, // Daha modern bir ikon
              size: 100,
              color: Colors.teal, // ✨ Turkuaz İkon
            ),
            const SizedBox(height: 20),
            const Text(
              "Borçlar biter, dostluk kalır.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.teal),
            ),
            const SizedBox(height: 10),
            const Text(
              "Harcamaları takip etmek için grubuna bir isim ver!",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 40),

            // 👇 GRUP ADI GİRİŞ ALANI
            TextField(
              controller: _groupNameController,
              decoration: InputDecoration(
                labelText: "Grup Adı",
                hintText: "Örn: Ev Arkadaşları, Yaz Tatili...",
                prefixIcon: const Icon(Icons.edit_note, color: Colors.teal),
                filled: true,
                fillColor: Colors.white,
                labelStyle: const TextStyle(color: Colors.teal),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: const BorderSide(color: Colors.teal, width: 2),
                ),
              ),
            ),

            const SizedBox(height: 40),

            // 👇 OLUŞTUR BUTONU
            SizedBox(
              height: 55,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _createGroup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal, // ✨ Turkuaz Buton
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                  "GRUP OLUŞTUR",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}