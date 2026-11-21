import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/voice/core/vi_text.dart';

void main() {
  test('chào tạm biệt: câu ngắn thì tự tắt, nằm trong câu khác thì không', () {
    for (final t in ['Tạm biệt', 'Tạm biệt Vy nhé', 'bye bye', 'Cảm ơn con, tạm biệt', 'hẹn gặp lại']) {
      expect(isGoodbyeText(t), true, reason: t);
    }
    for (final t in ['nhắn cho Lan là tạm biệt nhé', 'chào', 'cảm ơn', 'mở nhạc tạm biệt', 'tôi muốn nói tạm biệt với bà Lan']) {
      expect(isGoodbyeText(t), false, reason: t);
    }
  });
}
