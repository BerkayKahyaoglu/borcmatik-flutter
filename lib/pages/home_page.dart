import 'package:borcmatik/pages/group_detail_page.dart';
import 'package:borcmatik/pages/login_page.dart';
import 'package:borcmatik/pages/profile_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  // --- ÇIKIŞ YAP ---
  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  // --- 🔍 YARDIMCI: AKILLI İSİM GÖSTERME ---
  String _getDynamicGroupName(Map<String, dynamic> data, String myUid) {
    if (data['isPrivate'] == true && data.containsKey('namesMap')) {
      Map<String, dynamic> names = data['namesMap'];
      String otherUid = names.keys.firstWhere(
              (k) => k != myUid,
          orElse: () => ""
      );
      if (otherUid.isNotEmpty && names[otherUid] != null) {
        return names[otherUid];
      }
    }
    return data['name'] ?? "İsimsiz";
  }

  // --- 🔥 GÜVENLİ SİLME FONKSİYONU (HER ŞEYİ TEMİZLER) ---
  // isFriend: Eğer bu bir arkadaş ise (true), onu hızlı erişim listesinden de sileriz.
  Future<void> _deleteGroupSafely(String groupId, String groupName, {bool isFriend = false}) async {
    try {
      // 1. Önce harcamaları bul
      var expensesSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('expenses')
          .get();

      // 2. Toplu silme işlemi başlat (Batch)
      WriteBatch batch = FirebaseFirestore.instance.batch();

      // Tüm harcamaları silme listesine ekle
      for (var doc in expensesSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // 3. Grubun kendisini silme listesine ekle
      batch.delete(FirebaseFirestore.instance.collection('groups').doc(groupId));

      // 4. Eğer bu bir arkadaş ise, "users -> friends" listesinden de sil
      if (isFriend) {
        final user = FirebaseAuth.instance.currentUser!;

        // Bu arkadaşın UID'sini bulalım (Grubun üyelerinden ben olmayanı bul)
        var groupDoc = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
        if (groupDoc.exists) {
          List members = groupDoc.data()!['members'];
          String friendUid = members.firstWhere((id) => id != user.uid, orElse: () => "");

          if (friendUid.isNotEmpty) {
            batch.delete(FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('friends')
                .doc(friendUid));
          }
        }
      }

      // 5. Hepsini uygula!
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$groupName tamamen silindi 🗑️"), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      print("Silme hatası: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Silinirken hata oluştu."), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- 🔥 YENİ GRUP OLUŞTURMA ---
  void _showCreateGroupDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text("Oluştur"),
          ),
        ],
      ),
    );
  }

  // --- 🔥 ARKADAŞ EKLEME ---
  void _showAddByEmailDialog() {
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

                      // Zaten var mı kontrolü
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

                      // Grubu oluştur
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

                      // Friends listesine ekle
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
          },
        );
      },
    );
  }

  // --- TOPLAM DURUM KARTI ---
  Widget _buildSummaryCard() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collectionGroup('expenses').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return _buildCardDesign("...", "...");

        double totalAlacak = 0;
        double totalVerecek = 0;
        final docs = snapshot.data?.docs ?? [];

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final double amount = double.tryParse(data['amount'].toString()) ?? 0.0;
          final String payerUid = data['payerUid'] ?? "";
          final String type = data['type'] ?? "expense";

          if (type == 'expense') {
            List<dynamic> involved = data['involvedUserIds'] ?? [];
            if (involved.isEmpty) continue;
            double splitAmount = amount / involved.length;

            if (payerUid == user.uid) {
              if (involved.contains(user.uid)) totalAlacak += (amount - splitAmount);
              else totalAlacak += amount;
            } else if (involved.contains(user.uid)) {
              totalVerecek += splitAmount;
            }
          } else if (type == 'settlement') {
            final String? receiverUid = data['receiverUid'];
            if (payerUid == user.uid) totalVerecek -= amount;
            else if (receiverUid == user.uid) totalAlacak -= amount;
          }
        }
        if (totalAlacak < 0.01) totalAlacak = 0;
        if (totalVerecek < 0.01) totalVerecek = 0;

        return _buildCardDesign("${totalAlacak.toStringAsFixed(2)} ₺", "${totalVerecek.toStringAsFixed(2)} ₺");
      },
    );
  }

  Widget _buildCardDesign(String alacak, String verecek) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.teal.shade700, Colors.teal.shade400], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.teal.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          const Text("Toplam Durum", style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(children: [const Icon(Icons.arrow_downward, color: Colors.white, size: 16), Text(alacak, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 40, width: 1, child: ColoredBox(color: Colors.white30)),
              Column(children: [const Icon(Icons.arrow_upward, color: Colors.white, size: 16), Text(verecek, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
            ],
          ),
        ],
      ),
    );
  }

  // --- 🔥 NORMAL GRUP KARTI (SİLME ÖZELLİĞİ EKLENDİ) ---
  Widget _buildNormalGroupCard(Map<String, dynamic> data, String docId) {
    return GestureDetector(
      // 🔥 BURASI YENİ: Normal gruba da basılı tutunca silme menüsü çıkacak
      onLongPress: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Grubu Sil 🗑️"),
            content: Text("${data['name']} grubunu ve TÜM HARCAMALARINI silmek istiyor musun? \n\n(Bu işlem geri alınamaz!)"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: () async {
                  await _deleteGroupSafely(docId, data['name'], isFriend: false); // isFriend: false
                  if (mounted) Navigator.pop(context);
                },
                child: const Text("SİL"),
              ),
            ],
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.groups, color: Colors.teal),
          ),
          title: Text(data['name'] ?? "İsimsiz Grup", style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text("${(data['members'] as List).length} Üye", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => GroupDetailPage(groupId: docId, groupName: data['name']))),
        ),
      ),
    );
  }

  // --- 🔥 ARKADAŞ KARTI (GÜVENLİ SİLME EKLENDİ) ---
  Widget _buildFriendCircle(Map<String, dynamic> data, String docId) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final displayName = _getDynamicGroupName(data, myUid);

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => GroupDetailPage(groupId: docId, groupName: displayName))),
      onLongPress: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Arkadaşı Sil 🗑️"),
            content: Text("$displayName kişisini ve TÜM GEÇMİŞİNİ silmek istiyor musun?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: () async {
                  // isFriend: true diyoruz ki Hızlı Erişim'den de silsin
                  await _deleteGroupSafely(docId, displayName, isFriend: true);
                  if (mounted) Navigator.pop(context);
                },
                child: const Text("Sil"),
              ),
            ],
          ),
        );
      },
      child: Container(
        width: 75,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.teal, width: 2)),
                  child: CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.orange.shade100,
                    child: Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : "?", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 18)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildAddFriendButton() {
    return GestureDetector(
      onTap: _showAddByEmailDialog,
      child: Container(
        width: 75,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(height: 56, width: 56, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300, width: 2)), child: Icon(Icons.add, color: Colors.teal.shade700, size: 28)),
            const SizedBox(height: 4),
            const Text("Ekle", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("BorçMatik", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false, elevation: 0,
        actions: [
          IconButton(icon: const CircleAvatar(backgroundColor: Colors.white, radius: 15, child: Icon(Icons.person, size: 18, color: Colors.teal)), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfilePage()))),
          IconButton(icon: const Icon(Icons.exit_to_app), onPressed: _logout),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('groups').where('members', arrayContains: user!.uid).orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final allDocs = snapshot.data?.docs ?? [];

          final normalGroups = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return (data['isPrivate'] ?? false) == false;
          }).toList();

          final friendGroups = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return (data['isPrivate'] ?? false) == true;
          }).toList();

          return Column(
            children: [
              _buildSummaryCard(),
              if (normalGroups.isNotEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 5), child: Align(alignment: Alignment.centerLeft, child: Text("Grupların", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))),
              Expanded(
                child: normalGroups.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.dashboard_customize_outlined, size: 50, color: Colors.grey.shade300), const SizedBox(height: 10), const Text("Henüz bir grubun yok", style: TextStyle(color: Colors.grey))]))
                    : ListView.builder(
                  padding: const EdgeInsets.only(top: 5, bottom: 20),
                  itemCount: normalGroups.length,
                  itemBuilder: (context, index) => _buildNormalGroupCard(normalGroups[index].data() as Map<String, dynamic>, normalGroups[index].id),
                ),
              ),
              Container(
                height: 150, width: double.infinity,
                decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, -5))], borderRadius: const BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(padding: const EdgeInsets.only(left: 20, top: 15, bottom: 10), child: Row(children: [const Text("Hızlı Erişim: Arkadaşlar", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), margin: const EdgeInsets.only(right: 20), decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10)), child: Text("${friendGroups.length}", style: TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.bold)))])),
                    Expanded(child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), itemCount: friendGroups.length + 1, itemBuilder: (context, index) { if (index == 0) return _buildAddFriendButton(); final doc = friendGroups[index - 1]; return _buildFriendCircle(doc.data() as Map<String, dynamic>, doc.id); })),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 140.0),
        child: FloatingActionButton(onPressed: _showCreateGroupDialog, backgroundColor: Colors.teal, child: const Icon(Icons.add, color: Colors.white)),
      ),
    );
  }
}