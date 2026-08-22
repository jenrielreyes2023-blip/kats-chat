import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:whatsapp_clone/features/chat/models/attachement.dart';
import 'package:whatsapp_clone/features/chat/models/message.dart';
import 'package:whatsapp_clone/features/chat/models/recent_chat.dart';
import 'package:whatsapp_clone/features/chat/views/chat.dart';
import 'package:whatsapp_clone/features/home/data/repositories/contact_repository.dart';
import 'package:whatsapp_clone/shared/repositories/download_service.dart';
import 'package:whatsapp_clone/shared/repositories/firebase_firestore.dart';
import 'package:whatsapp_clone/features/home/views/contacts.dart';
import 'package:whatsapp_clone/shared/models/user.dart';
import 'package:whatsapp_clone/shared/repositories/isar_db.dart';
import 'package:whatsapp_clone/shared/repositories/push_notifications.dart';
import 'package:whatsapp_clone/shared/utils/abc.dart';
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
  late final StreamSubscription<List<Message>> messageListener;
  late TabController _tabController;
  late List<Widget> _floatingButtons;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        ref.read(firebaseFirestoreRepositoryProvider).setActivityStatus(
            userId: widget.user.id,
            statusValue: UserActivityStatus.online.value);
        break;
      default:
        ref.read(firebaseFirestoreRepositoryProvider).setActivityStatus(
            userId: widget.user.id,
            statusValue: UserActivityStatus.offline.value);
        break;
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  void initState() {
    final firestore = ref.read(firebaseFirestoreRepositoryProvider);
    firestore.setActivityStatus(
      userId: widget.user.id,
      statusValue: UserActivityStatus.online.value,
    );

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
      if (message == null) return;

      await handleNotificationClick(message);
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
    _tabController.removeListener(handleTabIndexChange);
    _tabController.dispose();
    messageListener.cancel();
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).custom.textTheme;
    final colorTheme = Theme.of(context).custom.colorTheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'WhatsApp',
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
            IconButton(
              onPressed: () {},
              icon: const Icon(
                Icons.more_vert,
              ),
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
            RecentChatsBody(user: widget.user),
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
      name: 'WhatsUp Assistant',
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
              'Subukan ang conversation interface kasama ang WhatsUp Assistant o mag-start ng bagong chat!',
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
                    builder: (context) => ChatPage(
                      self: currentUser,
                      other: botUser,
                      otherUserContactName: 'WhatsUp Assistant 🤖',
                    ),
                    settings: const RouteSettings(name: 'chat'),
                  ),
                );
              },
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text(
                'Subukan ang Chat Interface',
                style: TextStyle(fontWeight: FontWeight.bold),
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
