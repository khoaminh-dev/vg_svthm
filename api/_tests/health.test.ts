import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { assess, predictHgb, predictLogistic, type RiskInput } from '../_lib/health/risk.ts';
import { HEALTH_MODELS } from '../_lib/health/models.ts';

const parity = JSON.parse(readFileSync(new URL('./fixtures/health_parity.json', import.meta.url), 'utf8')) as {
  model: 'stroke' | 'heart';
  input: Record<string, number>;
  p: number;
}[];

test('TypeScript khớp scikit-learn trên 120 đầu vào ngẫu nhiên', () => {
  for (const c of parity) {
    const m = HEALTH_MODELS[c.model];
    const x = m.features.map((f: string) => c.input[f]);
    const p = c.model === 'stroke' ? predictLogistic(m, x) : predictHgb(m, x);
    assert.ok(Math.abs(p - c.p) < 1e-6, `${c.model} ${JSON.stringify(c.input)}: ${p} vs ${c.p}`);
  }
});

const reading = (s: number, d: number, pulse: number | null = 70) => ({
  systolic: s,
  diastolic: d,
  pulse,
  measuredAt: '2026-11-14T08:00:00Z',
});

const base: RiskInput = {
  birthYear: 1958,
  sex: 'male',
  hypertension: false,
  heartDisease: false,
  smoker: false,
  bpMeds: false,
  diabetes: false,
  hadStroke: false,
  readings: [reading(125, 80)],
  year: 2026,
};

test('người trẻ khoẻ mạnh: mức thấp', () => {
  const r = assess(HEALTH_MODELS, { ...base, birthYear: 1991, sex: 'female', readings: [reading(110, 70)] });
  assert.equal(r.level, 'low');
  assert.deepEqual(r.reasons, []);
});

test('nhiều yếu tố nguy cơ: mức cao và nêu đúng lý do', () => {
  const r = assess(HEALTH_MODELS, {
    ...base,
    hypertension: true,
    heartDisease: true,
    smoker: true,
    diabetes: true,
    readings: [reading(150, 95)],
  });
  assert.equal(r.level, 'high');
  assert.deepEqual(r.reasons, ['bp_high_now', 'heart_disease', 'diabetes', 'smoker', 'age_65']);
});

test('huyết áp cao hơn thì nguy cơ tim mạch không giảm', () => {
  const lo = assess(HEALTH_MODELS, { ...base, readings: [reading(120, 78)] });
  const hi = assess(HEALTH_MODELS, { ...base, readings: [reading(170, 105)] });
  assert.ok(hi.heart.p >= lo.heart.p);
});

test('cơn tăng huyết áp: khẩn cấp bất kể model', () => {
  assert.equal(assess(HEALTH_MODELS, { ...base, readings: [reading(190, 100)] }).level, 'urgent');
  assert.equal(assess(HEALTH_MODELS, { ...base, readings: [reading(150, 120)] }).level, 'urgent');
});

test('suy ra tăng huyết áp từ trung vị 3 lần đo gần nhất', () => {
  const r = assess(HEALTH_MODELS, {
    ...base,
    readings: [reading(145, 88), reading(150, 92), reading(120, 80)],
  });
  assert.equal(r.hypertensionDerived, true);
  const r2 = assess(HEALTH_MODELS, { ...base, readings: [reading(145, 88), reading(120, 78), reading(118, 76)] });
  assert.equal(r2.hypertensionDerived, false);
});

test('từng bị đột quỵ: tối thiểu cần chú ý; trên 70 tuổi có cờ ngoài khoảng huấn luyện', () => {
  const r = assess(HEALTH_MODELS, { ...base, birthYear: 1990, sex: 'female', hadStroke: true, readings: [reading(110, 70)] });
  assert.notEqual(r.level, 'low');
  assert.ok(r.reasons.includes('prior_stroke'));
  assert.equal(assess(HEALTH_MODELS, { ...base, birthYear: 1945 }).ageOutOfRange, true);
  assert.equal(assess(HEALTH_MODELS, base).ageOutOfRange, false);
});

test('thiếu mạch vẫn tính được; không có lần đo thì báo lỗi', () => {
  const r = assess(HEALTH_MODELS, { ...base, readings: [reading(125, 80, null)] });
  assert.ok(Number.isFinite(r.heart.p));
  assert.throws(() => assess(HEALTH_MODELS, { ...base, readings: [] }), /no_reading/);
});
