import '../../meds/domain/meds_models.dart';
import '../../voice/core/vy_reminders.dart' show bpReminderDue;

/// Việc kế tiếp hiện ở đầu Trang chủ người cao tuổi. Chỉ một việc, chọn theo thứ tự ưu tiên.
enum NextTaskKind {
  /// Đang đến giờ uống thuốc: nút "Đã uống".
  doseDue,

  /// Đến giờ đo huyết áp mà chưa đo: nút "Đo bây giờ".
  bpDue,

  /// Cữ thuốc kế tiếp (chưa đến giờ): chạm để xem lịch thuốc.
  doseNext,

  /// Không còn việc hôm nay.
  none,
}

class NextTask {
  const NextTask(this.kind, {this.dose});

  final NextTaskKind kind;
  final Dose? dose;
}

/// Chọn việc kế tiếp. Thuốc đến giờ > đến giờ đo huyết áp > cữ thuốc kế tiếp > không có.
/// [bpSlots] là giờ nhắc đo ({"morning": "08:00"}); rỗng/null = chưa bật nhắc nên không có việc đo.
/// [measured] là các lần đo gần đây (chỉ cần thời điểm).
NextTask pickNextTask({
  required DateTime now,
  Dose? dose,
  Map<String, String>? bpSlots,
  List<DateTime> measured = const [],
}) {
  if (dose != null && dose.stateAt(now) == DoseState.due) {
    return NextTask(NextTaskKind.doseDue, dose: dose);
  }
  if (bpSlots != null && bpSlots.isNotEmpty && bpReminderDue(now, bpSlots, measured) != null) {
    return const NextTask(NextTaskKind.bpDue);
  }
  if (dose != null) return NextTask(NextTaskKind.doseNext, dose: dose);
  return const NextTask(NextTaskKind.none);
}
