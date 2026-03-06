import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../widgets/add_expense_dialog.dart';
import '../widgets/add_member_dialog.dart';

import '../services/notification_service.dart';
import '../services/debt_service.dart';

class GroupDetailPage extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupDetailPage({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  final Map<String, IconData> _categories = {
    'Market': Icons.shopping_cart,
    'Yemek': Icons.fastfood,
    'Ulaşım': Icons.directions_bus,
    'Fatura': Icons.lightbulb,
    'Eğlence': Icons.movie,
    'Kira': Icons.home,
    'Diğer': Icons.receipt,
  };

  String _selectedCategory = 'Diğer';
  final DebtService _debtService = DebtService();

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

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(imageUrl, fit: BoxFit.contain),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Kapat", style: TextStyle(color: Colors.teal))),
          ],
        ),
      ),
    );
  }

  Future<QuerySnapshot> _fetchGroupMembers() async {
    final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).get();
    List memberIds = List<String>.from(groupDoc['members'] ?? []);
    if (memberIds.isEmpty) throw "Grupta üye yok!";
    return FirebaseFirestore.instance.collection('users').where('uid', whereIn: memberIds.take(10).toList()).get();
  }

  void _showDebtStatusDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Borç Durumu 💰"),
          content: FutureBuilder<List<Map<String, dynamic>>>(
            future: _debtService.calculateDebts(widget.groupId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: Colors.teal)));
              if (snapshot.hasError) return Text("Hata: ${snapshot.error}");

              final debts = snapshot.data!;
              if (debts.isEmpty) return const Text("Herkes ödeşmiş! Borç yok. ✅", textAlign: TextAlign.center);

              return SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: debts.length,
                  itemBuilder: (context, index) {
                    final debt = debts[index];
                    final currentUid = FirebaseAuth.instance.currentUser!.uid;
                    final canSettle = (currentUid == debt['debtorUid'] || currentUid == debt['creditorUid']);

                    return Card(
                      color: Colors.teal.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text("${debt['debtorName']} ➡️ ${debt['creditorName']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                if (canSettle)
                                  TextButton(
                                    style: TextButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, minimumSize: const Size(0, 30)),
                                    onPressed: () => _settleDebt(debt),
                                    child: const Text("Ödeme Yap", style: TextStyle(fontSize: 12)),
                                  )
                              ],
                            ),
                            const SizedBox(height: 5),
                            Align(alignment: Alignment.centerLeft, child: Text("Kalan Borç: ${debt['amount'].toStringAsFixed(2)} ₺", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Kapat"))],
        );
      },
    );
  }

  Future<void> _settleDebt(Map<String, dynamic> debt) async {
    final amountController = TextEditingController(text: debt['amount'].toStringAsFixed(2));
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Hızlı Ödeme Yap 💳"),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("${debt['creditorName']} kişisine ödeme yapılacak."),
              const SizedBox(height: 15),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: "Ödenen Tutar", border: OutlineInputBorder(), prefixText: "₺ "),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Vazgeç")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            onPressed: () async {
              final double payAmount = double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0;
              if (payAmount <= 0) return;

              await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).collection('expenses').add({
                'description': "Borç Ödemesi (${debt['debtorName']} -> ${debt['creditorName']})",
                'amount': payAmount,
                'paidBy': debt['debtorName'],
                'payerUid': FirebaseAuth.instance.currentUser!.uid,
                'type': 'settlement',
                'receiverUid': debt['creditorUid'],
                'date': FieldValue.serverTimestamp(),
              });

              if (mounted) {
                Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
                await Future.delayed(const Duration(milliseconds: 500));
                if (mounted) _showDebtStatusDialog();
              }
            },
            child: const Text("Onayla"),
          ),
        ],
      ),
    );
  }

  void _showMembersDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Grup Üyeleri"),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('groups').doc(widget.groupId).get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.teal));
              final groupData = snapshot.data!.data() as Map<String, dynamic>;
              final memberIds = List<String>.from(groupData['members'] ?? []);

              return FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance.collection('users').where('uid', whereIn: memberIds).get(),
                builder: (context, userSnap) {
                  if (!userSnap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.teal));
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: userSnap.data!.docs.length,
                    itemBuilder: (context, i) {
                      final u = userSnap.data!.docs[i].data() as Map<String, dynamic>;
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: Colors.teal.shade100, child: Text(u['name'][0].toUpperCase(), style: const TextStyle(color: Colors.teal))),
                        title: Text(u['name']),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Kapat"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName),
        actions: [
          IconButton(icon: const Icon(Icons.attach_money), tooltip: 'Borç Durumu', onPressed: _showDebtStatusDialog),
          IconButton(icon: const Icon(Icons.people), tooltip: 'Üyeler', onPressed: _showMembersDialog),
          IconButton(icon: const Icon(Icons.person_add), tooltip: 'Üye Ekle', onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AddMemberDialog(groupId: widget.groupId),
            );
          },),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed:() {
          showDialog(
            context: context,
            builder: (context) => AddExpenseDialog(groupId: widget.groupId),
          );
        },
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Harcama Ekle", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.teal,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('groups').doc(widget.groupId).collection('expenses').orderBy('date', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.teal));
          final expenses = snapshot.data?.docs ?? [];
          if (expenses.isEmpty) return const Center(child: Text("Henüz harcama yok! 💸", style: TextStyle(fontSize: 18, color: Colors.grey)));

          return ListView.builder(
            itemCount: expenses.length,
            itemBuilder: (context, index) {
              final doc = expenses[index];
              final data = doc.data() as Map<String, dynamic>;

              final isSettlement = data['type'] == 'settlement';
              final currentUid = FirebaseAuth.instance.currentUser!.uid;
              final isMyEntry = data['payerUid'] == currentUid;
              final hasImage = data['imageUrl'] != null;

              return Dismissible(
                key: Key(doc.id),
                direction: DismissDirection.endToStart,
                background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
                confirmDismiss: (d) async {
                  if (!isMyEntry) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bunu sadece ekleyen kişi silebilir! 🔒"), backgroundColor: Colors.red));
                    return false;
                  }
                  return true;
                },
                onDismissed: (d) => FirebaseFirestore.instance.collection('groups').doc(widget.groupId).collection('expenses').doc(doc.id).delete(),
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: Colors.teal, child: Icon(_categories[data['category']] ?? Icons.receipt, color: Colors.white)),
                    title: Text(data['description'] ?? ""),
                    subtitle: Text("${data['paidBy']} ödedi"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasImage) IconButton(icon: const Icon(Icons.receipt_long, color: Colors.teal), onPressed: () => _showImageDialog(data['imageUrl'])),
                        Text("${data['amount']} ₺", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 16)),
                      ],
                    ),
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