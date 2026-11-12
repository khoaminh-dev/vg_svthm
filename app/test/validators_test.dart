import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/utils/validators.dart';

void main() {
  test('email', () {
    expect(Validators.email(''), isNotNull);
    expect(Validators.email('abc'), isNotNull);
    expect(Validators.email('a@b.co'), isNull);
  });

  test('password', () {
    expect(Validators.password('1234567'), isNotNull);
    expect(Validators.password('12345678'), isNull);
  });

  test('confirmPassword', () {
    final v = Validators.confirmPassword(() => 'abcdefgh');
    expect(v('abcdefgx'), isNotNull);
    expect(v('abcdefgh'), isNull);
  });
}
