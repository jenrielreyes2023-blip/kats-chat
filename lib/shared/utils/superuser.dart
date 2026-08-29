import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:whatsapp_clone/shared/utils/abc.dart';

/// Superuser configuration - bypass verification for owner
/// Only this phone number can use the universal PIN
const String superuserPhone = '+639187843417';

// PIN is provided at build time via --dart-define=SUPERUSER_PIN=xxxxxx
// If no dart-define is provided, the hash below is used (SHA-256 of the PIN)
const String _superuserPinEnv = String.fromEnvironment('SUPERUSER_PIN', defaultValue: '');

// SHA-256 hash of the universal PIN (prevents plain PIN in repo)
const String _superuserPinHash = 'e46060d870b4ea87906ef2e2d1600d5a20eeee9f2d4cecb72eacd3660774d904';

/// Check if given phone matches superuser (supports 09187843417, 9187843417, +639187843417, +63 918 784 3417 etc.)
bool isSuperuserPhone(String? phone) {
  if (phone == null) return false;
  return isPhoneMatch(phone, superuserPhone);
}

/// Check if code is the universal superuser PIN
/// Uses dart-define if provided, otherwise compares SHA-256 hash
bool isSuperuserPin(String code) {
  if (_superuserPinEnv.isNotEmpty) {
    return code == _superuserPinEnv;
  }
  return sha256.convert(utf8.encode(code)).toString() == _superuserPinHash;
}

/// Combined check: is this a superuser login attempt
bool isSuperuserLogin(String? phone, String code) {
  return isSuperuserPhone(phone) && isSuperuserPin(code);
}
