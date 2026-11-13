import { test } from 'node:test';
import assert from 'node:assert/strict';
import { step, norm, resolveRecipient, type Contact, type DState, type Nlu, type Ui } from '../_lib/voice/dm.ts';

const contacts: Contact[] = [
  { id: 'u1', kind: 'direct', name: 'Nguyễn Văn Hùng', username: 'hung' },
  { id: 'u2', kind: 'direct', name: 'Lan', username: 'lan', aliases: ['con gai'] },
  { id: 'g1', kind: 'group', name: 'Gia đình' },
];
const ui: Ui = { screen: 'home', contacts, honorific: 'bác' };

const nluSend = (recipient: string, content = ''): Nlu => async () => ({ intent: 'send_message', recipient, content, feature: '', say: '' });
const noNlu: Nlu = async () => { throw new Error('should not call'); };

test('norm bỏ dấu', () => assert.equal(norm('Nhắn cho Con Trai!'), 'nhan cho con trai'));

test('nhắn tin: thiếu người nhận → hỏi', async () => {
  const d = await step({ text: 'tôi muốn nhắn tin', state: {}, ui }, nluSend(''));
  assert.equal(d.action, 'ask');
  assert.equal(d.pending, 'recipient');
  assert.equal(d.expects, 'name');
});

test('"con trai" chưa có bí danh → hỏi tên, rồi học bí danh', async () => {
  const d1 = await step({ text: 'nhắn cho con trai', state: {}, ui }, nluSend('con trai'));
  assert.equal(d1.action, 'ask');
  assert.equal(d1.aliasPhrase, 'con trai');
  const st: DState = { task: d1.task, pending: d1.pending, expects: d1.expects, aliasPhrase: d1.aliasPhrase };
  const d2 = await step({ text: 'Hùng', state: st, ui }, noNlu);
  assert.equal(d2.pending, 'content');
  assert.deepEqual(d2.learnAlias, { alias: 'con trai', contactId: 'u1' });
});

test('bí danh đã học → bỏ qua bước hỏi tên', async () => {
  const d = await step({ text: 'nhắn cho con gái', state: {}, ui }, nluSend('con gái', 'mai về ăn cơm'));
  assert.equal(d.action, 'confirm');
  assert.equal(d.task?.slots.room_id, 'u2');
  assert.match(d.say, /Lan/);
});

test('nội dung tin nhắn không bị phân loại ý định', async () => {
  const st: DState = { task: { intent: 'send_message', slots: { room_id: 'u1', recipient_name: 'Nguyễn Văn Hùng' } }, pending: 'content', expects: 'free_text' };
  const d = await step({ text: 'quay lại trang chủ nhé', state: st, ui }, noNlu);
  assert.equal(d.action, 'confirm');
  assert.equal(d.task?.slots.content, 'Quay lại trang chủ nhé');
});

test('xác nhận "gửi" → execute; "sửa" → hỏi lại nội dung', async () => {
  const st: DState = { task: { intent: 'send_message', slots: { room_id: 'u1', recipient_name: 'Hùng', content: 'Xin chào' } }, expects: 'yes_no' };
  assert.equal((await step({ text: 'gửi đi', state: st, ui }, noNlu)).action, 'execute');
  const e = await step({ text: 'sửa lại', state: st, ui }, noNlu);
  assert.equal(e.action, 'ask');
  assert.equal(e.pending, 'content');
  const c = await step({ text: 'không, nhắn lại là hẹn mai nhé', state: st, ui }, noNlu);
  assert.equal(c.action, 'confirm');
  assert.equal(c.task?.slots.content, 'Hẹn mai nhé');
});

test('độ tin cậy thấp thì không tự nhận "gửi"', async () => {
  const st: DState = { task: { intent: 'send_message', slots: { room_id: 'u1', recipient_name: 'Hùng', content: 'Xin chào' } }, expects: 'yes_no' };
  const d = await step({ text: 'gửi', state: st, ui, lowConfidence: true }, nluSend('', ''));
  assert.notEqual(d.action, 'execute');
});

test('hủy, khẩn cấp, lệnh nhanh không gọi LLM', async () => {
  assert.equal((await step({ text: 'thôi', state: {}, ui }, noNlu)).action, 'cancel');
  const em = await step({ text: 'tôi đau ngực quá', state: {}, ui }, noNlu);
  assert.equal(em.intent, 'emergency');
  assert.equal(em.sayClass, 'emergency');
  assert.equal((await step({ text: 'về trang chủ', state: {}, ui }, noNlu)).intent, 'go_home');
  assert.equal((await step({ text: 'đo huyết áp', state: {}, ui }, noNlu)).intent, 'measure_bp');
});

test('nhiều người trùng → hỏi chọn', async () => {
  const cs: Contact[] = [
    { id: 'a', kind: 'direct', name: 'Hùng An' },
    { id: 'b', kind: 'direct', name: 'Hùng Bình' },
  ];
  const d = await step({ text: 'nhắn cho hùng', state: {}, ui: { ...ui, contacts: cs } }, nluSend('hùng'));
  assert.equal(d.expects, 'choice');
  assert.equal(d.choices.length, 2);
  const st: DState = { task: d.task, pending: d.pending, expects: d.expects, choices: d.choices };
  const d2 = await step({ text: 'người thứ hai', state: st, ui: { ...ui, contacts: cs } }, noNlu);
  assert.equal(d2.pending, 'content');
});

test('nghe nhầm nhẹ vẫn tìm đúng', () => {
  const r = resolveRecipient('Hung', contacts);
  assert.equal(r.kind, 'one');
});

test('LLM lỗi → thông báo trục trặc, không văng', async () => {
  const d = await step({ text: 'abc xyz lạ lắm', state: {}, ui }, async () => { throw new Error('down'); });
  assert.equal(d.action, 'answer');
});

test('videoQuery: mở bài / nghe nhạc / phát video', async () => {
  const { videoQuery } = await import('../_lib/voice/dm.ts');
  assert.equal(videoQuery('mo bai noi vong tay lon'), 'noi vong tay lon');
  assert.equal(videoQuery('cho nghe nhac xua'), 'nhac xua');
  assert.equal(videoQuery('phat video con meo'), 'con meo');
  assert.equal(videoQuery('xem video cai luong tren youtube'), 'cai luong');
  assert.equal(videoQuery('mo huyet ap'), null);
  assert.equal(videoQuery('mo tin nhan cho con'), null);
  assert.equal(videoQuery('xem con meo'), null);
});

test('nói "nghe nhạc xưa" → play_video với từ khoá có dấu', async () => {
  const d = await step({ text: 'cho nghe nhạc xưa', state: {}, ui }, noNlu);
  assert.equal(d.action, 'execute');
  assert.equal(d.intent, 'play_video');
  assert.equal(d.task?.slots.content?.toLowerCase(), 'nhạc xưa');
});

test('"mở giải trí" mở mục giải trí', async () => {
  const d = await step({ text: 'mở giải trí', state: {}, ui }, noNlu);
  assert.equal(d.action, 'execute');
  assert.equal(d.task?.slots.feature, 'fun');
});

test('điều khiển video: dừng, bài khác, nhỏ đi', async () => {
  const { videoControl } = await import('../_lib/voice/dm.ts');
  assert.equal(videoControl('dung lai'), 'pause');
  assert.equal(videoControl('tam dung a'), 'pause');
  assert.equal(videoControl('tiep tuc'), 'play');
  assert.equal(videoControl('bai khac'), 'next');
  assert.equal(videoControl('bai truoc'), 'previous');
  assert.equal(videoControl('to len chut'), 'louder');
  assert.equal(videoControl('nho di'), 'quieter');
  assert.equal(videoControl('mo bai noi vong tay lon'), null);
  const d = await step({ text: 'bài khác', state: {}, ui }, noNlu);
  assert.equal(d.action, 'execute');
  assert.equal(d.intent, 'video_control');
  assert.equal(d.task?.slots.content?.toLowerCase(), 'next');
});
