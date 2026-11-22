// Ý định đọc lịch thuốc ("tối nay tôi phải uống thuốc gì?"): chỉ nhận CÂU HỎI, không bắt nhầm câu khẳng định hay lệnh mở màn.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { medsQuery, norm, step, type Nlu } from '../_lib/voice/dm.ts';

const noNlu: Nlu = async () => { throw new Error('không được gọi mô hình'); };

const YES = [
  'tối nay tôi phải uống thuốc gì',
  'hôm nay uống thuốc gì',
  'uống thuốc gì',
  'bác phải uống thuốc gì hôm nay',
  'sáng nay uống thuốc gì',
  'mấy giờ uống thuốc',
  'mấy giờ tôi phải uống thuốc',
  'khi nào uống thuốc',
  'bao giờ phải uống thuốc',
  'uống thuốc lúc nào',
  'lúc nào uống thuốc',
  'đến giờ uống thuốc chưa',
  'cữ thuốc kế tiếp',
  'cữ kế tiếp',
  'lần thuốc tiếp theo',
  'thuốc hôm nay',
  'thuốc tối nay',
  'thuốc kế tiếp',
  'ừ cho bác hỏi tối nay uống thuốc gì nhé',
  'uống thuốc huyết áp lúc nào',
];

const NO = [
  'tôi uống thuốc rồi',
  'bác uống thuốc rồi',
  'uống rồi',
  'tôi chưa uống thuốc',
  'mở thuốc',
  'mở lịch thuốc',
  'xem lịch thuốc',
  'vào thuốc',
  'thêm đơn thuốc',
  'chụp đơn thuốc',
  'quét đơn thuốc',
  'sửa lịch thuốc',
  'hết thuốc rồi',
  'mua thuốc ở đâu',
  'thuốc này có tác dụng phụ gì',
  'thuốc huyết áp có hại không',
  'đổi thuốc được không',
  'lịch thuốc',
  'xin chào',
  'huyết áp của tôi bao nhiêu',
  'nhắn cho con là tôi uống thuốc rồi',
];

test('medsQuery nhận các câu hỏi về lịch thuốc', () => {
  const bad = YES.filter((s) => !medsQuery(norm(s)));
  assert.deepEqual(bad, []);
});

test('medsQuery KHÔNG nhận câu khẳng định, lệnh mở màn hay câu hỏi y khoa', () => {
  const bad = NO.filter((s) => medsQuery(norm(s)));
  assert.deepEqual(bad, []);
});

test('step: câu hỏi lịch thuốc → read_meds chạy ngay, không gọi mô hình, app tự nói kết quả', async () => {
  const d = await step({ text: 'tối nay tôi phải uống thuốc gì', state: {}, ui: { screen: '/', contacts: [], honorific: 'bác' } }, noNlu);
  assert.equal(d.action, 'execute');
  assert.equal(d.intent, 'read_meds');
  assert.equal(d.say, ''); // câu trả lời do app đọc từ lịch thật
});

test('step: "uống thuốc gì" không còn bị xếp vào câu hỏi sức khoẻ chung (health_status)', async () => {
  const nlu: Nlu = async () => ({ intent: 'health_status', recipient: '', content: 'other', feature: '', say: '' });
  const d = await step({ text: 'tôi phải uống thuốc gì', state: {}, ui: { screen: '/', contacts: [], honorific: 'bác' } }, nlu);
  assert.equal(d.intent, 'read_meds');
});

test('step: "tôi uống thuốc rồi" không phải câu hỏi lịch thuốc', async () => {
  const nlu: Nlu = async () => ({ intent: 'unsupported', recipient: '', content: '', feature: '', say: '' });
  const d = await step({ text: 'tôi uống thuốc rồi', state: {}, ui: { screen: '/', contacts: [], honorific: 'bác' } }, nlu);
  assert.notEqual(d.intent, 'read_meds');
});

test('đã có màn Thuốc: "uống rồi" vẫn là nút Đã uống, còn "uống thuốc gì" là câu hỏi đọc lịch', async () => {
  const ctx = {
    role: 'elder' as const, route: '/bp', dialog: null, lists: [], player: { open: false, playing: false },
    controls: [{ id: 'meds.taken.x', label: 'Đã uống Túi Tối', aliases: ['tôi uống rồi', 'uống rồi'], kind: 'button' as const, level: 1 as const, enabled: true }],
  };
  const ui = { screen: '/bp', contacts: [], honorific: 'bác', context: ctx };
  const a = await step({ text: 'tôi uống rồi', state: {}, ui }, noNlu);
  assert.equal(a.intent, 'invoke_control');
  const b = await step({ text: 'hôm nay uống thuốc gì', state: {}, ui }, noNlu);
  assert.equal(b.intent, 'read_meds');
});

import { forgotQuery, markDoseQuery, snoozeDoseQuery } from '../_lib/voice/dm.ts';

test('forgotQuery: nhận câu hỏi quên cữ, không nhận câu khẳng định', () => {
  for (const s of ['hôm nay tôi có quên uống thuốc cữ nào không', 'tôi có quên cữ thuốc nào không', 'có bỏ sót cữ nào không', 'hôm nay tôi uống thuốc chưa', 'còn cữ nào chưa uống không']) {
    assert.equal(forgotQuery(norm(s)), true, s);
  }
  for (const s of ['tôi quên uống thuốc rồi', 'tôi uống thuốc rồi', 'mở thuốc', 'nhắn cho Lan là quên mang thuốc']) {
    assert.equal(forgotQuery(norm(s)), false, s);
  }
});

test('markDoseQuery / snoozeDoseQuery', () => {
  for (const s of ['uống rồi', 'tôi uống thuốc rồi', 'tôi uống rồi ạ', 'đã uống thuốc rồi', 'con uống xong rồi']) {
    assert.equal(markDoseQuery(norm(s)), true, s);
  }
  for (const s of ['tôi chưa uống thuốc', 'uống thuốc chưa', 'tôi uống thuốc gì', 'có uống rồi không']) {
    assert.equal(markDoseQuery(norm(s)), false, s);
  }
  for (const s of ['chưa uống', 'lát nữa tôi uống', 'nhắc lại sau']) assert.equal(snoozeDoseQuery(norm(s)), true, s);
  assert.equal(snoozeDoseQuery(norm('chưa uống thuốc gì cả')), false);
});

test('step: "hôm nay có quên cữ nào không" → read_meds forgot; "uống rồi" → mark_dose', async () => {
  const ui = { screen: '/', contacts: [], honorific: 'bác' };
  const a = await step({ text: 'hôm nay tôi có quên uống thuốc cữ nào không', state: {}, ui }, noNlu);
  assert.equal(a.intent, 'read_meds');
  assert.equal((a.task?.slots.content ?? '').toLowerCase(), 'forgot');
  const b = await step({ text: 'tôi uống thuốc rồi', state: {}, ui }, noNlu);
  assert.equal(b.intent, 'mark_dose');
  assert.equal(b.action, 'execute');
  const c = await step({ text: 'lát nữa tôi uống', state: {}, ui }, noNlu);
  assert.equal(c.intent, 'snooze_dose');
});
