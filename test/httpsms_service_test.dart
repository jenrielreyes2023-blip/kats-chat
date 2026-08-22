import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:whatsapp_clone/shared/repositories/httpsms_service.dart';

// Import auth_repository to test fallback routing exists (file contains check)
import 'dart:io';

void main() {
  group('HttpsmsService public interface', () {
    test('generateOtp returns 6-digit numeric', () {
      for (var i=0;i<20;i++) {
        final otp = HttpsmsService.generateOtp();
        expect(otp.length, 6, reason: 'OTP must be 6 chars');
        expect(int.tryParse(otp), isNotNull, reason: 'OTP must be numeric');
        expect(int.parse(otp) >= 100000 && int.parse(otp) <= 999999, true);
      }
      print('PASS generateOtp 6-digit numeric (20 samples)');
    });

    test('buildPayload creates correct HttpSMS API payload', () {
      final payload = HttpsmsService.buildPayload(toPhone: '+639187843417', otp: '123456');
      expect(payload['from'], '+639187843417');
      expect(payload['to'], '+639187843417');
      expect(payload['content'], contains('123456'));
      expect(payload['content'], contains('Valid for 5 minutes'));
      // json encode check
      final jsonStr = jsonEncode(payload);
      final decoded = jsonDecode(jsonStr) as Map<String,dynamic>;
      expect(decoded['from'], '+639187843417');
      expect(decoded['to'], '+639187843417');
      print('PASS buildPayload from=+639187843417 to=+639187843417 content contains OTP');
    });

    test('buildHeaders contains x-api-key', () {
      final headers = HttpsmsService.buildHeaders();
      expect(headers['x-api-key'], startsWith('pk_'));
      expect(headers['Content-Type'], 'application/json');
      expect(headers['Accept'], 'application/json');
      print('PASS buildHeaders x-api-key present');
    });

    test('storeOtp creates Firestore doc with correct fields', () async {
      final fake = FakeFirebaseFirestore();
      final phone = '+639187843417';
      final otp = '654321';
      await HttpsmsService.storeOtp(firestore: fake, phoneNumber: phone, otp: otp);
      final doc = await fake.collection('otp_codes').doc(phone).get();
      expect(doc.exists, true);
      expect(doc.data()!['code'], otp);
      expect(doc.data()!['phone'], phone);
      expect(doc.data()!['attempts'], 0);
      expect(doc.data()!['createdAt'], isNotNull);
      final expiresAt = (doc.data()!['expiresAt'] as Timestamp).toDate();
      expect(expiresAt.isAfter(DateTime.now()), true);
      expect(expiresAt.difference(DateTime.now()).inMinutes, closeTo(5, 1));
      print('PASS storeOtp creates otp_codes/$phone with code $otp, attempts 0, expiresAt +5min');
    });

    test('verifyOtp correct code returns true and deletes doc', () async {
      final fake = FakeFirebaseFirestore();
      await HttpsmsService.storeOtp(firestore: fake, phoneNumber: '+639123456789', otp: '222222');
      final ok = await HttpsmsService.verifyOtp(firestore: fake, phoneNumber: '+639123456789', code: '222222');
      expect(ok, true);
      final doc = await fake.collection('otp_codes').doc('+639123456789').get();
      expect(doc.exists, false, reason: 'doc should be deleted after success');
      print('PASS verifyOtp correct → true and deleted');
    });

    test('verifyOtp wrong code throws Invalid OTP and increments attempts', () async {
      final fake = FakeFirebaseFirestore();
      await HttpsmsService.storeOtp(firestore: fake, phoneNumber: '+639000000001', otp: '999999');
      expect(
        () => HttpsmsService.verifyOtp(firestore: fake, phoneNumber: '+639000000001', code: '000000'),
        throwsA(isA<Exception>().having((e)=>e.toString(), 'message', contains('Invalid OTP'))),
      );
      final doc = await fake.collection('otp_codes').doc('+639000000001').get();
      expect(doc.data()!['attempts'], 1);
      print('PASS verifyOtp wrong → Invalid OTP! and attempts=1');
    });

    test('verifyOtp expired throws and deletes doc', () async {
      final fake = FakeFirebaseFirestore();
      // Manually create expired doc
      await fake.collection('otp_codes').doc('+639000000002').set({
        'code': '123456',
        'phone': '+639000000002',
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().subtract(Duration(minutes:1))),
        'attempts': 0,
      });
      expect(
        () => HttpsmsService.verifyOtp(firestore: fake, phoneNumber: '+639000000002', code: '123456'),
        throwsA(isA<Exception>().having((e)=>e.toString(), 'message', contains('expired'))),
      );
      final doc = await fake.collection('otp_codes').doc('+639000000002').get();
      expect(doc.exists, false, reason: 'expired doc should be deleted');
      print('PASS verifyOtp expired → expired and deleted');
    });

    test('verifyOtp not found throws', () async {
      final fake = FakeFirebaseFirestore();
      expect(
        () => HttpsmsService.verifyOtp(firestore: fake, phoneNumber: '+639999999999', code: '123456'),
        throwsA(isA<Exception>().having((e)=>e.toString(), 'message', contains('not found'))),
      );
      print('PASS verifyOtp not found → not found');
    });

    test('resend overwrites OTP', () async {
      final fake = FakeFirebaseFirestore();
      final phone = '+639111111111';
      await HttpsmsService.storeOtp(firestore: fake, phoneNumber: phone, otp: '111111');
      final first = (await fake.collection('otp_codes').doc(phone).get()).data()!['code'];
      await HttpsmsService.storeOtp(firestore: fake, phoneNumber: phone, otp: '222222');
      final second = (await fake.collection('otp_codes').doc(phone).get()).data()!['code'];
      expect(first, '111111');
      expect(second, '222222');
      expect(
        () => HttpsmsService.verifyOtp(firestore: fake, phoneNumber: phone, code: '111111'),
        throwsA(isA<Exception>().having((e)=>e.toString(), 'message', contains('Invalid OTP'))),
      );
      expect(await HttpsmsService.verifyOtp(firestore: fake, phoneNumber: phone, code: '222222'), true);
      print('PASS resend overwrites: first $first rejected, second $second accepted');
    });

    test('123456 does NOT bypass', () async {
      final fake = FakeFirebaseFirestore();
      await HttpsmsService.storeOtp(firestore: fake, phoneNumber: '+639333333333', otp: '654321');
      expect(
        () => HttpsmsService.verifyOtp(firestore: fake, phoneNumber: '+639333333333', code: '123456'),
        throwsA(isA<Exception>().having((e)=>e.toString(), 'message', contains('Invalid OTP'))),
      );
      print('PASS 123456 does NOT bypass (was removed)');
    });

    test('auth_repository fallback routing exists', () async {
      final file = File('lib/features/auth/data/repositories/auth_repository.dart');
      final content = await file.readAsString();
      expect(content.contains('HttpsmsService.sendOtp'), true, reason: 'primary HttpSMS');
      expect(content.contains('HttpsmsService.verifyOtp'), true, reason: 'verify via Httpsms');
      expect(content.contains('auth.verifyPhoneNumber'), true, reason: 'Firebase fallback');
      expect(content.contains('123456'), false, reason: 'bypass removed');
      expect(content.contains('fallback-mock-vid'), false, reason: 'mock removed');
      expect(content.contains("verificationID.startsWith('+')"), true, reason: 'routing by phone prefix');
      print('PASS auth_repository: HttpSMS primary + Firebase fallback, bypass removed');
    });
  });
}
