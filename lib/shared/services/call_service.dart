import 'package:flutter/material.dart';
import 'package:tencent_calls_uikit/debug/generate_test_user_sig.dart';
import 'package:tencent_calls_uikit/tencent_calls_uikit.dart';
import 'package:whatsapp_clone/shared/models/user.dart';
import 'package:whatsapp_clone/shared/utils/abc.dart';

class CallService {
  static const int sdkAppId = 20047194;
  static const String secretKey =
      '142f82f08ed2c9c2993ef632f96d46f462cd1c3bec75feb80fc8abcb0870257a';

  static bool _isLoggedIn = false;

  /// Generates the official Tencent cryptographic UserSig using Tencent's official algorithm
  static String generateUserSig(String userId) {
    return GenerateTestUserSig.genTestSig(userId, sdkAppId, secretKey);
  }

  /// Logs into TUICallKit with the current user credentials
  static Future<void> login(User user) async {
    try {
      final userSig = generateUserSig(user.id);
      final res = await TUICallKit.instance.login(
        sdkAppId,
        user.id,
        userSig,
      );

      if (res.code.isEmpty || res.code == '0') {
        _isLoggedIn = true;
        try {
          await TUICallKit.instance.setSelfInfo(user.name, user.avatarUrl);
        } catch (_) {}
        try {
          await TUICallKit.instance.enableFloatWindow(true);
        } catch (_) {}
        debugPrint('Tencent CallKit logged in successfully for ${user.name} (${user.id})');
      } else {
        debugPrint(
            'Tencent CallKit login failed - code: ${res.code}, msg: ${res.message}');
      }
    } catch (e) {
      debugPrint('Error logging in to Tencent CallKit: $e');
    }
  }

  /// Start a 1-on-1 Voice Call
  static Future<void> startVoiceCall(
    BuildContext context,
    String calleeId, {
    String? calleeName,
  }) async {
    if (calleeId == 'whatsup_bot') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hindi available ang voice call para sa WhatsUp Assistant 🤖. Subukan tumawag sa isang totoong contact.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (!_isLoggedIn) {
      final currUser = getCurrentUser();
      if (currUser != null) {
        await login(currUser);
      }
    }

    try {
      final res = await TUICallKit.instance.calls([calleeId], TUICallMediaType.audio);
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
  }) async {
    if (calleeId == 'whatsup_bot') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hindi available ang video call para sa WhatsUp Assistant 🤖. Subukan tumawag sa isang totoong contact.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (!_isLoggedIn) {
      final currUser = getCurrentUser();
      if (currUser != null) {
        await login(currUser);
      }
    }

    try {
      final res = await TUICallKit.instance.calls([calleeId], TUICallMediaType.video);
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
