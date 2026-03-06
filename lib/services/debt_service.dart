import 'package:cloud_firestore/cloud_firestore.dart';

class DebtService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Tüm borç hesaplama algoritması artık burada, güvende!
  Future<List<Map<String, dynamic>>> calculateDebts(String groupId) async {
    final groupDoc = await _firestore.collection('groups').doc(groupId).get();
    final memberIds = List<String>.from(groupDoc['members'] ?? []);

    Map<String, String> userNames = {};
    if (memberIds.isNotEmpty) {
      final usersQuery = await _firestore.collection('users')
          .where('uid', whereIn: memberIds.take(10).toList())
          .get();
      for (var doc in usersQuery.docs) {
        userNames[doc['uid']] = doc['name'];
      }
    }

    final expensesQuery = await _firestore.collection('groups')
        .doc(groupId)
        .collection('expenses')
        .get();

    // NET BAKİYE TABLOSU
    Map<String, double> netBalances = {for (var id in memberIds) id: 0.0};

    for (var doc in expensesQuery.docs) {
      final data = doc.data();
      final amount = (data['amount'] as num).toDouble();
      final payerUid = data['payerUid'] as String?;

      if (payerUid == null) continue;
      if (!netBalances.containsKey(payerUid)) netBalances[payerUid] = 0;

      if (data['type'] == 'settlement') {
        // Ödeme işlemi
        netBalances[payerUid] = netBalances[payerUid]! + amount;
        final receiverUid = data['receiverUid'] as String?;
        if (receiverUid != null) {
          if (!netBalances.containsKey(receiverUid)) netBalances[receiverUid] = 0;
          netBalances[receiverUid] = netBalances[receiverUid]! - amount;
        }
      } else {
        // Harcama işlemi
        netBalances[payerUid] = netBalances[payerUid]! + amount;

        List<String> involvedUsers = [];
        if (data['involvedUserIds'] != null) {
          involvedUsers = List<String>.from(data['involvedUserIds']);
        } else {
          involvedUsers = List<String>.from(memberIds);
        }

        involvedUsers = involvedUsers.where((uid) => memberIds.contains(uid)).toList();

        if (involvedUsers.isNotEmpty) {
          double splitAmount = amount / involvedUsers.length;
          for (var uid in involvedUsers) {
            if (!netBalances.containsKey(uid)) netBalances[uid] = 0;
            netBalances[uid] = netBalances[uid]! - splitAmount;
          }
        }
      }
    }

    // EŞLEŞTİRME
    List<Map<String, dynamic>> debtors = [];
    List<Map<String, dynamic>> creditors = [];
    List<Map<String, dynamic>> results = [];

    netBalances.forEach((uid, balance) {
      if (balance < -0.01) debtors.add({'uid': uid, 'amount': -balance});
      if (balance > 0.01) creditors.add({'uid': uid, 'amount': balance});
    });

    int i = 0, j = 0;
    while (i < debtors.length && j < creditors.length) {
      double amount = debtors[i]['amount'] < creditors[j]['amount']
          ? debtors[i]['amount']
          : creditors[j]['amount'];

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
}