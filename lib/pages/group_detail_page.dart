import 'dart:io'; // Dosya işlemleri için
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart'; // Depolama
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // Resim seçme
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:borcmatik/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
  // 👇 KATEGORİ LİSTESİ VE İKONLARI
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

  // --- 1. RESİM YÜKLEME FONKSİYONU ---
  Future<String?> _uploadReceiptImage(File imageFile) async {
    try {
      String fileName = "${widget.groupId}/${DateTime.now().millisecondsSinceEpoch}.jpg";
      Reference storageRef = FirebaseStorage.instance.ref().child('receipts').child(fileName);

      UploadTask uploadTask = storageRef.putFile(imageFile);
      TaskSnapshot snapshot = await uploadTask;

      String downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print("Resim yükleme hatası: $e");
      return null;
    }
  }

  // --- 2. RESİM GÖSTERME PENCERESİ ---
  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(imageUrl, fit: BoxFit.contain),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Kapat", style: TextStyle(color: Colors.teal)),
            ),
          ],
        ),
      ),
    );
  }

  // --- 3. BORÇ DURUMU PENCERESİ (RENKLER GÜNCELLENDİ) ---
  void _showDebtStatusDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Borç Durumu 💰"),
          content: FutureBuilder<List<Map<String, dynamic>>>(
            future: _calculateDebts(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: Colors.teal)));
              }
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
                      color: Colors.teal.shade50, // ✨ Turkuaz Arka Plan
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    "${debt['debtorName']} ➡️ ${debt['creditorName']}",
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                if (canSettle)
                                  TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor: Colors.teal, // ✨ Buton Rengi
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(0, 30)
                                    ),
                                    onPressed: () => _settleDebt(debt),
                                    child: const Text("Ödeme Yap", style: TextStyle(fontSize: 12)),
                                  )
                                else
                                  const Tooltip(
                                    message: "Sadece taraflar ödeme yapabilir",
                                    child: Icon(Icons.lock_outline, size: 18, color: Colors.grey),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text("Kalan Borç: ${debt['amount'].toStringAsFixed(2)} ₺",
                                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Kapat", style: TextStyle(color: Colors.teal)))],
        );
      },
    );
  }

  // --- 4. KISMİ ÖDEME FONKSİYONU ---
  Future<void> _settleDebt(Map<String, dynamic> debt) async {
    final amountController = TextEditingController(text: debt['amount'].toStringAsFixed(2));
    String? creditorIban;

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(debt['creditorUid']).get();
      if (userDoc.exists) creditorIban = (userDoc.data() as Map<String, dynamic>)['iban'];
    } catch (e) { debugPrint("IBAN Hatası: $e"); }

    final Map<String, String> bankWebLinks = {
      'Ziraat': 'https://www.ziraatbank.com.tr',
      'İş Bankası': 'https://www.isbank.com.tr',
      'Garanti': 'https://www.garantibvva.com.tr',
      'Akbank': 'https://www.akbank.com',
      'Yapı Kredi': 'https://www.yapikredi.com.tr',
      'Papara': 'https://www.papara.com',
    };

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Hızlı Ödeme Yap 💳"),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("${debt['creditorName']} kişisine ödeme yapılacak."),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: amountController.text.replaceAll(',', '.')));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tutar kopyalandı!")));
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text("Tutar"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (creditorIban != null && creditorIban.isNotEmpty)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: creditorIban!));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("IBAN kopyalandı!")));
                          },
                          icon: const Icon(Icons.account_balance, size: 16),
                          label: const Text("IBAN"),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.teal),
                        ),
                      ),
                  ],
                ),
                const Divider(height: 30),
                const Text("Banka İnternet Şubesi", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: bankWebLinks.keys.map((bankName) {
                    return InkWell(
                      onTap: () async {
                        final Uri url = Uri.parse(bankWebLinks[bankName]!);
                        try {
                          if (kIsWeb) {
                            await launchUrl(url, mode: LaunchMode.platformDefault);
                          } else {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("$bankName sayfası açılırken bir hata oluştu."))
                          );
                        }
                      },
                      child: Container(
                        width: 75,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.teal.shade100),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.language, color: Colors.teal, size: 22),
                            const SizedBox(height: 4),
                            Text(bankName, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 25),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: "Ödenen Tutar", border: OutlineInputBorder(), prefixText: "₺ "),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Vazgeç")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            onPressed: () async {
              final double payAmount = double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0;
              if (payAmount <= 0) return;

              // Firebase Kayıt
              await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).collection('expenses').add({
                'description': "Borç Ödemesi (${debt['debtorName']} -> ${debt['creditorName']})",
                'amount': payAmount,
                'paidBy': debt['debtorName'],
                'payerUid': FirebaseAuth.instance.currentUser!.uid,
                'type': 'settlement',
                'receiverUid': debt['creditorUid'],
                'date': FieldValue.serverTimestamp(),
              });

              // 🔥 BİLDİRİM TETİKLE (Ödeme Alan Kişiye)
              try {
                var creditorDoc = await FirebaseFirestore.instance.collection('users').doc(debt['creditorUid']).get();
                String? token = creditorDoc.data()?['fcmToken'];
                if (token != null) {
                  NotificationService.sendPushNotification(
                      token,
                      "Ödeme Aldın! ✅",
                      "${debt['debtorName']} sana $payAmount ₺ borcunu ödedi."
                  );
                }
              } catch (e) {}

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

  // --- 5. BORÇ HESAPLAMA MANTIĞI (AYNI) ---
  // --- 5. BORÇ HESAPLAMA MANTIĞI (GELİŞMİŞ) ---
  // --- 5. BORÇ HESAPLAMA (GELİŞMİŞ - KİŞİ BAZLI) ---
  Future<List<Map<String, dynamic>>> _calculateDebts() async {
    final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).get();
    final memberIds = List<String>.from(groupDoc['members'] ?? []);

    Map<String, String> userNames = {};
    if (memberIds.isNotEmpty) {
      // Yine 10'arlı paketler halinde çekmek daha güvenli ama şimdilik basit tutalım
      final usersQuery = await FirebaseFirestore.instance.collection('users').where('uid', whereIn: memberIds.take(10).toList()).get();
      for (var doc in usersQuery.docs) userNames[doc['uid']] = doc['name'];
    }

    final expensesQuery = await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).collection('expenses').get();

    // NET BAKİYE TABLOSU (Herkesin ID'si ve Bakiyesi)
    Map<String, double> netBalances = {for (var id in memberIds) id: 0.0};

    for (var doc in expensesQuery.docs) {
      final data = doc.data();
      final amount = (data['amount'] as num).toDouble();
      final payerUid = data['payerUid'] as String?;

      if (payerUid == null) continue;
      // Eğer ödeyen kişi gruptan çıktıysa bakiyeyi hesaplayamayız, o yüzden kontrol
      if (!netBalances.containsKey(payerUid)) netBalances[payerUid] = 0;

      if (data['type'] == 'settlement') {
        // --- ÖDEME ---
        netBalances[payerUid] = netBalances[payerUid]! + amount; // Ödeyen artıda
        final receiverUid = data['receiverUid'] as String?;
        if (receiverUid != null) {
          if (!netBalances.containsKey(receiverUid)) netBalances[receiverUid] = 0;
          netBalances[receiverUid] = netBalances[receiverUid]! - amount; // Alan ekside
        }
      } else {
        // --- HARCAMA ---
        // 1. Ödeyen Alacaklı (+)
        netBalances[payerUid] = netBalances[payerUid]! + amount;

        // 2. Kimler borçlu?
        List<String> involvedUsers = [];
        if (data['involvedUserIds'] != null) {
          involvedUsers = List<String>.from(data['involvedUserIds']);
        } else {
          // Eski usul kayıtlar için herkes dahil
          involvedUsers = List<String>.from(memberIds);
        }

        // Grupta olmayanları temizle
        involvedUsers = involvedUsers.where((uid) => memberIds.contains(uid)).toList();

        if (involvedUsers.isNotEmpty) {
          double splitAmount = amount / involvedUsers.length;
          // 3. Dahil olanlar Borçlu (-)
          for (var uid in involvedUsers) {
            if (!netBalances.containsKey(uid)) netBalances[uid] = 0;
            netBalances[uid] = netBalances[uid]! - splitAmount;
          }
        }
      }
    }

    // --- EŞLEŞTİRME ---
    List<Map<String, dynamic>> debtors = [];
    List<Map<String, dynamic>> creditors = [];
    List<Map<String, dynamic>> results = [];

    netBalances.forEach((uid, balance) {
      if (balance < -0.01) debtors.add({'uid': uid, 'amount': -balance});
      if (balance > 0.01) creditors.add({'uid': uid, 'amount': balance});
    });

    int i = 0, j = 0;
    while (i < debtors.length && j < creditors.length) {
      double amount = debtors[i]['amount'] < creditors[j]['amount'] ? debtors[i]['amount'] : creditors[j]['amount'];

      results.add({
        'debtorName': userNames[debtors[i]['uid']] ?? "Bilinmiyor",
        'debtorUid': debtors[i]['uid'],
        'creditorName': userNames[creditors[j]['uid']] ?? "Bilinmiyor",
        'creditorUid': creditors[j]['uid'],
        'amount': amount,
      });

      debtors[i]['amount'] -= amount;
      creditors[j]['amount'] -= amount;

      if (debtors[i]['amount'] < 0.01) i++;
      if (creditors[j]['amount'] < 0.01) j++;
    }

    return results;
  }

  // --- 6. ÜYE LİSTESİ PENCERESİ ---
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
              if (memberIds.isEmpty) return const Text("Üye yok");

              return FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance.collection('users').where('uid', whereIn: memberIds).get(),
                builder: (context, userSnap) {
                  if (!userSnap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.teal));
                  final users = userSnap.data!.docs;
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: users.length,
                    itemBuilder: (context, i) {
                      final u = users[i].data() as Map<String, dynamic>;
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: Colors.teal.shade100, child: Text(u['name'][0].toUpperCase(), style: const TextStyle(color: Colors.teal))),
                        title: Text(u['name']),
                        subtitle: Text(u['email'] ?? ""),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Kapat", style: TextStyle(color: Colors.teal)))],
      ),
    );
  }

  // --- 7. 🔥 HİBRİT ÜYE EKLEME ---
  void _showAddMemberDialog() {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    showDialog(
      context: context,
      builder: (context) {
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
                    Navigator.pop(context);
                    _showAddByEmailDialog();
                  },
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text("Kayıtlı Arkadaşların:", style: TextStyle(color: Colors.grey)),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('users').doc(currentUid).collection('friends').snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.teal));
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text("Listen boş.\nYukarıdan yeni kişi ekle!"));
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
                                  } catch (e) { print(e); }
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
      },
    );
  }

  // --- 8. E-POSTA İLE EKLEME ---
  // --- 8. E-POSTA İLE EKLEME (DÜZELTİLDİ: HER ZAMAN ARKADAŞA KAYDEDER) ---
  // --- 8. E-POSTA İLE EKLEME (HATA GÖSTEREN VERSİYON) ---
  // --- 🔥 GÜÇLENDİRİLMİŞ ARKADAŞ EKLEME FONKSİYONU ---
  void _showAddByEmailDialog() {
    final emailController = TextEditingController();

    // Yükleniyor durumunu kontrol etmek için StatefulBuilder kullanıyoruz
    showDialog(
      context: context,
      builder: (context) {
        bool isLoading = false;
        String? errorMessage; // Hata mesajını ekrana basmak için

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
                      errorText: errorMessage, // Hata varsa burada kırmızı yazar
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
                    // 1. Temizlik ve Kontrol
                    final email = emailController.text.trim().toLowerCase(); // Küçük harfe çevir
                    final currentUser = FirebaseAuth.instance.currentUser!;

                    if (email.isEmpty) return;

                    if (email == currentUser.email) {
                      setState(() => errorMessage = "Kendini arkadaş olarak ekleyemezsin 😅");
                      return;
                    }

                    setState(() {
                      isLoading = true;
                      errorMessage = null; // Eski hatayı sil
                    });

                    try {
                      // 2. Kullanıcıyı Veritabanında Ara
                      // NOT: Firestore'da e-postalar birebir aynı kayıtlı olmalı.
                      final userQuery = await FirebaseFirestore.instance
                          .collection('users')
                          .where('email', isEqualTo: email)
                          .limit(1)
                          .get();

                      // Kullanıcı Bulunamadıysa
                      if (userQuery.docs.isEmpty) {
                        setState(() {
                          isLoading = false;
                          errorMessage = "Bu e-posta ile kayıtlı kullanıcı bulunamadı.";
                        });
                        return;
                      }

                      final userDoc = userQuery.docs.first;
                      final uid = userDoc.id;
                      final name = userDoc.data()['name'] ?? "İsimsiz";
                      final userEmail = userDoc.data()['email'] ?? email;

                      // 3. Zaten Ekli mi Kontrol Et?
                      // Mevcut özel gruplara bakıyoruz
                      final existingCheck = await FirebaseFirestore.instance
                          .collection('groups')
                          .where('members', arrayContains: currentUser.uid)
                          .get();

                      bool alreadyExists = false;
                      for (var doc in existingCheck.docs) {
                        final data = doc.data();
                        // isPrivate kontrolünü güvenli yapıyoruz
                        final isPrivate = data.containsKey('isPrivate') ? data['isPrivate'] : false;

                        if (isPrivate == true) {
                          List members = data['members'];
                          if (members.contains(uid)) {
                            alreadyExists = true;
                            break;
                          }
                        }
                      }

                      if (alreadyExists) {
                        setState(() {
                          isLoading = false;
                          errorMessage = "Bu kişi zaten arkadaş listenizde var.";
                        });
                        return;
                      }

                      // 4. Arkadaşı Ekle (Grup Oluştur)
                      await FirebaseFirestore.instance.collection('groups').add({
                        'name': name, // Grubun adı arkadaşın ismi olur
                        'members': [currentUser.uid, uid],
                        'memberEmails': [currentUser.email, userEmail],
                        'createdAt': FieldValue.serverTimestamp(),
                        'createdBy': currentUser.uid,
                        'isPrivate': true, // ÖZEL GRUP (ARKADAŞ)
                        'totalDebt': 0,
                      });

                      // Ayrıca Users altına friends koleksiyonuna da ekleyelim (Yedek olarak)
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(currentUser.uid)
                          .collection('friends')
                          .doc(uid)
                          .set({
                        'uid': uid,
                        'name': name,
                        'email': userEmail,
                        'addedAt': FieldValue.serverTimestamp(),
                      });

                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("$name başarıyla eklendi! ✅"), backgroundColor: Colors.teal)
                        );
                      }

                    } catch (e) {
                      print("Hata Detayı: $e");
                      setState(() {
                        isLoading = false;
                        // Hata mesajını kullanıcıya gösteriyoruz ki ne olduğunu anlayalım
                        errorMessage = "Bir hata oluştu: ${e.toString().split(']')[0]}"; // Hatanın başını göster
                      });
                    }
                  },
                  child: isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("Ekle"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- 9. HARCAMA EKLEME (FUTUREBUILDER İLE - GARANTİLİ) ---
  void _showAddExpenseDialog() {
    final descController = TextEditingController();
    final amountController = TextEditingController();
    _selectedCategory = 'Diğer';
    File? selectedImage;
    bool isUploading = false;

    // Varsayılan olarak seçili üyeler (Sonradan dolduracağız)
    List<String> selectedMemberIds = [];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Harcama Ekle"),
              // 🔥 BURASI KRİTİK: FutureBuilder kullanarak veriyi güvenle çekiyoruz
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- KATEGORİLER ---
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
                                avatar: Icon(_categories[cat], size: 18),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 15),

                      // --- FOTOĞRAF ALANI ---
                      GestureDetector(
                        onTap: () async {
                          final picker = ImagePicker();
                          showModalBottomSheet(
                            context: context,
                            builder: (context) => Wrap(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.camera_alt, color: Colors.teal),
                                  title: const Text("Fotoğraf Çek"),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 40);
                                    if (picked != null) setState(() => selectedImage = File(picked.path));
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.photo_library, color: Colors.teal),
                                  title: const Text("Galeriden Seç"),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 40);
                                    if (picked != null) setState(() => selectedImage = File(picked.path));
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                        child: Container(
                          height: 90,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: selectedImage != null ? Colors.teal.shade50 : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: selectedImage != null ? Colors.teal : Colors.grey.shade400),
                          ),
                          child: selectedImage != null
                              ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(selectedImage!, fit: BoxFit.cover))
                              : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera_alt, color: Colors.grey), Text("Fiş/Fotoğraf Ekle", style: TextStyle(color: Colors.grey))]),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // --- FORM ALANLARI ---
                      TextField(controller: descController, decoration: const InputDecoration(labelText: "Ne aldın?", prefixIcon: Icon(Icons.edit_note), contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 10))),
                      const SizedBox(height: 10),
                      TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Tutar", prefixIcon: Icon(Icons.attach_money), suffixText: "₺", contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 10))),

                      const SizedBox(height: 15),
                      const Align(alignment: Alignment.centerLeft, child: Text("Kime Borç Yazılacak?", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 13))),
                      const Divider(),

                      // 🔥🔥🔥 ÜYE LİSTESİ (HATAYI YAKALAYAN KISIM) 🔥🔥🔥
                      FutureBuilder<QuerySnapshot>(
                        future: _fetchGroupMembers(), // Aşağıda tanımladığım yardımcı fonksiyon
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
                          }
                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text("Hata: ${snapshot.error}", style: const TextStyle(color: Colors.red)),
                            );
                          }
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return const Text("Üye bulunamadı.");
                          }

                          final members = snapshot.data!.docs;

                          // Eğer ilk açılışsa ve seçim listesi boşsa, herkesi seçili yap (Varsayılan: Alman Usulü)
                          if (selectedMemberIds.isEmpty) {
                            // Sadece bir kere çalışsın diye kontrol ediyoruz (FutureBuilder rebuild edebilir)
                            // Bu mantığı buraya koymak UI'ı kitleyebilir, o yüzden build dışında tutmak daha iyi ama
                            // Hızlı çözüm için: Kullanıcı henüz elle müdahale etmediyse hepsini ekle.
                            // Not: Bu kısım basit tutuldu. Kullanıcı seçimini kaybetmemesi için dışarıda tutuyoruz.
                            // Ancak ilk render'da listeyi doldurmak için küçük bir hile:
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (selectedMemberIds.isEmpty && context.mounted) {
                                setState(() {
                                  selectedMemberIds = members.map((d) => d['uid'] as String).toList();
                                });
                              }
                            });
                          }

                          return SizedBox(
                            height: 120,
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: members.length,
                              itemBuilder: (context, index) {
                                final data = members[index].data() as Map<String, dynamic>;
                                final uid = data['uid'];
                                final name = data['name'];
                                final isSelected = selectedMemberIds.contains(uid);

                                return CheckboxListTile(
                                  dense: true,
                                  activeColor: Colors.teal,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(name, style: const TextStyle(fontSize: 14)),
                                  value: isSelected,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        selectedMemberIds.add(uid);
                                      } else {
                                        if (selectedMemberIds.length > 1) {
                                          selectedMemberIds.remove(uid);
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("En az 1 kişi seçmelisin!"), duration: Duration(milliseconds: 700)));
                                        }
                                      }
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
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                  onPressed: isUploading ? null : () async {
                    if (descController.text.isEmpty || amountController.text.isEmpty) return;
                    setState(() => isUploading = true);

                    try {
                      final user = FirebaseAuth.instance.currentUser!;
                      String payerName = user.displayName ?? user.email!.split('@')[0];
                      final amount = double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0;

                      String? imageUrl;
                      if (selectedImage != null) imageUrl = await _uploadReceiptImage(selectedImage!);

                      // 🔥 KAYIT İŞLEMİ
                      await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).collection('expenses').add({
                        'description': descController.text.trim(),
                        'amount': amount,
                        'paidBy': payerName,
                        'payerUid': user.uid,
                        'type': 'expense',
                        'category': _selectedCategory,
                        'imageUrl': imageUrl,
                        'date': FieldValue.serverTimestamp(),
                        'involvedUserIds': selectedMemberIds.isEmpty ? [user.uid] : selectedMemberIds, // Boşsa kendine yazsın
                      });

                      if (mounted) Navigator.pop(context);
                    } catch (e) {
                      print("Kaydetme hatası: $e");
                      setState(() => isUploading = false);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
                    }
                  },
                  child: isUploading ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Text("Kaydet"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- 10. HARCAMA DÜZENLEME (EKSİK OLAN FONKSİYON) ---
  void _showEditExpenseDialog(String docId, String currentDesc, dynamic currentAmount) {
    final descController = TextEditingController(text: currentDesc);
    final amountController = TextEditingController(text: currentAmount.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Harcamayı Düzenle"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: "Açıklama", prefixIcon: Icon(Icons.edit))
            ),
            const SizedBox(height: 10),
            TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Tutar", prefixIcon: Icon(Icons.attach_money))
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
            onPressed: () async {
              final newAmount = double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0;
              if (newAmount <= 0) return;

              // Firebase Güncelleme
              await FirebaseFirestore.instance
                  .collection('groups')
                  .doc(widget.groupId)
                  .collection('expenses')
                  .doc(docId)
                  .update({
                'description': descController.text.trim(),
                'amount': newAmount
              });

              if (mounted) Navigator.pop(context);
            },
            child: const Text("Güncelle"),
          )
        ],
      ),
    );
  }


  // 🔥 YARDIMCI FONKSİYON: Grup Üyelerini Çeken Güvenli Sorgu
  Future<QuerySnapshot> _fetchGroupMembers() async {
    // 1. Önce grubun üye listesini al
    final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).get();
    List memberIds = List<String>.from(groupDoc['members'] ?? []);

    if (memberIds.isEmpty) {
      throw "Grupta üye yok!";
    }

    // 2. Üyelerin detaylarını Users tablosundan çek
    // Not: whereIn en fazla 10 eleman alır. Eğer grup 10 kişiden büyükse bu kod hata verir.
    // Güvenlik için ilk 10 kişiyi alıyoruz şimdilik.
    return FirebaseFirestore.instance
        .collection('users')
        .where('uid', whereIn: memberIds.take(10).toList())
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName),
        actions: [
          IconButton(icon: const Icon(Icons.attach_money), tooltip: 'Borç Durumu', onPressed: _showDebtStatusDialog),
          IconButton(icon: const Icon(Icons.people), tooltip: 'Üyeler', onPressed: _showMembersDialog),
          IconButton(icon: const Icon(Icons.person_add), tooltip: 'Üye Ekle', onPressed: _showAddMemberDialog),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddExpenseDialog,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Harcama Ekle", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.teal,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('groups').doc(widget.groupId).collection('expenses').orderBy('date', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.teal));
          final expenses = snapshot.data?.docs ?? [];
          if (expenses.isEmpty) {
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Lottie.asset('assets/animations/empty.json', width: 200, height: 200, fit: BoxFit.fill),
              const SizedBox(height: 20),
              const Text("Henüz harcama yok! 💸", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
            ]));
          }
          double totalAmount = 0;
          for (var doc in expenses) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['type'] != 'settlement') totalAmount += (data['amount'] as num).toDouble();
          }
          return Column(
            children: [
              Container(width: double.infinity, padding: const EdgeInsets.all(20), color: Colors.teal.shade50, child: Column(children: [
                Text("Toplam Harcama", style: TextStyle(color: Colors.teal.shade800)),
                const SizedBox(height: 5),
                Text("${totalAmount.toStringAsFixed(2)} ₺", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.teal)),
              ])),
              Expanded(
                child: ListView.builder(
                  itemCount: expenses.length,
                  itemBuilder: (context, index) {
                    final doc = expenses[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isSettlement = data['type'] == 'settlement';
                    final hasImage = data['imageUrl'] != null;
                    final payerUid = data['payerUid'];
                    final currentUid = FirebaseAuth.instance.currentUser!.uid;
                    final isMyEntry = payerUid == currentUid;
                    final Timestamp? timestamp = data['date'] as Timestamp?;
                    String formattedDate = timestamp != null ? DateFormat('dd.MM HH:mm').format(timestamp.toDate()) : "";

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
                        color: isSettlement ? Colors.green.shade50 : Colors.white,
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          onTap: () {
                            if(!isSettlement && isMyEntry) _showEditExpenseDialog(doc.id, data['description'], data['amount']);
                          },
                          leading: CircleAvatar(backgroundColor: isSettlement ? Colors.green.shade100 : Colors.teal.shade100, child: Icon(isSettlement ? Icons.check : (_categories[data['category']] ?? Icons.receipt), size: 20, color: isSettlement ? Colors.green : Colors.teal)),
                          title: Text(data['description'] ?? ""),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(isSettlement ? "Ödeme Kaydedildi" : "${data['paidBy']} ödedi"),
                            if (formattedDate.isNotEmpty) Text(formattedDate, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ]),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (hasImage) IconButton(icon: const Icon(Icons.receipt_long, color: Colors.teal), onPressed: () => _showImageDialog(data['imageUrl'])),
                            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text("${data['amount']} ₺", style: TextStyle(fontWeight: FontWeight.bold, color: isSettlement ? Colors.green : Colors.red)),
                              if (isMyEntry && !isSettlement) const Icon(Icons.edit, size: 12, color: Colors.grey)
                            ]),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              )
            ],
          );
        },
      ),
    );
  }
}