import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whatsapp_clone/features/auth/data/repositories/auth_repository.dart';
import 'package:whatsapp_clone/features/auth/views/welcome.dart';
import 'package:whatsapp_clone/features/chat/models/attachement.dart';
import 'package:whatsapp_clone/features/chat/models/message.dart';
import 'package:whatsapp_clone/features/chat/models/recent_chat.dart';
import 'package:whatsapp_clone/features/chat/views/chat.dart';
import 'package:whatsapp_clone/features/home/data/repositories/contact_repository.dart';
import 'package:whatsapp_clone/shared/repositories/download_service.dart';
import 'package:whatsapp_clone/shared/repositories/firebase_firestore.dart';
import 'package:whatsapp_clone/features/home/views/contacts.dart';
import 'package:whatsapp_clone/features/home/views/profile.dart';
import 'package:whatsapp_clone/shared/models/user.dart';
import 'package:whatsapp_clone/shared/repositories/isar_db.dart';
import 'package:whatsapp_clone/shared/repositories/push_notifications.dart';
import 'package:whatsapp_clone/shared/services/call_service.dart';
import 'package:whatsapp_clone/shared/utils/abc.dart';
import 'package:whatsapp_clone/shared/utils/chat_sounds.dart';
import 'package:whatsapp_clone/shared/utils/shared_pref.dart';
import 'package:whatsapp_clone/theme/theme.dart';
import '../../../shared/utils/storage_paths.dart';
import '../../../theme/color_theme.dart';

class HomePage extends ConsumerStatefulWidget {
  final User user;
  const HomePage({super.key, required this.user});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
  with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late User _currentUser;
  late final StreamSubscription<List<Message>> messageListener;
  late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> _usersSubscription;
  late TabController _tabController;
  late List<Widget> _floatingButtons;
  Timer? _heartbeatTimer;

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    ref.read(firebaseFirestoreRepositoryProvider).sendHeartbeat(
          userId: _currentUser.id,
        );
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.read(firebaseFirestoreRepositoryProvider).sendHeartbeat(
            userId: _currentUser.id,
          );
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        _startHeartbeat();
        break;
      default:
        _stopHeartbeat();
        ref.read(firebaseFirestoreRepositoryProvider).setActivityStatus(
            userId: _currentUser.id,
            statusValue: UserActivityStatus.offline.value);
        break;
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  void initState() {
    _currentUser = widget.user;
    final firestore = ref.read(firebaseFirestoreRepositoryProvider);
    _startHeartbeat();
    CallService.login(_currentUser);

    // Restore / sync last 2 days messages from cloud
    _syncLast2DaysMessages(_currentUser.id);

    // Listen to live user profile changes (avatar, name) across all devices
    _usersSubscription = FirebaseFirestore.instance
        .collection('users')
        .snapshots()
        .listen((snapshot) async {
      final updatedUsers = <User>[];
      for (final doc in snapshot.docs) {
        if (doc.data().isNotEmpty) {
          try {
            updatedUsers.add(User.fromMap(doc.data()));
          } catch (_) {}
        }
      }
      if (updatedUsers.isNotEmpty) {
        await IsarDb.saveUsers(updatedUsers);
        if (mounted) setState(() {});
      }
    });

    messageListener = firestore.getChatStream(widget.user.id).listen(
      (messages) async {
        for (final message in messages) {
          message.status = MessageStatus.delivered;
          firestore.sendSystemMessage(
            message: SystemMessage(
              targetId: message.id,
              action: MessageAction.statusUpdate,
              update: MessageStatus.delivered.value,
            ),
            receiverId: message.senderId,
          );

          if (message.attachment != null && message.attachment!.autoDownload) {
            DownloadService.download(
              taskId: message.id,
              url: message.attachment!.url,
              path: DeviceStorage.getMediaFilePath(
                message.attachment!.fileName,
              ),
              onDownloadComplete: (_) {},
              onDownloadError: () {},
            );
          }
        }

        IsarDb.addMessages(messages);
        if (messages.isNotEmpty) {
          ChatSounds.playReceived();
        }
      },
    );

    ref.read(pushNotificationsRepoProvider).init(
      onMessageOpenedApp: (message) async {
        await handleNotificationClick(message);
      },
    );

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message != null) {
        await handleNotificationClick(message);
      }
    });

    _tabController = TabController(length: 3, vsync: this, initialIndex: 0);
    _tabController.addListener(handleTabIndexChange);

    _floatingButtons = [
      FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ContactsPage(
                user: widget.user,
              ),
            ),
          );
        },
        child: const Icon(Icons.chat),
      ),
      Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            backgroundColor: AppColorsDark.appBarColor,
            onPressed: () {},
            child: const Icon(Icons.edit),
          ),
          const SizedBox(
            height: 16.0,
          ),
          FloatingActionButton(
            onPressed: () {},
            child: const Icon(Icons.camera_alt_rounded),
          ),
        ],
      ),
      FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add_call),
      )
    ];

    super.initState();
  }

  @override
  void dispose() {
    _stopHeartbeat();
    try {
      ref.read(firebaseFirestoreRepositoryProvider).setActivityStatus(
          userId: _currentUser.id,
          statusValue: UserActivityStatus.offline.value);
    } catch (_) {}
    _tabController.removeListener(handleTabIndexChange);
    _tabController.dispose();
    messageListener.cancel();
    _usersSubscription.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void handleTabIndexChange() {
    setState(() {});
  }

  Future<void> handleNotificationClick(RemoteMessage message) async {
    final author = await ref
        .read(firebaseFirestoreRepositoryProvider)
        .getUserById(message.data['authorId']);

    final contact = await ref
        .read(contactsRepositoryProvider)
        .getContactByPhone(author!.phone.number!);

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => ChatPage(
          self: widget.user,
          other: author,
          otherUserContactName:
              contact?.displayName ?? author.phone.getFormattedNumber(),
        ),
      ),
      (route) => route.settings.name == "/",
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Sigurado ka bang nais mong mag-log out sa KatsChat?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await ref.read(authRepositoryProvider).auth.signOut();
              } catch (_) {}
              await CallService.logout();
              await SharedPref.instance.remove('user');
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const WelcomePage()),
                (route) => false,
              );
            },
            child: const Text(
              'LOG OUT',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _syncLast2DaysMessages(String userId) async {
    try {
      final firestore = ref.read(firebaseFirestoreRepositoryProvider);
      final messages = await firestore.restoreLast2DaysMessages(userId);
      if (messages.isNotEmpty) {
        await IsarDb.addMessages(messages);

        for (final message in messages) {
          if (message.attachment != null &&
              message.attachment!.autoDownload &&
              message.attachment!.url.isNotEmpty) {
            final localPath = DeviceStorage.getMediaFilePath(
              message.attachment!.fileName,
            );
            if (!File(localPath).existsSync()) {
              DownloadService.download(
                taskId: message.id,
                url: message.attachment!.url,
                path: localPath,
                onDownloadComplete: (_) {},
                onDownloadError: () {},
              );
            }
          }
        }
      }
      firestore.cleanupOldCloudMessages(userId);
    } catch (e) {
      debugPrint('Error syncing last 2 days messages: $e');
    }
  }

  void _openProfilePage() async {
    final updatedUser = await Navigator.of(context).push<User>(
      MaterialPageRoute(
        builder: (context) => ProfilePage(
          user: _currentUser,
          onProfileUpdated: (user) {
            setState(() {
              _currentUser = user;
            });
          },
        ),
      ),
    );
    if (updatedUser != null && mounted) {
      setState(() {
        _currentUser = updatedUser;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).custom.textTheme;
    final colorTheme = Theme.of(context).custom.colorTheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'KatsChat',
            style: textTheme.titleLarge.copyWith(color: colorTheme.iconColor),
          ),
          actions: [
            IconButton(
              onPressed: () {},
              icon: const Icon(
                Icons.camera_alt_outlined,
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(
                Icons.search,
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              color: colorTheme.appBarColor,
              onSelected: (value) {
                if (value == 'logout') {
                  _showLogoutDialog();
                } else if (value == 'profile') {
                  _openProfilePage();
                } else if (value == 'new_group') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ContactsPage(user: _currentUser),
                    ),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'new_group',
                  child: Text('New group'),
                ),
                const PopupMenuItem(
                  value: 'profile',
                  child: Text('Profile / Settings'),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('Log out', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelStyle: textTheme.labelLarge,
            tabs: const [
              Tab(
                text: 'CHATS',
              ),
              Tab(
                text: 'STATUS',
              ),
              Tab(
                text: 'CALLS',
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          children: [
            RecentChatsBody(user: _currentUser),
            const Center(
              child: Text('Coming soon'),
            ),
            const Center(
              child: Text('Coming soon'),
            )
          ],
        ),
        floatingActionButton: _floatingButtons[_tabController.index],
      ),
    );
  }
}

class RecentChatsBody extends ConsumerWidget {
  const RecentChatsBody({
    super.key,
    required this.user,
  });

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorTheme = Theme.of(context).custom.colorTheme;

    return StreamBuilder<List<RecentChat>>(
      stream: IsarDb.getRecentChatStream(ref),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container();
        }

        final chats = snapshot.data!;
        if (chats.isEmpty) {
          return const HomePageContactsList();
        }

        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: ListView.builder(
                itemCount: chats.length,
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  RecentChat chat = chats[index];
                  Message msg = chat.message;
                  String msgContent = chat.message.content;
                  String msgStatus = '';

                  if (msg.senderId == user.id) {
                    msgStatus = msg.status.value;
                  }
                  return RecentChatWidget(
                    user: user,
                    chat: chat,
                    colorTheme: colorTheme,
                    title: chat.user.name,
                    msgStatus: msgStatus,
                    msgContent: msgContent,
                  );
                },
              ),
            ),
            if (chats.isNotEmpty) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock,
                      size: 18,
                      color: Theme.of(context).brightness == Brightness.light
                          ? colorTheme.greyColor
                          : colorTheme.iconColor,
                    ),
                    const SizedBox(width: 4),
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodySmall,
                        children: [
                          TextSpan(
                            text: 'Your personal messages are ',
                            style: TextStyle(color: colorTheme.greyColor),
                          ),
                          TextSpan(
                            text: 'end-to-end encrypted',
                            style: TextStyle(color: colorTheme.greenColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ]
          ],
        );
      },
    );
  }
}

class HomePageContactsList extends StatelessWidget {
  const HomePageContactsList({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorTheme = Theme.of(context).custom.colorTheme;
    final currentUser = getCurrentUser();

    final botUser = User(
      id: 'whatsup_bot',
      name: 'KatsChat Assistant',
      avatarUrl: 'https://cdn-icons-png.flaticon.com/512/4712/4712035.png',
      phone: Phone(code: '+1', number: '1000000000', formattedNumber: '+1 000 000 0000'),
      activityStatus: UserActivityStatus.online,
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorTheme.greenColor.withOpacity(0.15),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 64,
                color: colorTheme.greenColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No chats yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: colorTheme.textColor1,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Subukan ang conversation interface kasama ang KatsChat Assistant o mag-start ng bagong chat!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colorTheme.greyColor,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorTheme.greenColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: () {
                if (currentUser == null) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ContactsPage(user: currentUser),
                  ),
                );
              },
              icon: const Icon(Icons.chat),
              label: const Text(
                'Mag-start ng Bagong Chat',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colorTheme.textColor1,
                side: BorderSide(color: colorTheme.greenColor.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: () {
                if (currentUser == null) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ChatPage(
                       self: currentUser,
                      other: botUser,
                      otherUserContactName: 'KatsChat Assistant 🤖',
                    ),
                    settings: const RouteSettings(name: 'chat'),
                  ),
                );
              },
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text(
                'Subukan ang KatsChat Assistant 🤖',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecentChatWidget extends StatelessWidget {
  const RecentChatWidget({
    super.key,
    required this.user,
    required this.chat,
    required this.colorTheme,
    required this.title,
    required this.msgStatus,
    required this.msgContent,
  });

  final User user;
  final RecentChat chat;
  final ColorTheme colorTheme;
  final String title;
  final String msgStatus;
  final String msgContent;

  @override
  Widget build(BuildContext context) {
    final trailingChildren = [
      RecentChatTime(chat: chat, colorTheme: colorTheme),
      if (chat.unreadCount > 0) ...[
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorTheme.greenColor,
          ),
          margin: const EdgeInsets.only(left: 4.0),
          padding: const EdgeInsets.all(6.0),
          child: Text(
            chat.unreadCount.toString(),
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w500,
            ),
          ),
        )
      ],
    ];

    return ListTile(
      onTap: () {
        chat.unreadCount = 0;

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatPage(
              self: user,
              other: chat.user,
              otherUserContactName: title,
            ),
            settings: const RouteSettings(name: 'chat'),
          ),
        );
      },
      leading: CircleAvatar(
        radius: 28.0,
        backgroundImage: CachedNetworkImageProvider(
          chat.user.avatarUrl,
        ),
      ),
      title: Text(
        title,
        style: Theme.of(context)
            .custom
            .textTheme
            .titleMedium
            .copyWith(color: colorTheme.textColor1),
      ),
      subtitle: Row(
        children: [
          if (msgStatus.isNotEmpty) ...[
            Image.asset(
              'assets/images/$msgStatus.png',
              color: msgStatus != 'SEEN' ? colorTheme.textColor1 : null,
              width: 15.0,
            ),
            const SizedBox(
              width: 2.0,
            )
          ],
          if (chat.message.attachment != null) ...[
            LayoutBuilder(
              builder: (context, _) {
                switch (chat.message.attachment!.type) {
                  case AttachmentType.audio:
                    return const Icon(
                      Icons.audiotrack_rounded,
                      size: 20,
                    );

                  case AttachmentType.voice:
                    return const Icon(
                      Icons.mic,
                      size: 20,
                    );

                  case AttachmentType.image:
                    return const Icon(
                      Icons.image_rounded,
                      size: 20,
                    );

                  case AttachmentType.video:
                    return const Icon(
                      Icons.videocam_rounded,
                      size: 20,
                    );

                  default:
                    return const Icon(
                      Icons.file_copy,
                      size: 20,
                    );
                }
              },
            ),
            const SizedBox(
              width: 2.0,
            )
          ],
          Text(
              msgContent.length > 30
                  ? '${msgContent.substring(0, 30)}...'
                  : msgContent == "\u00A0" || msgContent.isEmpty
                      ? chat.message.attachment!.type.value
                      : msgContent,
              style: Theme.of(context).custom.textTheme.subtitle2)
        ],
      ),
      trailing: chat.unreadCount > 0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: trailingChildren,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: trailingChildren,
            ),
    );
  }
}

class RecentChatTime extends StatefulWidget {
  const RecentChatTime({
    super.key,
    required this.chat,
    required this.colorTheme,
  });

  final RecentChat chat;
  final ColorTheme colorTheme;

  @override
  State<RecentChatTime> createState() => _RecentChatTimeState();
}

class _RecentChatTimeState extends State<RecentChatTime> {
  late final Timer timer;

  @override
  void initState() {
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
    super.initState();
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      formattedTimestamp(
        widget.chat.message.timestamp,
      ),
      style: Theme.of(context).custom.textTheme.caption.copyWith(
            color: widget.chat.unreadCount > 0
                ? widget.colorTheme.greenColor
                : Theme.of(context).custom.colorTheme.greyColor,
          ),
    );
  }
}
