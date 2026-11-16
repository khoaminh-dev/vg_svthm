import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { assess, ageCode, calibrateDiabetes, predictHgb, predictLogistic, type RiskInput } from '../_lib/health/risk.ts';
import { HEALTH_MODELS } from '../_lib/health/models.ts';

const parity = JSON.parse(readFileSync(new URL('./fixtures/health_parity.json', import.meta.url), 'utf8')) as {
  model: 'stroke' | 'heart' | 'diabetes';
  input: Record<string, number>;
  p: number;
}[];

test('TypeScript khớp scikit-learn trên 180 đầu vào ngẫu nhiên (3 model)', () => {
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

test('mã nhóm tuổi BRFSS', () => {
  assert.equal(ageCode(18), 1);
  assert.equal(ageCode(24), 1);
  assert.equal(ageCode(25), 2);
  assert.equal(ageCode(67), 10);
  assert.equal(ageCode(79), 12);
  assert.equal(ageCode(80), 13);
  assert.equal(ageCode(95), 13);
});

test('hiệu chỉnh tiểu đường: dữ liệu 50/50 được kéo về tỉ lệ nền 14%', () => {
  assert.ok(Math.abs(calibrateDiabetes(0.5) - 0.14) < 1e-9);
  assert.ok(calibrateDiabetes(0.9) < 0.9 && calibrateDiabetes(0.9) > calibrateDiabetes(0.5));
  assert.ok(calibrateDiabetes(0.1) < 0.03);
});

test('tiểu đường: thiếu chiều cao/cân nặng thì không tính; đã có tiểu đường thì không tính', () => {
  assert.equal(assess(HEALTH_MODELS, base).diabetes, null);
  assert.equal(assess(HEALTH_MODELS, { ...base, heightCm: 160, weightKg: 70, diabetes: true }).diabetes, null);
  const r = assess(HEALTH_MODELS, { ...base, heightCm: 160, weightKg: 70 });
  assert.ok(r.diabetes);
  assert.equal(r.diabetes!.bmi, 27.3);
  assert.ok(r.diabetes!.p > 0 && r.diabetes!.p < 1);
});

test('tiểu đường: người béo phì, huyết áp cao, mỡ máu cao có nguy cơ cao hơn người gầy khoẻ cùng tuổi', () => {
  const lean = assess(HEALTH_MODELS, { ...base, heightCm: 170, weightKg: 58 }).diabetes!;
  const risky = assess(HEALTH_MODELS, {
    ...base,
    hypertension: true,
    highCholesterol: true,
    difficultyWalking: true,
    heightCm: 160,
    weightKg: 90,
  }).diabetes!;
  assert.ok(risky.p > lean.p * 1.5, `${risky.p} vs ${lean.p}`);
  assert.notEqual(risky.level, 'low');
});

test('thêm tiểu đường không làm đổi mức tổng (chỉ hai model đột quỵ và tim mạch quyết định)', () => {
  const a = assess(HEALTH_MODELS, base);
  const b = assess(HEALTH_MODELS, { ...base, heightCm: 160, weightKg: 95, highCholesterol: true });
  assert.equal(a.level, b.level);
  assert.deepEqual(a.stroke, b.stroke);
});
