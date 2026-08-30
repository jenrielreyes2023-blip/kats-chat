import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:tencent_calls_uikit/debug/generate_test_user_sig.dart';
import 'package:tencent_calls_uikit/tencent_calls_uikit.dart';
import 'package:whatsapp_clone/shared/models/user.dart';
import 'package:whatsapp_clone/shared/repositories/push_notifications.dart';
import 'package:whatsapp_clone/shared/utils/abc.dart';

class CallService {
  static const int sdkAppId = 20047194;
  static const String secretKey =
      '142f82f08ed2c9c2993ef632f96d46f462cd1c3bec75feb80fc8abcb0870257a';

  static bool _isLoggedIn = false;
  static String _loggedInUserId = '';

  /// Generates the official Tencent cryptographic UserSig using Tencent's official algorithm
  static String generateUserSig(String userId) {
    return GenerateTestUserSig.genTestSig(userId, sdkAppId, secretKey);
  }

  /// Logs into TUICallKit with the current user credentials
  static Future<bool> login(User user) async {
    if (_isLoggedIn && _loggedInUserId == user.id) {
      return true;
    }

    try {
      // 1. Ensure user is imported to Tencent Cloud first
      await ensureUserImported(
        userId: user.id,
        name: user.name,
        avatarUrl: user.avatarUrl,
      );

      // 2. Perform TUICallKit Login
      final userSig = generateUserSig(user.id);
      final res = await TUICallKit.instance.login(
        sdkAppId,
        user.id,
        userSig,
      );

      if (res.code.isEmpty || res.code == '0') {
        _isLoggedIn = true;
        _loggedInUserId = user.id;
        try {
          await TUICallKit.instance.setSelfInfo(user.name, user.avatarUrl);
        } catch (_) {}
        try {
          await TUICallKit.instance.enableFloatWindow(true);
        } catch (_) {}
        try {
          TUICallKit.instance.enableIncomingBanner(true);
        } catch (_) {}
        debugPrint('Tencent CallKit logged in successfully for ${user.name} (${user.id})');
        return true;
      } else {
        debugPrint(
            'Tencent CallKit login failed - code: ${res.code}, msg: ${res.message}');
        return false;
      }
    } catch (e) {
      debugPrint('Error logging in to Tencent CallKit: $e');
      return false;
    }
  }

  /// Automatically registers/imports user to Tencent Cloud IM via REST API
  /// so that their tinyid exists on Tencent servers immediately without waiting for them to log in.
  static Future<void> ensureUserImported({
    required String userId,
    String name = 'User',
    String avatarUrl = '',
  }) async {
    try {
      final adminUserSig = GenerateTestUserSig.genTestSig(
        'administrator',
        sdkAppId,
        secretKey,
      );
      final random = DateTime.now().millisecondsSinceEpoch % 4294967295;
      final url = Uri.parse(
        'https://adminapisgp.im.qcloud.com/v4/im_open_login_svc/account_import'
        '?sdkappid=$sdkAppId&identifier=administrator&usersig=$adminUserSig&random=$random&contenttype=json',
      );

      final payload = {
        'UserID': userId,
        'Nick': name.isNotEmpty ? name : 'User',
        'FaceUrl': avatarUrl.isNotEmpty
            ? avatarUrl
            : 'https://cdn-icons-png.flaticon.com/512/149/149071.png',
      };

      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (_) {}
  }

  /// Start a 1-on-1 Voice Call
  static Future<void> startVoiceCall(
    BuildContext context,
    String calleeId, {
    String? calleeName,
    String? calleeAvatar,
  }) async {
    if (calleeId == 'whatsup_bot') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hindi available ang voice call para sa KatsChat Assistant 🤖. Subukan tumawag sa isang totoong contact.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final currUser = getCurrentUser();
    if (currUser != null) {
      await login(currUser);
    }

    // Auto-ensure callee is imported to Tencent Cloud to guarantee tinyid exists
    await ensureUserImported(
      userId: calleeId,
      name: calleeName ?? 'User',
      avatarUrl: calleeAvatar ?? '',
    );

    final pushInfo = TUIOfflinePushInfo()
      ..title = currUser?.name ?? 'KatsChat'
      ..desc = 'Incoming Voice Call'
      ..androidSound = 'phone_ringing'
      ..androidFCMChannelID = 'high_importance_channel';

    final params = TUICallParams()..offlinePushInfo = pushInfo;

    // Trigger FCM background notification to wake up recipient device
    PushNotificationsRepo.notifyIncomingCall(
      receiverId: calleeId,
      callerName: currUser?.name ?? 'User',
      callerAvatar: currUser?.avatarUrl ?? '',
      isVideo: false,
    );

    try {
      var res = await TUICallKit.instance.calls([calleeId], TUICallMediaType.audio, params);
      if (res.code.isNotEmpty && res.code != '0') {
        // If tinyid failed, retry login and re-call once
        if ((res.message ?? '').contains('tinyid') && currUser != null) {
          _isLoggedIn = false;
          await login(currUser);
          await ensureUserImported(
            userId: calleeId,
            name: calleeName ?? 'User',
            avatarUrl: calleeAvatar ?? '',
          );
          res = await TUICallKit.instance.calls([calleeId], TUICallMediaType.audio, params);
        }
      }

      if (res.code.isNotEmpty && res.code != '0') {
        debugPrint('Tencent Voice Call error: ${res.code} - ${res.message}');
        if (context.mounted) {
          final errorMsg = res.message != null && res.message!.isNotEmpty
              ? res.message!
              : res.code;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Call failed: $errorMsg'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error initiating voice call: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hindi makatawag: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Start a 1-on-1 Video Call
  static Future<void> startVideoCall(
    BuildContext context,
    String calleeId, {
    String? calleeName,
    String? calleeAvatar,
  }) async {
    if (calleeId == 'whatsup_bot') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hindi available ang video call para sa KatsChat Assistant 🤖. Subukan tumawag sa isang totoong contact.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final currUser = getCurrentUser();
    if (currUser != null) {
      await login(currUser);
    }

    // Auto-ensure callee is imported to Tencent Cloud to guarantee tinyid exists
    await ensureUserImported(
      userId: calleeId,
      name: calleeName ?? 'User',
      avatarUrl: calleeAvatar ?? '',
    );

    final videoPushInfo = TUIOfflinePushInfo()
      ..title = currUser?.name ?? 'KatsChat'
      ..desc = 'Incoming Video Call'
      ..androidSound = 'phone_ringing'
      ..androidFCMChannelID = 'high_importance_channel';

    final videoParams = TUICallParams()..offlinePushInfo = videoPushInfo;

    // Trigger FCM background notification to wake up recipient device
    PushNotificationsRepo.notifyIncomingCall(
      receiverId: calleeId,
      callerName: currUser?.name ?? 'User',
      callerAvatar: currUser?.avatarUrl ?? '',
      isVideo: true,
    );

    try {
      var res = await TUICallKit.instance.calls([calleeId], TUICallMediaType.video, videoParams);
      if (res.code.isNotEmpty && res.code != '0') {
        // If tinyid failed, retry login and re-call once
        if ((res.message ?? '').contains('tinyid') && currUser != null) {
          _isLoggedIn = false;
          await login(currUser);
          await ensureUserImported(
            userId: calleeId,
            name: calleeName ?? 'User',
            avatarUrl: calleeAvatar ?? '',
          );
          res = await TUICallKit.instance.calls([calleeId], TUICallMediaType.video, videoParams);
        }
      }

      if (res.code.isNotEmpty && res.code != '0') {
        debugPrint('Tencent Video Call error: ${res.code} - ${res.message}');
        if (context.mounted) {
          final errorMsg = res.message != null && res.message!.isNotEmpty
              ? res.message!
              : res.code;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Video call failed: $errorMsg'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error initiating video call: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hindi makatawag: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Logs out of TUICallKit
  static Future<void> logout() async {
    try {
      if (_isLoggedIn) {
        await TUICallKit.instance.logout();
        _isLoggedIn = false;
      }
    } catch (_) {}
  }
}
