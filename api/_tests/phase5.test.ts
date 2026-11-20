// Vy giai đoạn 5: nhập số đo bằng giọng (có xác nhận), đọc tin nhắn, gọi điện.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { callTarget, norm, parseBp, step, type Nlu } from '../_lib/voice/dm.ts';

const noNlu: Nlu = async () => { throw new Error('không được gọi mô hình'); };
const ui = { screen: '/', contacts: [], honorific: 'bác' };
const n = (s: string) => norm(s);

test('parseBp: các cách đọc số đo thật', () => {
  const cases: [string, number, number, number?][] = [
    ['huyết áp 130 trên 80', 130, 80],
    ['huyết áp của tôi 130 trên 80 mạch 72', 130, 80, 72],
    ['ghi huyết áp 125 80', 125, 80],
    ['vừa đo được 118 trên 76', 118, 76],
    ['huyết áp cao 140 thấp 90', 140, 90],
    ['tâm thu 150 tâm trương 95 nhịp tim 80', 150, 95, 80],
    ['130 trên 80', 130, 80],
    ['lưu huyết áp 135 trên 85 mạch là 70', 135, 85, 70],
    ['huyết áp 130/80', 130, 80],
  ];
  for (const [say, sys, dia, pulse] of cases) {
    const r = parseBp(n(say));
    assert.ok(r && r.ok, say);
    if (r && r.ok) assert.deepEqual([r.sys, r.dia, r.pulse], [sys, dia, pulse], say);
  }
});

test('parseBp: số vô lý thì ok:false (không ghi bậy); câu thường thì null', () => {
  for (const say of ['huyết áp 40 trên 80', 'huyết áp 80 trên 130', 'huyết áp 300 trên 100', 'huyết áp 130 trên 130']) {
    const r = parseBp(n(say));
    assert.ok(r && !r.ok, say);
  }
  for (const say of ['huyết áp của tôi bao nhiêu', 'đọc huyết áp', 'đo huyết áp', 'xem huyết áp', 'nhắn cho con', 'tôi uống thuốc 2 viên', 'mở nhạc', '115', 'gọi 115']) {
    assert.equal(parseBp(n(say)), null, say);
  }
  // mạch ngoài khoảng thì bỏ mạch nhưng vẫn ghi số đo
  const r = parseBp(n('huyết áp 130 trên 80 mạch 300'));
  assert.ok(r && r.ok && r.pulse === undefined);
});

test('record_bp: phải xác nhận trước khi lưu; "lưu" mới thực thi; "hủy/sửa" không lưu', async () => {
  const d1 = await step({ text: 'huyết áp 130 trên 80 mạch 72', state: {}, ui }, noNlu);
  assert.equal(d1.action, 'confirm');
  assert.equal(d1.intent, 'record_bp');
  assert.deepEqual([d1.task!.slots.systolic, d1.task!.slots.diastolic, d1.task!.slots.pulse], ['130', '80', '72']);
  assert.match(d1.say, /130 trên 80, mạch 72/);
  assert.deepEqual(d1.chips, ['Lưu', 'Sửa', 'Hủy']);
  const st = { task: d1.task, expects: d1.expects };
  for (const yes of ['lưu', 'đúng rồi', 'ừ', 'lưu đi', 'đồng ý']) {
    const d = await step({ text: yes, state: st, ui }, noNlu);
    assert.equal(d.action, 'execute', yes);
    assert.equal(d.task!.slots.systolic, '130');
  }
  for (const no of ['sửa', 'không', 'sai rồi']) {
    const d = await step({ text: no, state: st, ui }, noNlu);
    assert.notEqual(d.action, 'execute', no);
    assert.match(d.say, /chưa ghi/);
  }
  const h = await step({ text: 'hủy', state: st, ui }, noNlu);
  assert.equal(h.action, 'cancel');
});

test('record_bp: số vô lý thì hỏi lại, không đi tới xác nhận', async () => {
  const d = await step({ text: 'huyết áp 80 trên 130', state: {}, ui }, noNlu);
  assert.notEqual(d.action, 'confirm');
  assert.notEqual(d.action, 'execute');
  assert.match(d.say, /chưa hợp lý/);
});

test('record_bp không làm hỏng các câu hỏi huyết áp cũ', async () => {
  const nlu: Nlu = async () => ({ intent: 'unsupported', recipient: '', content: '', feature: '', say: '' });
  assert.equal((await step({ text: 'huyết áp của tôi bao nhiêu', state: {}, ui }, nlu)).intent, 'read_bp');
  assert.equal((await step({ text: 'xem lịch sử huyết áp', state: {}, ui }, nlu)).intent, 'show_bp');
  assert.equal((await step({ text: 'đo huyết áp', state: {}, ui }, nlu)).intent, 'measure_bp');
});

test('đọc tin nhắn: các cách hỏi', async () => {
  for (const say of ['đọc tin nhắn', 'đọc tin nhắn mới', 'đọc tin', 'có tin nhắn mới không', 'có tin mới không', 'nghe tin nhắn', 'ai nhắn cho tôi']) {
    const d = await step({ text: say, state: {}, ui }, noNlu);
    assert.equal(d.intent, 'read_messages', say);
    assert.equal(d.action, 'execute');
  }
  // không nhầm với mở màn hay gửi tin
  const nlu: Nlu = async () => ({ intent: 'unsupported', recipient: '', content: '', feature: '', say: '' });
  assert.equal((await step({ text: 'mở tin nhắn', state: {}, ui }, nlu)).intent, 'open_feature');
  assert.equal((await step({ text: 'nhắn tin', state: {}, ui }, nlu)).intent, 'send_message');
});

test('callTarget: nhận lệnh gọi, bỏ qua "gợi ý" và gọi video', () => {
  assert.equal(callTarget(n('gọi điện cho con trai')), 'con trai');
  assert.equal(callTarget(n('gọi cho cô Lan đi')), 'co lan');
  assert.equal(callTarget(n('gọi điện thoại cho Minh nhé')), 'minh');
  assert.equal(callTarget(n('gọi điện')), '');
  assert.equal(callTarget(n('gọi 115')), '115');
  assert.equal(callTarget(n('gọi video cho con')), null);
  assert.equal(callTarget(n('gợi ý bài hát')), null);
  assert.equal(callTarget(n('nhắn cho con')), null);
});

test('call_contact đi tới app (app tự có đếm ngược và nút Huỷ)', async () => {
  const d = await step({ text: 'gọi cho con trai', state: {}, ui }, noNlu);
  assert.equal(d.action, 'execute');
  assert.equal(d.intent, 'call_contact');
  assert.equal(d.task!.slots.recipient_text, 'con trai');
  const e = await step({ text: 'gọi 115', state: {}, ui }, noNlu);
  assert.equal(e.task!.slots.recipient_text, '115');
  // khẩn cấp vẫn đi đường khẩn cấp (không tự gọi)
  const k = await step({ text: 'tôi đau ngực gọi cấp cứu', state: {}, ui }, noNlu);
  assert.equal(k.intent, 'emergency');
});

test('"đúng rồi" là đồng ý (không bị hiểu thành "dừng" → huỷ), cả khi xác nhận gửi tin; "dừng" vẫn là huỷ', async () => {
  const send = await step({ text: 'nhắn cho Lan là mai bác về', state: {}, ui: { screen: '/', honorific: 'bác', contacts: [{ id: 'u2', kind: 'direct', name: 'Lan', username: 'lan' }] } }, noNlu);
  assert.equal(send.action, 'confirm');
  const st = { task: send.task, expects: send.expects };
  const yes = await step({ text: 'đúng rồi', state: st, ui }, noNlu);
  assert.equal(yes.action, 'execute');
  assert.equal(yes.intent, 'send_message');
  const stop = await step({ text: 'dừng', state: st, ui }, noNlu);
  assert.equal(stop.action, 'cancel');
  const stop2 = await step({ text: 'dừng lại', state: st, ui }, noNlu);
  assert.equal(stop2.action, 'cancel');
});

test('SOS nói rõ: "gọi SOS" → sos_start (app đếm ngược 5 giây có Huỷ); "bấm SOS"/"SOS" trơn chỉ chỉ vào nút, không bắt đầu', async () => {
  const { sosExplicit } = await import('../_lib/voice/dm.ts');
  for (const say of ['gọi SOS', 'báo SOS', 'gọi sos đi', 'kích hoạt SOS', 'gọi nút SOS', 'báo SOS ngay', 'gọi SOS giúp tôi']) {
    assert.equal(sosExplicit(n(say)), true, say);
    const d = await step({ text: say, state: {}, ui }, noNlu);
    assert.equal(d.intent, 'sos_start', say);
    assert.equal(d.action, 'execute');
    assert.match(d.say, /giữ nút SOS/); // bản app cũ vẫn có hướng dẫn, không im lặng
  }
  for (const say of ['SOS', 'bấm SOS', 'nút SOS ở đâu', 'tôi muốn xem SOS', 'sos của tôi', 'đăng xuất']) {
    assert.equal(sosExplicit(n(say)), false, say);
  }
  // có ngữ cảnh màn hình (SOS là mức 3): "gọi SOS" nói rõ vẫn là sos_start, còn "bấm SOS" thì chỉ chỉ
  const ctx = {
    role: 'elder' as const, route: '/', dialog: null, lists: [], player: { open: false, playing: false },
    controls: [{ id: 'home.sos', label: 'SOS', aliases: ['báo động', 'gọi sos'], kind: 'button' as const, level: 3 as const, enabled: true }],
  };
  const uic = { screen: '/', contacts: [], honorific: 'bác', context: ctx };
  assert.equal((await step({ text: 'gọi SOS', state: {}, ui: uic }, noNlu)).intent, 'sos_start');
  const pt = await step({ text: 'bấm SOS', state: {}, ui: uic }, noNlu);
  assert.equal(pt.intent, 'point_control');
  assert.equal(pt.task?.slots.control_id, undefined);
});

test('khẩn cấp thật (đau ngực...) vẫn đi đường khẩn cấp, không tự bắt đầu SOS', async () => {
  const d = await step({ text: 'tôi đau ngực quá', state: {}, ui }, noNlu);
  assert.equal(d.intent, 'emergency');
  assert.notEqual(d.intent, 'sos_start');
});
