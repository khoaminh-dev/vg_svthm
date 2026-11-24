import { test } from 'node:test';
import assert from 'node:assert/strict';
import { dialect } from '../_lib/voice/dialect.ts';
import { norm, step, type Contact, type Nlu, type Ui } from '../_lib/voice/dm.ts';
import { isReferentialQuery, readListIntent, scrollIntent } from '../_lib/voice/video_nlu.ts';
import { ordinalFromText } from '../_lib/voice/ui_cmd.ts';

// Lỗi b51 (24/11/2026): "coi thời sự" mở nhầm Giải trí, "coi video đầu tiên trong danh sách" mở video tên "đầu tiên",
// "lướt xuống" bị từ chối. Kiểm thử bằng chữ, miễn phí.

test('chuẩn hoá: "coi" là "xem", đệm miền Nam được gọt', () => {
  const cases: [string, string][] = [
    ['coi thoi su', 'xem thoi su'],
    ['cho toi coi cai luong', 'cho toi xem cai luong'],
    ['coi thu bai nay', 'xem bai nay'],
    ['nghe thu nhac xua', 'nghe nhac xua'],
    ['mo thoi su len coi', 'mo thoi su len xem'],
    ['tui muon nghe nhac', 'toi muon nghe nhac'],
    ['tui khong thich', 'toi khong thich'],
    ['hok thich bai nay', 'khong thich bai nay'],
    ['ko nghe nua', 'khong nghe nua'],
    ['toi hong thich', 'toi khong thich'],
    ['bua nay toi met', 'hom nay toi met'],
    ['hoi nay toi nghe bai gi', 'luc nay toi nghe bai gi'],
    ['mo nhac xua nghen', 'mo nhac xua'],
  ];
  for (const [a, b] of cases) assert.equal(dialect(a), b, a);
});

test('chuẩn hoá KHÔNG làm đổi nghĩa câu thường', () => {
  const same = [
    'xem thoi su', 'mo nhac xua', 'bac si noi gi', 'may hong roi', 'mau hong dep qua', 'da uong tui sang', 'uong tui toi',
    'tui thuoc cua toi', 'nhan cho ba', 'huyet ap hom nay', 'xem huyet ap', 'coi chung', 'gia dinh',
  ];
  for (const s of same) assert.equal(dialect(s), s === 'coi chung' ? 'xem chung' : s, s);
});

const contacts: Contact[] = [{ id: 'u2', kind: 'direct', name: 'Lan', username: 'lan' }];
const list = { id: 'ent.videos', title: 'Kết quả video', items: [1, 2, 3, 4, 5].map((n) => ({ n, title: `Bản tin số ${n}` })) };
const base = { role: 'elder' as const, route: '/entertainment', dialog: null, controls: [], player: { open: false, playing: false } };
const withList: Ui = { screen: 'x', contacts, honorific: 'bác', context: { ...base, lists: [list] } };
const noList: Ui = { screen: 'x', contacts, honorific: 'bác', context: { ...base, lists: [] } };

async function route(text: string, ui: Ui, nlu?: Nlu) {
  let llm = false;
  const stub: Nlu = nlu ?? (async () => {
    llm = true;
    return { intent: 'unsupported', recipient: '', content: '', feature: '', say: '' };
  });
  const wrapped: Nlu = async (...a) => {
    llm = true;
    return stub(...a);
  };
  const d = await step({ text, state: {}, ui }, wrapped);
  return { d, llm };
}

// ---- L2: nói "coi" ----
const COI: [string, string][] = [
  ['tôi muốn coi thời sự', 'tin tuc'],
  ['coi thời sự', 'tin tuc'],
  ['coi tin tức', 'tin tuc'],
  ['cho tôi coi cải lương', 'cai luong'],
  ['coi cải lương Lệ Thủy', 'cai luong le thuy'],
  ['tui muốn coi hài', 'hai kich'],
  ['coi thử thời sự', 'tin tuc'],
  ['bữa nay coi thời sự đi', 'tin tuc'],
  ['coi thời sự nghen', 'tin tuc'],
  ['cho tui coi cải lương đi', 'cai luong'],
  ['mở thời sự lên coi', 'tin tuc'],
  ['nghe thử nhạc xưa', 'nhac xua'],
  ['coi kinh Phật', 'kinh phat'],
  ['coi bóng đá', 'bong da'],
];
for (const [text, query] of COI) {
  test(`miền Nam: "${text}" → phát ${query}, không mở nhầm Giải trí, không gọi LLM`, async () => {
    const { d, llm } = await route(text, noList);
    assert.equal(llm, false);
    assert.equal(d.action, 'execute');
    assert.equal(d.intent, 'play_video');
    assert.equal(norm(d.task?.slots.content ?? ''), query);
  });
}

test('"coi phim", "coi tivi" chưa nói gì cụ thể: hỏi một câu, không mở bừa', async () => {
  for (const text of ['coi phim', 'coi tivi', 'tui muốn coi tivi']) {
    const { d, llm } = await route(text, noList);
    assert.equal(llm, false, text);
    assert.equal(d.action, 'ask', text);
    assert.equal(d.intent, 'play_video', text);
  }
});

// ---- L3: số thứ tự và lưới an toàn ----
const ORD: [string, string][] = [
  ['tôi muốn coi video đầu tiên trong danh sách', '1'],
  ['coi video đầu tiên', '1'],
  ['xem video đầu tiên trong danh sách', '1'],
  ['video đầu tiên trong danh sách đó', '1'],
  ['coi cái đầu', '1'],
  ['mở cái trên cùng', '1'],
  ['cái trên cùng', '1'],
  ['coi video thứ hai trong danh sách', '2'],
  ['cho tôi coi bài số 3', '3'],
  ['tui muốn coi cái thứ ba', '3'],
  ['mở cái thứ năm', '5'],
  ['xem video số 4 trong danh sách', '4'],
  ['coi cái cuối cùng', '5'],
  ['mở video cuối trong danh sách', '5'],
  ['cái dưới cùng', '5'],
];
for (const [text, n] of ORD) {
  test(`số thứ tự: "${text}" → mục ${n}, không tìm chữ "đầu tiên"`, async () => {
    const { d, llm } = await route(text, withList);
    assert.equal(llm, false);
    assert.equal(d.intent, 'choose_item');
    assert.equal(d.task?.slots.n, n);
  });
}

test('lưới an toàn: LLM trả về play_video "đầu tiên" thì vẫn chọn mục 1, không tìm trên YouTube', async () => {
  const llmSaysPlay: Nlu = async () => ({ intent: 'play_video', recipient: '', content: 'video đầu tiên trong danh sách', feature: '', say: '' });
  const { d, llm } = await route('ờ cái video mà nằm đầu tiên trong cái danh sách đó', withList, llmSaysPlay);
  assert.equal(llm, true);
  assert.equal(d.intent, 'choose_item');
  assert.equal(d.task?.slots.n, '1');
});

test('lưới an toàn: không có danh sách thì hỏi lại, không mở video tên "đầu tiên"', async () => {
  const llmSaysPlay: Nlu = async () => ({ intent: 'play_video', recipient: '', content: 'đầu tiên trong danh sách', feature: '', say: '' });
  const { d } = await route('ờ cái video mà nằm đầu tiên trong cái danh sách đó', noList, llmSaysPlay);
  assert.equal(d.action, 'ask');
  assert.equal(d.intent, 'play_video');
  assert.equal(d.task?.slots.content ?? '', '');
});

test('nhận ra nội dung chỉ là tham chiếu; tên bài thật thì không', () => {
  for (const c of ['đầu tiên', 'đầu tiên trong danh sách', 'cái thứ hai', 'video số 3', 'cái trên cùng', 'bài cuối cùng', 'cái đó', 'video đầu tiên trong danh sách']) {
    assert.equal(isReferentialQuery(c), true, c);
  }
  for (const c of ['Nối vòng tay lớn', 'cải lương', 'tin tức', 'Tình đầu tiên', 'nhạc Trịnh', 'số phận', 'con mèo', 'Đường chiều của Khánh Ly', '']) {
    assert.equal(isReferentialQuery(c), false, c);
  }
});

test('số thứ tự nằm đâu đó trong câu', () => {
  assert.equal(ordinalFromText('cai video nam dau tien trong danh sach'), 1);
  assert.equal(ordinalFromText('thu ba'), 3);
  assert.equal(ordinalFromText('so 7'), 7);
  assert.equal(ordinalFromText('cai cuoi cung'), 'last');
  assert.equal(ordinalFromText('nhac xua'), null);
});

// ---- L4: cuộn và đọc danh sách ----
const SCROLL: [string, string][] = [
  ['lướt xuống để tôi xem mấy video khác', 'down'],
  ['cuộn xuống', 'down'],
  ['kéo xuống', 'down'],
  ['trượt xuống', 'down'],
  ['xuống nữa', 'down'],
  ['xuống thêm chút', 'down'],
  ['xem thêm', 'down'],
  ['mấy video khác', 'down'],
  ['mấy cái khác', 'down'],
  ['còn video nào nữa không', 'down'],
  ['cho tôi xem mấy bài khác', 'down'],
  ['tui muốn coi mấy video khác', 'down'],
  ['lướt lên', 'up'],
  ['lên trên', 'up'],
  ['kéo lên trên', 'up'],
  ['về đầu danh sách', 'top'],
  ['cuộn lên đầu', 'top'],
  ['xuống cuối', 'bottom'],
  ['cuộn xuống cuối', 'bottom'],
];
for (const [text, dir] of SCROLL) {
  test(`cuộn: "${text}" → ${dir}`, async () => {
    for (const ui of [withList, noList]) {
      const { d, llm } = await route(text, ui);
      assert.equal(llm, false);
      assert.equal(d.intent, 'scroll', text);
      assert.equal(d.task?.slots.content?.toLowerCase(), dir, text);
    }
  });
}

const READ: string[] = ['đọc tên các video', 'đọc danh sách', 'có những video nào', 'đọc các bài', 'đọc danh sách đi', 'cho tôi nghe tên các bài', 'còn những bài nào'];
for (const text of READ) {
  test(`đọc danh sách: "${text}"`, async () => {
    const { d, llm } = await route(text, withList);
    assert.equal(llm, false);
    assert.equal(d.intent, 'read_list', text);
  });
}

test('cuộn không bắt nhầm lệnh khác', async () => {
  for (const text of ['xem tin tức', 'xem huyết áp', 'xem thời sự', 'mở nhạc xưa', 'đọc tin nhắn', 'xuống xe']) {
    assert.equal(scrollIntent(norm(text)), null, text);
  }
  assert.equal(readListIntent(norm('đọc tin nhắn')), false);
  const { d } = await route('xem tin tức', withList);
  assert.equal(d.intent, 'play_video');
});
