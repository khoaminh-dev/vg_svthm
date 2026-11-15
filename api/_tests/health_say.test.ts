import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildHealthSay, topicOf, type BpRow, type HealthCtx } from '../_lib/voice/health_say.ts';
import { norm, step, healthTopic, type Nlu, type Ui } from '../_lib/voice/dm.ts';

const NOW = new Date('2026-11-15T03:00:00Z');
const daysAgo = (n: number) => new Date(NOW.getTime() - n * 86_400_000).toISOString();
const row = (s: number, d: number, ago: number): BpRow => ({ systolic: s, diastolic: d, measured_at: daysAgo(ago) });

const ctx = (p: Partial<HealthCtx> = {}): HealthCtx => ({
  hon: 'bác',
  now: NOW,
  readings: [],
  assessment: null,
  hasProfile: true,
  ...p,
});

test('chưa có số đo: mời đo, không bịa số', () => {
  for (const t of ['general', 'trend', 'risk', 'habit'] as const) {
    const r = buildHealthSay(t, ctx());
    assert.match(r.say, /chưa đo huyết áp lần nào/);
    assert.equal(r.systolic, null);
  }
});

test('câu hỏi y khoa chung: chỉ chỉ đường, không nói nội dung', () => {
  const r = buildHealthSay('other', ctx({ readings: [row(120, 80, 0)] }));
  assert.match(r.say, /hỏi bác sĩ/);
  assert.match(r.say, /115/);
  assert.doesNotMatch(r.say, /120/);
});

test('số đo rất cao và còn mới: luôn nói 115 trước, bất kể hỏi gì', () => {
  for (const t of ['general', 'trend', 'risk', 'habit'] as const) {
    const r = buildHealthSay(t, ctx({ readings: [row(190, 110, 0)] }));
    assert.match(r.say, /190 trên 110/);
    assert.match(r.say, /gọi 115/);
    assert.equal(r.sayClass, 'important');
  }
});

test('số đo rất cao nhưng đã cũ (>1 ngày): không báo khẩn như mới', () => {
  const r = buildHealthSay('general', ctx({ readings: [row(190, 110, 5)] }));
  assert.doesNotMatch(r.say, /gọi 115/);
  assert.match(r.say, /5 ngày trước/);
});

test('số đo cũ ≥3 ngày: nói rõ ngày đo và nhắc đo lại', () => {
  const r = buildHealthSay('general', ctx({ readings: [row(125, 82, 4)] }));
  assert.match(r.say, /4 ngày trước/);
  assert.match(r.say, /đo lại/);
});

test('tình trạng chung: số gần nhất + mức nguy cơ', () => {
  const r = buildHealthSay('general', ctx({ readings: [row(118, 78, 0)], assessment: { level: 'attention', reasons: [] } }));
  assert.match(r.say, /118 trên 78, bình thường/);
  assert.match(r.say, /cần chú ý/);
  assert.equal(r.level, 'attention');
});

test('xu hướng: ít hơn 2 lần đo thì chưa kết luận', () => {
  const r = buildHealthSay('trend', ctx({ readings: [row(130, 85, 0)] }));
  assert.match(r.say, /chưa thấy được xu hướng/);
});

test('xu hướng: trung bình 7 ngày và hướng tăng/giảm/ổn định', () => {
  // mới nhất trước: gần đây cao, cũ thấp → tăng
  const up = buildHealthSay('trend', ctx({ readings: [row(150, 95, 0), row(148, 94, 1), row(130, 84, 3), row(128, 82, 4)] }));
  assert.match(up.say, /4 lần/);
  assert.match(up.say, /trung bình 139 trên 89/);
  assert.match(up.say, /tăng/);
  const down = buildHealthSay('trend', ctx({ readings: [row(120, 80, 0), row(122, 80, 1), row(140, 90, 3), row(142, 90, 4)] }));
  assert.match(down.say, /giảm/);
  const flat = buildHealthSay('trend', ctx({ readings: [row(125, 82, 0), row(126, 82, 2), row(124, 81, 4), row(125, 82, 6)] }));
  assert.match(flat.say, /ổn định/);
});

test('xu hướng: lần đo ngoài 7 ngày không tính vào trung bình', () => {
  const r = buildHealthSay('trend', ctx({ readings: [row(120, 80, 0), row(122, 80, 2), row(190, 110, 20)] }));
  assert.match(r.say, /2 lần/);
  assert.match(r.say, /trung bình 121 trên 80/);
});

test('thói quen: đếm số lần trong 7 ngày', () => {
  const few = buildHealthSay('habit', ctx({ readings: [row(120, 80, 0), row(120, 80, 3)] }));
  assert.match(few.say, /đã đo 2 lần/);
  assert.match(few.say, /đo đều hơn/);
  const many = buildHealthSay('habit', ctx({ readings: [row(120, 80, 0), row(120, 80, 1), row(120, 80, 2), row(120, 80, 3)] }));
  assert.match(many.say, /đo rất đều/);
});

test('nguy cơ: chưa có hồ sơ / chưa có đánh giá', () => {
  assert.match(buildHealthSay('risk', ctx({ readings: [row(120, 80, 0)], hasProfile: false })).say, /nhập hồ sơ sức khoẻ/);
  assert.match(buildHealthSay('risk', ctx({ readings: [row(120, 80, 0)] })).say, /chưa có đánh giá/);
});

test('nguy cơ cao nhưng huyết áp bình thường: tách hai ý, không nghe mâu thuẫn', () => {
  const r = buildHealthSay(
    'risk',
    ctx({ readings: [row(118, 78, 0)], assessment: { level: 'high', reasons: ['hypertension', 'diabetes', 'prior_stroke'] } }),
  );
  assert.match(r.say, /118 trên 78 là bình thường, nhưng/);
  assert.match(r.say, /tăng huyết áp/);
  assert.match(r.say, /tiểu đường/);
  assert.doesNotMatch(r.say, /đột quỵ/, 'chỉ nêu tối đa 2 yếu tố');
  assert.match(r.say, /đi khám sớm/);
});

test('nguy cơ thấp: ngắn, không dọa; xưng hô theo người dùng', () => {
  const r = buildHealthSay('risk', ctx({ hon: 'cô', readings: [row(118, 78, 0)], assessment: { level: 'low', reasons: [] } }));
  assert.match(r.say, /Mức nguy cơ của cô đang thấp/);
  assert.doesNotMatch(r.say, /bác/);
});

test('không bao giờ bảo uống, bỏ hay đổi thuốc điều trị (nhắc "hút thuốc" là yếu tố nguy cơ thì được)', () => {
  const all: string[] = [];
  for (const t of ['general', 'trend', 'risk', 'habit', 'other'] as const) {
    for (const lv of ['low', 'attention', 'high']) {
      all.push(buildHealthSay(t, ctx({ readings: [row(150, 95, 0), row(130, 85, 2)], assessment: { level: lv, reasons: ['hypertension', 'smoker'] } })).say);
    }
  }
  for (const s of all) assert.doesNotMatch(s, /(uống|bỏ|ngừng|đổi|dùng|tên) thuốc(?! lá)/i);
});

test('topicOf: giá trị lạ về general', () => {
  assert.equal(topicOf('trend'), 'trend');
  assert.equal(topicOf('lạ'), 'general');
  assert.equal(topicOf(undefined), 'general');
});

test('nhận diện câu hỏi sức khoẻ bằng luật nhanh (không gọi LLM)', () => {
  const cases: [string, string | null][] = [
    ['Huyết áp tôi dạo này thế nào', 'trend'],
    ['dạo này huyết áp của bác sao rồi', 'trend'],
    ['Tôi có nguy hiểm không', 'risk'],
    ['nguy cơ của tôi thế nào', 'risk'],
    ['Tuần này tôi đo mấy lần', 'habit'],
    ['Tình trạng sức khoẻ của tôi', 'general'],
    ['tôi bị đau đầu có sao không', 'other'],
    ['mở nhạc xưa', null],
    ['nhắn cho con trai', null],
  ];
  for (const [text, want] of cases) assert.equal(healthTopic(norm(text)), want, text);
});

test('"huyết áp hôm nay bao nhiêu" vẫn đọc số cho app (read_bp), không bị cướp', async () => {
  const noNlu: Nlu = async () => { throw new Error('should not call'); };
  const ui: Ui = { screen: 'home', contacts: [], honorific: 'bác' };
  const a = await step({ text: 'huyết áp hôm nay bao nhiêu', state: {}, ui }, noNlu);
  assert.equal(a.intent, 'read_bp');
  const b = await step({ text: 'dạo này huyết áp của tôi thế nào', state: {}, ui }, noNlu);
  assert.equal(b.intent, 'health_status');
  assert.equal(b.action, 'execute');
  assert.equal(b.task?.slots.content?.toLowerCase(), 'trend');
});

test('đau ngực vẫn bị luật khẩn cấp bắt trước câu hỏi sức khoẻ', async () => {
  const noNlu: Nlu = async () => { throw new Error('should not call'); };
  const d = await step({ text: 'tôi đau ngực có sao không', state: {}, ui: { honorific: 'bác' } }, noNlu);
  assert.equal(d.intent, 'emergency');
});
