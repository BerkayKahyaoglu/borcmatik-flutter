import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AddFriendDialog extends StatefulWidget {
  const AddFriendDialog({super.key});

  @override
  State<AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<AddFriendDialog> {
  final emailController = TextEditingController();
  bool isLoading = false;
  String? errorMessage;

  @override
  Widget build(BuildContext context) {
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
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("İptal", style: TextStyle(color: Colors.grey))
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
          onPressed: isLoading ? null : () async {
            final email = emailController.text.trim().toLowerCase();
            final currentUser = FirebaseAuth.instance.currentUser!;

            if (email.isEmpty) return;
            if (email == currentUser.email) {
              setState(() => errorMessage = "Kendini ekleyemezsin.");
              return;
            }

            setState(() { isLoading = true; errorMessage = null; });

            try {
              final friendQuery = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: email).limit(1).get();

              if (friendQuery.docs.isEmpty) {
                setState(() { isLoading = false; errorMessage = "Kullanıcı bulunamadı."; });
                return;
              }

              final friendDoc = friendQuery.docs.first;
              final friendUid = friendDoc.id;
              final friendName = friendDoc.data()['name'] ?? "İsimsiz";
              final friendEmail = friendDoc.data()['email'] ?? email;

              final myDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
              final myName = myDoc.data()?['name'] ?? currentUser.email!.split('@')[0];

              final existingCheck = await FirebaseFirestore.instance.collection('groups').where('members', arrayContains: currentUser.uid).get();
              bool alreadyExists = false;
              for (var doc in existingCheck.docs) {
                final data = doc.data();
                if (data['isPrivate'] == true && (data['members'] as List).contains(friendUid)) {
                  alreadyExists = true; break;
                }
              }

              if (alreadyExists) {
                setState(() { isLoading = false; errorMessage = "Zaten ekli."; });
                return;
              }

              await FirebaseFirestore.instance.collection('groups').add({
                'name': friendName,
                'namesMap': { currentUser.uid: myName, friendUid: friendName },
                'members': [currentUser.uid, friendUid],
                'memberEmails': [currentUser.email, friendEmail],
                'createdAt': FieldValue.serverTimestamp(),
                'createdBy': currentUser.uid,
                'isPrivate': true,
                'totalDebt': 0,
              });

              await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).collection('friends').doc(friendUid).set({
                'uid': friendUid, 'name': friendName, 'email': friendEmail, 'addedAt': FieldValue.serverTimestamp(),
              });

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$friendName eklendi! ✅"), backgroundColor: Colors.teal));
              }
            } catch (e) {
              setState(() { isLoading = false; errorMessage = "Hata: $e"; });
            }
          },
          child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("Ekle"),
        ),
      ],
    );
  }
}