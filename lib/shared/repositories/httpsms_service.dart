import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

/// HttpSMS OTP Service
/// Uses httpsms.com gateway to send OTP via your Android phone.
/// ApiKey and gateway phone are configured here.
class HttpsmsService {
  // Provided by user - gateway credentials
  static const String _apiKey = 'pk_v3gfqfP0FCENI8V6zKt2nu7vOWn8hnhurofHcUTX-dC0R-G-WrckjoismC0Zs0yj';
  // The phone ID / gateway number. For httpsms, 'from' should be the device phone.
  // Using the provided number as gateway identifier.
  static const String _gatewayPhone = '+639187843417';

  static const String _baseUrl = 'https://api.httpsms.com/v1/messages/send';

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
    final message = 'Your WhatsUp code is $otp. Valid for 5 minutes. Do not share this code.';
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
  static Future<bool> sendOtp({
    required String toPhone,
    required String otp,
  }) async {
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
        // Log response for debugging but throw to trigger fallback handling
        throw Exception('HttpSMS failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Store OTP in Firestore with 5-min expiry
  static Future<void> storeOtp({
    required FirebaseFirestore firestore,
    required String phoneNumber,
    required String otp,
  }) async {
    final expiresAt = DateTime.now().add(const Duration(minutes: 5));
    await firestore.collection('otp_codes').doc(phoneNumber).set({
      'code': otp,
      'phone': phoneNumber,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'attempts': 0,
    });
  }

  /// Verify OTP from Firestore
  static Future<bool> verifyOtp({
    required FirebaseFirestore firestore,
    required String phoneNumber,
    required String code,
  }) async {
    final doc = await firestore.collection('otp_codes').doc(phoneNumber).get();
    if (!doc.exists) {
      throw Exception('OTP not found. Please request a new code.');
    }
    final data = doc.data()!;
    final storedCode = data['code'] as String;
    final expiresAt = (data['expiresAt'] as Timestamp).toDate();

    if (DateTime.now().isAfter(expiresAt)) {
      await firestore.collection('otp_codes').doc(phoneNumber).delete();
      throw Exception('OTP expired. Please request a new code.');
    }

    if (storedCode != code) {
      // Increment attempts
      await firestore.collection('otp_codes').doc(phoneNumber).update({
        'attempts': FieldValue.increment(1),
      });
      throw Exception('Invalid OTP!');
    }

    // OTP valid - delete it
    await firestore.collection('otp_codes').doc(phoneNumber).delete();
    return true;
  }
}
