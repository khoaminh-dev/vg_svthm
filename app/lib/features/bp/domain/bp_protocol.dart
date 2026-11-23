/// Luật quyết định huyết áp theo chuẩn AHA/ACC. Thuần Dart, không phụ thuộc Flutter.
/// Bản TypeScript song song: api/_lib/health/bp_protocol.ts. Cả hai chạy chung bộ ca
/// api/_tests/fixtures/bp_protocol_cases.json (xem test/bp_protocol_test.dart).
library;

import '../../../shared/honorific.dart';

enum BpLevel { normal, elevated, stage1, stage2, crisis }

enum BpAction {
  none,
  restRecheck,
  recheck1min,
  askSymptoms,
  monitor,
  callDoctorToday,
  callDoctorNow,
  call115,
}

/// Bối cảnh trước số đo đầu tiên.
enum BpContext { wokeUp, exertion, caffeineSmoke }

/// Khoá câu cố định (nguồn: api/_lib/health/bp_script.json).
enum BpScript {
  prep,
  wokeUp,
  afterWalk,
  caffeineSmoke,
  secondReading,
  highRecheck,
  stillHigh,
  severeWait,
  askSymptoms,
  severeConfirm,
  emergency,
  normal,
  elevated,
  keepMonitoring,
  singleReading,
  irregular,
}

/// Số đọc có vẻ lạ nên cần người dùng xác nhận: chênh lệch tâm thu/tâm trương quá nhỏ hoặc quá lớn,
/// huyết áp rất cao (tránh báo động nhầm vì đọc sai chữ số), hoặc nhảy mạnh so với số đo trước trong phiên.
bool bpLooksSuspicious(int sys, int dia, {BpSample? previous}) {
  final pp = sys - dia;
  if (pp < 20 || pp > 100) return true;
  if (bpIsSevere(sys, dia)) return true;
  if (previous != null &&
      ((sys - previous.sys).abs() >= 40 || (dia - previous.dia).abs() >= 25)) {
    return true;
  }
  return false;
}

/// Một số đo trong phiên: [rested] = đã ngồi nghỉ yên đủ 5 phút trước số đo này.
class BpSample {
  const BpSample(this.sys, this.dia, {this.rested = false});
  final int sys;
  final int dia;
  final bool rested;
}

class BpDecision {
  const BpDecision({
    required this.avgSys,
    required this.avgDia,
    required this.count,
    required this.level,
    required this.action,
    required this.script,
    required this.protocolOk,
  });

  final int avgSys;
  final int avgDia;
  final int count;
  final BpLevel level;
  final BpAction action;
  final BpScript script;
  final bool protocolOk;
}

/// Ngưỡng AHA: cao hơn 180 hoặc cao hơn 120 là rất cao (180/120 đúng chưa tính).
bool bpIsSevere(int sys, int dia) => sys > 180 || dia > 120;

BpLevel bpLevelOf(int sys, int dia) {
  if (bpIsSevere(sys, dia)) return BpLevel.crisis;
  if (sys >= 140 || dia >= 90) return BpLevel.stage2;
  if (sys >= 130 || dia >= 80) return BpLevel.stage1;
  if (sys >= 120) return BpLevel.elevated;
  return BpLevel.normal;
}

int _avg(Iterable<int> xs) => (xs.reduce((a, b) => a + b) / xs.length).round();

BpDecision bpDecide(
  List<BpSample> readings, {
  Set<BpContext> context = const {},
  bool? symptoms,
}) {
  if (readings.isEmpty) {
    return const BpDecision(
      avgSys: 0,
      avgDia: 0,
      count: 0,
      level: BpLevel.normal,
      action: BpAction.none,
      script: BpScript.normal,
      protocolOk: false,
    );
  }
  final latest = readings.last;
  final latestSevere = bpIsSevere(latest.sys, latest.dia);
  final anySevere = readings.any((r) => bpIsSevere(r.sys, r.dia));
  final protocolOk = readings.any((r) => r.rested);
  // Số chưa ngồi nghỉ đủ chuẩn bị bỏ khi đã có số đủ chuẩn, trừ khi có số rất cao (an toàn trước).
  final pool = anySevere || !protocolOk
      ? readings
      : readings.where((r) => r.rested).toList();
  final aSys = _avg(pool.map((r) => r.sys));
  final aDia = _avg(pool.map((r) => r.dia));
  final level = latestSevere ? BpLevel.crisis : bpLevelOf(aSys, aDia);

  BpDecision out(BpAction action, BpScript key) => BpDecision(
    avgSys: aSys,
    avgDia: aDia,
    count: pool.length,
    level: level,
    action: action,
    script: key,
    protocolOk: protocolOk,
  );

  if (symptoms == true) return out(BpAction.call115, BpScript.emergency);

  if (latestSevere) {
    if (readings.length == 1)
      return out(BpAction.recheck1min, BpScript.severeWait);
    if (symptoms == false)
      return out(BpAction.callDoctorNow, BpScript.severeConfirm);
    return out(BpAction.askSymptoms, BpScript.askSymptoms);
  }

  if (level == BpLevel.normal) return out(BpAction.none, BpScript.normal);

  if (pool.length == 1 &&
      !pool.first.rested &&
      context.contains(BpContext.caffeineSmoke)) {
    return out(BpAction.restRecheck, BpScript.caffeineSmoke);
  }

  if (pool.length == 1) {
    if (!pool.first.rested && context.contains(BpContext.wokeUp)) {
      return out(BpAction.restRecheck, BpScript.wokeUp);
    }
    if (!pool.first.rested && context.contains(BpContext.exertion)) {
      return out(BpAction.restRecheck, BpScript.afterWalk);
    }
    return out(BpAction.restRecheck, BpScript.highRecheck);
  }

  if (level == BpLevel.elevated)
    return out(BpAction.monitor, BpScript.elevated);
  if (level == BpLevel.stage1)
    return out(BpAction.monitor, BpScript.keepMonitoring);
  return out(BpAction.callDoctorToday, BpScript.stillHigh);
}

/// Câu cố định (gốc viết sẵn là "bác", đổi theo cách xưng hô hiện tại qua [hon]).
const Map<BpScript, String> bpScriptBase = {
  BpScript.prep: 'Bác ngồi thẳng, tựa lưng, tay đặt lên bàn, băng quấn ngang tim. Bác đừng nói chuyện, con đếm 5 phút nhé.',
  BpScript.wokeUp: 'Bác mới ngủ dậy nên số đo có thể cao hơn bình thường. Bác ngồi yên, tựa lưng 5 phút rồi mình đo lại nhé, bác đừng đi lại.',
  BpScript.afterWalk: 'Bác vừa mới hoạt động nên số đo có thể cao. Bác ngồi yên, tựa lưng 5 phút rồi mình đo lại nhé.',
  BpScript.caffeineSmoke: 'Bác vừa uống cà phê hoặc hút thuốc nên số đo chưa chuẩn. Bác ngồi yên, chờ khoảng 30 phút rồi mình đo lại nhé.',
  BpScript.secondReading:
      'Bác ngồi yên thêm 1 phút, rồi mình đo số thứ hai nhé.',
  BpScript.highRecheck: 'Số này hơi cao. Một số đo cao chưa phải là bệnh. Bác ngồi yên, tựa lưng 5 phút rồi đo lại hai lần, cách nhau 1 phút nhé.',
  BpScript.stillHigh: 'Đo lại vẫn còn cao. Bác báo người thân hoặc nhân viên y tế trong hôm nay, và đừng tự bỏ thuốc nhé.',
  BpScript.severeWait: 'Số đo rất cao. Bác ngồi yên, chờ 1 phút rồi đo lại. Nếu bác đau ngực, khó thở, tê yếu, méo miệng hay nói khó thì gọi 115 ngay.',
  BpScript.askSymptoms:
      'Bác có đau ngực, khó thở, tê yếu, méo miệng hoặc nói khó không ạ?',
  BpScript.severeConfirm: 'Vẫn rất cao. Bác gọi nhân viên y tế hoặc người thân ngay bây giờ. Nếu có đau ngực, khó thở, tê yếu hay nói khó thì gọi 115.',
  BpScript.emergency: 'Bác có dấu hiệu nguy hiểm. Bác gọi 115 ngay, đừng chờ xem huyết áp có hạ không.',
  BpScript.normal:
      'Huyết áp bình thường. Bác cứ đo đều, cùng giờ mỗi ngày nhé.',
  BpScript.elevated: 'Huyết áp hơi cao. Bác cứ đo đều mỗi ngày, cùng giờ, và nhớ ngồi yên 5 phút trước khi đo nhé.',
  BpScript.keepMonitoring: 'Huyết áp đang cao. Bác đo đều vài ngày, mỗi lần ngồi yên 5 phút trước khi đo, và nhắc bác sĩ xem các số đo nhé.',
  BpScript.singleReading: 'Mới đo một lần nên chưa chuẩn. Bác ngồi yên 1 phút rồi đo thêm một số nữa nhé.',
  BpScript.irregular: 'Máy báo nhịp tim không đều nên số đo có thể chưa chính xác. Bác cho bác sĩ biết trong lần khám tới, và đi khám sớm nếu thấy hồi hộp hay chóng mặt nhé.',
};

String bpScriptText(BpScript key) => hon(bpScriptBase[key]!);
