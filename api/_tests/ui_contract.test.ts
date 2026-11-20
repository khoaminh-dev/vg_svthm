// Kiểm thử HỢP ĐỒNG app ↔ máy chủ bằng ngữ cảnh THẬT: `fixtures/real_ui_ctx.json` là ảnh chụp `ui.context` do chính app
// sinh ra trên máy ảo (bản build có VG_TRACE, 20/11/2026), không phải do tay viết. Nếu app đổi nhãn/mức/mã mà quên
// cập nhật phía máy chủ (hoặc ngược lại) thì bộ này sẽ vỡ. Chụp lại: build VG_TRACE, mở Vy ở từng màn, đọc vg_trace.log.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseUiContext, resolveUiCommand, type UiContext } from '../_lib/voice/ui_cmd.ts';
import { step, type Nlu } from '../_lib/voice/dm.ts';

const raw = JSON.parse(readFileSync(new URL('./fixtures/real_ui_ctx.json', import.meta.url), 'utf8')) as Record<string, unknown>;
const ctx = (k: string): UiContext => {
  const c = parseUiContext(raw[k]);
  assert.ok(c, `không đọc được ngữ cảnh ${k}`);
  return c!;
};
const noNlu: Nlu = async () => { throw new Error('không được gọi mô hình'); };

function show(c: UiContext, say: string): string {
  const r = resolveUiCommand(say, c);
  if (!r) return 'null';
  if (r.kind === 'invoke') return `invoke:${r.control.id.replace(/\.[0-9a-f-]{36}$/, '.*').replace(/\.[0-9]{6,}$/, '.#')}${r.set === undefined ? '' : r.set ? ':1' : ':0'}`;
  if (r.kind === 'choose') return `choose:${r.n}`;
  if (r.kind === 'refuse') return `${r.why === 'level3' ? 'refuse3' : r.why}:${r.control.id}`;
  return r.kind === 'ambiguous' ? 'amb' : 'oor';
}

function check(name: string, key: string, cases: [string, string][]) {
  test(`hợp đồng thật: ${name}`, () => {
    const c = ctx(key);
    const bad = cases.map(([s, want]) => [s, want, show(c, s)]).filter(([, w, g]) => w !== g).map(([s, w, g]) => `  "${s}" → ${g} (mong đợi ${w})`);
    assert.equal(bad.length, 0, `\n${bad.join('\n')}`);
  });
}

check('Thuốc (/bp): chỉ một cữ chờ uống thì "tôi uống rồi" là cữ đó', 'meds', [
  ['tôi uống rồi', 'invoke:meds.taken.*'],
  ['uống rồi', 'invoke:meds.taken.*'],
  ['bấm đã uống', 'invoke:meds.taken.*'],
  ['đã uống túi tối', 'invoke:meds.taken.*'],
  ['bỏ qua', 'invoke:meds.skip.*'],
  ['hoàn tác', 'invoke:meds.undo.*'],
  ['xem lịch thuốc', 'invoke:meds.manage'],
  ['sửa lịch thuốc', 'invoke:meds.manage'],
  ['thêm đơn thuốc', 'invoke:meds.add'],
  ['chụp đơn thuốc', 'invoke:meds.scan'],
  ['về trang chủ', 'invoke:nav.home'],
  ['xem huyết áp', 'null'],
]);

check('Giải trí có danh sách video: chọn theo số', 'videos', [
  ['cái thứ hai', 'choose:2'],
  ['số 3', 'choose:3'],
  ['bài đầu tiên', 'choose:1'],
  ['bài cuối', 'choose:10'],
  ['số mười', 'choose:10'],
  ['số 11', 'oor'],
  ['chọn mục khác', 'invoke:ent.categories'],
  ['bài sau', 'null'],
  ['đau', 'null'],
]);

check('Giải trí: các thể loại', 'categories', [
  ['mở nhạc xưa', 'invoke:ent.cat.#'],
  ['mở cải lương', 'invoke:ent.cat.#'],
  ['mở thiền', 'invoke:ent.cat.#'],
  ['mở hài kịch', 'invoke:ent.cat.#'],
  ['cái thứ hai', 'null'], // chưa có danh sách
]);

check('Trang chủ người cao tuổi', 'home', [
  ['mở thuốc', 'invoke:home.meds'],
  ['mở giải trí', 'invoke:home.relax'],
  ['đo huyết áp', 'invoke:home.measure'],
  ['mở tin nhắn', 'invoke:home.messages'],
  ['bấm SOS', 'refuse3:home.sos'],
  ['báo động', 'refuse3:home.sos'],
]);

check('Hồ sơ: công tắc có giá trị, mức 3 không bấm', 'profile', [
  ['tắt chữ phụ đề', 'invoke:prof.captions:0'],
  ['bật chữ phụ đề', 'already:prof.captions'],
  ['tắt tiếng ting', 'invoke:prof.sounds:0'],
  ['tắt đọc lời khuyên', 'invoke:prof.speak:0'],
  ['tắt nhắc đo huyết áp', 'invoke:prof.bpremind:0'],
  ['tắt thông báo tin nhắn', 'invoke:prof.push:0'],
  ['mời người thân', 'invoke:prof.invite'],
  ['mở thẻ y tế', 'invoke:prof.emergency'],
  ['đăng xuất', 'refuse3:prof.logout'],
  ['bấm đăng xuất', 'refuse3:prof.logout'],
  ['đổi vai trò', 'refuse3:prof.role'],
]);

test('hợp đồng thật: mức 3 trong ngữ cảnh thật không bao giờ thành execute (toàn bộ câu × toàn bộ màn)', async () => {
  const verbs = ['', 'bấm ', 'nhấn ', 'mở ', 'vào ', 'chọn ', 'bật ', 'tắt ', 'cho tôi ', 'ừ bấm '];
  let n = 0;
  for (const k of Object.keys(raw)) {
    const c = ctx(k);
    const level3 = c.controls.filter((x) => x.level === 3);
    for (const l3 of level3) {
      for (const name of [l3.label, ...l3.aliases]) {
        for (const v of verbs) {
          const d = await step({ text: `${v}${name} đi`, state: {}, ui: { screen: c.route, contacts: [], honorific: 'bác', context: c } }, noNlu).catch(() => null);
          n++;
          if (d) {
            assert.notEqual(d.intent, 'invoke_control', `"${v}${name}" bấm mức 3 ${l3.id}`);
            assert.notEqual(d.task?.slots.control_id, l3.id, `"${v}${name}" có control_id mức 3 ${l3.id}`);
          }
        }
      }
    }
  }
  assert.ok(n > 40);
});

test('hợp đồng thật: xác nhận mức 2 rồi mới làm, và nói đúng việc', async () => {
  const c = ctx('meds');
  const ui = { screen: c.route, contacts: [], honorific: 'bác', context: c };
  const d1 = await step({ text: 'bỏ qua', state: {}, ui }, noNlu);
  assert.equal(d1.action, 'confirm');
  assert.match(d1.say, /Bỏ qua cữ Túi Tối/);
  const d2 = await step({ text: 'đồng ý', state: { task: d1.task, expects: d1.expects }, ui }, noNlu);
  assert.equal(d2.action, 'execute');
  assert.match(d2.task!.slots.control_id, /^meds\.skip\./);
  assert.match(d2.say, /bỏ qua cữ Túi Tối/);
  const d3 = await step({ text: 'tôi uống rồi', state: {}, ui }, noNlu);
  assert.equal(d3.action, 'execute');
  assert.match(d3.say, /^Dạ, con ghi bác đã uống Túi Tối rồi ạ\.$/); // {hon} đã được thay
});
