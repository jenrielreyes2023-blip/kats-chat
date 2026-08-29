import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_calls_uikit/tencent_calls_uikit.dart';
import 'package:whatsapp_clone/shared/models/user.dart';

class CallService {
  static const int sdkAppId = 20047194;
  static const String secretKey =
      '142f82f08ed2c9c2993ef632f96d46f462cd1c3bec75feb80fc8abcb0870257a';
  static const int expireTime = 604800; // 7 days in seconds

  static bool _isLoggedIn = false;

  /// Generates the official Tencent cryptographic UserSig for authentication
  static String generateUserSig(String userId) {
    final currTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sigDoc = <String, dynamic>{
      'TLS.ver': '2.0',
      'TLS.identifier': userId,
      'TLS.sdkappid': sdkAppId,
      'TLS.expire': expireTime,
      'TLS.time': currTime,
    };

    final contentToBeSigned = "TLS.identifier:$userId\n"
        "TLS.sdkappid:$sdkAppId\n"
        "TLS.time:$currTime\n"
        "TLS.expire:$expireTime\n";

    final hmacSha256 = Hmac(sha256, utf8.encode(secretKey));
    final digest = hmacSha256.convert(utf8.encode(contentToBeSigned));
    final sig = base64.encode(digest.bytes);
    sigDoc['TLS.sig'] = sig;

    final jsonStr = json.encode(sigDoc);
    final compressed = zlib.encode(utf8.encode(jsonStr));

    // Tencent specific Base64 URL encoding replacements
    return base64.encode(compressed)
        .replaceAll('+', '*')
        .replaceAll('/', '-')
        .replaceAll('=', '_');
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

      if (res.errorCode == 0) {
        _isLoggedIn = true;
        await TUICallKit.instance.setSelfInfo(user.name, user.avatarUrl);
        await TUICallKit.instance.enableFloatWindow(true);
        debugPrint('Tencent CallKit logged in successfully for ${user.name}');
      } else {
        debugPrint(
            'Tencent CallKit login code: ${res.errorCode}, msg: ${res.errorMessage}');
      }
    } catch (e) {
      debugPrint('Error logging in to Tencent CallKit: $e');
    }
  }

  /// Start a 1-on-1 Voice Call
  static Future<void> startVoiceCall(String calleeId) async {
    try {
      await TUICallKit.instance.calls([calleeId], CallMediaType.audio);
    } catch (e) {
      debugPrint('Error initiating voice call: $e');
    }
  }

  /// Start a 1-on-1 Video Call
  static Future<void> startVideoCall(String calleeId) async {
    try {
      await TUICallKit.instance.calls([calleeId], CallMediaType.video);
    } catch (e) {
      debugPrint('Error initiating video call: $e');
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
