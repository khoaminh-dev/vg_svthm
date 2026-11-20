// Bộ kiểm thử BẰNG CHỮ (miễn phí) cho "người lái màn hình": câu nói thật của người cao tuổi × màn hình mẫu.
// Các màn mẫu bên dưới là HỢP ĐỒNG với app: app phải khai báo đúng id/nhãn/từ đồng nghĩa/mức như ở đây.
// Tiêu chí đạt (kế hoạch Giai đoạn 2): ra đúng điều khiển/giá trị, và 0 lần vượt mức xác nhận (mức 3 không bao giờ được bấm).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseUiContext, resolveUiCommand, type UiContext, type UiControl, type UiLevel, type UiKind } from '../_lib/voice/ui_cmd.ts';
import { step, type Nlu, type Ui } from '../_lib/voice/dm.ts';

function c(id: string, label: string, o: { level?: UiLevel; aliases?: string[]; kind?: UiKind; value?: boolean; enabled?: boolean; say?: string } = {}): UiControl {
  return { id, label, aliases: o.aliases ?? [], kind: o.kind ?? 'button', level: o.level ?? 0, enabled: o.enabled ?? true, value: o.value, say: o.say };
}
function ctx(route: string, controls: UiControl[], extra: Partial<UiContext> = {}): UiContext {
  return { role: 'elder', route, dialog: null, controls, lists: [], player: { open: false, playing: false }, ...extra };
}

// ---------------- màn hình mẫu ----------------
const HOME = ctx('/', [
  c('home.measure', 'Đo huyết áp', { aliases: ['chụp huyết áp', 'đo huyết áp bây giờ'] }),
  c('home.meds', 'Thuốc', { kind: 'tab', aliases: ['lịch uống thuốc'] }),
  c('home.health', 'Sức khoẻ', { kind: 'tab' }),
  c('home.chat', 'Tin nhắn', { kind: 'tab' }),
  c('home.community', 'Cộng đồng', { kind: 'tab' }),
  c('home.relax', 'Thư giãn', { kind: 'tab', aliases: ['giải trí'] }),
  c('home.sos', 'SOS', { level: 3, aliases: ['báo động', 'gọi sos', 'nút sos'] }),
]);

const MEDS = ctx('/meds', [
  c('meds.taken', 'Đã uống', { level: 1, aliases: ['tôi uống rồi', 'bác uống rồi', 'uống rồi', 'đã uống rồi', 'uống thuốc rồi'], say: 'Dạ, con ghi {hon} đã uống rồi ạ.' }),
  c('meds.skip', 'Bỏ qua cữ này', { level: 2, aliases: ['bỏ qua'] }),
  c('meds.undo', 'Hoàn tác', { level: 2 }),
  c('meds.plans', 'Xem và sửa lịch thuốc', { aliases: ['lịch thuốc', 'xem lịch thuốc', 'sửa lịch thuốc'] }),
  c('meds.add', 'Thêm đơn thuốc', { aliases: ['thêm đơn'] }),
  c('nav.home', 'Về trang chủ', { aliases: ['trang chủ'] }),
]);

const MEDS_TWO = ctx('/meds', [
  c('meds.taken.sang', 'Đã uống Túi Sáng', { level: 1, aliases: ['đã uống', 'tôi uống rồi', 'uống rồi'] }),
  c('meds.taken.toi', 'Đã uống Túi Tối', { level: 1, aliases: ['đã uống', 'tôi uống rồi', 'uống rồi'] }),
]);

const BP = ctx('/bp', [
  c('bp.measure', 'Đo huyết áp bây giờ', { aliases: ['đo huyết áp', 'đo bây giờ', 'chụp huyết áp', 'đo lại'] }),
  c('bp.risk', 'Xem nguy cơ sức khoẻ', { aliases: ['nguy cơ', 'xem nguy cơ', 'nguy cơ sức khoẻ'] }),
  c('nav.home', 'Về trang chủ', { aliases: ['trang chủ'] }),
]);

const VIDEOS = ['Liên khúc nhạc xưa hay nhất', 'Nối vòng tay lớn', 'Đường về quê hương', 'Tình ca', 'Hạ trắng'];
const ENT = ctx('/fun', [
  c('ent.music', 'Nhạc xưa', { aliases: ['nhạc'] }),
  c('ent.opera', 'Cải lương'),
  c('ent.news', 'Tin tức', { aliases: ['thời sự'] }),
  c('ent.meditate', 'Thiền thư giãn', { aliases: ['thiền'] }),
  c('ent.comedy', 'Hài kịch', { aliases: ['hài'] }),
  c('ent.health', 'Dưỡng sinh'),
  c('nav.back', 'Quay lại'),
], { lists: [{ id: 'ent.videos', title: 'Kết quả video', items: VIDEOS.map((t, i) => ({ n: i + 1, title: t })) }] });

const PROFILE = ctx('/profile', [
  c('prof.captions', 'Hiện chữ khi Vy nói', { kind: 'toggle', value: true, aliases: ['chữ phụ đề', 'phụ đề', 'chữ khi vy nói'] }),
  c('prof.sounds', 'Tiếng khi bật và tắt Vy', { kind: 'toggle', value: true, aliases: ['tiếng ting', 'âm thanh vy'] }),
  c('prof.speak', 'Đọc lời khuyên sau khi đo', { kind: 'toggle', value: true, aliases: ['đọc lời khuyên', 'lời khuyên'] }),
  c('prof.bpremind', 'Nhắc đo huyết áp', { kind: 'toggle', value: true, aliases: ['nhắc nhở đo huyết áp'] }),
  c('prof.push', 'Thông báo tin nhắn', { kind: 'toggle', value: true }),
  c('prof.logout', 'Đăng xuất', { level: 3, aliases: ['thoát tài khoản'] }),
  c('prof.role', 'Đổi vai trò', { level: 3 }),
  c('prof.invite', 'Mời người thân', { aliases: ['mã mời'] }),
]);
const PROFILE_OFF = ctx('/profile', PROFILE.controls.map((x) => (x.kind === 'toggle' ? { ...x, value: false } : x)));

const DIALOG_LOGOUT = ctx('/profile', PROFILE.controls, {
  dialog: { id: 'dlg.logout', title: 'Đăng xuất khỏi Viegrand?', controls: [
    c('dlg.logout.ok', 'Đăng xuất', { level: 3, aliases: ['đồng ý', 'có', 'chắc chắn'] }),
    c('dlg.logout.stay', 'Ở lại', { aliases: ['không', 'thôi', 'huỷ', 'hủy', 'không đăng xuất'] }),
  ] },
});
const DIALOG_SKIP = ctx('/meds', MEDS.controls, {
  dialog: { id: 'dlg.skip', title: 'Bỏ qua cữ thuốc này?', controls: [
    c('dlg.skip.ok', 'Đồng ý', { aliases: ['đúng rồi', 'vâng', 'có', 'ok', 'được'] }),
    c('dlg.skip.no', 'Hủy', { aliases: ['không', 'thôi', 'huỷ'] }),
  ] },
});

// ---------------- bảng câu nói ----------------
// Kết quả mong đợi: invoke:<id>[:1|:0] | choose:<n> | refuse3:<id> | already:<id> | disabled:<id> | oor | amb | null
type Case = [string, string];

function show(cmd: ReturnType<typeof resolveUiCommand>): string {
  if (!cmd) return 'null';
  switch (cmd.kind) {
    case 'invoke': return `invoke:${cmd.control.id}${cmd.set === undefined ? '' : cmd.set ? ':1' : ':0'}`;
    case 'choose': return `choose:${cmd.n}`;
    case 'refuse': return cmd.why === 'level3' ? `refuse3:${cmd.control.id}` : `${cmd.why}:${cmd.control.id}`;
    case 'ambiguous': return 'amb';
    case 'out_of_range': return 'oor';
  }
}

function run(name: string, context: UiContext, cases: Case[]): { ok: number; total: number } {
  const bad: string[] = [];
  for (const [say, want] of cases) {
    const got = show(resolveUiCommand(say, context));
    if (got !== want) bad.push(`  "${say}" → ${got} (mong đợi ${want})`);
  }
  test(name, () => assert.equal(bad.length, 0, `\n${bad.join('\n')}`));
  return { ok: cases.length - bad.length, total: cases.length };
}

const tallies: { ok: number; total: number }[] = [];

tallies.push(run('Trang chủ người cao tuổi: mở ô, và SOS không bao giờ bấm', HOME, [
  ['mở thuốc', 'invoke:home.meds'],
  ['vào thuốc đi', 'invoke:home.meds'],
  ['mở màn hình thuốc cho bác', 'invoke:home.meds'],
  ['ừ bấm vào thuốc nhé', 'invoke:home.meds'],
  ['cho tôi xem thuốc', 'invoke:home.meds'],
  ['lịch uống thuốc', 'invoke:home.meds'],
  ['mở tin nhắn', 'invoke:home.chat'],
  ['vào tin nhắn cho bác', 'invoke:home.chat'],
  ['mở cộng đồng', 'invoke:home.community'],
  ['mở giải trí', 'invoke:home.relax'],
  ['vào thư giãn', 'invoke:home.relax'],
  ['mở sức khoẻ', 'invoke:home.health'],
  ['đo huyết áp', 'invoke:home.measure'],
  ['chụp huyết áp', 'invoke:home.measure'],
  ['ờ đo huyết áp bây giờ đi', 'invoke:home.measure'],
  ['bấm đo huyết áp', 'invoke:home.measure'],
  ['nhấn vào đo huyết áp', 'invoke:home.measure'],
  // SOS: mức 3, Vy không bấm
  ['bấm SOS', 'refuse3:home.sos'],
  ['SOS', 'refuse3:home.sos'],
  ['gọi SOS', 'refuse3:home.sos'],
  ['bấm nút SOS đi', 'refuse3:home.sos'],
  ['báo động', 'refuse3:home.sos'],
  // câu nói thường KHÔNG được bắt nhầm vào ô nào
  ['xem huyết áp', 'null'],
  ['đọc huyết áp cho tôi', 'null'],
  ['huyết áp của tôi bao nhiêu', 'null'],
  ['nhắn cho con trai là mai bác về', 'null'],
  ['nhắn tin cho Lan', 'null'],
  ['xin chào', 'null'],
  ['cảm ơn Vy', 'null'],
  ['tôi thấy hơi mệt', 'null'],
  ['bác muốn nghe nhạc', 'null'],
  ['hôm nay trời đẹp quá', 'null'],
  ['mở nhạc xưa', 'null'],
]));

tallies.push(run('Màn Thuốc: đã uống, bỏ qua, hoàn tác, lịch thuốc', MEDS, [
  ['tôi uống rồi', 'invoke:meds.taken'],
  ['bác uống rồi', 'invoke:meds.taken'],
  ['uống rồi', 'invoke:meds.taken'],
  ['uống rồi nhé', 'invoke:meds.taken'],
  ['ừ bác uống rồi đó', 'invoke:meds.taken'],
  ['đã uống rồi', 'invoke:meds.taken'],
  ['bấm đã uống', 'invoke:meds.taken'],
  ['bấm vào nút đã uống đi', 'invoke:meds.taken'],
  ['nhấn đã uống', 'invoke:meds.taken'],
  ['chọn đã uống', 'invoke:meds.taken'],
  ['bỏ qua cữ này', 'invoke:meds.skip'],
  ['bỏ qua', 'invoke:meds.skip'],
  ['bấm bỏ qua', 'invoke:meds.skip'],
  ['hoàn tác', 'invoke:meds.undo'],
  ['bấm hoàn tác đi', 'invoke:meds.undo'],
  ['xem lịch thuốc', 'invoke:meds.plans'],
  ['sửa lịch thuốc', 'invoke:meds.plans'],
  ['mở lịch thuốc', 'invoke:meds.plans'],
  ['thêm đơn thuốc', 'invoke:meds.add'],
  ['bấm thêm đơn', 'invoke:meds.add'],
  ['về trang chủ', 'invoke:nav.home'],
  ['bấm về trang chủ', 'invoke:nav.home'],
  // không bắt nhầm
  ['tôi chưa uống', 'null'],
  ['thuốc này uống mấy viên', 'null'],
  ['hôm qua tôi uống rồi', 'null'],
  ['xem huyết áp', 'null'],
]));

tallies.push(run('Hai cữ thuốc cùng lúc: nói chung chung thì hỏi lại, nói rõ thì đúng cữ', MEDS_TWO, [
  ['tôi uống rồi', 'amb'],
  ['đã uống', 'amb'],
  ['bấm đã uống', 'amb'],
  ['đã uống túi sáng', 'invoke:meds.taken.sang'],
  ['bấm đã uống túi tối', 'invoke:meds.taken.toi'],
]));

tallies.push(run('Màn Huyết áp: đo, nguy cơ', BP, [
  ['đo huyết áp', 'invoke:bp.measure'],
  ['đo bây giờ', 'invoke:bp.measure'],
  ['đo lại', 'invoke:bp.measure'],
  ['bấm đo huyết áp bây giờ', 'invoke:bp.measure'],
  ['chụp huyết áp đi', 'invoke:bp.measure'],
  ['xem nguy cơ', 'invoke:bp.risk'],
  ['nguy cơ sức khoẻ', 'invoke:bp.risk'],
  ['bấm nguy cơ', 'invoke:bp.risk'],
  ['mở nguy cơ sức khoẻ', 'invoke:bp.risk'],
  ['về trang chủ', 'invoke:nav.home'],
  ['huyết áp của tôi dạo này sao', 'null'],
  ['cao huyết áp là gì', 'null'],
]));

tallies.push(run('Màn Giải trí: thể loại và chọn video theo số', ENT, [
  ['mở nhạc xưa', 'invoke:ent.music'],
  ['bấm nhạc xưa', 'invoke:ent.music'],
  ['nhạc xưa', 'invoke:ent.music'],
  ['mở cải lương', 'invoke:ent.opera'],
  ['cải lương', 'invoke:ent.opera'],
  ['xem tin tức', 'invoke:ent.news'],
  ['mở thiền', 'invoke:ent.meditate'],
  ['mở hài kịch cho bác', 'invoke:ent.comedy'],
  ['mở dưỡng sinh', 'invoke:ent.health'],
  ['quay lại', 'invoke:nav.back'],
  // danh sách có số
  ['cái thứ hai', 'choose:2'],
  ['cái thứ nhất', 'choose:1'],
  ['cái đầu tiên', 'choose:1'],
  ['cái đầu', 'choose:1'],
  ['bài đầu tiên', 'choose:1'],
  ['bài đầu', 'choose:1'],
  ['số 1', 'choose:1'],
  ['số 3', 'choose:3'],
  ['số ba', 'choose:3'],
  ['số hai', 'choose:2'],
  ['mở số 2', 'choose:2'],
  ['mở số ba', 'choose:3'],
  ['mở bài số bốn', 'choose:4'],
  ['chọn bài thứ năm', 'choose:5'],
  ['chọn số 5', 'choose:5'],
  ['bài thứ ba', 'choose:3'],
  ['cái thứ tư', 'choose:4'],
  ['cái thứ năm', 'choose:5'],
  ['bài cuối', 'choose:5'],
  ['cái cuối cùng', 'choose:5'],
  ['mở bài cuối đi', 'choose:5'],
  ['cho nghe bài thứ hai', 'choose:2'],
  ['hai', 'choose:2'],
  ['3', 'choose:3'],
  ['cái số 2 đó', 'choose:2'],
  ['ừ mở cái thứ hai cho bác', 'choose:2'],
  // ngoài phạm vi danh sách
  ['cái thứ sáu', 'oor'],
  ['số 9', 'oor'],
  ['bài thứ mười', 'oor'],
  // KHÔNG được chọn nhầm
  ['đau', 'null'],
  ['bài sau', 'null'],
  ['bài trước', 'null'],
  ['bài khác', 'null'],
  ['tiếp theo', 'null'],
  ['nhỏ đi', 'null'],
  ['dừng lại', 'null'],
  ['mẹ tôi tên là Hai', 'null'],
]));

tallies.push(run('Hồ sơ: công tắc cần biết bật hay tắt, mức 3 không bao giờ bấm', PROFILE, [
  ['tắt chữ phụ đề', 'invoke:prof.captions:0'],
  ['tắt phụ đề đi', 'invoke:prof.captions:0'],
  ['tắt hiện chữ khi vy nói', 'invoke:prof.captions:0'],
  ['bật chữ phụ đề', 'already:prof.captions'],
  ['bật phụ đề', 'already:prof.captions'],
  ['tắt tiếng ting', 'invoke:prof.sounds:0'],
  ['tắt âm thanh vy', 'invoke:prof.sounds:0'],
  ['tắt đọc lời khuyên', 'invoke:prof.speak:0'],
  ['tắt lời khuyên đi', 'invoke:prof.speak:0'],
  ['bật đọc lời khuyên', 'already:prof.speak'],
  ['tắt nhắc đo huyết áp', 'invoke:prof.bpremind:0'],
  ['tắt nhắc nhở đo huyết áp đi', 'invoke:prof.bpremind:0'],
  ['tắt thông báo tin nhắn', 'invoke:prof.push:0'],
  ['bật thông báo tin nhắn', 'already:prof.push'],
  ['không hiện chữ khi vy nói', 'invoke:prof.captions:0'],
  ['mời người thân', 'invoke:prof.invite'],
  ['mở mã mời', 'invoke:prof.invite'],
  // mức 3: chỉ nhắc người dùng tự bấm
  ['đăng xuất', 'refuse3:prof.logout'],
  ['bấm đăng xuất', 'refuse3:prof.logout'],
  ['thoát tài khoản', 'refuse3:prof.logout'],
  ['cho tôi đăng xuất đi', 'refuse3:prof.logout'],
  ['đổi vai trò', 'refuse3:prof.role'],
  ['bấm đổi vai trò', 'refuse3:prof.role'],
  // công tắc không có động từ: không đoán
  ['chữ phụ đề', 'null'],
  ['tiếng ting', 'null'],
]));

tallies.push(run('Hồ sơ khi công tắc đang tắt: bật được, tắt thì báo đã tắt', PROFILE_OFF, [
  ['bật chữ phụ đề', 'invoke:prof.captions:1'],
  ['bật tiếng ting', 'invoke:prof.sounds:1'],
  ['bật đọc lời khuyên', 'invoke:prof.speak:1'],
  ['bật nhắc đo huyết áp', 'invoke:prof.bpremind:1'],
  ['tắt chữ phụ đề', 'already:prof.captions'],
  ['tắt tiếng ting', 'already:prof.sounds'],
]));

tallies.push(run('Hộp thoại Đăng xuất che màn phía sau: chỉ nút của hộp thoại, "đồng ý" là mức 3', DIALOG_LOGOUT, [
  ['ở lại', 'invoke:dlg.logout.stay'],
  ['không', 'invoke:dlg.logout.stay'],
  ['thôi', 'invoke:dlg.logout.stay'],
  ['huỷ', 'invoke:dlg.logout.stay'],
  ['không đăng xuất', 'invoke:dlg.logout.stay'],
  ['bấm ở lại', 'invoke:dlg.logout.stay'],
  ['đồng ý', 'refuse3:dlg.logout.ok'],
  ['có', 'refuse3:dlg.logout.ok'],
  ['chắc chắn', 'refuse3:dlg.logout.ok'],
  ['bấm đăng xuất', 'refuse3:dlg.logout.ok'],
  // màn phía sau không với tới được
  ['tắt chữ phụ đề', 'null'],
  ['mời người thân', 'null'],
  ['đổi vai trò', 'null'],
]));

tallies.push(run('Hộp thoại Bỏ qua cữ thuốc: nút Đồng ý/Hủy là xác nhận, không hỏi thêm lần nữa', DIALOG_SKIP, [
  ['đồng ý', 'invoke:dlg.skip.ok'],
  ['vâng', 'invoke:dlg.skip.ok'],
  ['đúng rồi', 'invoke:dlg.skip.ok'],
  ['ok', 'invoke:dlg.skip.ok'],
  ['được', 'invoke:dlg.skip.ok'],
  ['hủy', 'invoke:dlg.skip.no'],
  ['không', 'invoke:dlg.skip.no'],
  ['thôi', 'invoke:dlg.skip.no'],
  ['uống rồi', 'null'], // màn phía sau bị che
]));

test('điều khiển không bấm được (tắt): báo chưa bấm được', () => {
  const x = ctx('/meds', [c('meds.undo', 'Hoàn tác', { level: 2, enabled: false })]);
  assert.equal(show(resolveUiCommand('hoàn tác', x)), 'disabled:meds.undo');
  assert.equal(show(resolveUiCommand('bấm hoàn tác', x)), 'disabled:meds.undo');
});

test('không có danh sách thì số thứ tự không bị bắt', () => {
  assert.equal(show(resolveUiCommand('cái thứ hai', MEDS)), 'null');
  assert.equal(show(resolveUiCommand('số 3', HOME)), 'null');
});

test('hộp thoại mở thì không chọn được danh sách phía sau', () => {
  const x = ctx('/fun', ENT.controls, { lists: ENT.lists, dialog: DIALOG_SKIP.dialog });
  assert.equal(show(resolveUiCommand('cái thứ hai', x)), 'null');
});

test('KHÔNG BAO GIỜ trả về invoke cho điều khiển mức 3 (quét mọi câu × mọi màn)', () => {
  const screens = [HOME, MEDS, BP, ENT, PROFILE, PROFILE_OFF, DIALOG_LOGOUT, DIALOG_SKIP, MEDS_TWO];
  const verbs = ['', 'bấm ', 'nhấn ', 'bấm vào nút ', 'mở ', 'vào ', 'chọn ', 'bật ', 'tắt ', 'cho tôi ', 'ừ bấm '];
  let checked = 0;
  for (const sc of screens) {
    const pools = [...sc.controls, ...(sc.dialog?.controls ?? [])];
    for (const ctl of pools) {
      for (const name of [ctl.label, ...ctl.aliases]) {
        for (const v of verbs) {
          for (const tail of ['', ' đi', ' nhé', ' cho bác']) {
            const cmd = resolveUiCommand(`${v}${name}${tail}`, sc);
            checked++;
            if (cmd?.kind === 'invoke') {
              assert.notEqual(cmd.control.level, 3, `"${v}${name}${tail}" bấm nhầm mức 3: ${cmd.control.id}`);
            }
          }
        }
      }
    }
  }
  assert.ok(checked > 2000, `chỉ quét ${checked} câu`);
});

test('điều khiển không rõ mức thì coi là mức 3 (an toàn), và cắt gọn dữ liệu quá cỡ', () => {
  const p = parseUiContext({
    role: 'elder', route: '/x', controls: [
      { id: 'a', label: 'Nút A' },
      { id: 'b', label: 'Nút B', level: 0 },
      { id: 'c', label: 'Nút C', level: 9 },
      { label: 'không id' },
      { id: 'd', label: '' },
    ],
    lists: [{ id: 'l', items: Array.from({ length: 30 }, (_, i) => ({ n: i + 1, title: `Mục ${i + 1}` })) }],
  });
  assert.ok(p);
  assert.deepEqual(p!.controls.map((x) => [x.id, x.level]), [['a', 3], ['b', 0], ['c', 3]]);
  assert.equal(p!.lists[0].items.length, 10);
  assert.equal(parseUiContext(null), undefined);
  assert.equal(parseUiContext('x'), undefined);
  const big = parseUiContext({ controls: Array.from({ length: 200 }, (_, i) => ({ id: `i${i}`, label: `Nhãn ${i}`, level: 0 })) });
  assert.equal(big!.controls.length, 60);
});

// ---------------- bước hội thoại (dm.step) có ngữ cảnh ----------------
const noNlu: Nlu = async () => { throw new Error('không được gọi mô hình khi ghép được với màn hình'); };
const uiOf = (context: UiContext): Ui => ({ screen: context.route, contacts: [], honorific: 'bác', context });

test('step: mức 0 làm ngay, nói đúng việc, không gọi mô hình', async () => {
  const d = await step({ text: 'mở thuốc', state: {}, ui: uiOf(HOME) }, noNlu);
  assert.equal(d.action, 'execute');
  assert.equal(d.intent, 'invoke_control');
  assert.equal(d.task?.slots.control_id, 'home.meds');
  assert.match(d.say, /Thuốc/);
});

test('step: mức 1 làm ngay và đọc lại bằng câu riêng của nút', async () => {
  const d = await step({ text: 'tôi uống rồi', state: {}, ui: uiOf(MEDS) }, noNlu);
  assert.equal(d.action, 'execute');
  assert.equal(d.say, 'Dạ, con ghi bác đã uống rồi ạ.');
});

test('step: mức 2 hỏi lại, "đồng ý" mới làm, và nói đúng việc (không phải "con gửi rồi")', async () => {
  const d1 = await step({ text: 'bỏ qua cữ này', state: {}, ui: uiOf(MEDS) }, noNlu);
  assert.equal(d1.action, 'confirm');
  assert.equal(d1.expects, 'yes_no');
  assert.equal(d1.task?.intent, 'invoke_control');
  const d2 = await step({ text: 'đồng ý', state: { task: d1.task, expects: d1.expects }, ui: uiOf(MEDS) }, noNlu);
  assert.equal(d2.action, 'execute');
  assert.equal(d2.task?.slots.control_id, 'meds.skip');
  assert.doesNotMatch(d2.say, /gửi/);
  const d3 = await step({ text: 'thôi', state: { task: d1.task, expects: d1.expects }, ui: uiOf(MEDS) }, noNlu);
  assert.equal(d3.action, 'cancel');
});

test('step: mức 3 không bao giờ invoke_control; chỉ point_control (con trỏ chỉ) và nhắc người dùng tự bấm', async () => {
  for (const say of ['bấm đăng xuất', 'đăng xuất', 'bấm SOS']) {
    const x = say.includes('SOS') ? HOME : PROFILE;
    const d = await step({ text: say, state: {}, ui: uiOf(x) }, noNlu);
    assert.equal(d.intent, 'point_control', say);
    assert.ok(d.task && d.task.intent === 'point_control');
    assert.equal(d.task!.slots.control_id, undefined, 'không được có control_id để bấm');
    assert.ok(d.task!.slots.target_id);
    assert.match(d.say, /tự bấm/);
  }
});

test('step: hộp thoại đang mở thì "huỷ"/"đồng ý" là nút của hộp thoại', async () => {
  const d = await step({ text: 'huỷ', state: {}, ui: uiOf(DIALOG_LOGOUT) }, noNlu);
  assert.equal(d.action, 'execute');
  assert.equal(d.task?.slots.control_id, 'dlg.logout.stay');
  const e = await step({ text: 'đồng ý', state: {}, ui: uiOf(DIALOG_LOGOUT) }, noNlu);
  assert.equal(e.intent, 'point_control'); // đăng xuất là mức 3: Vy chỉ chỉ vào nút, không bấm thay
  assert.equal(e.task?.slots.control_id, undefined);
});

test('step: công tắc có động từ rõ thì set đúng giá trị', async () => {
  const d = await step({ text: 'tắt chữ phụ đề', state: {}, ui: uiOf(PROFILE) }, noNlu);
  assert.equal(d.action, 'execute');
  assert.equal(d.task?.slots.set, '0');
  const e = await step({ text: 'bật chữ phụ đề', state: {}, ui: uiOf(PROFILE) }, noNlu);
  assert.equal(e.action, 'answer');
  assert.match(e.say, /đang bật rồi/);
});

test('step: chọn theo số trong danh sách, hỏi lại khi trùng, báo khi quá số', async () => {
  const d = await step({ text: 'cái thứ hai', state: {}, ui: uiOf(ENT) }, noNlu);
  assert.equal(d.action, 'execute');
  assert.equal(d.intent, 'choose_item');
  assert.equal(d.task?.slots.n, '2');
  assert.match(d.say, /Nối vòng tay lớn/);
  const e = await step({ text: 'cái thứ sáu', state: {}, ui: uiOf(ENT) }, noNlu);
  assert.equal(e.action, 'answer');
  assert.match(e.say, /5 mục/);
  const f = await step({ text: 'tôi uống rồi', state: {}, ui: uiOf(MEDS_TWO) }, noNlu);
  assert.equal(f.action, 'ask');
  assert.equal(f.chips.length, 2);
});

test('step: lệnh cũ vẫn chạy khi không có ngữ cảnh, và khi ngữ cảnh không khớp', async () => {
  const nlu: Nlu = async () => ({ intent: 'unsupported', recipient: '', content: '', feature: '', say: '' });
  const a = await step({ text: 'xem huyết áp', state: {}, ui: { screen: '/', contacts: [], honorific: 'bác' } }, nlu);
  assert.equal(a.intent, 'show_bp');
  const b = await step({ text: 'xem huyết áp', state: {}, ui: uiOf(HOME) }, nlu);
  assert.equal(b.intent, 'show_bp');
  const d = await step({ text: 'tôi đau ngực', state: {}, ui: uiOf(HOME) }, noNlu);
  assert.equal(d.intent, 'emergency'); // khẩn cấp luôn đứng trước
  const g = await step({ text: 'tắt nhạc', state: {}, ui: uiOf(ENT) }, nlu);
  assert.equal(g.intent, 'video_control');
});

test('tổng kết: tỉ lệ câu mẫu đúng', () => {
  const ok = tallies.reduce((a, t) => a + t.ok, 0);
  const total = tallies.reduce((a, t) => a + t.total, 0);
  console.log(`# Người lái màn hình: ${ok}/${total} câu mẫu đúng (${((ok / total) * 100).toFixed(1)}%)`);
  assert.ok(ok / total >= 0.95, `chỉ đạt ${ok}/${total}`);
});
