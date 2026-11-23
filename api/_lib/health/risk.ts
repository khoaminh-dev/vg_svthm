// Chạy hai model sức khoẻ (xuất từ scikit-learn sang JSON) và gộp thành một mức hiển thị.
// Không import gì để vừa chạy trên Vercel vừa chạy được trong node --test; model được truyền vào từ ngoài.

export type Level = 'low' | 'attention' | 'high' | 'urgent';

const sigmoid = (z: number) => 1 / (1 + Math.exp(-z));

type Imputed = { median: number[] };

function fill(m: Imputed, x: number[]): number[] {
  return x.map((v, i) => (Number.isFinite(v) ? v : m.median[i]));
}

/** Hồi quy logistic: impute trung vị, chuẩn hoá, rồi sigmoid. */
export function predictLogistic(
  m: Imputed & { mean: number[]; scale: number[]; coef: number[]; intercept: number },
  x: number[],
): number {
  const v = fill(m, x);
  let z = m.intercept;
  for (let i = 0; i < v.length; i++) z += m.coef[i] * ((v[i] - m.mean[i]) / m.scale[i]);
  return sigmoid(z);
}

type Tree = { f: number[]; t: number[]; l: number[]; r: number[]; v: number[] };

/** Hist Gradient Boosting nhị phân: cộng giá trị lá của từng cây rồi sigmoid (ngưỡng "<=" như scikit-learn). */
export function predictHgb(m: Imputed & { baseline: number; trees: Tree[] }, x: number[]): number {
  const v = fill(m, x);
  let raw = m.baseline;
  for (const tr of m.trees) {
    let n = 0;
    while (tr.f[n] !== -1) n = v[tr.f[n]] <= tr.t[n] ? tr.l[n] : tr.r[n];
    raw += tr.v[n];
  }
  return sigmoid(raw);
}

export interface Reading {
  systolic: number;
  diastolic: number;
  pulse: number | null;
  measuredAt: string;
  /** false = đo chưa ngồi nghỉ đủ chuẩn (null/undefined = không rõ, số cũ). Số false không dùng để suy ra tăng huyết áp. */
  protocolOk?: boolean | null;
}

export interface RiskInput {
  birthYear: number;
  sex: 'male' | 'female';
  // null = "không rõ", tính như không có
  hypertension: boolean | null;
  heartDisease: boolean | null;
  smoker: boolean | null;
  bpMeds: boolean | null;
  diabetes: boolean | null;
  hadStroke: boolean | null;
  // Cho model tiểu đường; thiếu chiều cao hoặc cân nặng thì bỏ qua model này.
  highCholesterol?: boolean | null;
  difficultyWalking?: boolean | null;
  heightCm?: number | null;
  weightKg?: number | null;
  /** Các lần đo gần nhất, mới nhất đứng đầu. */
  readings: Reading[];
  year: number;
}

export interface RiskResult {
  level: Level;
  stroke: { p: number; level: Exclude<Level, 'urgent'> };
  heart: { p: number; level: Exclude<Level, 'urgent'> };
  /** Nguy cơ tiểu đường (đã hiệu chỉnh tỉ lệ nền); null nếu đã có tiểu đường hoặc thiếu chiều cao/cân nặng. */
  diabetes: { p: number; level: Exclude<Level, 'urgent'>; bmi: number } | null;
  reasons: string[];
  bp: Reading;
  hypertensionDerived: boolean;
  /** Model tim mạch chỉ huấn luyện đến 70 tuổi: người lớn hơn bị đánh giá thấp. */
  ageOutOfRange: boolean;
}

const ORDER: Level[] = ['low', 'attention', 'high', 'urgent'];
const worse = (a: Level, b: Level): Level => (ORDER.indexOf(a) >= ORDER.indexOf(b) ? a : b);

// Mốc chia mức: tạm thời, chỉnh lại khi có dữ liệu người dùng thật.
export const strokeLevel = (p: number): 'low' | 'attention' | 'high' => (p < 0.1 ? 'low' : p < 0.25 ? 'attention' : 'high');
export const diabetesLevel = (p: number): 'low' | 'attention' | 'high' => (p < 0.15 ? 'low' : p < 0.3 ? 'attention' : 'high');

/**
 * Model tiểu đường huấn luyện trên bộ dữ liệu cân bằng 50/50 nên xác suất thô cao hơn thực tế rất nhiều.
 * Hiệu chỉnh bằng cách dời log-odds từ tỉ lệ nền 50% về tỉ lệ nền thật (≈14% theo khảo sát BRFSS 2015 của Mỹ,
 * nguồn của bộ dữ liệu); chưa kiểm chứng cho người Việt.
 */
export const DIABETES_BASE_RATE = 0.14;
export function calibrateDiabetes(pRaw: number): number {
  const p = Math.min(Math.max(pRaw, 1e-6), 1 - 1e-6);
  const shift = Math.log(DIABETES_BASE_RATE / (1 - DIABETES_BASE_RATE)); // log-odds của 50% là 0
  return sigmoid(Math.log(p / (1 - p)) + shift);
}

/** Mã nhóm tuổi của BRFSS: 1 = 18-24, 2 = 25-29, …, 12 = 75-79, 13 = từ 80. */
export function ageCode(age: number): number {
  return age < 25 ? 1 : Math.min(13, Math.floor((age - 25) / 5) + 2);
}

export const heartLevel = (p: number): 'low' | 'attention' | 'high' => (p < 0.3 ? 'low' : p < 0.5 ? 'attention' : 'high');

function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

export function assess(models: { stroke: any; heart: any; diabetes?: any }, input: RiskInput): RiskResult {
  const newest = input.readings[0];
  if (!newest) throw new Error('no_reading');
  // Số đo chưa đủ chuẩn (vừa ngủ dậy, vừa đi lại...) không dùng cho model và việc suy ra tăng huyết áp.
  // Riêng ngưỡng khẩn cấp vẫn xét số mới nhất bất kể chuẩn (an toàn trước).
  const trusted = input.readings.filter((r) => r.protocolOk !== false);
  const latest = trusted[0] ?? newest;
  const age = input.year - input.birthYear;
  const male = input.sex === 'male' ? 1 : 0;
  const b = (v: boolean | null) => (v ? 1 : 0);

  // Tăng huyết áp: người dùng đã khai, hoặc trung vị tối đa 3 lần đo gần nhất từ 140/90 trở lên.
  const recent = (trusted.length ? trusted : input.readings).slice(0, 3);
  const sysMed = median(recent.map((r) => r.systolic));
  const diaMed = median(recent.map((r) => r.diastolic));
  // AHA: không chẩn đoán từ một ngày; cần số đo ở ít nhất 2 ngày khác nhau.
  const days = new Set(recent.map((r) => r.measuredAt.slice(0, 10))).size;
  const hypertensionDerived = days >= 2 && (sysMed >= 140 || diaMed >= 90);
  const hyp = input.hypertension === true || hypertensionDerived;

  const pStroke = predictLogistic(models.stroke, [age, male, b(hyp), b(input.heartDisease), b(input.smoker)]);
  const pHeart = predictHgb(models.heart, [
    male,
    age,
    b(input.smoker),
    b(input.bpMeds),
    b(input.hadStroke),
    b(hyp),
    b(input.diabetes),
    latest.systolic,
    latest.diastolic,
    latest.pulse ?? NaN, // thiếu mạch thì dùng trung vị lúc huấn luyện
  ]);

  let diabetes: RiskResult['diabetes'] = null;
  const h = input.heightCm;
  const w = input.weightKg;
  if (models.diabetes && input.diabetes !== true && h && w && h > 100 && w > 25) {
    const bmi = Math.min(98, Math.max(12, w / ((h / 100) * (h / 100))));
    const raw = predictHgb(models.diabetes, [
      ageCode(age),
      bmi,
      b(hyp),
      b(input.highCholesterol ?? null),
      b(input.heartDisease),
      b(input.hadStroke),
      b(input.smoker),
      b(input.difficultyWalking ?? null),
    ]);
    const p = calibrateDiabetes(raw);
    diabetes = { p, level: diabetesLevel(p), bmi: Math.round(bmi * 10) / 10 };
  }

  const strokeLv = strokeLevel(pStroke);
  const heartLv = heartLevel(pHeart);
  let level: Level = worse(strokeLv, heartLv);
  // Luật cố định, không qua model: từng bị đột quỵ thì tối thiểu "cần chú ý"; cơn tăng huyết áp thì khẩn cấp.
  if (input.hadStroke) level = worse(level, 'attention');
  if (newest.systolic > 180 || newest.diastolic > 120) level = 'urgent'; // AHA: "cao hơn" 180/120

  const reasons: string[] = [];
  if (latest.systolic >= 140 || latest.diastolic >= 90) reasons.push('bp_high_now');
  else if (hyp) reasons.push('hypertension');
  if (input.hadStroke) reasons.push('prior_stroke');
  if (input.heartDisease) reasons.push('heart_disease');
  if (input.diabetes) reasons.push('diabetes');
  if (input.smoker) reasons.push('smoker');
  if (age >= 65) reasons.push('age_65');

  return {
    level,
    stroke: { p: pStroke, level: strokeLv },
    heart: { p: pHeart, level: heartLv },
    diabetes,
    reasons,
    bp: latest,
    hypertensionDerived,
    ageOutOfRange: age > 70,
  };
}
