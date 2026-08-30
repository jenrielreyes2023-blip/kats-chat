import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whatsapp_clone/features/chat/models/attachement.dart';
import 'package:whatsapp_clone/features/chat/models/recent_chat.dart';
import 'package:whatsapp_clone/features/home/data/repositories/contact_repository.dart';
import 'package:whatsapp_clone/shared/models/contact.dart';
import 'package:whatsapp_clone/shared/models/messages.dart';
import 'package:whatsapp_clone/shared/models/user.dart';
import 'package:whatsapp_clone/shared/repositories/firebase_firestore.dart';
import 'package:whatsapp_clone/shared/utils/abc.dart';
import 'package:whatsapp_clone/shared/utils/shared_pref.dart';

import '../../features/chat/models/message.dart';

final isarProvider = Provider((ref) => IsarDb());

class IsarDb {
  static late final Isar isar;

  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    isar = await Isar.open(
      [StoredMessageSchema, ContactSchema, UserSchema],
      directory: dir.path,
    );
  }

  static Future<void> addMessage(Message message) async {
    final existing = await isar.storedMessages
        .filter()
        .messageIdEqualTo(message.id)
        .build()
        .findFirst();

    if (existing != null) {
      if (existing.status != message.status) {
        await updateMessage(message.id, status: message.status);
      }
      return;
    }

    final storedMsg = StoredMessage(
      messageId: message.id,
      chatId: getChatId(message.senderId, message.receiverId),
      content: message.content,
      senderId: message.senderId,
      receiverId: message.receiverId,
      status: message.status,
      timestamp: message.timestamp.toDate(),
      attachment: message.attachment != null
          ? EmbeddedAttachment(
              fileName: message.attachment!.fileName,
              fileExtension: message.attachment!.fileExtension,
              fileSize: message.attachment!.fileSize,
              width: message.attachment!.width,
              height: message.attachment!.height,
              autoDownload: message.attachment!.autoDownload,
              uploadStatus: message.attachment!.uploadStatus,
              url: message.attachment!.url,
              type: message.attachment!.type,
              samples: message.attachment!.samples,
            )
          : null,
    );

    await isar.writeTxn(() async {
      await isar.storedMessages.put(storedMsg);
    });
  }

  static Future<void> addMessages(List<Message> messages) async {
    if (messages.isEmpty) return;

    final existingList = await isar.storedMessages
        .filter()
        .anyOf(messages, (q, Message m) => q.messageIdEqualTo(m.id))
        .build()
        .findAll();
    final existingIds = existingList.map((e) => e.messageId).toSet();

    final newStoredMessages = messages
        .where((m) => !existingIds.contains(m.id))
        .map(
          (message) => StoredMessage(
            messageId: message.id,
            chatId: getChatId(message.senderId, message.receiverId),
            content: message.content,
            senderId: message.senderId,
            receiverId: message.receiverId,
            status: message.status,
            timestamp: message.timestamp.toDate(),
            attachment: message.attachment != null
                ? EmbeddedAttachment(
                    fileName: message.attachment!.fileName,
                    fileExtension: message.attachment!.fileExtension,
                    fileSize: message.attachment!.fileSize,
                    width: message.attachment!.width,
                    height: message.attachment!.height,
                    uploadStatus: message.attachment!.uploadStatus,
                    autoDownload: message.attachment!.autoDownload,
                    url: message.attachment!.url,
                    type: message.attachment!.type,
                    samples: message.attachment!.samples,
                  )
                : null,
          ),
        )
        .toList();

    if (newStoredMessages.isEmpty) return;

    await isar.writeTxn(() async {
      await isar.storedMessages.putAll(newStoredMessages);
    });
  }

  static Future<void> updateMessage(
    String messageId, {
    String? content,
    MessageStatus? status,
    Attachment? attachment,
  }) async {
    await isar.writeTxn(() async {
      StoredMessage? msg = await isar.storedMessages
          .filter()
          .messageIdEqualTo(messageId)
          .build()
          .findFirst();

      if (msg == null) return;

      msg.content = content ?? msg.content;
      msg.status = status ?? msg.status;

      if (attachment != null) {
        msg.attachment = EmbeddedAttachment(
          fileName: attachment.fileName,
          fileExtension: attachment.fileExtension,
          fileSize: attachment.fileSize,
          width: attachment.width,
          height: attachment.height,
          uploadStatus: attachment.uploadStatus,
          autoDownload: attachment.autoDownload,
          url: attachment.url,
          type: attachment.type,
          samples: attachment.samples,
        );
      }

      await isar.storedMessages.put(msg);
    });
  }

  static Stream<List<Message>> getChatStream(String chatId) {
    return isar.storedMessages
        .filter()
        .chatIdEqualTo(chatId)
        .sortByTimestampDesc()
        .build()
        .watch(fireImmediately: true)
        .map((event) => event
            .map(
              (msg) => Message(
                id: msg.messageId,
                content: msg.content,
                senderId: msg.senderId,
                receiverId: msg.receiverId,
                timestamp: Timestamp.fromDate(msg.timestamp),
                status: msg.status,
                attachment: msg.attachment != null
                    ? Attachment(
                        fileName: msg.attachment!.fileName!,
                        fileExtension: msg.attachment!.fileExtension!,
                        fileSize: msg.attachment!.fileSize!,
                        width: msg.attachment!.width,
                        height: msg.attachment!.height,
                        uploadStatus: msg.attachment!.uploadStatus!,
                        autoDownload: msg.attachment!.autoDownload ?? false,
                        url: msg.attachment!.url!,
                        type: msg.attachment!.type!,
                        samples: msg.attachment!.samples,
                      )
                    : null,
              ),
            )
            .toList());
  }

  static Stream<List<RecentChat>> getRecentChatStream(WidgetRef ref) {
    final currentUser = User.fromMap(
      jsonDecode(SharedPref.instance.getString('user')!),
    );

    return isar.storedMessages
        .where()
        .sortByTimestampDesc()
        .watch(fireImmediately: true)
        .asyncMap((event) async {
      final Map<String, int> visitedPartners = {};
      final recentChats = <RecentChat>[];

      for (final msg in event) {
        final clientIsSender = msg.senderId == currentUser.id;
        final partnerId = clientIsSender ? msg.receiverId : msg.senderId;

        if (visitedPartners.containsKey(partnerId)) {
          if (!clientIsSender && msg.status != MessageStatus.seen) {
            visitedPartners[partnerId] = visitedPartners[partnerId]! + 1;
          }
          continue;
        }

        var sender = await IsarDb.getUserById(partnerId);

        Contact? contact;
        if (sender != null && sender.phone.number != null) {
          try {
            contact = await ref
                .read(contactsRepositoryProvider)
                .getContactByPhone(sender.phone.number!);
          } catch (_) {}
        }

        if (sender == null) {
          try {
            sender = await ref
                .read(firebaseFirestoreRepositoryProvider)
                .getUserById(partnerId);
          } catch (_) {}
        }

        sender ??= User(
          id: partnerId,
          name: partnerId,
          avatarUrl: 'https://en.gravatar.com/userimage/238463648/8cc16f6f5423605920569a634fd097eb.jpeg?size=256',
          phone: Phone(code: '', number: partnerId, formattedNumber: partnerId),
          activityStatus: UserActivityStatus.offline,
        );

        final senderName =
            contact?.displayName ?? (sender.name.isNotEmpty ? sender.name : sender.phone.formattedNumber);

        recentChats.add(
          RecentChat(
            message: Message(
              id: msg.messageId,
              content: msg.content,
              senderId: msg.senderId,
              receiverId: msg.receiverId,
              timestamp: Timestamp.fromDate(msg.timestamp),
              status: msg.status,
              attachment: msg.attachment != null
                  ? Attachment(
                      fileName: msg.attachment!.fileName ?? '',
                      fileExtension: msg.attachment!.fileExtension ?? '',
                      fileSize: msg.attachment!.fileSize ?? 0,
                      width: msg.attachment!.width ?? 1,
                      height: msg.attachment!.height ?? 1,
                      uploadStatus: msg.attachment!.uploadStatus ?? UploadStatus.uploaded,
                      autoDownload: msg.attachment!.autoDownload ?? false,
                      url: msg.attachment!.url ?? '',
                      type: msg.attachment!.type ?? AttachmentType.document,
                    )
                  : null,
            ),
            user: User.fromMap(
              sender.toMap()..addAll({'name': senderName}),
            ),
          ),
        );

        visitedPartners[partnerId] =
            (!clientIsSender && msg.status != MessageStatus.seen) ? 1 : 0;
      }

      for (final chat in recentChats) {
        final clientIsSender = chat.message.senderId == currentUser.id;
        final partnerId = clientIsSender ? chat.message.receiverId : chat.message.senderId;
        chat.unreadCount = visitedPartners[partnerId] ?? 0;
      }

      return recentChats;
    });
  }

  static Future<void> addContacts() async {
    final providerContainer = ProviderContainer();
    final self = getCurrentUser();
    if (self == null) return;

    // 1. Get all registered users from Firestore
    List<User> allRegisteredUsers = [];
    try {
      allRegisteredUsers = await providerContainer
          .read(firebaseFirestoreRepositoryProvider)
          .getAllRegisteredUsers();
    } catch (_) {}

    final otherRegisteredUsers = <User>[];
    final seenRegisteredPhoneKeys = <String>{};
    for (final user in allRegisteredUsers) {
      if (user.id == self.id || user.id == 'whatsup_bot') continue;

      final phoneKey = normalizePhoneNumber(user.phone.rawNumber);
      final userKey = phoneKey.isNotEmpty ? phoneKey : 'user:${user.id}';
      if (seenRegisteredPhoneKeys.add(userKey)) {
        otherRegisteredUsers.add(user);
      }
    }

    // 2. Get local phone contacts
    var localContacts = <Contact>[];
    try {
      localContacts = await providerContainer
          .read(contactsRepositoryProvider)
          .getContacts(self: self);
    } catch (_) {}

    final finalContacts = <Contact>[];
    final matchedLocalContactIds = <String>{};
    final addedContactKeys = <String>{};

    // 3. For every registered user on WhatsUp, match with local contact or add as registered user.
    for (final regUser in otherRegisteredUsers) {
      final phoneKey = normalizePhoneNumber(regUser.phone.rawNumber);
      final registeredKey = phoneKey.isNotEmpty
          ? 'phone:$phoneKey'
          : 'user:${regUser.id}';
      if (!addedContactKeys.add(registeredKey)) continue;

      Contact? matchedLocal;
      for (final lc in localContacts) {
        if (isPhoneMatch(lc.phoneNumber, regUser.phone.rawNumber) ||
            isPhoneMatch(lc.phoneNumber, regUser.phone.number) ||
            isPhoneMatch(lc.phoneNumber, regUser.phone.formattedNumber)) {
          matchedLocal = lc;
          matchedLocalContactIds.add(lc.contactId);
          break;
        }
      }

      finalContacts.add(
        Contact(
          userId: regUser.id,
          avatarUrl: regUser.avatarUrl,
          contactId: matchedLocal?.contactId ?? 'cloud_${regUser.id}',
          displayName: matchedLocal?.displayName ??
              (regUser.name.isNotEmpty
                  ? regUser.name
                  : regUser.phone.getFormattedNumber()),
          phoneNumber: matchedLocal?.phoneNumber ??
              regUser.phone.getFormattedNumber(),
        ),
      );
    }

    // 4. For remaining local contacts that are not registered on WhatsUp, add to "Invite" list.
    for (final lc in localContacts) {
      final phoneKey = normalizePhoneNumber(lc.phoneNumber);
      final localKey = phoneKey.isNotEmpty
          ? 'phone:$phoneKey'
          : 'contact:${lc.contactId}';
      if (matchedLocalContactIds.contains(lc.contactId) ||
          !addedContactKeys.add(localKey)) {
        continue;
      }

      finalContacts.add(
        Contact(
          contactId: lc.contactId,
          displayName: lc.displayName,
          phoneNumber: lc.phoneNumber,
        ),
      );
    }

    await isar.writeTxn(() async {
      await isar.contacts.putAll(finalContacts);
      await isar.users.putAll(otherRegisteredUsers);
    });
  }

  static Future<void> refreshContacts() async {
    await isar.writeTxn(() async {
      await isar.contacts.clear();
      await isar.users.clear();
    });

    await IsarDb.addContacts();
  }

  static Future<List<Contact>> getContacts() async {
    final contacts = await isar.contacts.where().findAll();
    final uniqueContacts = <Contact>[];
    final duplicateIds = <int>[];
    final seenKeys = <String>{};

    for (final contact in contacts) {
      final phoneKey = normalizePhoneNumber(contact.phoneNumber);
      final key = contact.userId != null && contact.userId!.isNotEmpty
          ? 'user:${contact.userId}'
          : phoneKey.isNotEmpty
              ? 'phone:$phoneKey'
              : 'contact:${contact.contactId}';

      if (seenKeys.add(key)) {
        uniqueContacts.add(contact);
      } else {
        duplicateIds.add(contact.id);
      }
    }

    if (duplicateIds.isNotEmpty) {
      await isar.writeTxn(() async {
        for (final id in duplicateIds) {
          await isar.contacts.delete(id);
        }
      });
    }

    return uniqueContacts;
  }

  static Future<User?> getUserById(String id) async {
    if (id == 'whatsup_bot') {
      return User(
        id: 'whatsup_bot',
        name: 'KatsChat Assistant',
        avatarUrl: 'https://cdn-icons-png.flaticon.com/512/4712/4712035.png',
        phone: Phone(code: '+1', number: '1000000000', formattedNumber: '+1 000 000 0000'),
        activityStatus: UserActivityStatus.online,
      );
    }
    final self = getCurrentUser();
    if (self != null && id == self.id) {
      return self;
    }
    return await isar.users.filter().idEqualTo(id).findFirst();
  }

  static Future<void> saveUser(User user) async {
    try {
      final existing =
          await isar.users.filter().idEqualTo(user.id).findFirst();
      if (existing != null) {
        user.isarId = existing.isarId;
      }
      await isar.writeTxn(() async {
        await isar.users.put(user);
      });
    } catch (_) {}
  }

  static Future<void> saveUsers(List<User> users) async {
    try {
      for (final user in users) {
        final existing =
            await isar.users.filter().idEqualTo(user.id).findFirst();
        if (existing != null) {
          user.isarId = existing.isarId;
        }
      }
      await isar.writeTxn(() async {
        await isar.users.putAll(users);
      });
    } catch (_) {}
  }

  static Future<List<Contact>> getWhatsAppContacts() async {
    return await isar.contacts.filter().userIdIsNotNull().findAll();
  }
}
