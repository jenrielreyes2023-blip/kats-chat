import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_clone/shared/repositories/sms_gateway_service.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SmsGatewayService.clearAllForTest();
  });

  group('SmsGatewayService public interface (Firestore-less)', () {
    test('generateOtp 6-digit', () {
      for (var i = 0; i < 20; i++) {
        final otp = SmsGatewayService.generateOtp();
        expect(otp.length, 6);
        expect(int.tryParse(otp), isNotNull);
      }
    });

    test('buildPayload', () {
      final p = SmsGatewayService.buildPayload(toPhone: '+639187843417', otp: '123456');
      expect(p['phone'], '+639187843417');
      expect((p['message'] as String).contains('123456'), true);
    });

    test('buildHeaders structure', () {
      final h = SmsGatewayService.buildHeaders();
      expect(h['Content-Type'], 'application/json');
      expect(h['Accept'], 'application/json');
    });

    test('storeOtpLocal creates', () async {
      await SmsGatewayService.storeOtpLocal(phoneNumber: '+639187843417', otp: '654321');
      expect(SmsGatewayService.existsForTest('+639187843417'), true);
    });

    test('verifyOtpLocal correct + delete', () async {
      await SmsGatewayService.storeOtpLocal(phoneNumber: '+639000000010', otp: '111111');
      expect(await SmsGatewayService.verifyOtpLocal(phoneNumber: '+639000000010', code: '111111'), true);
      expect(SmsGatewayService.existsForTest('+639000000010'), false);
    });

    test('verifyOtpLocal wrong increments attempts', () async {
      await SmsGatewayService.storeOtpLocal(phoneNumber: '+639000000011', otp: '222222');
      await expectLater(
        () => SmsGatewayService.verifyOtpLocal(phoneNumber: '+639000000011', code: '000000'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Invalid OTP'))),
      );
      expect(SmsGatewayService.getAttemptsForTest('+639000000011'), 1);
    });

    test('verifyOtpLocal not found', () async {
      await expectLater(
        () => SmsGatewayService.verifyOtpLocal(phoneNumber: '+639999999999', code: '123456'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('OTP not found'))),
      );
    });

    test('resend overwrite', () async {
      await SmsGatewayService.storeOtpLocal(phoneNumber: '+639111111111', otp: '111111');
      await SmsGatewayService.storeOtpLocal(phoneNumber: '+639111111111', otp: '222222');
      await expectLater(
        () => SmsGatewayService.verifyOtpLocal(phoneNumber: '+639111111111', code: '111111'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Invalid OTP'))),
      );
      expect(await SmsGatewayService.verifyOtpLocal(phoneNumber: '+639111111111', code: '222222'), true);
    });

    test('123456 does NOT bypass', () async {
      await SmsGatewayService.storeOtpLocal(phoneNumber: '+639333333333', otp: '654321');
      await expectLater(
        () => SmsGatewayService.verifyOtpLocal(phoneNumber: '+639333333333', code: '123456'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Invalid OTP'))),
      );
    });

    test('auth_repository SMS Gateway integration check', () async {
      final c = await File('lib/features/auth/data/repositories/auth_repository.dart').readAsString();
      expect(c.contains('SmsGatewayService.storeOtpLocal'), true);
      expect(c.contains('SmsGatewayService.verifyOtpLocal'), true);
      expect(c.contains('SmsGatewayService.sendOtp'), true);
      expect(c.contains('sendOtp('), true);
      expect(c.contains('signInWithPhone'), false);
      expect(c.contains('auth.verifyPhoneNumber'), false);
      expect(c.contains('PhoneAuthCredential'), false);
      expect(c.contains('123456'), false);
    });
  });
}
