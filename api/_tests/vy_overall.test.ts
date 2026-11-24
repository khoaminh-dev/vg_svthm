import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setClock, step, type Contact, type Nlu, type Ui } from '../_lib/voice/dm.ts';
import { parseReminder, spokenTime, vnParts } from '../_lib/voice/daily.ts';
import { familyQuery } from '../_lib/voice/family.ts';
import { bpHistoryQuery, screenIntent, skipDoseQuery } from '../_lib/voice/nav.ts';

// Kế hoạch Vy tổng thể (docs/KE_HOACH_VY_TONG_THE.md) đợt 1–7. Bằng chữ, miễn phí, không LLM.

// 24/11/2026 09:05 giờ Việt Nam = 02:05 UTC (thứ ba)
const NOW = new Date('2026-11-24T02:05:00Z');
setClock(() => NOW);

const contacts: Contact[] = [
  { id: 'u1', kind: 'direct', name: 'Hùng', username: 'hung' },
  { id: 'u2', kind: 'direct', name: 'Lan', username: 'lan', aliases: ['con gai'] },
];
type Ctx = NonNullable<Ui['context']>;
const base: Ctx = { role: 'elder', route: '/', dialog: null, controls: [], lists: [], player: { open: false, playing: false } };
const ui = (ctx: Partial<Ctx> = {}): Ui => ({ screen: '/', contacts, honorific: 'bác', context: { ...base, ...ctx } });

async function go(text: string, ctx: Partial<Ctx> = {}, state = {}) {
  let llm = false;
  const nlu: Nlu = async () => {
    llm = true;
    return { intent: 'unsupported', recipient: '', content: '', feature: '', say: '' };
  };
  const d = await step({ text, state, ui: ui(ctx) }, nlu);
  return { d, llm };
}

// ================= ĐỢT 1: AN TOÀN =================

const EMERGENCY: string[] = [
  'tôi bị ngã', 'tôi bị ngã rồi', 'tôi té', 'tôi bị té', 'cứu tôi với', 'cứu với', 'cứu tôi', 'tôi sắp ngất', 'tôi muốn ngất', 'tối sầm mặt mày',
  'tôi bị đột quỵ', 'mặt tôi méo', 'miệng tôi méo', 'tay tôi yếu không nhấc được', 'chân tôi yếu', 'tôi liệt nửa người', 'tôi nói không rõ', 'tôi nói ngọng',
  'đau ngực', 'tôi đau ngực dữ dội', 'tôi khó thở', 'tôi không thở được', 'tôi thở không nổi', 'nghẹt thở', 'đau tim', 'nhồi máu cơ tim',
  'tim đập rất nhanh', 'tim đập mạnh quá', 'tôi bị ngất', 'bất tỉnh', 'chảy máu nhiều', 'tôi nôn ra máu', 'ho ra máu', 'đi ngoài ra máu',
  'có người ngã', 'mẹ tôi ngã rồi', 'tôi muốn chết', 'tôi không muốn sống nữa', 'cấp cứu', 'tôi cần cấp cứu',
];
for (const text of EMERGENCY) {
  test(`khẩn cấp: "${text}" → báo ngay, có nút Gọi 115 và Báo SOS, không đọc số liệu`, async () => {
    const { d, llm } = await go(text);
    assert.equal(llm, false);
    assert.equal(d.intent, 'emergency', text);
    assert.equal(d.sayClass, 'emergency');
    assert.deepEqual(d.chips, ['Gọi 115', 'Báo SOS']);
    assert.match(d.say, /^[A-ZÀ-Ỹ]/, 'câu mở đầu viết hoa');
    assert.match(d.say, /115/);
  });
}

test('không báo động nhầm câu hỏi, đọc số liệu, tin nhắn', async () => {
  const calm: [string, string][] = [
    ['tôi có nguy cơ đột quỵ không', 'health_status'],
    ['huyết áp hôm nay bao nhiêu', 'read_bp'],
    ['đo huyết áp', 'measure_bp'],
    ['ăn gì tốt cho tim mạch', 'health_status'],
  ];
  for (const [text, intent] of calm) {
    const { d } = await go(text);
    assert.equal(d.intent, intent, text);
  }
});

test('"gọi 115" và "gọi cấp cứu" quay số có đếm ngược, không đọc một đoạn khuyên', async () => {
  for (const text of ['gọi 115', 'gọi cấp cứu', 'gọi xe cấp cứu', 'bấm gọi cấp cứu', 'gọi cấp cứu đi', 'quay số cấp cứu']) {
    const { d, llm } = await go(text);
    assert.equal(llm, false, text);
    assert.equal(d.intent, 'call_contact', text);
    assert.equal(d.task?.slots.recipient_text, '115', text);
  }
});

const SOFT = ['tôi mệt lắm', 'tôi choáng quá', 'tôi xây xẩm', 'hơi choáng váng', 'tôi khó chịu lắm', 'tôi chóng mặt dữ dội'];
for (const text of SOFT) {
  test(`dấu hiệu mơ hồ: "${text}" → hỏi MỘT câu có hai nút, chưa báo động`, async () => {
    const { d } = await go(text);
    assert.equal(d.intent, 'emergency_check', text);
    assert.equal(d.action, 'confirm');
    assert.deepEqual(d.chips, ['Có, giúp con', 'Không sao']);
    assert.equal((d.say.match(/\?/g) ?? []).length, 2, 'đúng hai ý hỏi, không dồn');
  });
}

test('trả lời câu hỏi mơ hồ: "có" thì báo động, "không sao" thì dịu lại', async () => {
  const q = (await go('tôi mệt lắm')).d;
  const st = { task: q.task, pending: q.pending, expects: q.expects };
  for (const yes of ['có', 'Có, giúp con', 'giúp con', 'gọi đi', 'báo đi']) {
    const { d } = await go(yes, {}, st);
    assert.equal(d.intent, 'emergency', yes);
  }
  for (const no of ['không sao', 'không', 'bình thường', 'tôi ổn rồi']) {
    const { d } = await go(no, {}, st);
    assert.equal(d.intent, 'chitchat', no);
    assert.match(d.say, /nghỉ ngơi/);
  }
  // nói việc khác thì coi là lệnh mới
  const other = await go('đo huyết áp', {}, st);
  assert.equal(other.d.intent, 'measure_bp');
});

test('đang soạn tin nhắn có chữ "mệt lắm" thì không bị ngắt giữa chừng', async () => {
  const { d } = await go('nhắn cho Lan là bác mệt lắm');
  assert.notEqual(d.intent, 'emergency_check');
  assert.notEqual(d.intent, 'emergency');
  assert.equal(d.intent, 'send_message');
});

const MED_DANGER: [string, RegExp, boolean][] = [
  ['tôi uống nhầm thuốc', /đừng tự xử lý/, true],
  ['uống gấp đôi liều được không', /đừng tự xử lý/, true],
  ['tôi lỡ uống hai lần', /đừng tự xử lý/, true],
  ['uống quá liều', /đừng tự xử lý/, true],
  ['tôi quên uống thuốc', /đừng uống gấp đôi/, false],
  ['tôi lỡ quên thuốc sáng nay', /đừng uống gấp đôi/, false],
  ['hết thuốc rồi', /đừng tự bỏ thuốc/, false],
  ['sắp hết thuốc', /đừng tự bỏ thuốc/, false],
  ['tôi có nên bỏ thuốc huyết áp không', /đừng tự ý ngưng hay bỏ thuốc/, false],
  ['tôi muốn ngưng thuốc', /đừng tự ý ngưng hay bỏ thuốc/, false],
  ['tác dụng phụ của thuốc', /không tư vấn thuốc/, false],
  ['thuốc này uống thế nào', /không tư vấn thuốc/, false],
];
for (const [text, re, hasCall] of MED_DANGER) {
  test(`thuốc nguy hiểm: "${text}" → kịch bản an toàn, không khuyên liều`, async () => {
    const { d, llm } = await go(text);
    assert.equal(llm, false);
    assert.equal(d.intent, 'chitchat', text);
    assert.match(d.say, re);
    assert.equal(d.sayClass, 'important');
    assert.equal(/115/.test(d.say), hasCall, '115 chỉ xuất hiện khi có nguy cơ quá liều');
    // không bao giờ tự đưa ra con số liều hay lời khuyên uống thêm
    assert.doesNotMatch(d.say, /uống thêm|nên uống \d|tăng liều|giảm liều|\d+ viên/);
  });
}

test('câu HỎI về lịch ("có quên cữ nào không") vẫn đọc lịch thuốc, không bị kịch bản nuốt', async () => {
  const { d } = await go('hôm nay tôi có quên uống thuốc cữ nào không');
  assert.equal(d.intent, 'read_meds');
});

// ================= ĐỢT 2: HIỂU SAI =================

test('"nhắc tôi đo huyết áp lúc 8 giờ" là đặt nhắc, KHÔNG mở màn đo', async () => {
  const { d } = await go('nhắc tôi đo huyết áp lúc 8 giờ');
  assert.equal(d.intent, 'set_reminder');
  const [ms, what] = (d.task?.slots.content ?? '').split('|');
  assert.equal(what, 'đo huyết áp');
  // 9:05 sáng đã qua 8 giờ sáng: lần gần nhất là 20:00 tối nay
  assert.equal(Number(ms), Date.parse('2026-11-24T13:00:00Z'));
});

test('"huyết áp bao nhiêu là cao" trả lời ngưỡng, không đọc số đo của người dùng', async () => {
  for (const text of ['huyết áp bao nhiêu là cao', 'huyết áp bao nhiêu thì nguy hiểm', 'huyết áp bình thường là bao nhiêu', 'mức huyết áp bình thường']) {
    const { d } = await go(text);
    assert.equal(d.intent, 'chitchat', text);
    assert.match(d.say, /120 trên 80/);
    assert.match(d.say, /180 trên 120/);
    assert.match(d.say, /hỏi bác sĩ/);
    assert.doesNotMatch(d.say, /lần đo gần nhất/);
  }
});

test('"tôi nên đo huyết áp lúc nào" trả lời cách đo chuẩn', async () => {
  const { d } = await go('tôi nên đo huyết áp lúc nào');
  assert.equal(d.intent, 'chitchat');
  assert.match(d.say, /sáng sau khi ngủ dậy/);
  assert.match(d.say, /5 phút/);
});

test('"nhắn cho cô Hoa": họ hàng + tên là một người nhận, không tách "cô" và "Hoa"', async () => {
  const a = await go('nhắn cho cô Hoa');
  assert.equal(a.d.intent, 'send_message');
  assert.equal(a.d.task?.slots.recipient_text, 'cô Hoa');
  assert.match(a.d.say, /cô Hoa/);
  const b = await go('nhắn cho chú Ba mai bác ghé chơi');
  assert.equal(b.d.task?.slots.recipient_text, 'chú Ba');
  assert.equal(b.d.task?.slots.content, 'Mai bác ghé chơi');
  // tên có trong danh bạ thì dùng đúng danh bạ
  const c = await go('nhắn cho con Lan mai về ăn cơm');
  assert.equal(c.d.task?.slots.room_id, 'u2');
  assert.equal(c.d.task?.slots.content, 'Mai về ăn cơm');
});

test('"gửi ảnh cho con": nói thật chưa gửi ảnh bằng giọng được, chỉ đường tới khung chat', async () => {
  for (const text of ['gửi ảnh cho con', 'gửi hình cho Lan', 'nhắn ảnh cho con gái', 'gửi video cho con']) {
    const { d, llm } = await go(text);
    assert.equal(llm, false, text);
    assert.equal(d.intent, 'chitchat', text);
    assert.match(d.say, /chưa gửi ảnh hay video bằng giọng/);
    assert.deepEqual(d.chips, ['Mở tin nhắn']);
  }
});

test('"gửi lại" không đoán người nhận: hỏi người nhận', async () => {
  const { d } = await go('gửi lại');
  assert.equal(d.intent, 'send_message');
  assert.equal(d.action, 'ask');
  assert.equal(d.pending, 'recipient');
});

test('"trả lời Lan là dạ" là một tin nhắn thường', async () => {
  const { d } = await go('trả lời Lan là dạ');
  assert.equal(d.intent, 'send_message');
  assert.equal(d.task?.slots.room_id, 'u2');
  assert.equal(d.task?.slots.content, 'Dạ');
  assert.equal(d.action, 'confirm');
});

// ================= ĐỢT 3: HẰNG NGÀY =================

test('giờ, ngày, thứ (giờ Việt Nam, không cần mạng)', async () => {
  const t = await go('mấy giờ rồi');
  assert.equal(t.d.intent, 'chitchat');
  assert.equal(t.d.say, 'Dạ, bây giờ là 9 giờ 5 phút sáng ạ.');
  for (const text of ['bây giờ là mấy giờ', 'giờ mấy rồi', 'cho tôi biết giờ']) {
    assert.match((await go(text)).d.say, /9 giờ 5 phút sáng/, text);
  }
  for (const text of ['hôm nay thứ mấy', 'hôm nay là thứ mấy', 'hôm nay ngày bao nhiêu', 'hôm nay là ngày mấy']) {
    assert.equal((await go(text)).d.say, 'Dạ, hôm nay là thứ ba, ngày 24 tháng 11 năm 2026 ạ.', text);
  }
});

test('đọc giờ đúng buổi', () => {
  assert.equal(spokenTime(0, 10), '12 giờ 10 phút đêm');
  assert.equal(spokenTime(6, 30), '6 giờ rưỡi sáng');
  assert.equal(spokenTime(12, 0), '12 giờ trưa');
  assert.equal(spokenTime(15, 45), '3 giờ 45 phút chiều');
  assert.equal(spokenTime(19, 0), '7 giờ tối');
  assert.equal(spokenTime(23, 5), '11 giờ 5 phút đêm');
  // 18:30 UTC ngày 23 = 01:30 ngày 24 giờ Việt Nam
  const p = vnParts(new Date('2026-11-23T18:30:00Z'));
  assert.deepEqual([p.d, p.h, p.mi, p.wd], [24, 1, 30, 2]);
});

test('thời tiết: nói thật là chưa xem được', async () => {
  for (const text of ['thời tiết hôm nay', 'hôm nay có mưa không', 'trời có nắng không']) {
    const { d } = await go(text);
    assert.equal(d.intent, 'chitchat', text);
    assert.match(d.say, /chưa xem được thời tiết/);
  }
});

const REMINDERS: [string, string, string][] = [
  // [câu nói, giờ (UTC ISO), việc]
  ['nhắc tôi 8 giờ sáng mai đi khám', '2026-11-25T01:00:00Z', 'đi khám'],
  ['nhắc tôi đi khám lúc 8 giờ sáng mai', '2026-11-25T01:00:00Z', 'đi khám'],
  ['nhắc tôi 3 giờ chiều nay uống thuốc', '2026-11-24T08:00:00Z', 'uống thuốc'],
  ['nhắc tôi tối nay 7 giờ gọi cho con', '2026-11-24T12:00:00Z', 'gọi cho con'],
  ['nhắc tôi 7 giờ rưỡi tối uống thuốc', '2026-11-24T12:30:00Z', 'uống thuốc'],
  ['nhắc tôi 10 giờ 15 đi chợ', '2026-11-24T03:15:00Z', 'đi chợ'],
  ['nhắc tôi sau 30 phút uống thuốc', '2026-11-24T02:35:00Z', 'uống thuốc'],
  ['nhắc tôi nửa tiếng nữa tắt bếp', '2026-11-24T02:35:00Z', 'tắt bếp'],
  ['nhắc tôi 2 tiếng nữa gọi điện', '2026-11-24T04:05:00Z', 'gọi điện'],
  ['nhắc tôi ngày mai 6h30 tập dưỡng sinh', '2026-11-24T23:30:00Z', 'tập dưỡng sinh'],
  ['nhắc tôi 12 giờ trưa ăn cơm', '2026-11-24T05:00:00Z', 'ăn cơm'],
];
for (const [text, iso, what] of REMINDERS) {
  test(`nhắc giờ: "${text}" → ${iso}`, async () => {
    const r = parseReminder(text, NOW);
    assert.ok(r && 'at' in r, text);
    assert.equal(new Date((r as { at: number }).at).toISOString().slice(0, 16), iso.slice(0, 16));
    assert.equal((r as { what: string }).what, what);
    const { d, llm } = await go(text);
    assert.equal(llm, false);
    assert.equal(d.intent, 'set_reminder');
  });
}

test('báo thức: "đặt báo thức 6 giờ sáng" là sáng mai (6 giờ sáng nay đã qua)', () => {
  const r = parseReminder('đặt báo thức 6 giờ sáng', NOW);
  assert.ok(r && 'at' in r);
  assert.equal(new Date((r as { at: number }).at).toISOString().slice(0, 16), '2026-11-24T23:00');
});

test('nhắc giờ thiếu giờ thì hỏi lại; không nhầm "nhạc", "bảo con", "hẹn giờ tắt nhạc"', async () => {
  const a = await go('nhắc tôi đi khám');
  assert.equal(a.d.intent, 'chitchat');
  assert.match(a.d.say, /lúc mấy giờ/);
  assert.equal(parseReminder('nhạc xưa', NOW), null);
  assert.equal(parseReminder('nhạc tôi hay nghe', NOW), null);
  assert.equal(parseReminder('bảo con gái gọi lại cho mẹ', NOW), null);
  assert.equal(parseReminder('hẹn giờ tắt nhạc sau 30 phút', NOW), null);
  assert.equal(parseReminder('nhắc lại tin nhắn', NOW), null);
  const b = await go('bảo con gái gọi lại cho mẹ');
  assert.equal(b.d.intent, 'send_message');
});

test('cỡ chữ bằng giọng', async () => {
  for (const text of ['tăng cỡ chữ', 'chữ to lên', 'phóng to chữ', 'chữ nhỏ quá', 'tôi không đọc được chữ']) {
    assert.equal((await go(text)).d.task?.slots.content?.toLowerCase(), 'font_up', text);
  }
  for (const text of ['giảm cỡ chữ', 'chữ nhỏ lại', 'chữ to quá', 'thu nhỏ chữ']) {
    assert.equal((await go(text)).d.task?.slots.content?.toLowerCase(), 'font_down', text);
  }
});

test('tâm sự, danh tính, khen: trả lời ấm áp, không "chưa làm được"', async () => {
  const cases: [string, RegExp][] = [
    ['bạn tên gì', /con là Vy/],
    ['bạn là ai', /con là Vy/],
    ['bạn bao nhiêu tuổi', /không có tuổi/],
    ['bạn có khoẻ không', /con khoẻ ạ/],
    ['Vy giỏi quá', /cảm ơn/],
    ['tôi thương bạn lắm', /cảm ơn/],
  ];
  for (const [text, re] of cases) {
    const { d, llm } = await go(text);
    assert.equal(llm, false, text);
    assert.equal(d.intent, 'chitchat', text);
    assert.match(d.say, re, text);
    assert.doesNotMatch(d.say, /chưa làm được/);
  }
  assert.equal((await go('kể chuyện cười')).d.task?.slots.content, 'Hài kịch');
  assert.match((await go('kể chuyện')).d.task?.slots.content ?? '', /Truyện đêm khuya/i);
});

test('"giúp tôi với" hỏi cần gì, có nút gọi 115; không phải lời từ chối', async () => {
  const { d } = await go('giúp tôi với');
  assert.equal(d.intent, 'chitchat');
  assert.match(d.say, /cần giúp gì/);
  assert.match(d.say, /cứu tôi/);
  assert.ok(d.chips.includes('Gọi 115'));
});

test('việc ngoài khả năng: lời từ chối có gợi ý chạm được', async () => {
  const { d } = await go('đặt vé máy bay giúp tôi');
  assert.equal(d.action, 'unsupported');
  assert.match(d.say, /đo huyết áp, mở nhạc xưa, đọc tin nhắn/);
  assert.deepEqual(d.chips, ['Đo huyết áp', 'Mở nhạc xưa', 'Đọc tin nhắn']);
});

// ================= ĐỢT 4: ĐIỀU HƯỚNG TOÀN CỤC =================

const SCREENS: [string, string][] = [
  ['mở cộng đồng', 'community'], ['vào cộng đồng', 'community'], ['cho tôi xem cộng đồng', 'community'], ['coi cộng đồng', 'community'],
  ['mở trang cá nhân', 'profile'], ['mở cài đặt', 'profile'], ['mở tài khoản của tôi', 'profile'], ['mở hồ sơ', 'profile'], ['xem thông tin của tôi', 'profile'],
  ['mở thẻ y tế', 'emergency_card'], ['xem thẻ khẩn cấp', 'emergency_card'], ['mở hồ sơ y tế', 'emergency_card'],
  ['mời người thân', 'family_invite'], ['thêm người thân', 'family_invite'], ['mở mời người thân', 'family_invite'],
  ['mở lịch thuốc', 'meds_plans'], ['sửa lịch thuốc', 'meds_plans'], ['đổi giờ uống thuốc', 'meds_plans'], ['xem danh sách thuốc', 'meds_plans'], ['mở đơn thuốc', 'meds_plans'],
  ['chụp đơn thuốc', 'meds_scan'], ['quét đơn thuốc', 'meds_scan'], ['thêm thuốc mới', 'meds_scan'],
  ['xem lịch sử sức khoẻ', 'health_history'], ['mở hồ sơ sức khoẻ', 'health_profile'],
];
for (const [text, key] of SCREENS) {
  test(`mở màn từ bất cứ đâu: "${text}" → ${key}`, async () => {
    const { d, llm } = await go(text);
    assert.equal(llm, false);
    assert.equal(d.intent, 'open_screen', text);
    assert.equal(d.task?.slots.content?.toLowerCase(), key, text);
    if (!text.startsWith('coi ')) assert.equal(screenIntent(text.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').toLowerCase()), key);
  });
}

test('"xem cảnh báo": với người cao tuổi không phải mở màn; với người thân là hỏi cảnh báo', async () => {
  const elder = await go('xem cảnh báo');
  assert.notEqual(elder.d.intent, 'open_screen');
  const fam = await go('xem cảnh báo', { role: 'family' });
  assert.equal(fam.d.intent, 'family_info');
  assert.equal(fam.d.task?.slots.content?.toLowerCase(), 'alerts|');
});

test('mở màn không cướp lệnh khác', async () => {
  const cases: [string, string][] = [
    ['mở huyết áp', 'show_bp'], ['mở tin nhắn', 'open_feature'], ['mở giải trí', 'open_feature'],
    ['tối nay uống thuốc gì', 'read_meds'], ['mở nhạc xưa', 'play_video'], ['mở tin tức', 'play_video'], ['quay lại', 'go_back'],
  ];
  for (const [text, intent] of cases) assert.equal((await go(text)).d.intent, intent, text);
});

// ================= ĐỢT 5: THUỐC VÀ HUYẾT ÁP BẰNG GIỌNG =================

test('bỏ qua cữ thuốc: hỏi lại trước khi ghi; đồng ý mới làm; app tự nói kết quả thật', async () => {
  for (const text of ['bỏ qua cữ này', 'bỏ qua cữ thuốc này', 'cữ này khỏi uống', 'hôm nay không uống cữ này', 'không uống lần này']) {
    assert.equal(skipDoseQuery(text.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').toLowerCase()), true, text);
  }
  const q = (await go('bỏ qua cữ này')).d;
  assert.equal(q.action, 'confirm');
  assert.equal(q.intent, 'skip_dose');
  assert.deepEqual(q.chips, ['Đúng', 'Không']);
  const st = { task: q.task, pending: q.pending, expects: q.expects };
  const yes = (await go('đúng', {}, st)).d;
  assert.equal(yes.action, 'execute');
  assert.equal(yes.intent, 'skip_dose');
  assert.equal(yes.say, '', 'app nói kết quả thật, không nói trước');
  const no = (await go('không', {}, st)).d;
  assert.equal(no.action, 'cancel');
});

const BPH: [string, string][] = [
  ['số đo hôm qua', 'yesterday'], ['huyết áp hôm qua', 'yesterday'], ['huyết áp hôm qua thế nào', 'yesterday'], ['hôm qua tôi đo bao nhiêu', 'yesterday'],
  ['trung bình huyết áp một tuần', 'week_avg'], ['huyết áp trung bình 7 ngày', 'week_avg'], ['huyết áp trung bình tuần này', 'week_avg'],
  ['huyết áp cao nhất tuần này', 'week_max'], ['lần đo cao nhất', 'week_max'],
  ['huyết áp thấp nhất tuần này', 'week_min'],
  ['mấy lần đo gần đây', 'recent'], ['3 lần đo gần nhất', 'recent'],
];
for (const [text, mode] of BPH) {
  test(`lịch sử huyết áp: "${text}" → ${mode}`, async () => {
    const { d, llm } = await go(text);
    assert.equal(llm, false);
    assert.equal(d.intent, 'read_bp', text);
    assert.equal(d.task?.slots.content?.toLowerCase().replace(/_/g, '_'), mode, text);
    assert.equal(bpHistoryQuery(text.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').toLowerCase().replace(/ the nao$/, '')), mode);
  });
}

test('"huyết áp hôm nay bao nhiêu" vẫn đọc số gần nhất (không có chế độ)', async () => {
  const { d } = await go('huyết áp hôm nay bao nhiêu');
  assert.equal(d.intent, 'read_bp');
  assert.ok(!d.task?.slots.content);
});

// ================= ĐỢT 6: VY CHO NGƯỜI THÂN =================

const FAM: [string, string, string][] = [
  ['huyết áp của mẹ thế nào', 'bp', 'me'],
  ['huyết áp của ba hôm nay', 'bp', 'ba'],
  ['huyết áp của bà Lan', 'bp', 'ba lan'],
  ['mẹ đo huyết áp chưa', 'bp', 'me'],
  ['mẹ uống thuốc chưa', 'meds', 'me'],
  ['ba đã uống thuốc chưa', 'meds', 'ba'],
  ['mẹ uống thuốc hôm nay chưa', 'meds', 'me'],
  ['thuốc của mẹ', 'meds', 'me'],
  ['mẹ có ổn không', 'overall', 'me'],
  ['ba khoẻ không', 'overall', 'ba'],
  ['tình hình của mẹ', 'overall', 'me'],
  ['sức khoẻ của ba', 'overall', 'ba'],
  ['xem cảnh báo', 'alerts', ''],
  ['có cảnh báo gì mới không', 'alerts', ''],
  ['có chuyện gì không', 'alerts', ''],
];
for (const [text, topic, subject] of FAM) {
  test(`người thân hỏi: "${text}" → ${topic} / ${subject || '(không ai cụ thể)'}`, async () => {
    const { d, llm } = await go(text, { role: 'family' });
    assert.equal(llm, false);
    assert.equal(d.intent, 'family_info', text);
    assert.equal(d.task?.slots.content?.toLowerCase(), `${topic}|${subject}`, text);
  });
}

test('người thân hỏi về chính mình thì đi đường cũ; người cao tuổi hỏi "mẹ…" không bị đổi nghĩa', async () => {
  for (const [text, intent] of [['huyết áp hôm nay của tôi', 'read_bp'], ['tôi uống thuốc chưa', 'read_meds'], ['huyết áp hôm nay bao nhiêu', 'read_bp']] as const) {
    const { d } = await go(text, { role: 'family' });
    assert.equal(d.intent, intent, text);
  }
  const elder = await go('mẹ uống thuốc chưa', { role: 'elder' });
  assert.notEqual(elder.d.intent, 'family_info');
  assert.equal(familyQuery('huyet ap cua toi'), null);
  assert.equal(familyQuery('huyet ap cua minh'), null);
});

// ================= ĐỢT 7: TRÍ NHỚ HỘI THOẠI =================

test('vừa nghe tin của Lan: "trả lời" và "trả lời là dạ" trả lời đúng người đó', async () => {
  const withLast: Partial<Ctx> = { last: { replyTo: 'Lan' } };
  const a = await go('trả lời', withLast);
  assert.equal(a.d.intent, 'send_message');
  assert.equal(a.d.task?.slots.room_id, 'u2');
  assert.equal(a.d.pending, 'content');
  const b = await go('trả lời là dạ', withLast);
  assert.equal(b.d.task?.slots.room_id, 'u2');
  assert.equal(b.d.task?.slots.content, 'Dạ');
  assert.equal(b.d.action, 'confirm');
  const c = await go('trả lời rằng bác sắp về', withLast);
  assert.equal(c.d.task?.slots.content, 'Bác sắp về');
  const d2 = await go('trả lời dạ', withLast);
  assert.equal(d2.d.task?.slots.content, 'Dạ');
  // không nhớ gì thì không đoán người nhận
  const e = await go('trả lời');
  assert.notEqual(e.d.task?.slots.room_id, 'u2');
});

test('nói tên người khác thì không bị trí nhớ ghi đè', async () => {
  const { d } = await go('trả lời Hùng là bác khoẻ', { last: { replyTo: 'Lan' } });
  assert.equal(d.task?.slots.room_id, 'u1');
});

test('ngữ cảnh "last" gửi lên bị cắt gọn và lọc', async () => {
  const { parseUiContext } = await import('../_lib/voice/ui_cmd.ts');
  assert.equal(parseUiContext({ last: { replyTo: 'Lan' } })?.last?.replyTo, 'Lan');
  assert.equal(parseUiContext({ last: { replyTo: 'x'.repeat(200) } })?.last?.replyTo.length, 60);
  assert.equal(parseUiContext({ last: { replyTo: '' } })?.last, undefined);
  assert.equal(parseUiContext({ last: 'bậy' })?.last, undefined);
});
