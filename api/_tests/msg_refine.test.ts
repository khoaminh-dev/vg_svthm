import test from 'node:test';
import assert from 'node:assert/strict';
import { fastSend, step, type Contact, type Nlu, type Refine } from '../_lib/voice/dm.ts';
import { acceptRefined, ensureEnd, finishMessage } from '../_lib/voice/msg_refine.ts';

const contacts: Contact[] = [
  { id: 'u1', kind: 'direct', name: 'Hải', username: 'hai' },
  { id: 'u2', kind: 'direct', name: 'Minh Anh', username: 'minhanh' },
  { id: 'u3', kind: 'direct', name: 'Minh Tuấn', username: 'minhtuan' },
  { id: 'u4', kind: 'direct', name: 'Lan', username: 'lan', aliases: ['con gái'] },
];
const noNlu: Nlu = async () => { throw new Error('không được gọi mô hình'); };

test('hỏi Hải ăn cơm chưa: tách người nhận và nội dung, không gọi mô hình', () => {
  const f = fastSend('hỏi Hải ăn cơm chưa', contacts);
  assert.deepEqual(f, { intent: 'send_message', recipient: 'Hải', content: 'ăn cơm chưa', verb: 'hoi' });
});

test('bảo / nói với / báo cho / nhắn: nhận đúng người và nội dung', () => {
  assert.deepEqual(fastSend('bảo Lan là mai bác về', contacts), { intent: 'send_message', recipient: 'Lan', content: 'mai bác về', verb: 'bao' });
  assert.deepEqual(fastSend('nói với Hải mai bác ghé chơi', contacts), { intent: 'send_message', recipient: 'Hải', content: 'mai bác ghé chơi', verb: 'noi' });
  assert.deepEqual(fastSend('báo cho Lan bác khoẻ', contacts), { intent: 'send_message', recipient: 'Lan', content: 'bác khoẻ', verb: 'bao' });
  const n = fastSend('nhắn cho Hải ăn cơm chưa', contacts);
  assert.equal(n?.recipient, 'Hải');
  assert.equal(n?.content, 'ăn cơm chưa');
  assert.equal(n?.verb, undefined);
});

test('tên hai từ khớp chính xác: lấy đủ tên, phần còn lại là nội dung', () => {
  const f = fastSend('hỏi Minh Anh có khoẻ không', contacts);
  assert.equal(f?.recipient, 'Minh Anh');
  assert.equal(f?.content, 'có khoẻ không');
});

test('chỉ tên (nhắn cho Lan): nội dung để trống, hỏi sau', () => {
  assert.deepEqual(fastSend('nhắn cho Lan', contacts), { intent: 'send_message', recipient: 'Lan', content: '', verb: undefined });
});

test('hỏi thăm / nói chuyện (không phải tên trong danh bạ): không bắt nhầm', () => {
  assert.equal(fastSend('hỏi thăm sức khoẻ giúp tôi', contacts), null);
  assert.equal(fastSend('nói chuyện với Vy', contacts), null);
  assert.equal(fastSend('hỏi Hùng ăn cơm chưa', contacts), null, 'tên không có trong danh bạ: để bước sau hỏi');
});

test('dấu thanh khác nhau vẫn là cùng tên (Hài/Hãi → Hải)', () => {
  assert.equal(fastSend('hỏi Hài ăn cơm chưa', contacts)?.recipient, 'Hài');
});

test('finishMessage: hỏi → "Hải ăn cơm chưa?"; nhắn thường → viết hoa và dấu câu', () => {
  assert.equal(finishMessage('ăn cơm chưa', 'Hải', 'hoi'), 'Hải ăn cơm chưa?');
  assert.equal(finishMessage('mai bác về', 'Lan'), 'Mai bác về.');
  assert.equal(finishMessage('ừm hôm nay bác hơi mệt', 'Lan'), 'Hôm nay bác hơi mệt.');
  assert.equal(finishMessage('con ăn cơm chưa', 'Lan'), 'Con ăn cơm chưa?');
});

test('ensureEnd giữ dấu có sẵn', () => {
  assert.equal(ensureEnd('Đã xong!'), 'Đã xong!');
  assert.equal(ensureEnd('Bác khoẻ'), 'Bác khoẻ.');
});

test('acceptRefined: nhận bản chỉnh chuẩn câu', () => {
  assert.equal(acceptRefined('ừm hôm nay bác hơi mệt mệt', 'Hôm nay bác hơi mệt.', 'Lan'), true);
  assert.equal(acceptRefined('ăn cơm chưa', 'Hải ăn cơm chưa?', 'Hải'), true);
  assert.equal(acceptRefined('mai bác về lúc ba giờ', 'Mai bác về lúc ba giờ.'), true);
});

test('acceptRefined: từ chối viết lại, đổi nghĩa, đổi số, bỏ phủ định, thêm ý', () => {
  assert.equal(acceptRefined('mai bác về lúc 3 giờ', 'Mai bác về lúc 4 giờ.'), false, 'đổi số');
  assert.equal(acceptRefined('bác chưa uống thuốc', 'Bác uống thuốc rồi.'), false, 'đổi nghĩa');
  assert.equal(acceptRefined('bác không đi được', 'Bác đi được.'), false, 'bỏ phủ định');
  assert.equal(acceptRefined('mai bác về', 'Dạ thưa con, ngày mai bác sẽ trở về nhà, con nhớ chuẩn bị cơm nhé.'), false, 'viết lại dài');
  assert.equal(acceptRefined('bác khoẻ', 'Chúc con một ngày tốt lành.'), false, 'thay hoàn toàn');
  assert.equal(acceptRefined('bác khoẻ', ''), false);
});

test('step: tin được chuẩn hoá ngay trước khi hỏi/gửi, và nói đúng tin đã chuẩn hoá', async () => {
  const refine: Refine = async ({ content, recipient, verb }) => finishMessage(content, recipient, verb === 'hoi' ? 'hoi' : undefined);
  const d = await step({ text: 'hỏi Hải ăn cơm chưa', state: {}, ui: { contacts, honorific: 'bác' } }, noNlu, refine);
  assert.equal(d.action, 'confirm');
  assert.equal(d.task?.slots.recipient_name, 'Hải');
  assert.equal(d.task?.slots.content, 'Hải ăn cơm chưa?');
  assert.match(d.say, /Con gửi cho Hải: Hải ăn cơm chưa\?/);
});

test('step: người dùng sửa tin thì chuẩn hoá lại bản mới (không dính "hỏi" cũ)', async () => {
  const calls: string[] = [];
  const refine: Refine = async ({ content, recipient, verb }) => { calls.push(`${content}|${verb ?? ''}`); return finishMessage(content, recipient, verb === 'hoi' ? 'hoi' : undefined); };
  const d1 = await step({ text: 'hỏi Hải ăn cơm chưa', state: {}, ui: { contacts } }, noNlu, refine);
  const d2 = await step(
    { text: 'sửa thành mai bác ghé', state: { task: d1.task, pending: null, expects: 'yes_no' }, ui: { contacts } },
    noNlu,
    refine,
  );
  assert.equal(d2.task?.slots.content, 'Mai bác ghé.');
  assert.deepEqual(calls, ['Ăn cơm chưa|hoi', 'Mai bác ghé|']);
});

test('step: không có bộ chuẩn hoá thì giữ nguyên nội dung (an toàn khi Groq tắt)', async () => {
  const d = await step({ text: 'bảo Lan là mai bác về', state: {}, ui: { contacts } }, noNlu);
  assert.equal(d.task?.slots.content, 'Mai bác về');
});

test('step: bộ chuẩn hoá lỗi thì vẫn gửi được nội dung gốc', async () => {
  const d = await step({ text: 'bảo Lan là mai bác về', state: {}, ui: { contacts } }, noNlu, async () => { throw new Error('x'); });
  assert.equal(d.action, 'confirm');
  assert.equal(d.task?.slots.content, 'Mai bác về');
});
