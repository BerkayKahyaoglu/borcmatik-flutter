import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CreateGroupDialog extends StatelessWidget {
  const CreateGroupDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final nameController = TextEditingController();

    return AlertDialog(
      title: const Text("Yeni Grup Oluştur"),
      content: TextField(
        controller: nameController,
        decoration: const InputDecoration(labelText: "Grup Adı", border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
          onPressed: () async {
            if (nameController.text.isNotEmpty) {
              final user = FirebaseAuth.instance.currentUser!;
              await FirebaseFirestore.instance.collection('groups').add({
                'name': nameController.text.trim(),
                'members': [user.uid],
                'memberEmails': [user.email],
                'createdAt': FieldValue.serverTimestamp(),
                'createdBy': user.uid,
                'isPrivate': false,
                'totalDebt': 0,
              });
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: const Text("Oluştur"),
        ),
      ],
    );
  }
}