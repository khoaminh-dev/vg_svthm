import { test } from 'node:test';
import assert from 'node:assert/strict';
import { step, norm, type Contact, type Nlu, type Ui } from '../_lib/voice/dm.ts';

// Kiểm thử bằng CHỮ, miễn phí: người cao tuổi nói gì về giải trí thì Vy phải ra đúng việc, và không gọi LLM khi luật đủ.
// Danh mục tình huống: docs/KE_HOACH_VY_GIAI_TRI.md mục 4.

const contacts: Contact[] = [
  { id: 'u1', kind: 'direct', name: 'Nguyễn Văn Hùng', username: 'hung' },
  { id: 'u2', kind: 'direct', name: 'Lan', username: 'lan', aliases: ['con gai'] },
];
const ui: Ui = { screen: 'home', contacts, honorific: 'bác' };

async function route(text: string) {
  let llm = false;
  const nlu: Nlu = async () => {
    llm = true;
    return { intent: 'unsupported', recipient: '', content: '', feature: '', say: '' };
  };
  const d = await step({ text, state: {}, ui }, nlu);
  return { d, llm };
}

const GENERAL = ['Nhạc xưa', 'Hài kịch', 'Tin tức'];
const DEFAULT_ASK = ['Nhạc xưa', 'Tin tức', 'Cải lương'];
const MOOD = ['Hài kịch', 'Nhạc xưa', 'Thiền thư giãn'];
const MUSIC = ['Nhạc xưa', 'Nhạc trữ tình', 'Nhạc không lời'];
const SLEEP = ['Nhạc ru ngủ', 'Truyện đêm khuya', 'Thiền thư giãn'];

// [câu nói, từ khoá tìm (không dấu)]
const PLAY: [string, string][] = [
  ['mở nhạc xưa', 'nhac xua'],
  ['cho tôi nghe nhạc xưa', 'nhac xua'],
  ['bật nhạc xưa lên', 'nhac xua'],
  ['mở nhạc vàng', 'nhac vang'],
  ['nghe nhạc trữ tình', 'nhac tru tinh'],
  ['cho bác nghe bolero', 'bolero'],
  ['mở bolero', 'bolero'],
  ['nghe nhạc Trịnh', 'nhac trinh cong son'],
  ['mở nhạc Trịnh Công Sơn', 'nhac trinh cong son'],
  ['nghe nhạc quê hương', 'nhac que huong'],
  ['mở nhạc cách mạng', 'nhac cach mang'],
  ['mở nhạc thiếu nhi', 'nhac thieu nhi'],
  ['bật nhạc không lời', 'nhac khong loi'],
  ['mở nhạc piano', 'nhac khong loi'],
  ['bật nhạc ru ngủ', 'nhac ru ngu'],
  ['mở nhạc để ngủ', 'nhac ru ngu'],
  ['mở nhạc thiền', 'nhac thien'],
  ['nghe nhạc nhẹ nhàng', 'nhac thien'],
  ['mở thiền', 'thien thu gian'],
  ['cho nghe thiền', 'thien thu gian'],
  ['mở thiền thư giãn', 'thien thu gian'],
  ['tập dưỡng sinh', 'bai tap duong sinh nguoi lon tuoi'],
  ['mở bài tập dưỡng sinh', 'bai tap duong sinh nguoi lon tuoi'],
  ['tập thể dục', 'bai tap duong sinh nguoi lon tuoi'],
  ['mở yoga', 'yoga cho nguoi cao tuoi'],
  ['xem thái cực quyền', 'thai cuc quyen nguoi cao tuoi'],
  ['mở cải lương', 'cai luong'],
  ['xem cải lương', 'cai luong'],
  ['mở cải lương Lệ Thủy', 'cai luong le thuy'],
  ['cho nghe cải lương Minh Vương', 'cai luong minh vuong'],
  ['mở tuồng', 'tuong co'],
  ['mở chèo', 'cheo co'],
  ['xem hài', 'hai kich'],
  ['mở hài kịch', 'hai kich'],
  ['xem tiểu phẩm hài', 'hai kich'],
  ['xem hài Hoài Linh', 'hai kich hoai linh'],
  ['mở phim bộ', 'phim bo'],
  ['xem phim Việt Nam', 'phim viet nam'],
  ['mở phim hoạt hình', 'phim hoat hinh thieu nhi'],
  ['mở karaoke', 'karaoke nhac xua'],
  ['mở karaoke nhạc vàng', 'karaoke nhac vang'],
  ['xem tin tức', 'tin tuc'],
  ['mở tin tức hôm nay', 'tin tuc hom nay'],
  ['cho nghe thời sự', 'tin tuc'],
  ['xem bản tin 19 giờ', 'tin tuc 19 gio'],
  ['xem bóng đá', 'bong da'],
  ['xem đá banh hôm qua', 'bong da hom qua'],
  ['mở ngoại hạng anh', 'ngoai hang anh'],
  ['nghe kinh Phật', 'kinh phat'],
  ['mở kinh', 'kinh phat'],
  ['bật kinh A Di Đà', 'kinh a di da'],
  ['mở kinh Quan Thế Âm', 'kinh quan the am'],
  ['nghe truyện', 'truyen dem khuya'],
  ['nghe truyện đêm khuya', 'truyen dem khuya'],
  ['đọc truyện Kiều', 'truyen kieu'],
  ['nghe sách nói', 'sach noi'],
  ['mở đài', 'dai phat thanh vov'],
  ['nghe radio', 'dai phat thanh vov'],
  ['nghe đài', 'dai phat thanh vov'],
  ['xem nấu ăn', 'day nau an mon ngon'],
  // ngủ
  ['mở cho tôi cái gì ru ngủ', 'nhac ru ngu'],
  ['cho nghe gì dễ ngủ', 'nhac ru ngu'],
  ['mở nhạc cho dễ ngủ', 'nhac ru ngu'],
  ['bật gì cho ngủ ngon', 'nhac ru ngu'],
  // có tên bài / ca sĩ cụ thể: đi đường tìm thẳng
  ['mở bài Nối vòng tay lớn', 'noi vong tay lon'],
  ['nghe Khánh Ly hát', 'khanh ly hat'],
  ['mở bài Đường chiều của Khánh Ly', 'duong chieu cua khanh ly'],
  ['cho bác nghe bài Đường chiều', 'duong chieu'],
  ['nghe Tuấn Vũ', 'tuan vu'],
  ['mở video con mèo', 'con meo'],
  ['mở bài hát của Trịnh Công Sơn', 'trinh cong son'],
  ['nghe nhạc Khánh Ly', 'nhac khanh ly'],
  ['phát video hài Hoài Linh', 'hai kich hoai linh'],
  ['mở bài của Tuấn Vũ', 'tuan vu'],
];

// [câu nói, gợi ý Vy đưa ra]
const ASK: [string, string[]][] = [
  ['mở nhạc', DEFAULT_ASK],
  ['bật nhạc lên', DEFAULT_ASK],
  ['mở bài đó đi', DEFAULT_ASK],
  ['xem phim', DEFAULT_ASK],
  ['cho nghe nhạc', DEFAULT_ASK],
  ['tôi muốn nghe nhạc', DEFAULT_ASK],
  ['mở video', DEFAULT_ASK],
  ['mở bài hát tôi hay nghe', DEFAULT_ASK], // chưa có thói quen thì hỏi
  ['mở nhạc như hôm qua', DEFAULT_ASK],
  ['mở cái gì vui vui', GENERAL],
  ['nghe gì đó', GENERAL],
  ['xem gì hay hay', GENERAL],
  ['cho tôi nghe cái gì đi', GENERAL],
  ['mở gì đi', GENERAL],
  ['bật cái gì cũng được', GENERAL],
  ['hôm nay có gì hay', GENERAL],
  ['có gì xem không', GENERAL],
  ['có chương trình gì hay không', GENERAL],
  ['có gì mới không', GENERAL],
  ['tối nay có phim gì xem', GENERAL],
  ['chán quá', MOOD],
  ['buồn quá', MOOD],
  ['tôi buồn quá', MOOD],
  ['bác thấy cô đơn', MOOD],
  ['nhớ nhà quá', MOOD],
  ['không vui', MOOD],
  ['chán quá mở cái gì đi', MOOD],
  ['buồn quá mở nhạc đi', MUSIC],
  ['khó ngủ quá', SLEEP],
  ['không ngủ được', SLEEP],
];

// [câu nói, nội dung lệnh]
const CTL: [string, string][] = [
  ['dừng lại', 'pause'], ['tạm dừng', 'pause'], ['tắt nhạc đi', 'pause'],
  ['tiếp tục', 'play'], ['bài khác', 'next'], ['chuyển bài', 'next'], ['bài trước', 'previous'],
  ['to lên', 'louder'], ['to tiếng lên', 'louder'], ['nhỏ tiếng chút', 'quieter'], ['nhỏ bớt', 'quieter'],
  ['tua lại', 'back:15'], ['lùi lại 30 giây', 'back:30'], ['tua tới 1 phút', 'fwd:60'],
  ['phát lại từ đầu', 'restart'], ['nghe lại từ đầu', 'restart'],
  ['tắt video', 'close'], ['đóng video', 'close'],
  ['hẹn giờ tắt nhạc sau 45 phút', 'sleep:45'], ['hẹn giờ tắt', 'sleep:30'],
  ['bài này của ai', 'info'], ['bài gì đây', 'info'], ['ai hát vậy', 'info'],
];

// Lệnh khác không được bị phần giải trí cướp
const OTHER: [string, string][] = [
  ['mở huyết áp', 'show_bp'],
  ['xem lịch sử huyết áp', 'show_bp'],
  ['đo huyết áp', 'measure_bp'],
  ['mở tin nhắn', 'open_feature'],
  ['đọc tin nhắn', 'read_messages'],
  ['có tin nhắn mới không', 'read_messages'],
  ['nhắn cho Lan là mai bác về', 'send_message'],
  ['gọi cho con trai', 'call_contact'],
  ['mở giải trí', 'open_feature'],
  ['về trang chủ', 'go_home'],
  ['quay lại', 'go_back'],
];

// Chưa có luật: giao cho mô hình (không được tự tìm chữ vô nghĩa)
const LLM: string[] = [
  'buồn ngủ quá', 'buồn cười quá', 'cho cháu xem hoạt hình', 'hôm nay trời đẹp quá',
];

for (const [text, query] of PLAY) {
  test(`phát: "${text}" → ${query}`, async () => {
    const { d, llm } = await route(text);
    assert.equal(llm, false, 'không được gọi LLM');
    assert.equal(d.action, 'execute');
    assert.equal(d.intent, 'play_video');
    assert.equal(norm(d.task?.slots.content ?? ''), query);
  });
}

for (const [text, chips] of ASK) {
  test(`hỏi một câu: "${text}"`, async () => {
    const { d, llm } = await route(text);
    assert.equal(llm, false, 'không được gọi LLM');
    assert.equal(d.action, 'ask');
    assert.equal(d.intent, 'play_video');
    assert.deepEqual(d.chips, chips);
    assert.equal(d.expectsReply, true);
    // Câu hỏi ngắn, có xưng hô, không hỏi dồn
    assert.ok(d.say.length < 140, d.say);
    assert.equal((d.say.match(/\?/g) ?? []).length, 1, d.say);
  });
}

// Đang phát video: màn phát mở (ngữ cảnh thật gửi từ app)
const playerUi: Ui = {
  ...ui,
  screen: 'player',
  context: { role: 'elder', route: '/player', dialog: null, controls: [], lists: [], player: { open: true, playing: true } },
};

for (const [text, content] of CTL) {
  test(`điều khiển khi đang phát: "${text}" → ${content}`, async () => {
    let llm = false;
    const d = await step({ text, state: {}, ui: playerUi }, async () => {
      llm = true;
      return { intent: 'unsupported', recipient: '', content: '', feature: '', say: '' };
    });
    assert.equal(llm, false);
    assert.equal(d.intent, 'video_control');
    assert.equal(d.task?.slots.content?.toLowerCase(), content);
  });
}

test('"dừng lại" khi KHÔNG có video đang phát vẫn là huỷ việc dở', async () => {
  const { d } = await route('dừng lại');
  assert.equal(d.action, 'cancel');
});

test('"dừng lại" khi đang chờ xác nhận (có việc dở) vẫn là huỷ, không phải dừng video', async () => {
  const d = await step(
    { text: 'dừng lại', state: { task: { intent: 'send_message', slots: { content: 'Mai về' } }, expects: 'yes_no' }, ui: playerUi },
    async () => { throw new Error('không được gọi LLM'); },
  );
  assert.equal(d.action, 'cancel');
});

for (const [text, intent] of OTHER) {
  test(`không cướp lệnh khác: "${text}" → ${intent}`, async () => {
    const { d } = await route(text);
    assert.equal(d.intent, intent);
  });
}

for (const text of LLM) {
  test(`giao cho mô hình, không đoán: "${text}"`, async () => {
    const { llm } = await route(text);
    assert.equal(llm, true);
  });
}

// Cùng một yêu cầu, nói nhiều kiểu (đệm đầu, đuôi, xưng hô): phải ra cùng kết quả
const WRAPS: ((v: string) => string)[] = [
  (v) => v,
  (v) => `Vy ơi ${v}`,
  (v) => `ừ ${v}`,
  (v) => `${v} đi`,
  (v) => `${v} nhé`,
  (v) => `${v} giúp con`,
  (v) => `làm ơn ${v}`,
];
const CORE: [string, string][] = [
  ['mở nhạc xưa', 'nhac xua'],
  ['mở cải lương', 'cai luong'],
  ['xem tin tức', 'tin tuc'],
  ['nghe kinh Phật', 'kinh phat'],
  ['mở thiền', 'thien thu gian'],
  ['xem hài', 'hai kich'],
  ['mở nhạc vàng', 'nhac vang'],
  ['nghe bolero', 'bolero'],
  ['mở bài Nối vòng tay lớn', 'noi vong tay lon'],
  ['nghe truyện', 'truyen dem khuya'],
];
for (const [core, query] of CORE) {
  for (const wrap of WRAPS) {
    const text = wrap(core);
    test(`nói nhiều kiểu: "${text}"`, async () => {
      const { d, llm } = await route(text);
      assert.equal(llm, false);
      assert.equal(d.intent, 'play_video');
      assert.equal(norm(d.task?.slots.content ?? ''), query);
    });
  }
}

test('trả lời câu hỏi của Vy bằng chip: "Hài kịch" → phát hài kịch, không hỏi lại', async () => {
  const first = await route('chán quá');
  assert.equal(first.d.action, 'ask');
  const st = { task: first.d.task, pending: first.d.pending, expects: first.d.expects };
  const d = await step({ text: 'Hài kịch', state: st, ui }, async () => {
    throw new Error('không được gọi LLM');
  });
  assert.equal(d.action, 'execute');
  assert.equal(d.intent, 'play_video');
  assert.equal(norm(d.task?.slots.content ?? ''), 'hai kich');
  // gợi ý riêng của câu hỏi không lọt sang app
  assert.equal(d.task?.slots.ask_say, undefined);
  assert.equal(d.task?.slots.ask_chips, undefined);
});

test('khó ngủ: chọn "Nhạc ru ngủ" → phát nhạc ru ngủ', async () => {
  const first = await route('khó ngủ quá');
  const st = { task: first.d.task, pending: first.d.pending, expects: first.d.expects };
  const d = await step({ text: 'Nhạc ru ngủ', state: st, ui }, async () => {
    throw new Error('không được gọi LLM');
  });
  assert.equal(d.action, 'execute');
  assert.equal(norm(d.task?.slots.content ?? ''), 'nhac ru ngu');
});

test('đau chân không bị hiểu là "chán" (mơ hồ chữ không dấu)', async () => {
  const { d } = await route('đau chân quá');
  assert.notEqual(d.intent, 'play_video');
});

// ---------- đợt 4: trí nhớ nghe/xem ----------

type Ctx = NonNullable<Ui['context']>;
const baseCtx: Ctx = { role: 'elder', route: '/', dialog: null, controls: [], lists: [], player: { open: false, playing: false } };
const habit = { top: 'nhạc xưa', topics: ['nhạc xưa', 'cải lương', 'tin tức'], resume: 'Tập 5 Tây Du Ký', last: 'Đường chiều' };

async function routeWith(text: string, ctx: Partial<Ctx> & { habit?: Ctx['habit'] }) {
  let llm = false;
  const d = await step(
    { text, state: {}, ui: { ...ui, context: { ...baseCtx, ...ctx } } },
    async () => {
      llm = true;
      return { intent: 'unsupported', recipient: '', content: '', feature: '', say: '' };
    },
  );
  return { d, llm };
}

const RECALL: [string, string][] = [
  ['mở lại bài lúc nãy', '@last'],
  ['nghe lại bài vừa rồi', '@last'],
  ['mở lại bài hôm qua', '@last'],
  ['mở bài hôm qua tôi nghe', '@last'],
  ['cho nghe lại bài vừa nghe', '@last'],
  ['phát lại video lúc nãy', '@last'],
  ['xem tiếp', '@resume'],
  ['nghe tiếp', '@resume'],
  ['mở tiếp', '@resume'],
  ['xem tiếp phim hôm qua', '@resume'],
  ['nghe tiếp truyện', '@resume'],
  ['mở tiếp tập đang xem dở', '@resume'],
  ['tiếp tục xem phim', '@resume'],
  ['mở bài tôi thích', '@favorite'],
  ['nghe những bài đã lưu', '@favorite'],
  ['mở nhạc yêu thích', '@favorite'],
  ['mở bài tôi hay nghe', '@habit'],
  ['mở nhạc như hôm qua', '@habit'],
  ['nghe như mọi khi', '@habit'],
  ['mở như mọi ngày', '@habit'],
];
for (const [text, token] of RECALL) {
  test(`nhớ lại: "${text}" → ${token}`, async () => {
    const { d, llm } = await routeWith(text, { habit });
    assert.equal(llm, false);
    assert.equal(d.intent, 'play_video');
    const c = d.task?.slots.content ?? '';
    assert.ok(c.toLowerCase().startsWith(token), `${c} ≠ ${token}`);
  });
}

test('nhớ lại hoạt động cả khi chưa có thói quen (app sẽ trả lời "chưa thấy bài nào")', async () => {
  const { d } = await routeWith('mở lại bài lúc nãy', {});
  assert.equal(d.intent, 'play_video');
  assert.ok((d.task?.slots.content ?? '').toLowerCase().startsWith('@last'));
});

test('đang phát: "nghe tiếp" là phát tiếp, "mở lại bài vừa rồi" là bài trước (không mở bài khác)', async () => {
  const player = { player: { open: true, playing: true } };
  const a = await routeWith('nghe tiếp', { ...player, habit });
  assert.equal(a.d.intent, 'video_control');
  assert.equal(a.d.task?.slots.content?.toLowerCase(), 'play');
  const b = await routeWith('mở lại bài vừa rồi', { ...player, habit });
  assert.equal(b.d.intent, 'video_control');
  assert.equal(b.d.task?.slots.content?.toLowerCase(), 'previous');
});

test('"tiếp tục" khi chưa phát gì: có bài xem dở thì mở tiếp, không có thì giữ nguyên báo chưa có video', async () => {
  const withResume = await routeWith('tiếp tục', { habit });
  assert.equal(withResume.d.intent, 'play_video');
  assert.equal(withResume.d.task?.slots.content?.toLowerCase(), '@resume');
  const none = await routeWith('tiếp tục', { habit: { ...habit, resume: '' } });
  assert.equal(none.d.intent, 'video_control');
});

const LIKE: [string, string][] = [
  ['bài này hay', 'like'], ['bài này hay quá', 'like'], ['hay quá', 'like'], ['thích bài này', 'like'], ['lưu bài này', 'like'],
  ['không thích bài này', 'dislike'], ['bài này dở', 'dislike'], ['chán bài này', 'dislike'], ['bỏ bài này', 'dislike'],
  ['đừng mở bài này nữa', 'dislike'], ['không muốn nghe bài này', 'dislike'],
];
for (const [text, fb] of LIKE) {
  test(`khen/chê khi đang phát: "${text}" → ${fb}`, async () => {
    const { d, llm } = await routeWith(text, { player: { open: true, playing: true } });
    assert.equal(llm, false);
    assert.equal(d.intent, 'video_control');
    assert.equal(d.task?.slots.content?.toLowerCase(), fb);
  });
}

test('khen/chê khi KHÔNG phát gì: không bắt nhầm (giao cho mô hình)', async () => {
  for (const text of ['bài này hay', 'không thích bài này']) {
    const { d } = await routeWith(text, {});
    assert.notEqual(d.intent, 'video_control', text);
  }
});

test('có thói quen: "mở nhạc" đoán đúng chủ đề nhạc, không hỏi', async () => {
  const { d, llm } = await routeWith('mở nhạc', { habit: { ...habit, topics: ['cải lương', 'nhạc vàng'], top: 'cải lương' } });
  assert.equal(llm, false);
  assert.equal(d.action, 'execute');
  assert.equal(d.task?.slots.content?.toLowerCase(), '@habit:nhạc vàng');
});

test('có thói quen nhưng chưa nghe nhạc bao giờ: "mở nhạc" vẫn hỏi, gợi ý đưa chủ đề hay nghe lên đầu', async () => {
  const { d } = await routeWith('mở nhạc', { habit: { ...habit, topics: ['cải lương', 'tin tức'], top: 'cải lương' } });
  assert.equal(d.action, 'ask');
  assert.deepEqual(d.chips, ['Cải lương', 'Tin tức', 'Nhạc xưa']);
});

test('"mở cái gì đó" có thói quen: phát luôn chủ đề hay nghe nhất; "hôm nay có gì hay": hỏi nhưng gợi ý theo thói quen', async () => {
  const play = await routeWith('mở cái gì vui vui', { habit });
  assert.equal(play.d.action, 'execute');
  assert.equal(play.d.task?.slots.content?.toLowerCase(), '@habit:nhạc xưa');
  const ask = await routeWith('hôm nay có gì hay', { habit });
  assert.equal(ask.d.action, 'ask');
  assert.deepEqual(ask.d.chips, ['Nhạc xưa', 'Cải lương', 'Hài kịch']);
});

test('tâm trạng và khó ngủ vẫn hỏi riêng theo hoàn cảnh, không bị thói quen che', async () => {
  const mood = await routeWith('chán quá', { habit });
  assert.equal(mood.d.action, 'ask');
  assert.deepEqual(mood.d.chips, MOOD);
  const sleep = await routeWith('khó ngủ quá', { habit });
  assert.deepEqual(sleep.d.chips, SLEEP);
});

test('không có thói quen: hỏi như đợt 2 (gợi ý mặc định)', async () => {
  const { d } = await routeWith('mở nhạc', {});
  assert.deepEqual(d.chips, DEFAULT_ASK);
});

test('ngữ cảnh thói quen gửi lên bị cắt gọn và lọc: rác thì bỏ, dài thì cắt', async () => {
  const { parseUiContext } = await import('../_lib/voice/ui_cmd.ts');
  const ok = parseUiContext({ habit: { top: 'nhạc xưa', topics: ['nhạc xưa', 'a'.repeat(100), 5, null], resume: 'x'.repeat(200), last: 'Đường chiều' } });
  assert.equal(ok?.habit?.top, 'nhạc xưa');
  assert.ok((ok?.habit?.resume.length ?? 0) <= 80);
  assert.ok((ok?.habit?.topics.length ?? 9) <= 3);
  assert.equal(parseUiContext({ habit: { top: '', topics: [], resume: '', last: '' } })?.habit, undefined);
  assert.equal(parseUiContext({ habit: 'bậy' })?.habit, undefined);
});

// ---------- đợt 5: tắt gợi ý chủ động ----------

for (const text of ['đừng gợi ý nữa', 'đừng gợi ý nhạc nữa', 'không cần gợi ý nữa', 'thôi đừng gợi ý', 'đừng hỏi nghe nhạc nữa', 'tắt gợi ý', 'khỏi gợi ý video nữa']) {
  test(`tắt gợi ý chủ động: "${text}"`, async () => {
    for (const ctx of [{}, { player: { open: true, playing: true } }]) {
      const { d, llm } = await routeWith(text, ctx);
      assert.equal(llm, false);
      assert.equal(d.intent, 'video_control', text);
      assert.equal(d.task?.slots.content?.toLowerCase(), 'suggest_off', text);
    }
  });
}

test('"đừng" nói chung vẫn là huỷ, không bị hiểu thành tắt gợi ý', async () => {
  const { d } = await routeWith('đừng', {});
  assert.notEqual(d.task?.slots.content?.toLowerCase(), 'suggest_off');
});
