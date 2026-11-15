// Vy trả lời về tình trạng sức khoẻ. KHÔNG dùng mô hình ngôn ngữ để viết câu: số liệu do server đọc từ
// bảng của chính người dùng rồi điền vào khuôn câu cố định, nên không thể bịa số và không gửi số liệu ra ngoài.
// Vy không chẩn đoán, không nói tên thuốc, không bảo uống hay bỏ thuốc.

export type Topic = 'general' | 'trend' | 'risk' | 'habit' | 'other';
export const TOPICS: Topic[] = ['general', 'trend', 'risk', 'habit', 'other'];

export function topicOf(v: unknown): Topic {
  const s = typeof v === 'string' ? v.trim().toLowerCase() : '';
  return (TOPICS as string[]).includes(s) ? (s as Topic) : 'general';
}

export type BpRow = { systolic: number; diastolic: number; pulse?: number | null; measured_at: string };
export type Assessed = { level: string; reasons: string[] };
export type HealthCtx = {
  hon: string;
  now: Date;
  /** Các lần đo, mới nhất trước. */
  readings: BpRow[];
  assessment: Assessed | null;
  hasProfile: boolean;
};
export type HealthSay = {
  say: string;
  sayClass: 'other' | 'important';
  level: string | null;
  systolic: number | null;
  diastolic: number | null;
};

const DAY = 86_400_000;

function cap(h: string): string {
  return h.charAt(0).toUpperCase() + h.slice(1);
}

/** Cùng ngưỡng với màn Huyết áp, chỉ dùng để gọi tên cho dễ nghe. */
export function bpWord(s: number, d: number): string {
  if (s >= 140 || d >= 90) return 'cao';
  if (s >= 130 || d >= 80) return 'hơi cao';
  if (s < 90 || d < 60) return 'hơi thấp';
  return 'bình thường';
}

const REASON: Record<string, (h: string) => string> = {
  bp_high_now: () => 'huyết áp lần đo gần nhất khá cao',
  hypertension: (h) => `${h} có tăng huyết áp`,
  prior_stroke: (h) => `${h} từng bị đột quỵ`,
  heart_disease: (h) => `${h} có bệnh tim`,
  diabetes: (h) => `${h} có tiểu đường`,
  smoker: (h) => `${h} đang hút thuốc`,
  age_65: (h) => `${h} trên 65 tuổi`,
};

function join(list: string[]): string {
  if (list.length <= 1) return list[0] ?? '';
  return `${list.slice(0, -1).join(', ')} và ${list[list.length - 1]}`;
}

function ago(days: number): string {
  if (days <= 0) return 'hôm nay';
  if (days === 1) return 'hôm qua';
  return `${days} ngày trước`;
}

function daysSince(iso: string, now: Date): number {
  return Math.max(0, Math.floor((now.getTime() - new Date(iso).getTime()) / DAY));
}

function last7(ctx: HealthCtx): BpRow[] {
  const from = ctx.now.getTime() - 7 * DAY;
  return ctx.readings.filter((r) => new Date(r.measured_at).getTime() >= from);
}

function mean(xs: number[]): number {
  return Math.round(xs.reduce((a, b) => a + b, 0) / xs.length);
}

export function buildHealthSay(topic: Topic, ctx: HealthCtx): HealthSay {
  const h = ctx.hon;
  const H = cap(h);
  const latest = ctx.readings[0] ?? null;
  const base = {
    level: ctx.assessment?.level ?? null,
    systolic: latest?.systolic ?? null,
    diastolic: latest?.diastolic ?? null,
  };
  const out = (say: string, important = false): HealthSay => ({ say, sayClass: important ? 'important' : 'other', ...base });

  // Câu hỏi y khoa chung: không trả lời nội dung, chỉ chỉ đường.
  if (topic === 'other') {
    return out(`Việc này ${h} nên hỏi bác sĩ nhé. Nếu ${h} thấy đau ngực, khó thở, méo miệng hoặc yếu liệt, hãy gọi 115 ngay.`);
  }

  if (!latest) {
    return out(`${H} chưa đo huyết áp lần nào. ${H} bấm Đo huyết áp để mình bắt đầu nhé.`);
  }

  const s = latest.systolic;
  const d = latest.diastolic;
  const age = daysSince(latest.measured_at, ctx.now);

  // Số đo rất cao và còn mới: luôn nói trước, bất kể hỏi gì.
  if ((s >= 180 || d >= 120) && age <= 1) {
    return out(
      `Huyết áp lần đo gần nhất của ${h} rất cao, ${s} trên ${d}. Nếu ${h} đau ngực, yếu liệt hoặc nói khó, hãy gọi 115 ngay. Nếu không có triệu chứng, ${h} ngồi nghỉ vài phút rồi đo lại nhé.`,
      true,
    );
  }

  const stale = age >= 3 ? `Lần đo gần nhất của ${h} là ${ago(age)}, ${s} trên ${d}. ` : '';
  const remeasure = age >= 3 ? ` ${H} nên đo lại để mình theo dõi cho đúng nhé.` : '';

  if (topic === 'habit') {
    const n = last7(ctx).length;
    const when = `Lần đo gần nhất cách đây ${age <= 0 ? 'chưa tới một ngày' : `${age} ngày`}.`;
    const nudge = n < 3 ? ` ${H} nên đo đều hơn, mỗi ngày một lần nhé.` : ` ${H} đo rất đều, tiếp tục nhé.`;
    return out(`Trong 7 ngày qua ${h} đã đo ${n} lần. ${when}${nudge}`);
  }

  if (topic === 'trend') {
    const week = last7(ctx);
    if (week.length < 2) {
      return out(`${stale || ''}${H} mới đo ${week.length} lần trong tuần này nên chưa thấy được xu hướng. ${H} đo đều mỗi ngày để mình theo dõi nhé.`);
    }
    const sys = mean(week.map((r) => r.systolic));
    const dia = mean(week.map((r) => r.diastolic));
    const half = Math.floor(week.length / 2);
    const newer = mean(week.slice(0, half).map((r) => r.systolic)); // mảng mới nhất trước
    const older = mean(week.slice(week.length - half).map((r) => r.systolic));
    const diff = newer - older;
    const dir = diff >= 5 ? 'đang có xu hướng tăng' : diff <= -5 ? 'đang có xu hướng giảm' : 'khá ổn định';
    return out(`Tuần này ${h} đo ${week.length} lần, trung bình ${sys} trên ${dia}, ${bpWord(sys, dia)} và ${dir}.${remeasure}`);
  }

  if (topic === 'risk') {
    if (!ctx.hasProfile) return out(`${H} cần nhập hồ sơ sức khoẻ trước thì con mới đánh giá được nhé.`);
    const a = ctx.assessment;
    if (!a) return out(`Con chưa có đánh giá cho ${h}. ${H} đo huyết áp để nhận đánh giá nhé.`);
    const levelWord = a.level === 'low' ? 'đang thấp' : a.level === 'attention' ? 'cần chú ý' : 'đang cao';
    const reasons = a.reasons.map((c) => REASON[c]?.(h)).filter((x): x is string => !!x).slice(0, 2);
    const advice =
      a.level === 'low'
        ? `${H} cứ đo huyết áp đều nhé.`
        : a.level === 'attention'
          ? `${H} nên đo mỗi ngày và gặp bác sĩ trong vài tuần tới.`
          : `${H} nên đi khám sớm để bác sĩ kiểm tra tim mạch.`;
    if (a.level === 'low') return out(`${stale}Mức nguy cơ của ${h} ${levelWord}. ${advice}`);
    const bpNormal = !a.reasons.includes('bp_high_now') && bpWord(s, d) === 'bình thường';
    const lead = bpNormal && reasons.length ? `Số đo gần nhất ${s} trên ${d} là bình thường, nhưng ${join(reasons)} nên mức nguy cơ ${levelWord}.` : reasons.length ? `Mức nguy cơ của ${h} ${levelWord}, chủ yếu vì ${join(reasons)}.` : `Mức nguy cơ của ${h} ${levelWord}.`;
    return out(`${stale}${lead} ${advice}`);
  }

  // general: tình trạng chung
  const w = bpWord(s, d);
  let line = `${stale || `Lần đo gần nhất của ${h} là ${s} trên ${d}, ${w}.`}`;
  if (stale) line += `Huyết áp lần đó ${w}.`;
  const a = ctx.assessment;
  if (a && a.level !== 'low') {
    line += a.level === 'attention' ? ` Mức nguy cơ cần chú ý, ${h} nên gặp bác sĩ trong vài tuần tới.` : ` Mức nguy cơ đang cao, ${h} nên đi khám sớm.`;
  } else if (a) {
    line += ` Mức nguy cơ đang thấp.`;
  }
  return out(line + remeasure);
}
