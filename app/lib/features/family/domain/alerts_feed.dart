import '../../bp/domain/bp_models.dart';
import '../../meds/domain/meds_models.dart';
import '../../safety/domain/safety_models.dart';
import 'family_models.dart';

enum AlertKind { sos, bpCrisis, bpHigh, doseMissed }

/// Mức nghiêm trọng: đỏ cần xử lý ngay, cam cần chú ý, xám chỉ để biết.
enum AlertLevel { red, orange, info }

class AlertItem {
  const AlertItem({
    required this.kind,
    required this.level,
    required this.ownerId,
    required this.ownerName,
    required this.at,
    required this.title,
    required this.detail,
    this.sosId,
  });

  final AlertKind kind;
  final AlertLevel level;
  final String ownerId;
  final String ownerName;
  final DateTime at;
  final String title;
  final String detail;
  final String? sosId;
}

String _nameOf(FamilyLink l) {
  final n = (l.otherName ?? '').trim();
  return n.isNotEmpty ? n : (l.otherUsername ?? 'Người thân');
}

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Gom các sự kiện đáng chú ý của những người tôi theo dõi trong [days] ngày qua, mới nhất trước.
/// Chỉ dùng dữ liệu mà quyền cho phép: huyết áp cần `health`, thuốc cần `meds_view`, SOS cần `alerts`.
List<AlertItem> buildAlerts({
  required List<FamilyLink> links,
  required Map<String, List<BpReading>> bp,
  required Map<String, List<Dose>> doses,
  required List<SosEvent> sos,
  required DateTime now,
  int days = 7,
  String? myId,
}) {
  final since = now.subtract(Duration(days: days));
  final out = <AlertItem>[];
  final byOwner = {for (final l in links) l.otherId: l};
  String nameOf(String id) => byOwner[id] == null ? 'Người thân' : _nameOf(byOwner[id]!);

  for (final l in links) {
    final name = _nameOf(l);

    if (l.can(FamilyPerm.health)) {
      for (final r in bp[l.otherId] ?? const <BpReading>[]) {
        if (r.measuredAt.isBefore(since) || r.measuredAt.isAfter(now)) continue;
        final crisis = r.systolic >= 180 || r.diastolic >= 120;
        final high = r.systolic >= 160 || r.diastolic >= 100;
        if (!crisis && !high) continue;
        out.add(
          AlertItem(
            kind: crisis ? AlertKind.bpCrisis : AlertKind.bpHigh,
            level: crisis ? AlertLevel.red : AlertLevel.orange,
            ownerId: l.otherId,
            ownerName: name,
            at: r.measuredAt,
            title: crisis ? 'Huyết áp của $name rất cao' : 'Huyết áp của $name cao',
            detail: '${r.systolic}/${r.diastolic} mmHg lúc ${_hm(r.measuredAt)}',
          ),
        );
      }
    }

    if (l.can(FamilyPerm.medsView)) {
      for (final d in doses[l.otherId] ?? const <Dose>[]) {
        if (d.dueAt.isBefore(since) || d.dueAt.isAfter(now)) continue;
        if (d.stateAt(now) != DoseState.missed) continue;
        out.add(
          AlertItem(
            kind: AlertKind.doseMissed,
            level: AlertLevel.orange,
            ownerId: l.otherId,
            ownerName: name,
            at: d.dueAt,
            title: '$name chưa uống ${d.bag ? 'túi ${d.label}' : d.label}',
            detail: 'Đến giờ ${_hm(d.dueAt)}, đã quá thời gian uống',
          ),
        );
      }
    }
  }

  for (final e in sos) {
    final l = byOwner[e.ownerId];
    if (l == null || !l.can(FamilyPerm.alerts)) continue;
    if (e.createdAt.isBefore(since)) continue;
    final String detail;
    final AlertLevel level;
    if (e.cancelled) {
      detail = 'Đã huỷ (bấm nhầm hoặc đã ổn)';
      level = AlertLevel.info;
    } else if (e.handled) {
      detail = '${e.handledBy != null && e.handledBy == myId ? 'Bạn' : nameOf(e.handledBy ?? '')} đã nhận lúc ${_hm(e.handledAt ?? e.createdAt)}';
      level = AlertLevel.orange;
    } else {
      detail = 'Chưa ai nhận. Bấm để xem và gọi ngay';
      level = AlertLevel.red;
    }
    out.add(
      AlertItem(
        kind: AlertKind.sos,
        level: level,
        ownerId: e.ownerId,
        ownerName: _nameOf(l),
        at: e.createdAt,
        title: '${_nameOf(l)} đã bấm SOS',
        detail: detail,
        sosId: e.id,
      ),
    );
  }

  out.sort((a, b) => b.at.compareTo(a.at));
  return out;
}

/// Nhãn nhóm theo ngày: "Hôm nay", "Hôm qua", hoặc ngày/tháng.
String dayLabel(DateTime t, DateTime now) {
  final d = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Hôm nay';
  if (diff == 1) return 'Hôm qua';
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
}
