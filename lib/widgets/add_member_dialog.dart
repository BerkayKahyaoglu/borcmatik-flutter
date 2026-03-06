import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AddMemberDialog extends StatefulWidget {
  final String groupId;

  const AddMemberDialog({super.key, required this.groupId});

  @override
  State<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<AddMemberDialog> {
  // E-POSTA İLE EKLEME PENCERESİ (Dahili Fonksiyon)
  void _showAddByEmailDialog(BuildContext context) {
    final emailController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        bool isLoading = false;
        String? errorMessage;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Arkadaş Ekle ➕"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Eklemek istediğin arkadaşının e-posta adresini gir."),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: "E-posta",
                      hintText: "ornek@gmail.com",
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.email),
                      errorText: errorMessage,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                  onPressed: isLoading ? null : () async {
                    final email = emailController.text.trim().toLowerCase();
                    final currentUser = FirebaseAuth.instance.currentUser!;

                    if (email.isEmpty) return;
                    if (email == currentUser.email) {
                      setState(() => errorMessage = "Kendini arkadaş olarak ekleyemezsin 😅");
                      return;
                    }

                    setState(() { isLoading = true; errorMessage = null; });

                    try {
                      final userQuery = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: email).limit(1).get();

                      if (userQuery.docs.isEmpty) {
                        setState(() { isLoading = false; errorMessage = "Kullanıcı bulunamadı."; });
                        return;
                      }

                      final userDoc = userQuery.docs.first;
                      final uid = userDoc.id;
                      final name = userDoc.data()['name'] ?? "İsimsiz";
                      final userEmail = userDoc.data()['email'] ?? email;

                      final existingCheck = await FirebaseFirestore.instance.collection('groups').where('members', arrayContains: currentUser.uid).get();

                      bool alreadyExists = false;
                      for (var doc in existingCheck.docs) {
                        final data = doc.data();
                        final isPrivate = data.containsKey('isPrivate') ? data['isPrivate'] : false;
                        if (isPrivate == true) {
                          List members = data['members'];
                          if (members.contains(uid)) { alreadyExists = true; break; }
                        }
                      }

                      if (alreadyExists) {
                        setState(() { isLoading = false; errorMessage = "Bu kişi zaten ekli."; });
                        return;
                      }

                      await FirebaseFirestore.instance.collection('groups').add({
                        'name': name,
                        'members': [currentUser.uid, uid],
                        'memberEmails': [currentUser.email, userEmail],
                        'createdAt': FieldValue.serverTimestamp(),
                        'createdBy': currentUser.uid,
                        'isPrivate': true,
                        'totalDebt': 0,
                      });

                      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).collection('friends').doc(uid).set({
                        'uid': uid,
                        'name': name,
                        'email': userEmail,
                        'addedAt': FieldValue.serverTimestamp(),
                      });

                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$name başarıyla eklendi! ✅"), backgroundColor: Colors.teal));
                      }
                    } catch (e) {
                      setState(() { isLoading = false; errorMessage = "Hata oluştu."; });
                    }
                  },
                  child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("Ekle"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    return AlertDialog(
      title: const Text("Üye Ekle"),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.person_add, color: Colors.white)),
              title: const Text("E-posta ile Yeni Kişi Ekle", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
              onTap: () {
                Navigator.pop(context); // Mevcut menüyü kapat
                _showAddByEmailDialog(context); // E-posta menüsünü aç
              },
            ),
            const Divider(),
            const Padding(padding: EdgeInsets.all(8.0), child: Text("Kayıtlı Arkadaşların:", style: TextStyle(color: Colors.grey))),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(currentUid).collection('friends').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.teal));
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text("Listen boş.\nYukarıdan yeni kişi ekle!", textAlign: TextAlign.center));
                  }
                  final friends = snapshot.data!.docs;
                  return ListView.builder(
                    itemCount: friends.length,
                    itemBuilder: (context, index) {
                      final friend = friends[index].data() as Map<String, dynamic>;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.teal.shade100, child: Text(friend['name'][0].toUpperCase(), style: const TextStyle(color: Colors.teal))),
                          title: Text(friend['name']),
                          subtitle: Text(friend['email'] ?? ""),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_circle, color: Colors.teal),
                            onPressed: () async {
                              try {
                                final groupRef = FirebaseFirestore.instance.collection('groups').doc(widget.groupId);
                                final groupSnap = await groupRef.get();
                                final List currentMembers = groupSnap['members'];

                                if (currentMembers.contains(friend['uid'])) {
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bu kişi zaten grupta!")));
                                  return;
                                }

                                await groupRef.update({
                                  'members': FieldValue.arrayUnion([friend['uid']]),
                                  'memberEmails': FieldValue.arrayUnion([friend['email']]),
                                });

                                if (mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${friend['name']} eklendi!"), backgroundColor: Colors.teal));
                                }
                              } catch (e) { debugPrint(e.toString()); }
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Kapat", style: TextStyle(color: Colors.teal)))],
    );
  }
}