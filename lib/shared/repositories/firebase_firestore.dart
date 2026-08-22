import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whatsapp_clone/features/chat/models/message.dart';
import 'package:whatsapp_clone/shared/models/user.dart';
import 'package:whatsapp_clone/shared/repositories/isar_db.dart';
import 'package:whatsapp_clone/shared/utils/shared_pref.dart';

import 'package:flutter/foundation.dart';
import 'package:whatsapp_clone/shared/utils/abc.dart';

final firebaseFirestoreRepositoryProvider = Provider(
  (ref) => FirebaseFirestoreRepo(
    firestore: FirebaseFirestore.instance
      ..settings = const Settings(persistenceEnabled: false),
    ref: ref,
  ),
);

class FirebaseFirestoreRepo {
  final FirebaseFirestore firestore;
  final ProviderRef ref;

  const FirebaseFirestoreRepo({
    required this.firestore,
    required this.ref,
  });

  Future<void> setActivityStatus({
    required String userId,
    required String statusValue,
  }) async {
    await firestore
        .collection('users')
        .doc(userId)
        .update({'activityStatus': statusValue});
  }

  Stream<UserActivityStatus> userActivityStatusStream({required userId}) {
    return firestore.collection('users').doc(userId).snapshots().map((event) {
      return UserActivityStatus.fromValue(event.data()!['activityStatus']);
    });
  }

  Stream<User?> userStream({required String userId}) {
    return firestore.collection('users').doc(userId).snapshots().map((event) {
      if (event.exists && event.data() != null) {
        final user = User.fromMap(event.data()!);
        IsarDb.saveUser(user);
        return user;
      }
      return null;
    });
  }

  Future<void> sendMessage(Message message) async {
    final now = DateTime.now();
    final expireAt = Timestamp.fromDate(
      now.add(const Duration(days: 2)),
    );
    final data = message.toMap()..addAll({'expireAt': expireAt});

    // 1. Transient real-time delivery queue for receiver
    await firestore
        .collection('chats')
        .doc(message.receiverId)
        .collection('messages')
        .doc(message.id)
        .set(data);

    // 2. 2-day cloud history for sender
    await firestore
        .collection('cloud_conversations')
        .doc(message.senderId)
        .collection('messages')
        .doc(message.id)
        .set(data);

    // 3. 2-day cloud history for receiver
    await firestore
        .collection('cloud_conversations')
        .doc(message.receiverId)
        .collection('messages')
        .doc(message.id)
        .set(data);
  }

  Future<void> updateCloudMessageStatus({
    required String messageId,
    required String senderId,
    required String receiverId,
    required String statusValue,
  }) async {
    final updateMap = {'status': statusValue};
    try {
      await firestore
          .collection('cloud_conversations')
          .doc(senderId)
          .collection('messages')
          .doc(messageId)
          .update(updateMap);
    } catch (_) {}

    try {
      await firestore
          .collection('cloud_conversations')
          .doc(receiverId)
          .collection('messages')
          .doc(messageId)
          .update(updateMap);
    } catch (_) {}
  }

  Future<void> sendSystemMessage({
    required SystemMessage message,
    required String receiverId,
  }) async {
    await firestore
        .collection('chats')
        .doc(receiverId)
        .collection('messages')
        .add(message.toMap());

    if (message.action == MessageAction.statusUpdate) {
      final currentUserId = getCurrentUser()?.id;
      if (currentUserId != null) {
        updateCloudMessageStatus(
          messageId: message.targetId,
          senderId: receiverId,
          receiverId: currentUserId,
          statusValue: message.update,
        );
      }
    }
  }

  Future<List<Message>> restoreLast2DaysMessages(String userId) async {
    try {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      final snap = await firestore
          .collection('cloud_conversations')
          .doc(userId)
          .collection('messages')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(twoDaysAgo))
          .get();

      final messages = <Message>[];
      for (final doc in snap.docs) {
        try {
          messages.add(Message.fromMap(doc.data()));
        } catch (e) {
          debugPrint('Error deserializing restored message ${doc.id}: $e');
        }
      }
      return messages;
    } catch (e) {
      debugPrint('Error restoring messages from cloud: $e');
      return [];
    }
  }

  Future<void> cleanupOldCloudMessages(String userId) async {
    try {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      final oldDocs = await firestore
          .collection('cloud_conversations')
          .doc(userId)
          .collection('messages')
          .where('timestamp', isLessThan: Timestamp.fromDate(twoDaysAgo))
          .get();

      if (oldDocs.docs.isEmpty) return;

      final batch = firestore.batch();
      for (final doc in oldDocs.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {}
  }

  Future<User?> getUserById(String id) async {
    final documentSnapshot = await firestore.collection('users').doc(id).get();

    return documentSnapshot.exists
        ? User.fromMap(documentSnapshot.data()!)
        : null;
  }

  Stream<List<Message>> getChatStream(String ownId) {
    return firestore
        .collection('chats')
        .doc(ownId)
        .collection('messages')
        .snapshots()
        .asyncMap(
      (querySnap) async {
        final messages = <Message>[];

        for (final docChange in querySnap.docChanges) {
          if (docChange.type == DocumentChangeType.removed) continue;

          final docData = docChange.doc.data()!;
          docChange.doc.reference.delete();

          final isSystemMessage = docData['action'] != null;
          if (isSystemMessage) {
            final msg = SystemMessage.fromMap(docData);
            switch (msg.action) {
              case MessageAction.statusUpdate:
                IsarDb.updateMessage(
                  msg.targetId,
                  status: MessageStatus.fromValue(msg.update),
                );
                break;
            }
            continue;
          }

          messages.add(Message.fromMap(docData));
        }

        return messages;
      },
    );
  }

  Future<User?> getUserByPhone(String phoneNumber) async {
    phoneNumber = phoneNumber
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('(', '')
        .replaceAll(')', '');

    QuerySnapshot<Map<String, dynamic>> snap;
    if (phoneNumber.startsWith('+')) {
      snap = await firestore
          .collection('users')
          .where('phone.rawNumber', isEqualTo: phoneNumber)
          .get();
    } else {
      snap = await firestore
          .collection('users')
          .where('phone.number', isEqualTo: phoneNumber)
          .get();
    }

    return snap.size == 0 ? null : User.fromMap(snap.docs[0].data());
  }

  Future<void> setFcmToken(String token) async {
    final userStr = SharedPref.instance.getString('user');
    if (userStr == null) return;
    try {
      final user = jsonDecode(userStr);
      return firestore
          .collection('fcmTokens')
          .doc(user['id'])
          .set({'token': token});
    } catch (_) {}
  }

  Future<String?> getFcmToken(String userId) async {
    try {
      final docSnap = await firestore.collection('fcmTokens').doc(userId).get();
      if (docSnap.exists && docSnap.data() != null) {
        return docSnap.data()?['token'] as String?;
      }
    } catch (_) {}
    return null;
  }
}
