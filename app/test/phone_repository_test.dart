import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/profile/data/phone_repository.dart';

void main() {
  test('normalizePhone: bỏ khoảng trắng/dấu, giữ + đầu, chỉ nhận 8–15 chữ số', () {
    expect(normalizePhone('0901 234 567'), '0901234567');
    expect(normalizePhone('(090) 123-4567'), '0901234567');
    expect(normalizePhone('+84 901.234.567'), '+84901234567');
    expect(normalizePhone('1234567'), isNull);
    expect(normalizePhone('09012345678901234'), isNull);
    expect(normalizePhone('abc12345678'), isNull);
    expect(normalizePhone(''), isNull);
  });
}
