import '../../bp/domain/bp_models.dart';
import '../../health/domain/health_models.dart';

/// Đèn trạng thái của một người thân trên màn Gia đình.
enum FamilyLight { green, yellow, red }

class FamilyStatus {
  const FamilyStatus(this.light, this.reasons);

  final FamilyLight light;

  /// Lý do bằng chữ, quan trọng nhất đứng đầu. Xanh thì có thể rỗng.
  final List<String> reasons;

  String get headline => switch (light) {
    FamilyLight.red => 'Cần chú ý ngay',
    FamilyLight.yellow => 'Nên để ý',
    FamilyLight.green => 'Ổn',
  };
}

/// Luật đèn trạng thái, tập trung một chỗ để kiểm thử. [readings] mới nhất trước.
/// Các luật về thuốc, vị trí, pin sẽ được thêm khi các tính năng đó có.
FamilyStatus computeFamilyStatus({
  required List<BpReading> readings,
  RiskResult? risk,
  required DateTime now,
}) {
  final red = <String>[];
  final yellow = <String>[];
  final latest = readings.isEmpty ? null : readings.first;

  if (latest == null) {
    yellow.add('Chưa đo huyết áp lần nào');
  } else {
    final age = now.difference(latest.measuredAt);
    if ((latest.systolic >= 180 || latest.diastolic >= 120) &&
        age <= const Duration(hours: 24)) {
      red.add('Huyết áp rất cao (${latest.systolic}/${latest.diastolic})');
    }
    if (readings.length >= 2) {
      final prev = readings[1];
      bool high(BpReading r) => r.systolic >= 140 || r.diastolic >= 90;
      if (high(latest) && high(prev) && red.isEmpty) {
        yellow.add(
          'Huyết áp cao hai lần liên tiếp (${latest.systolic}/${latest.diastolic})',
        );
      }
    }
    if (age > const Duration(days: 3)) {
      yellow.add('Chưa đo huyết áp ${age.inDays} ngày');
    }
  }

  if (risk != null) {
    final recent =
        latest != null &&
        risk.measuredAt.isAfter(
          latest.measuredAt.subtract(const Duration(minutes: 1)),
        );
    if (risk.level == RiskLevel.urgent && recent && red.isEmpty) {
      red.add('Đánh giá: cần đi khám ngay');
    } else if (risk.level == RiskLevel.high) {
      yellow.add('Nguy cơ sức khoẻ ở mức cao');
    }
  }

  if (red.isNotEmpty) return FamilyStatus(FamilyLight.red, [...red, ...yellow]);
  if (yellow.isNotEmpty) return FamilyStatus(FamilyLight.yellow, yellow);
  return const FamilyStatus(FamilyLight.green, []);
}
