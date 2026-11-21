import test from 'node:test';
import assert from 'node:assert/strict';
import { buildLiveSession, liveAllowed, pickMode, safetyId, validSdp, LIVE_TOOLS, ACK_DELAY_MS } from '../_lib/voice/live.ts';

test('liveAllowed: rỗng thì không ai được, có trong danh sách thì được', () => {
  assert.equal(liveAllowed('u1', ''), false);
  assert.equal(liveAllowed('u1', undefined), false);
  assert.equal(liveAllowed('u1', 'u2, u1 ,u3'), true);
  assert.equal(liveAllowed('u9', 'u2,u1'), false);
});

test('safetyId: ổn định, không chứa id thật', () => {
  assert.equal(safetyId('abc'), safetyId('abc'));
  assert.notEqual(safetyId('abc'), safetyId('abd'));
  assert.ok(!safetyId('abc').includes('abc'));
});

test('validSdp', () => {
  assert.equal(validSdp('v=0\r\n' + 'a'.repeat(100)), true);
  assert.equal(validSdp('xyz'), false);
  assert.equal(validSdp(42), false);
  assert.equal(validSdp('v=0\r\n' + 'a'.repeat(40_000)), false);
});

test('pickMode: mặc định R, chỉ C khi chọn rõ', () => {
  assert.equal(pickMode(undefined, undefined), 'R');
  assert.equal(pickMode('C', undefined), 'C');
  assert.equal(pickMode('x', 'C'), 'R');
  assert.equal(pickMode(undefined, 'C'), 'C');
});

test('buildLiveSession chế độ R: Luna + hàm, không có hàm nguy hiểm', () => {
  const s = buildLiveSession('R', 'bác', {}) as any;
  assert.equal(s.model, 'gpt-live-1');
  assert.equal(s.delegation.type, 'responses');
  assert.equal(s.delegation.responses.model, 'gpt-6-luna');
  const names = s.delegation.responses.tools.map((t: any) => t.name);
  assert.ok(names.includes('prepare_message'));
  for (const bad of ['send_message', 'sos', 'delete', 'pay', 'confirm']) assert.ok(!names.includes(bad), bad);
  assert.equal(names.length, LIVE_TOOLS.length);
  assert.match(s.instructions, /bác/);
});

test('buildLiveSession chế độ R: cấu hình thêm hợp lệ được trộn, hỏng thì bỏ qua', () => {
  const ok = buildLiveSession('R', 'bác', { LIVE_RESPONSES_EXTRA: '{"reasoning":{"effort":"none"}}' } as any) as any;
  assert.deepEqual(ok.delegation.responses.reasoning, { effort: 'none' });
  const bad = buildLiveSession('R', 'bác', { LIVE_RESPONSES_EXTRA: '{oops' } as any) as any;
  assert.equal(bad.delegation.responses.reasoning, undefined);
});

test('buildLiveSession chế độ C: client delegation', () => {
  const s = buildLiveSession('C', 'cô', {}) as any;
  assert.deepEqual(s.delegation, { type: 'client', acknowledgement_delay_ms: ACK_DELAY_MS });
  assert.ok(ACK_DELAY_MS <= 800, 'OpenAI từ chối lời đệm trên 800 ms; vượt trần làm mỗi lần mở Live mất thêm ~4 giây');
  assert.match(s.instructions, /CHỈ tự trả lời chào hỏi/);
  // Chế độ C buộc đọc nguyên văn và chuyển mọi câu trả lời kế tiếp; chế độ R không có các dòng này.
  assert.match(s.instructions, /NGUYÊN VĂN/);
  assert.match(s.instructions, /không tự xác nhận/);
  assert.ok(!(buildLiveSession('R', 'cô', {}) as any).instructions.includes('NGUYÊN VĂN'));
});
