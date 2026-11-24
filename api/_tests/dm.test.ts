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
  const d = await step({ text: 'nhắn cho con gái là mai về ăn cơm', state: {}, ui }, noNlu);
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

test('lời nói thật có đệm/đuôi vẫn ra đúng lệnh, không gọi LLM (lỗi đo thực tế 20/11)', async () => {
  const cases: [string, string, string?][] = [
    ['Ừ rồi mở màn hình huyết áp cho bác đi', 'show_bp'],
    ['thì mở huyết áp cho bác để bác xem', 'show_bp'],
    ['Mở trang huyết áp cho bác', 'show_bp'],
    ['mở màn hình huyết áp', 'show_bp'],
    ['quay lại đi', 'go_back'],
    ['Mở cho tôi bài nhạc xưa', 'play_video'],
    ['ừm mở tin nhắn cho bác nhé', 'open_feature', 'chat'],
  ];
  for (const [text, intent, feature] of cases) {
    const d = await step({ text, state: {}, ui }, noNlu);
    assert.equal(d.action, 'execute', text);
    assert.equal(d.intent, intent, text);
    if (feature) assert.equal(d.task?.slots.feature, feature, text);
  }
});

test('tidy không làm hỏng lệnh nhắn tin và đo huyết áp', async () => {
  const { tidy } = await import('../_lib/voice/dm.ts');
  assert.equal(tidy('mo huyet ap'), 'mo huyet ap');
  assert.equal(tidy('do huyet ap cho toi'), 'do huyet ap');
  assert.equal(tidy('u'), 'u'); // không gọt thành rỗng
  const d = await step({ text: 'nhắn cho Lan là mai bác về', state: {}, ui }, noNlu);
  assert.equal(d.intent, 'send_message');
  assert.equal(d.task?.slots.content, 'Mai bác về');
});

test('LLM chọn "mở một mục" nhưng quên mục: lấy từ câu nói, không hỏi lại', async () => {
  const nluOpen: Nlu = async () => ({ intent: 'open_feature', recipient: '', content: '', feature: '', say: '' });
  const d = await step({ text: 'cho bác xem cái phần huyết áp của bác nhé', state: {}, ui }, nluOpen);
  assert.equal(d.action, 'execute');
  assert.equal(d.task?.slots.feature, 'bp');
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

test('videoQuery: gọt đệm, câu chưa cụ thể trả "" để hỏi lại thay vì tìm chữ vô nghĩa (24/11)', async () => {
  const { videoQuery } = await import('../_lib/voice/dm.ts');
  // đệm đầu/đuôi
  assert.equal(videoQuery('mo bai cua tuan vu'), 'tuan vu');
  assert.equal(videoQuery('nghe nhac cua trinh cong son'), 'nhac trinh cong son');
  assert.equal(videoQuery('bat bai nhac vang cho toi'), 'nhac vang');
  assert.equal(videoQuery('cho bac nghe bai duong chieu'), 'duong chieu');
  // chưa nói gì cụ thể: hỏi lại
  for (const t of ['mo nhac', 'bat nhac len', 'xem phim', 'mo bai do di', 'mo video dau tien', 'phat nhac nhe', 'mo bai hat toi hay nghe', 'mo nhac nhu hom qua', 'nghe bai luc nay']) {
    assert.equal(videoQuery(t), '', t);
  }
  // vẫn tìm bình thường
  assert.equal(videoQuery('nghe khanh ly hat'), 'khanh ly hat');
  assert.equal(videoQuery('mo nhac xua'), 'nhac xua');
});

test('"bật nhạc lên" / "mở bài đó đi" không gọi LLM, không tìm chữ vô nghĩa mà hỏi người dùng muốn nghe gì', async () => {
  for (const text of ['bật nhạc lên', 'mở nhạc', 'mở bài đó đi', 'xem phim']) {
    const d = await step({ text, state: {}, ui }, noNlu);
    assert.equal(d.action, 'ask', text);
    assert.equal(d.intent, 'play_video', text);
    assert.deepEqual(d.chips, ['Nhạc xưa', 'Tin tức', 'Cải lương'], text);
  }
});

test('điều khiển video mở rộng: tua, về đầu, thoát, hẹn giờ, hỏi tên bài, âm lượng nói tự nhiên (24/11)', async () => {
  const { videoControl } = await import('../_lib/voice/dm.ts');
  const cases: [string, string][] = [
    ['tua lai', 'back:15'], ['lui lai mot chut', 'back:15'], ['lui lai 30 giay', 'back:30'], ['tua lai 1 phut', 'back:60'],
    ['tua toi', 'fwd:15'], ['tua toi 2 phut', 'fwd:120'], ['tua nhanh', 'fwd:15'],
    ['phat lai tu dau', 'restart'], ['nghe lai bai nay', 'restart'], ['tu dau', 'restart'],
    ['phat lai', 'play'], ['tiep tuc', 'play'],
    ['tat video', 'close'], ['dong video di', 'close'], ['tat nhac di', 'pause'],
    ['hen gio tat nhac sau 45 phut', 'sleep:45'], ['hen gio tat nhac sau 2 tieng', 'sleep:120'], ['hen gio tat', 'sleep:30'],
    ['bai nay cua ai', 'info'], ['bai gi day', 'info'], ['ten bai', 'info'], ['ai hat vay', 'info'],
    ['nho tieng chut', 'quieter'], ['nho bot', 'quieter'], ['to tieng len', 'louder'],
    ['to tieng', 'louder'], ['to nua', 'louder'], ['lon len', 'louder'],
  ];
  for (const [t, want] of cases) assert.equal(videoControl(t), want, t);
  // không bắt nhầm tên bài / lệnh khác
  assert.equal(videoControl('mo bai tua lai'), null);
  assert.equal(videoControl('tua lai 999 giay'), 'back:600');
  assert.equal(videoControl('quay lai'), null);
});

test('nhắn tin bằng luật: người nhận + nội dung không gọi LLM', async () => {
  let d = await step({ text: 'nhắn cho Lan là mai bác về ăn cơm', state: {}, ui }, noNlu);
  assert.equal(d.action, 'confirm');
  assert.equal(d.task?.slots.room_id, 'u2');
  assert.match(d.task?.slots.content ?? '', /^Mai bác về ăn cơm$/);
  d = await step({ text: 'nhắn tin cho Lan', state: {}, ui }, noNlu);
  assert.equal(d.action, 'ask');
  assert.equal(d.pending, 'content');
  d = await step({ text: 'nhắn tin', state: {}, ui }, noNlu);
  assert.equal(d.pending, 'recipient');
  d = await step({ text: 'nhắn cho con trai', state: {}, ui }, noNlu);
  assert.equal(d.pending, 'recipient'); // họ hàng chưa có bí danh → hỏi tên
});

test('nhắn tin: người nhận lạ → vẫn để LLM xử lý; tên trong danh bạ + nội dung không cần "là" → luật nhanh', async () => {
  let called = 0;
  const nlu: Nlu = async () => { called++; return { intent: 'unsupported', recipient: '', content: '', feature: '', say: '' }; };
  await step({ text: 'nhắn cho ông Tuấn là chiều qua chơi', state: {}, ui }, nlu);
  const d = await step({ text: 'nhắn tin cho Lan hôm nay bác hơi mệt', state: {}, ui }, nlu);
  assert.equal(called, 1, 'câu thứ hai do luật nhanh xử lý, không gọi mô hình');
  assert.equal(d.action, 'confirm');
  assert.equal(d.task?.slots.content, 'Hôm nay bác hơi mệt');
});

test('chào hỏi, cảm ơn, việc chưa hỗ trợ trả lời ngay không gọi LLM', async () => {
  const g = await step({ text: 'Chào Vy', state: {}, ui }, noNlu);
  assert.equal(g.intent, 'chitchat');
  assert.match(g.say, /^Dạ, con chào bác/);
  assert.equal((await step({ text: 'cảm ơn con', state: {}, ui }, noNlu)).intent, 'chitchat');
  const call = await step({ text: 'gọi điện cho con trai', state: {}, ui }, noNlu); // đã hỗ trợ từ Vy giai đoạn 5
  assert.equal(call.intent, 'call_contact');
  assert.equal((await step({ text: 'gọi video cho con', state: {}, ui }, noNlu)).action, 'unsupported');
  assert.equal((await step({ text: 'thời tiết hôm nay', state: {}, ui }, noNlu)).action, 'unsupported');
});

test('tạm biệt: nhận câu ngắn, không nhận khi nằm trong nội dung tin nhắn', async () => {
  const { isGoodbye } = await import('../_lib/voice/dm.js');
  for (const t of ['tam biet', 'tam biet vy', 'bye bye', 'chao tam biet con nhe', 'cam on con tam biet', 'hen gap lai nhe']) {
    assert.equal(isGoodbye(t), true, t);
  }
  for (const t of ['nhan cho lan la tam biet nhe', 'chao', 'cam on', 'mo nhac tam biet', 'toi muon noi tam biet voi ba lan']) {
    assert.equal(isGoodbye(t), false, t);
  }
});

test('tạm biệt trong lúc đang chờ xác nhận: chào rồi kết thúc phiên, không gửi tin', async () => {
  const nlu: Nlu = async () => ({ intent: 'other', recipient: '', content: '', feature: '', say: '' });
  const ui: Ui = { honorific: 'bác', contacts: [] } as unknown as Ui;
  const d = await step({ text: 'Tạm biệt', state: { expects: 'yes_no', task: { intent: 'send_message', slots: { recipient_id: 'x', content: 'a' } } } as unknown as DState, ui }, nlu);
  assert.equal(d.endSession, true);
  assert.equal(d.intent, 'goodbye');
  assert.match(d.say, /chào/);
});
