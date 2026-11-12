import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/voice/domain/voice_models.dart';

void main() {
  test('parse quyết định xác nhận gửi tin', () {
    final r = VoiceTurnResult.fromJson({
      'transcript': 'nhắn cho con trai',
      'stt': {'provider': 'groq-whisper'},
      'decision': {
        'action': 'confirm',
        'intent': 'send_message',
        'task': {
          'intent': 'send_message',
          'slots': {'room_id': 'r1', 'content': 'Xin chào'},
        },
        'expects': 'yes_no',
        'say': 'Con gửi cho Hùng: Xin chào bác gửi nhé?',
        'say_class': 'important',
        'expects_reply': true,
        'chips': ['Gửi', 'Sửa', 'Hủy'],
        'choices': [],
      },
    });
    expect(r.decision.action, 'confirm');
    expect(r.decision.expects, VoiceExpect.yesNo);
    expect(r.decision.task!.slots['room_id'], 'r1');
    expect(r.decision.chips, ['Gửi', 'Sửa', 'Hủy']);
    expect(r.sttProvider, 'groq-whisper');
  });

  test('trạng thái hội thoại gửi lên máy chủ đúng định dạng', () {
    const d = VoiceDialog(
      task: VoiceTask(intent: 'send_message', slots: {'recipient_text': 'con trai'}),
      pending: 'recipient',
      expects: VoiceExpect.person,
      aliasPhrase: 'con trai',
    );
    final j = d.toJson();
    expect(j['expects'], 'name');
    expect(j['alias_phrase'], 'con trai');
    expect((j['task'] as Map)['intent'], 'send_message');
  });

  test('VoiceContact.toJson', () {
    const c = VoiceContact(id: 'a', kind: 'direct', name: 'Hùng', username: 'hung', aliases: ['con trai']);
    expect(c.toJson()['aliases'], ['con trai']);
  });
}
