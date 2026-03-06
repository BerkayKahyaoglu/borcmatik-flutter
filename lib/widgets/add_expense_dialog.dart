import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/notification_service.dart';

class AddExpenseDialog extends StatefulWidget {
  final String groupId;

  const AddExpenseDialog({super.key, required this.groupId});

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final descController = TextEditingController();
  final amountController = TextEditingController();
  String _selectedCategory = 'Diğer';
  File? selectedImage;
  bool isUploading = false;
  List<String> selectedMemberIds = [];

  final Map<String, IconData> _categories = {
    'Market': Icons.shopping_cart,
    'Yemek': Icons.fastfood,
    'Ulaşım': Icons.directions_bus,
    'Fatura': Icons.lightbulb,
    'Eğlence': Icons.movie,
    'Kira': Icons.home,
    'Diğer': Icons.receipt,
  };

  Future<String?> _uploadReceiptImage(File imageFile) async {
    try {
      String fileName = "${widget.groupId}/${DateTime.now().millisecondsSinceEpoch}.jpg";
      Reference storageRef = FirebaseStorage.instance.ref().child('receipts').child(fileName);
      UploadTask uploadTask = storageRef.putFile(imageFile);
      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint("Resim yükleme hatası: $e");
      return null;
    }
  }

  Future<QuerySnapshot> _fetchGroupMembers() async {
    final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).get();
    List memberIds = List<String>.from(groupDoc['members'] ?? []);
    if (memberIds.isEmpty) throw "Grupta üye yok!";
    return FirebaseFirestore.instance.collection('users').where('uid', whereIn: memberIds.take(10).toList()).get();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Harcama Ekle"),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _categories.keys.map((cat) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: _selectedCategory == cat,
                        selectedColor: Colors.teal,
                        labelStyle: TextStyle(color: _selectedCategory == cat ? Colors.white : Colors.black),
                        onSelected: (s) => setState(() => _selectedCategory = cat),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 15),
              GestureDetector(
                onTap: () async {
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 40);
                  if (picked != null) setState(() => selectedImage = File(picked.path));
                },
                child: Container(
                  height: 90,
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
                  child: selectedImage != null
                      ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(selectedImage!, fit: BoxFit.cover))
                      : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera_alt), Text("Fiş Ekle")]),
                ),
              ),
              const SizedBox(height: 10),
              TextField(controller: descController, decoration: const InputDecoration(labelText: "Ne aldın?", prefixIcon: Icon(Icons.edit_note))),
              const SizedBox(height: 10),
              TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Tutar", suffixText: "₺")),
              const SizedBox(height: 15),
              const Divider(),
              FutureBuilder<QuerySnapshot>(
                future: _fetchGroupMembers(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const CircularProgressIndicator();
                  final members = snapshot.data!.docs;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (selectedMemberIds.isEmpty && context.mounted) {
                      setState(() => selectedMemberIds = members.map((d) => d['uid'] as String).toList());
                    }
                  });
                  return SizedBox(
                    height: 120,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final data = members[index].data() as Map<String, dynamic>;
                        final uid = data['uid'];
                        return CheckboxListTile(
                          title: Text(data['name']),
                          value: selectedMemberIds.contains(uid),
                          onChanged: (val) {
                            setState(() {
                              if (val == true) selectedMemberIds.add(uid);
                              else if (selectedMemberIds.length > 1) selectedMemberIds.remove(uid);
                            });
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
        ElevatedButton(
          onPressed: isUploading ? null : () async {
            if (descController.text.isEmpty || amountController.text.isEmpty) return;
            setState(() => isUploading = true);
            try {
              final user = FirebaseAuth.instance.currentUser!;
              String payerName = user.displayName ?? user.email!.split('@')[0];
              final amount = double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0;
              String? imageUrl;
              if (selectedImage != null) imageUrl = await _uploadReceiptImage(selectedImage!);

              await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).collection('expenses').add({
                'description': descController.text.trim(),
                'amount': amount,
                'paidBy': payerName,
                'payerUid': user.uid,
                'type': 'expense',
                'category': _selectedCategory,
                'imageUrl': imageUrl,
                'date': FieldValue.serverTimestamp(),
                'involvedUserIds': selectedMemberIds,
              });
              for (String uid in selectedMemberIds) {
                if (uid != user.uid) {
                  try {
                    var userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
                    if (userDoc.exists) {
                      String? token = userDoc.data()?['fcmToken'];
                      if (token != null && token.isNotEmpty) {
                        NotificationService.sendPushNotification(
                            token,
                            "Yeni Harcama! 💸",
                            "$payerName, '${descController.text}' için $amount ₺ harcama ekledi."
                        );
                      }
                    }
                  } catch (e) {
                    debugPrint("Bildirim gönderme hatası: $e");
                  }
                }
              }

              if (mounted) Navigator.pop(context);
            } catch (e) { setState(() => isUploading = false); }
          },
          child: isUploading ? const CircularProgressIndicator() : const Text("Kaydet"),
        ),
      ],
    );
  }
}