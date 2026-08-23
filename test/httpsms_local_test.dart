import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_clone/shared/repositories/httpsms_service.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await HttpsmsService.clearAllForTest();
  });

  group('HttpsmsService public interface (Firestore-less)', () {
    test('generateOtp 6-digit', () {
      for (var i = 0; i < 20; i++) {
        final otp = HttpsmsService.generateOtp();
        expect(otp.length, 6);
        expect(int.tryParse(otp), isNotNull);
      }
    });

    test('buildPayload', () {
      final p = HttpsmsService.buildPayload(toPhone: '+639187843417', otp: '123456');
      expect(p['from'], isNotEmpty);
      expect(p['to'], '+639187843417');
      expect((p['content'] as String).contains('123456'), true);
    });

    test('buildHeaders structure', () {
      final h = HttpsmsService.buildHeaders();
      expect(h.containsKey('x-api-key'), true);
      expect(h['Content-Type'], 'application/json');
      expect(h['Accept'], 'application/json');
    });

    test('storeOtpLocal creates', () async {
      await HttpsmsService.storeOtpLocal(phoneNumber: '+639187843417', otp: '654321');
      expect(HttpsmsService.existsForTest('+639187843417'), true);
    });

    test('verifyOtpLocal correct + delete', () async {
      await HttpsmsService.storeOtpLocal(phoneNumber: '+639000000010', otp: '111111');
      expect(await HttpsmsService.verifyOtpLocal(phoneNumber: '+639000000010', code: '111111'), true);
      expect(HttpsmsService.existsForTest('+639000000010'), false);
    });

    test('verifyOtpLocal wrong increments attempts', () async {
      await HttpsmsService.storeOtpLocal(phoneNumber: '+639000000011', otp: '222222');
      await expectLater(
        () => HttpsmsService.verifyOtpLocal(phoneNumber: '+639000000011', code: '000000'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Invalid OTP'))),
      );
      expect(HttpsmsService.getAttemptsForTest('+639000000011'), 1);
    });

    test('verifyOtpLocal not found', () async {
      await expectLater(
        () => HttpsmsService.verifyOtpLocal(phoneNumber: '+639999999999', code: '123456'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('OTP not found'))),
      );
    });

    test('resend overwrite', () async {
      await HttpsmsService.storeOtpLocal(phoneNumber: '+639111111111', otp: '111111');
      await HttpsmsService.storeOtpLocal(phoneNumber: '+639111111111', otp: '222222');
      await expectLater(
        () => HttpsmsService.verifyOtpLocal(phoneNumber: '+639111111111', code: '111111'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Invalid OTP'))),
      );
      expect(await HttpsmsService.verifyOtpLocal(phoneNumber: '+639111111111', code: '222222'), true);
    });

    test('123456 does NOT bypass', () async {
      await HttpsmsService.storeOtpLocal(phoneNumber: '+639333333333', otp: '654321');
      await expectLater(
        () => HttpsmsService.verifyOtpLocal(phoneNumber: '+639333333333', code: '123456'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Invalid OTP'))),
      );
    });

    test('auth_repository HttpSMS-only no Firebase fallback and uses sendOtp', () async {
      final c = await File('lib/features/auth/data/repositories/auth_repository.dart').readAsString();
      expect(c.contains('HttpsmsService.storeOtpLocal'), true);
      expect(c.contains('HttpsmsService.verifyOtpLocal'), true);
      expect(c.contains('HttpsmsService.sendOtp'), true);
      expect(c.contains('sendOtp('), true);
      expect(c.contains('signInWithPhone'), false);
      expect(c.contains('auth.verifyPhoneNumber'), false);
      expect(c.contains('PhoneAuthCredential'), false);
      expect(c.contains('123456'), false);
    });
  });
}
