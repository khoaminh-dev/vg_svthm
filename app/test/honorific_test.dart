import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/shared/honorific.dart';

void main() {
  tearDown(() => setHonorific(null));

  test('mặc định là "bác": chữ không đổi', () {
    expect(hon('Bác chưa đo lần nào, bác thử lại nhé.'), 'Bác chưa đo lần nào, bác thử lại nhé.');
  });

  test('đổi sang "cô": thay bác/Bác, giữ chữ hoa đầu câu', () {
    setHonorific('Cô');
    expect(hon('Bác chưa đo. Cảm ơn bác nhé.'), 'Cô chưa đo. Cảm ơn cô nhé.');
    expect(honorific, 'cô');
  });

  test('không đụng vào "bác sĩ" hay từ chứa chữ bác', () {
    setHonorific('chú');
    expect(hon('Hỏi bác sĩ nhé, bác uống thuốc chưa?'), 'Hỏi bác sĩ nhé, chú uống thuốc chưa?');
    expect(hon('tiếng Việt bách khoa'), 'tiếng Việt bách khoa');
  });

  test('rỗng thì về "bác"', () {
    setHonorific('bà');
    setHonorific('  ');
    expect(honorific, 'bác');
  });
}
