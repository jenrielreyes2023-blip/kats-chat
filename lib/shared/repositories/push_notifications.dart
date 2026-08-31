import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Message;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln show Message;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:whatsapp_clone/shared/repositories/firebase_firestore.dart';
import 'package:whatsapp_clone/shared/utils/abc.dart';
import 'package:whatsapp_clone/shared/utils/shared_pref.dart';

import '../../features/chat/models/attachement.dart';
import '../../features/chat/models/message.dart';

final pushNotificationsRepoProvider = Provider(
  (ref) => PushNotificationsRepo(FirebaseMessaging.instance, ref),
);

// Global local notification plugin instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// In-memory conversation message history for Android MessagingStyle threading
final Map<String, List<fln.Message>> _conversationThreads = {};

bool _isLocalNotificationsInitialized = false;

Future<void> ensureLocalNotificationsInitialized([
  Future<void> Function(RemoteMessage)? onMessageOpenedApp,
]) async {
  if (_isLocalNotificationsInitialized) return;

  try {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse:
          (NotificationResponse response) async {
        if (response.payload != null &&
            response.payload!.isNotEmpty &&
            onMessageOpenedApp != null) {
          try {
            final Map<String, dynamic> data = jsonDecode(response.payload!);
            onMessageOpenedApp(RemoteMessage(data: data));
          } catch (_) {}
        }
      },
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important chat notifications.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _isLocalNotificationsInitialized = true;
  } catch (e) {
    debugPrint('Error initializing local notifications: $e');
  }
}

class PushNotificationsRepo {
  final FirebaseMessaging instance;
  final ProviderRef ref;

  PushNotificationsRepo(this.instance, this.ref);

  static String? _cachedServerUrl;

  /// Dynamically resolves the notification server endpoint from Firestore with local caching
  static Future<String> getNotificationServerUrl() async {
    if (_cachedServerUrl != null && _cachedServerUrl!.isNotEmpty) {
      return _cachedServerUrl!;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('system_config')
          .doc('notifications')
          .get(const GetOptions(source: Source.serverAndCache));
      final url = doc.data()?['url'] as String?;
      if (url != null && url.isNotEmpty) {
        _cachedServerUrl = url;
        SharedPref.instance.setString('notification_server_url', url);
        return url;
      }
    } catch (_) {}

    final saved = SharedPref.instance.getString('notification_server_url');
    if (saved != null && saved.isNotEmpty) {
      _cachedServerUrl = saved;
      return saved;
    }

    return 'https://strand-salmon-assessed-sponsor.trycloudflare.com/new_message';
  }

  Future<void> init({
    required Future<void> Function(RemoteMessage) onMessageOpenedApp,
  }) async {
    try {
      // 1. Initialize local notification plugin and channel
      await ensureLocalNotificationsInitialized(onMessageOpenedApp);

      // 2. Request runtime notification permissions (Android 13+ & iOS)
      final settings = await instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      // 3. Set foreground presentation options to display heads-up banners
      await instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 4. Fetch and register initial FCM token immediately
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await instance.getToken();
        if (token != null) {
          handleTokenRefresh(token, ref);
        }
      }
    } catch (e) {
      debugPrint('Push notification init error: $e');
    }

    // Foreground listener -> Build & display Android MessagingStyle notification
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      await showMessagingNotification(message);
    });

    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(onMessageOpenedApp);
    instance.onTokenRefresh.listen((token) => handleTokenRefresh(token, ref));
  }

  Future<void> sendPushNotification(Message message) async {
    try {
      final token = await ref
          .read(firebaseFirestoreRepositoryProvider)
          .getFcmToken(message.receiverId);

      if (token == null || token.isEmpty) return;

      final String url = await getNotificationServerUrl();
      final Map<String, String> headers = {"Content-Type": "application/json"};

      String messageContent = message.content;
      if (message.attachment != null && messageContent.isEmpty) {
        messageContent = message.attachment!.type == AttachmentType.image
            ? "📷 Photo"
            : "Sent an attachment";
      }

      final user = getCurrentUser();
      if (user == null) return;

      final String messageJson = jsonEncode(
        {
          'token': token,
          'messageId': message.id,
          'messageContent': messageContent,
          'authorId': user.id,
          'authorName': user.name,
          'authorAvatarUrl': user.avatarUrl,
          'chatId': getChatId(user.id, message.receiverId),
          'attachmentUrl': message.attachment?.url ?? '',
          'attachmentType': message.attachment?.type.name ?? '',
          'timestamp': message.timestamp.millisecondsSinceEpoch.toString(),
        },
      );

      await http.post(
        Uri.parse(url),
        headers: headers,
        body: messageJson,
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  static Future<void> notifyIncomingCall({
    required String receiverId,
    required String callerName,
    required String callerAvatar,
    required bool isVideo,
  }) async {
    try {
      final docSnap = await FirebaseFirestore.instance
          .collection('fcmTokens')
          .doc(receiverId)
          .get();
      final token = docSnap.data()?['token'] as String?;
      if (token == null || token.isEmpty) return;

      final String url = await getNotificationServerUrl();
      final Map<String, String> headers = {"Content-Type": "application/json"};

      final user = getCurrentUser();
      if (user == null) return;

      final String messageJson = jsonEncode(
        {
          'token': token,
          'messageId': 'call_${DateTime.now().millisecondsSinceEpoch}',
          'messageContent': isVideo
              ? '📹 Incoming Video Call...'
              : '📞 Incoming Voice Call...',
          'authorId': user.id,
          'authorName': callerName.isNotEmpty ? callerName : user.name,
          'authorAvatarUrl':
              callerAvatar.isNotEmpty ? callerAvatar : user.avatarUrl,
        },
      );

      await http.post(
        Uri.parse(url),
        headers: headers,
        body: messageJson,
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}

/// Builds and displays notification using Android's MessagingStyle (with Person objects)
/// or BigPictureStyle strictly when an image attachment is present.
Future<void> showMessagingNotification(RemoteMessage remoteMessage) async {
  try {
    await ensureLocalNotificationsInitialized();

    final data = remoteMessage.data;
    final String authorId = data['authorId'] ?? '';
    final String authorName = data['authorName'] ??
        remoteMessage.notification?.title ??
        'New Message';
    final String authorAvatarUrl = data['authorAvatarUrl'] ?? '';
    final String messageContent = data['messageContent'] ??
        remoteMessage.notification?.body ??
        '';
    final String chatId = data['chatId'] ??
        (authorId.isNotEmpty
            ? getChatId(getCurrentUser()?.id ?? '', authorId)
            : 'default_chat');
    final String attachmentUrl = data['attachmentUrl'] ?? '';
    final String attachmentType = data['attachmentType'] ?? '';
    final int timestamp = int.tryParse(data['timestamp'] ?? '') ??
        DateTime.now().millisecondsSinceEpoch;

    // Threading: Use chatId.hashCode as notification ID to thread messages per conversation
    final int notificationId = chatId.hashCode.abs() % 2147483647;

    // Download circular profile avatar bytes if present
    Uint8List? avatarBytes;
    if (authorAvatarUrl.isNotEmpty) {
      try {
        final res = await http
            .get(Uri.parse(authorAvatarUrl))
            .timeout(const Duration(seconds: 2));
        if (res.statusCode == 200) {
          avatarBytes = res.bodyBytes;
        }
      } catch (_) {}
    }

    // Check if the payload explicitly contains an image attachment
    final bool isImageAttachment = attachmentType.toLowerCase() == 'image' ||
        (attachmentUrl.isNotEmpty &&
            RegExp(r'\.(jpg|jpeg|png|webp|gif)(\?.*)?$', caseSensitive: false)
                .hasMatch(attachmentUrl));

    Uint8List? attachmentImageBytes;
    if (isImageAttachment && attachmentUrl.isNotEmpty) {
      try {
        final res = await http
            .get(Uri.parse(attachmentUrl))
            .timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          attachmentImageBytes = res.bodyBytes;
        }
      } catch (_) {}
    }

    StyleInformation styleInformation;

    // 1. Trigger BigPictureStyle ONLY if payload explicitly contains an image attachment
    if (isImageAttachment && attachmentImageBytes != null) {
      styleInformation = BigPictureStyleInformation(
        ByteArrayAndroidBitmap(attachmentImageBytes),
        contentTitle: authorName,
        summaryText:
            messageContent.isNotEmpty ? messageContent : '📷 Photo',
        largeIcon: avatarBytes != null
            ? ByteArrayAndroidBitmap(avatarBytes)
            : null,
        hideExpandedLargeIcon: false,
      );
    } else {
      // 2. Otherwise: Use Android's MessagingStyleInformation with Person objects
      final senderPerson = Person(
        name: authorName,
        key: authorId,
        icon:
            avatarBytes != null ? ByteArrayAndroidIcon(avatarBytes) : null,
      );

      final threadList =
          _conversationThreads.putIfAbsent(chatId, () => <fln.Message>[]);
      threadList.add(
        fln.Message(
          messageContent,
          DateTime.fromMillisecondsSinceEpoch(timestamp),
          senderPerson,
        ),
      );
      if (threadList.length > 10) {
        threadList.removeAt(0);
      }

      styleInformation = MessagingStyleInformation(
        senderPerson,
        conversationTitle: authorName,
        groupConversation: false,
        messages: List.from(threadList),
      );
    }

    final androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription:
          'This channel is used for important chat notifications.',
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: styleInformation,
      largeIcon:
          avatarBytes != null ? ByteArrayAndroidBitmap(avatarBytes) : null,
      tag: chatId,
      groupKey: 'com.kats.chat.MESSAGES',
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await flutterLocalNotificationsPlugin.show(
      notificationId,
      authorName,
      messageContent,
      notificationDetails,
      payload: jsonEncode(data),
    );
  } catch (e) {
    debugPrint('Error displaying messaging notification: $e');
  }
}

@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
  final data = message.data;

  // Send status update acknowledgement to Firestore
  if (data['messageId'] != null && data['authorId'] != null) {
    try {
      await ProviderContainer()
          .read(firebaseFirestoreRepositoryProvider)
          .sendSystemMessage(
            message: SystemMessage(
              targetId: data['messageId'],
              action: MessageAction.statusUpdate,
              update: MessageStatus.delivered.value,
            ),
            receiverId: data['authorId'],
          );
    } catch (_) {}
  }

  // Show MessagingStyle / BigPictureStyle notification in background
  await showMessagingNotification(message);
}

void handleTokenRefresh(String newToken, ProviderRef ref) {
  final oldToken = SharedPref.instance.getString('fcmToken');
  if (newToken == oldToken) return;

  SharedPref.instance.setString('fcmToken', newToken);
  ref.read(firebaseFirestoreRepositoryProvider).setFcmToken(newToken);
}
