import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Một nút trên thẻ. "Chạm = nói": chạm nút làm đúng việc mà lời nói tương ứng sẽ làm.
@immutable
class VyCardAction {
  const VyCardAction({required this.label, required this.run, this.primary = false});

  final String label;
  final VoidCallback run;

  /// Nút chính (đặc); các nút còn lại là phụ (nền nhạt).
  final bool primary;
}

/// Thẻ kết quả trong panel Vy (kế hoạch mục 8): thông tin hoặc lựa chọn có sẵn nút, thay cho một đoạn chữ dài.
/// Thẻ chỉ giữ DỮ LIỆU và việc cần làm khi chạm; vẽ ở `vy_cards.dart`.
@immutable
sealed class VyCard {
  const VyCard({this.actions = const [], this.hold, this.replacesSpeech = true});

  final List<VyCardAction> actions;

  /// Thẻ chỉ để xem lướt: sau thời gian này thì thu về thanh nhỏ (nếu người dùng chưa chạm vào). Null = giữ tới khi có việc khác.
  final Duration? hold;

  /// Thẻ đã nói đủ ý nên không lặp lại câu Vy nói ở dạng chữ trong thẻ lớn.
  final bool replacesSpeech;
}

/// Thẻ Huyết áp: số lớn, mức, thời điểm; nút "Xem biểu đồ", "Đo lại".
class BpCard extends VyCard {
  BpCard({
    required this.systolic,
    required this.diastolic,
    this.pulse,
    required this.levelLabel,
    required this.levelColor,
    required this.when,
    super.actions,
  }) : super(hold: const Duration(seconds: 6));

  final int systolic;
  final int diastolic;
  final int? pulse;
  final String levelLabel;
  final Color levelColor;

  /// "hôm nay 07:05", "hôm qua 19:30"...
  final String when;
}

/// Một dòng của thẻ Thuốc.
@immutable
class MedRow {
  const MedRow({
    required this.time,
    required this.name,
    required this.status,
    required this.statusColor,
    this.items = const [],
    this.highlight = false,
  });

  final String time;
  final String name;
  final String status;
  final Color statusColor;

  /// "Amlodipine 5 mg, 1 viên".
  final List<String> items;

  /// Cữ kế tiếp (nhấn mạnh).
  final bool highlight;
}

/// Thẻ Thuốc: giờ, tên túi/cữ, trạng thái, thuốc trong túi. Giữ cho tới khi có việc khác.
class MedCard extends VyCard {
  MedCard({required this.title, required this.rows, super.actions});

  final String title;
  final List<MedRow> rows;
}

/// Thẻ "Đã gửi": tick xanh, gửi cho ai, nội dung. Tự thu về sau vài giây.
class SentCard extends VyCard {
  SentCard({required this.to, required this.text, super.actions}) : super(hold: const Duration(seconds: 5));

  final String to;
  final String text;
}

/// Thẻ đang hiện (hoặc null). Nơi tạo thẻ (bộ thực thi lệnh) gọi [show]; VyCore xoá khi đóng hoặc người dùng làm việc khác.
class VyCardNotifier extends Notifier<VyCard?> {
  @override
  VyCard? build() => null;

  void show(VyCard card) => state = card;

  void clear() {
    if (state != null) state = null;
  }
}

final vyCardProvider = NotifierProvider<VyCardNotifier, VyCard?>(VyCardNotifier.new);
