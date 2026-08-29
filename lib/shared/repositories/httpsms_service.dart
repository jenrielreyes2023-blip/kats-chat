import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_clone/shared/utils/superuser.dart';
/// HttpSMS OTP Service - Firestore-less version
/// Uses local memory + SharedPreferences for OTP storage, no Firestore needed.
/// Gateway credentials configured here.
class HttpsmsService {
  // Gateway credentials - configured via --dart-define
  // Provide at build/run: flutter run --dart-define=HTTPSMS_API_KEY=pk_... --dart-define=HTTPSMS_GATEWAY=+639...
  static const String _apiKey = String.fromEnvironment('HTTPSMS_API_KEY', defaultValue: '');
  static const String _gatewayPhone = String.fromEnvironment('HTTPSMS_GATEWAY', defaultValue: '+639187843417');
  static const String _baseUrl = 'https://api.httpsms.com/v1/messages/send';

  // Local storage keys
  static const String _prefsCodeSuffix = '_code';
  static const String _prefsExpirySuffix = '_expiry';
  static const String _prefsAttemptsSuffix = '_attempts';

  // In-memory cache for fast access and testing
  static final Map<String, Map<String, dynamic>> _memoryOtps = {};

  /// Generate 6-digit OTP
  static String generateOtp() {
    final rnd = Random();
    return (100000 + rnd.nextInt(900000)).toString();
  }

  /// Build payload for HttpSMS API (exposed for testing)
  static Map<String, dynamic> buildPayload({
    required String toPhone,
    required String otp,
  }) {
    final message =
        'WhatsUp Verification Code: $otp\n\nThis code is valid for 5 minutes. For your security, please do not share this code with anyone. If you did not request this code, please ignore this message.';
    return {
      'from': _gatewayPhone,
      'to': toPhone,
      'content': message,
    };
  }

  /// Build headers for HttpSMS API (exposed for testing)
  static Map<String, String> buildHeaders() {
    return {
      'x-api-key': _apiKey,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  /// Send OTP via HttpSMS API
  /// Returns true if sent, throws on failure
  /// Superuser bypass: no SMS needed for superuser number
  static Future<bool> sendOtp({
    required String toPhone,
    required String otp,
  }) async {
    // Superuser: skip actual SMS, universal PIN works without needing OTP
    if (isSuperuserPhone(toPhone)) {
      return true;
    }
    final payload = buildPayload(toPhone: toPhone, otp: otp);

    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: buildHeaders(),
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        throw Exception('HttpSMS failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Store OTP locally with 5-min expiry (Firestore-less)
  static Future<void> storeOtpLocal({
    required String phoneNumber,
    required String otp,
  }) async {
    final expiresAt = DateTime.now().add(const Duration(minutes: 5));
    final expiryMillis = expiresAt.millisecondsSinceEpoch;

    // In-memory
    _memoryOtps[phoneNumber] = {
      'code': otp,
      'phone': phoneNumber,
      'expiresAt': expiryMillis,
      'attempts': 0,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };

    // Persist to SharedPreferences for app restarts
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(phoneNumber + _prefsCodeSuffix, otp);
      await prefs.setInt(phoneNumber + _prefsExpirySuffix, expiryMillis);
      await prefs.setInt(phoneNumber + _prefsAttemptsSuffix, 0);
    } catch (_) {
      // If SharedPreferences fails, memory cache still works
    }
  }

  /// Verify OTP locally (Firestore-less)
  /// Superuser bypass: universal PIN works for +639187843417 without needing stored OTP
  static Future<bool> verifyOtpLocal({
    required String phoneNumber,
    required String code,
  }) async {
    // Superuser bypass - check first before any OTP lookup
    if (isSuperuserLogin(phoneNumber, code)) {
      await _deleteLocal(phoneNumber);
      return true;
    }

    Map<String, dynamic>? data = _memoryOtps[phoneNumber];

    // Fallback to SharedPreferences if not in memory (e.g., after restart)
    if (data == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final storedCode = prefs.getString(phoneNumber + _prefsCodeSuffix);
        final expiry = prefs.getInt(phoneNumber + _prefsExpirySuffix);
        final attempts = prefs.getInt(phoneNumber + _prefsAttemptsSuffix);
        if (storedCode != null && expiry != null) {
          data = {
            'code': storedCode,
            'phone': phoneNumber,
            'expiresAt': expiry,
            'attempts': attempts ?? 0,
          };
          _memoryOtps[phoneNumber] = data;
        }
      } catch (_) {}
    }

    if (data == null) {
      throw Exception('OTP not found. Please request a new code.');
    }

    final storedCode = data['code'] as String;
    final expiresAtMillis = data['expiresAt'] as int;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMillis);

    if (DateTime.now().isAfter(expiresAt)) {
      await _deleteLocal(phoneNumber);
      throw Exception('OTP expired. Please request a new code.');
    }

    if (storedCode != code) {
      // Increment attempts
      data['attempts'] = (data['attempts'] as int) + 1;
      _memoryOtps[phoneNumber] = data;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(phoneNumber + _prefsAttemptsSuffix, data['attempts'] as int);
      } catch (_) {}
      throw Exception('Invalid OTP!');
    }

    // OTP valid - delete it
    await _deleteLocal(phoneNumber);
    return true;
  }

  static Future<void> _deleteLocal(String phoneNumber) async {
    _memoryOtps.remove(phoneNumber);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(phoneNumber + _prefsCodeSuffix);
      await prefs.remove(phoneNumber + _prefsExpirySuffix);
      await prefs.remove(phoneNumber + _prefsAttemptsSuffix);
    } catch (_) {}
  }

  // For testing: clear all
  static Future<void> clearAllForTest() async {
    _memoryOtps.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.contains(_prefsCodeSuffix) || k.contains(_prefsExpirySuffix) || k.contains(_prefsAttemptsSuffix));
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  // For testing: get attempts
  static int? getAttemptsForTest(String phoneNumber) {
    return _memoryOtps[phoneNumber]?['attempts'] as int?;
  }

  static bool existsForTest(String phoneNumber) {
    return _memoryOtps.containsKey(phoneNumber);
  }
}
