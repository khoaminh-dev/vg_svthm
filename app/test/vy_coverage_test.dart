import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Chốt độ phủ giọng nói: các màn người cao tuổi dùng hằng ngày phải khai báo điều khiển cho Vy (`VyControlScope`).
/// Thêm màn mới vào danh sách này khi nó đã có điều khiển; đừng bớt màn nào ra.
const _covered = [
  'lib/features/home/presentation/elder_home_screen.dart',
  'lib/features/home/presentation/main_shell.dart',
  'lib/features/bp/presentation/screens/bp_screen.dart',
  'lib/features/bp/presentation/screens/measure_screen.dart',
  'lib/features/meds/presentation/meds_view.dart',
  'lib/features/meds/presentation/med_scan_screen.dart',
  'lib/features/chat/presentation/screens/room_list_screen.dart',
  'lib/features/chat/presentation/screens/chat_screen.dart',
  'lib/features/entertainment/presentation/entertainment_screen.dart',
  'lib/features/profile/presentation/profile_screen.dart',
  'lib/features/community/presentation/community_screen.dart',
  'lib/features/meds/presentation/med_plan_edit_screen.dart',
  'lib/features/meds/presentation/med_plan_list_screen.dart',
  'lib/features/health/presentation/screens/health_setup_screen.dart',
  'lib/features/family/presentation/family_invite_screen.dart',
];

/// Màn còn thiếu điều khiển cho Vy. SOS để trống có chủ ý (việc an toàn, người dùng tự bấm). Các màn Gia đình là của người thân.
/// Khi thêm điều khiển, chuyển màn sang danh sách trên.
const _todo = [
  'lib/features/safety/presentation/sos_screen.dart',
  'lib/features/entertainment/presentation/player_screen.dart',
  'lib/features/family/presentation/family_join_screen.dart',
  'lib/features/family/presentation/family_home_screen.dart',
  'lib/features/family/presentation/alerts_screen.dart',
];

void main() {
  test('màn người cao tuổi dùng hằng ngày đều có điều khiển cho Vy', () {
    for (final f in _covered) {
      final src = File(f).readAsStringSync();
      expect(src.contains('VyControlScope('), isTrue, reason: '$f thiếu VyControlScope');
    }
  });

  test('danh sách việc còn lại không lẫn với danh sách đã phủ', () {
    for (final f in _todo) {
      expect(File(f).existsSync(), isTrue, reason: '$f không còn: cập nhật danh sách');
      expect(_covered.contains(f), isFalse, reason: f);
    }
  });
}
