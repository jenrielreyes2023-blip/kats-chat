import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whatsapp_clone/features/auth/domain/repositories/auth_repository.dart';
import 'package:whatsapp_clone/shared/repositories/httpsms_service.dart';
import 'package:whatsapp_clone/shared/utils/snackbars.dart';

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
    // verificationID is now the phoneNumber when using HttpSMS
    // Try HttpSMS verification first (Firestore otp_codes)
    try {
      final isHttpsms = verificationID.startsWith('+');
      if (isHttpsms) {
        final valid = await HttpsmsService.verifyOtp(
          firestore: firestore,
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
      }
    } catch (e) {
      // If httpsms verification throws (invalid/expired), rethrow to show error
      // Fall through to Firebase verification if not httpsms
      if (verificationID.startsWith('+')) {
        rethrow;
      }
    }

    // Fallback to Firebase Phone Auth verification
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationID,
        smsCode: smsCode,
      );

      return await auth.signInWithCredential(credential).then((_) {
        return true;
      });
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> signInWithPhone(
    BuildContext context,
    ProviderRef ref,
    String phoneNumber,
    void Function(String code) onCodeSent,
  ) async {
    // Primary: HttpSMS OTP (free via gateway)
    try {
      final otp = HttpsmsService.generateOtp();
      await HttpsmsService.storeOtp(
        firestore: firestore,
        phoneNumber: phoneNumber,
        otp: otp,
      );

      await HttpsmsService.sendOtp(
        toPhone: phoneNumber,
        otp: otp,
      );

      // Use phoneNumber as verificationId for HttpSMS flow
      onCodeSent(phoneNumber);
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        showSnackBar(
          context: context,
          content: "OTP Sent via HttpSMS!",
          type: SnacBarType.info,
        );
      }
      return;
    } catch (e) {
      debugPrint('HttpSMS send failed: $e');
      // Fall through to Firebase as fallback
    }

    // Fallback: Firebase Phone Auth
    try {
      await auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await auth.signInWithCredential(credential);
          } catch (_) {}
        },
        verificationFailed: (FirebaseAuthException e) {
          if (context.mounted) Navigator.pop(context);
          if (context.mounted) {
            showSnackBar(
              context: context,
              content: "Verification failed: ${e.message}",
              type: SnacBarType.error,
            );
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId);
          if (context.mounted) Navigator.pop(context);
          if (context.mounted) {
            showSnackBar(
              context: context,
              content: "OTP Sent!",
              type: SnacBarType.info,
            );
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        showSnackBar(
          context: context,
          content: "Failed to send OTP. Please try again.",
          type: SnacBarType.error,
        );
      }
    }
  }

  @override
  Future<bool> registerUser(Map<String, dynamic> userData) async {
    try {
      await firestore.collection('users').doc(userData['id']).set(userData);
    } catch (e) {
      debugPrint("Firestore user set error: $e");
    }
    return true;
  }
}
