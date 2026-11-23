import '../../../shared/honorific.dart';
import 'bp_models.dart';
import 'bp_protocol.dart';

/// Nhận xét ngắn cho một lần đo (không thay thế ý kiến bác sĩ). Câu chính là câu cố định của luật AHA
/// ([bpDecide]); thêm mạch và so với lần trước. Không bao giờ khuyên đi lại hay vận động.
String bpAdvice(BpReading r, {BpReading? previous, BpDecision? decision}) {
  final d =
      decision ??
      bpDecide([
        BpSample(r.systolic, r.diastolic, rested: r.protocolOk == true),
      ]);
  final parts = <String>[bpScriptText(d.script)];
  final pulse = r.pulse;
  if (pulse != null && pulse > 100) {
    parts.add('Mạch hơi nhanh ($pulse lần/phút).');
  }
  if (pulse != null && pulse < 50) {
    parts.add('Mạch hơi chậm ($pulse lần/phút).');
  }
  if (previous != null) {
    final delta = r.systolic - previous.systolic;
    if (delta.abs() >= 10) {
      parts.add(
        delta > 0
            ? 'Tâm thu cao hơn lần trước ${delta.abs()} mmHg.'
            : 'Tâm thu thấp hơn lần trước ${delta.abs()} mmHg.',
      );
    }
  }
  return hon(parts.join(' '));
}
