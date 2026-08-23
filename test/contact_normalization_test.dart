import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_clone/shared/utils/abc.dart';

void main() {
  group('Phone normalization and matching regression tests', () {
    test('normalizes 09187843417, 9187843417, and +639187843417 to identical value', () {
      final normLocal = normalizePhoneNumber('09187843417');
      final normNoZero = normalizePhoneNumber('9187843417');
      final normIntl = normalizePhoneNumber('+639187843417');
      final normFormatted = normalizePhoneNumber('+63 918 784 3417');

      expect(normLocal, '9187843417');
      expect(normNoZero, '9187843417');
      expect(normIntl, '9187843417');
      expect(normFormatted, '9187843417');

      expect(normLocal, equals(normNoZero));
      expect(normNoZero, equals(normIntl));
      expect(normIntl, equals(normFormatted));
    });

    test('isPhoneMatch returns true for same phone across different formats', () {
      expect(isPhoneMatch('09187843417', '9187843417'), isTrue);
      expect(isPhoneMatch('09187843417', '+639187843417'), isTrue);
      expect(isPhoneMatch('+639187843417', '9187843417'), isTrue);
      expect(isPhoneMatch('+63 918 784 3417', '09187843417'), isTrue);
      expect(isPhoneMatch('0918-784-3417', '+63 918 784 3417'), isTrue);
    });

    test('isPhoneMatch returns false for different phone numbers', () {
      expect(isPhoneMatch('09187843417', '09187843418'), isFalse);
      expect(isPhoneMatch('+639187843417', '+639171234567'), isFalse);
      expect(isPhoneMatch('09187843417', '09170000000'), isFalse);
      expect(isPhoneMatch('', '09187843417'), isFalse);
      expect(isPhoneMatch(null, '09187843417'), isFalse);
      expect(isPhoneMatch('09187843417', null), isFalse);
    });
  });
}
