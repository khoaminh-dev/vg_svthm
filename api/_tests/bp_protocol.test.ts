import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { decide, scriptText, SCRIPT_KEYS, categoryOf, isSevere, type BpContext, type Reading } from '../_lib/health/bp_protocol.ts';
import { violatesBpAdvice } from '../_lib/voice/bp_guard.ts';

type Case = { name: string; readings: [number, number, number][]; context: BpContext[]; symptoms: boolean | null; expect: { action: string; script: string; category: string; protocolOk: boolean } };
const cases: Case[] = JSON.parse(readFileSync(new URL('./fixtures/bp_protocol_cases.json', import.meta.url), 'utf8'));
const rd = (r: [number, number, number][]): Reading[] => r.map(([s, d, x]) => ({ s, d, rested: x === 1 }));

for (const c of cases) {
  test(`bp_protocol: ${c.name}`, () => {
    const r = decide({ readings: rd(c.readings), context: c.context, symptoms: c.symptoms });
    assert.deepEqual({ action: r.action, script: r.script, category: r.category, protocolOk: r.protocolOk }, c.expect);
  });
}

test('ngưỡng AHA: 180/120 chưa severe, 181 hoặc 121 là severe', () => {
  assert.equal(isSevere(180, 120), false);
  assert.equal(isSevere(181, 80), true);
  assert.equal(isSevere(120, 121), true);
  assert.equal(categoryOf(119, 79), 'normal');
  assert.equal(categoryOf(120, 79), 'elevated');
  assert.equal(categoryOf(130, 70), 'stage1');
  assert.equal(categoryOf(110, 90), 'stage2');
});

test('mọi câu cố định: không chứa lời khuyên cấm, đều nhắc ngồi yên/gọi khi cần', () => {
  for (const k of SCRIPT_KEYS) {
    const t = scriptText(k);
    assert.equal(violatesBpAdvice(t), false, k);
    assert.doesNotMatch(t, /đi vòng|đi bộ|chạy|tập thể dục/);
  }
  for (const k of ['woke_up', 'after_walk', 'high_recheck', 'severe_wait'] as const) assert.match(scriptText(k), /ngồi yên/);
  assert.match(scriptText('severe_wait'), /115/);
});

test('scriptText đổi cách xưng hô nhưng giữ "bác sĩ"', () => {
  const t = scriptText('still_high', 'cô');
  assert.match(t, /^Đo lại vẫn còn cao\. Cô báo/);
  assert.match(scriptText('keep_monitoring', 'cô'), /nhắc bác sĩ/);
});

test('mọi tổ hợp hợp lệ 1-3 số đều ra quyết định, không ném lỗi, severe không bao giờ là "none"', () => {
  const vals = [[110, 70], [125, 78], [135, 85], [150, 95], [181, 100], [150, 121]];
  for (const a of vals) for (const b of [null, ...vals]) for (const rested of [false, true]) for (const sym of [null, false, true]) {
    const readings: Reading[] = [{ s: a[0], d: a[1], rested }];
    if (b) readings.push({ s: b[0], d: b[1], rested: true });
    const r = decide({ readings, symptoms: sym });
    if (readings.some((x) => isSevere(x.s, x.d))) assert.notEqual(r.action, 'none');
    if (sym === true) assert.equal(r.action, 'call_115');
  }
});
