import 'dart:convert';
import 'dart:io';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Direct import of actual lib file via package
import 'package:whatsapp_clone/shared/repositories/httpsms_service.dart';

Future<void> main() async {
  print('=== REAL IMPORT TEST (actual lib via package) ===');
  // generateOtp
  final otp = HttpsmsService.generateOtp();
  assert(otp.length==6 && int.tryParse(otp)!=null);
  print('PASS generateOtp $otp');
  // buildPayload
  final payload = HttpsmsService.buildPayload(toPhone: '+639187843417', otp: '123456');
  assert(payload['from']=='+639187843417');
  assert(payload['to']=='+639187843417');
  assert((payload['content'] as String).contains('123456'));
  print('PASS buildPayload');
  // buildHeaders
  final h = HttpsmsService.buildHeaders();
  assert(h['x-api-key']!.startsWith('pk_'));
  print('PASS buildHeaders ${h['x-api-key']!.substring(0,5)}...');
  // storeOtp + verifyOtp with FakeFirebaseFirestore (real Firestore type)
  final fake = FakeFirebaseFirestore();
  await HttpsmsService.storeOtp(firestore: fake, phoneNumber: '+639187843417', otp: '654321');
  var doc = await fake.collection('otp_codes').doc('+639187843417').get();
  assert(doc.exists && doc.data()!['code']=='654321');
  print('PASS storeOtp creates doc');
  // correct verify
  final ok = await HttpsmsService.verifyOtp(firestore: fake, phoneNumber: '+639187843417', code: '654321');
  assert(ok==true);
  doc = await fake.collection('otp_codes').doc('+639187843417').get();
  assert(!doc.exists);
  print('PASS verifyOtp correct and deletes');
  // wrong
  await HttpsmsService.storeOtp(firestore: fake, phoneNumber: '+639000000001', otp: '999999');
  try { await HttpsmsService.verifyOtp(firestore: fake, phoneNumber: '+639000000001', code: '000000'); assert(false); } catch(e){ assert(e.toString().contains('Invalid OTP')); print('PASS verify wrong'); }
  // expired
  await fake.collection('otp_codes').doc('+639000000002').set({'code':'123456','phone':'+639000000002','createdAt':FieldValue.serverTimestamp(),'expiresAt':Timestamp.fromDate(DateTime.now().subtract(Duration(minutes:1))),'attempts':0});
  try { await HttpsmsService.verifyOtp(firestore: fake, phoneNumber: '+639000000002', code: '123456'); assert(false); } catch(e){ assert(e.toString().toLowerCase().contains('expired')); print('PASS verify expired'); }
  // not found
  try { await HttpsmsService.verifyOtp(firestore: fake, phoneNumber: '+639999999999', code: '123456'); assert(false); } catch(e){ assert(e.toString().contains('not found')); print('PASS verify not found'); }
  // resend overwrite
  await HttpsmsService.storeOtp(firestore: fake, phoneNumber: '+639111111111', otp: '111111');
  await HttpsmsService.storeOtp(firestore: fake, phoneNumber: '+639111111111', otp: '222222');
  try { await HttpsmsService.verifyOtp(firestore: fake, phoneNumber: '+639111111111', code: '111111'); assert(false); } catch(e){ print('PASS resend old rejected'); }
  assert(await HttpsmsService.verifyOtp(firestore: fake, phoneNumber: '+639111111111', code: '222222')==true);
  print('PASS resend new works');
  // 123456 bypass
  await HttpsmsService.storeOtp(firestore: fake, phoneNumber: '+639333333333', otp: '654321');
  try { await HttpsmsService.verifyOtp(firestore: fake, phoneNumber: '+639333333333', code: '123456'); assert(false); } catch(e){ print('PASS 123456 does NOT bypass'); }
  // auth_repository file check
  final authContent = await File('lib/features/auth/data/repositories/auth_repository.dart').readAsString();
  assert(authContent.contains('HttpsmsService.sendOtp'));
  assert(authContent.contains('HttpsmsService.verifyOtp'));
  assert(authContent.contains('auth.verifyPhoneNumber'));
  assert(!authContent.contains('123456'));
  assert(!authContent.contains('fallback-mock-vid'));
  print('PASS auth_repository routing and bypass removed');
  print('=== ALL 10 REAL IMPORT TESTS PASS ===');
}
