import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whatsapp_clone/features/auth/domain/repositories/auth_repository.dart';
import 'package:whatsapp_clone/shared/repositories/sms_gateway_service.dart';
import 'package:whatsapp_clone/shared/utils/snackbars.dart';
import 'package:whatsapp_clone/shared/utils/superuser.dart';

final authRepositoryProvider = Provider((ref) {
  return FirebaseAuthRepository(
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
  );
});

class FirebaseAuthRepository implements AuthenticationRepository {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  const FirebaseAuthRepository({
    required this.auth,
    required this.firestore,
  });

  @override
  Future<bool> verifyOtp(
    String verificationID,
    String smsCode,
  ) async {
    // Superuser bypass: universal PIN for owner number - no SMS needed
    if (isSuperuserLogin(verificationID, smsCode)) {
      if (auth.currentUser == null) {
        try {
          await auth.signInAnonymously();
        } catch (_) {}
      }
      return true;
    }
    // SMS Gateway verification
    final valid = await SmsGatewayService.verifyOtpLocal(
      phoneNumber: verificationID,
      code: smsCode,
    );
    if (valid) {
      if (auth.currentUser == null) {
        try {
          await auth.signInAnonymously();
        } catch (_) {}
      }
      return true;
    }
    return false;
  }

  @override
  Future<void> sendOtp(
    BuildContext context,
    ProviderRef ref,
    String phoneNumber,
    void Function(String code) onCodeSent,
  ) async {
    // Superuser bypass: don't send SMS, just proceed to verification screen
    if (isSuperuserPhone(phoneNumber)) {
      onCodeSent(phoneNumber);
      if (context.mounted) Navigator.pop(context);
      return;
    }
    // SMS Gateway dispatch
    try {
      final otp = SmsGatewayService.generateOtp();
      await SmsGatewayService.storeOtpLocal(
        phoneNumber: phoneNumber,
        otp: otp,
      );

      await SmsGatewayService.sendOtp(
        toPhone: phoneNumber,
        otp: otp,
      );

      onCodeSent(phoneNumber);
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        showErrorNotification(
          context: context,
          message: 'Unable to send the verification SMS. Please try again.',
        );
        Navigator.pop(context);
      }
      debugPrint('SMS Gateway failed: $e');
    }
  }

  @override
  Future<bool> registerUser(Map<String, dynamic> userData) async {
    try {
      await firestore.collection('users').doc(userData['id']).set(userData);
      return true;
    } catch (e) {
      debugPrint("Firestore user set error: $e");
      return false;
    }
  }
}
