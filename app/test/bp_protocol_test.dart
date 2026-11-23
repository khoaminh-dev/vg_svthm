import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/bp/domain/bp_protocol.dart';
import 'package:vg_svthm/shared/honorific.dart';

String _snake(String camel) => camel.replaceAllMapped(
  RegExp(r'[A-Z]|[0-9]+'),
  (m) => '_${m[0]!.toLowerCase()}',
);

void main() {
  final root = Directory.current.path.endsWith('app') ? '..' : '.';
  final cases = jsonDecode(
    File('$root/api/_tests/fixtures/bp_protocol_cases.json').readAsStringSync(),
  ) as List;
  final script = jsonDecode(
    File('$root/api/_lib/health/bp_script.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  for (final c in cases) {
    test('bp_protocol (chung với TS): ${c['name']}', () {
      final readings = [
        for (final r in c['readings'] as List)
          BpSample(r[0] as int, r[1] as int, rested: r[2] == 1),
      ];
      const ctxOf = {
        'woke_up': BpContext.wokeUp,
        'exertion': BpContext.exertion,
        'caffeine_smoke': BpContext.caffeineSmoke,
      };
      final d = bpDecide(
        readings,
        context: {for (final x in c['context'] as List) ctxOf[x]!},
        symptoms: c['symptoms'] as bool?,
      );
      final e = c['expect'] as Map;
      expect(_snake(d.action.name), e['action']);
      expect(_snake(d.script.name), e['script']);
      expect(d.level.name, e['category']);
      expect(d.protocolOk, e['protocolOk']);
    });
  }

  test('câu cố định Dart khớp từng chữ với bp_script.json (nguồn chung)', () {
    setHonorific('bác');
    expect(BpScript.values.length, script.length);
    for (final k in BpScript.values) {
      expect(bpScriptBase[k], script[_snake(k.name)], reason: k.name);
    }
  });

  test('ngưỡng AHA: 180/120 chưa phải severe', () {
    expect(bpIsSevere(180, 120), isFalse);
    expect(bpIsSevere(181, 80), isTrue);
    expect(bpIsSevere(100, 121), isTrue);
    expect(bpLevelOf(119, 79), BpLevel.normal);
    expect(bpLevelOf(120, 79), BpLevel.elevated);
    expect(bpLevelOf(130, 70), BpLevel.stage1);
    expect(bpLevelOf(110, 90), BpLevel.stage2);
  });

  test('câu cố định đổi xưng hô, giữ "bác sĩ"', () {
    setHonorific('cô');
    expect(bpScriptText(BpScript.keepMonitoring), contains('nhắc bác sĩ'));
    expect(
      bpScriptText(BpScript.stillHigh),
      startsWith('Đo lại vẫn còn cao. Cô báo'),
    );
    setHonorific('bác');
  });
}
