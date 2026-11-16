// Đọc đơn thuốc từ CHỮ đã che thông tin cá nhân trên máy (ảnh gốc không bao giờ lên máy chủ).
// Mô hình chỉ được phép trích từ văn bản, mỗi mục phải kèm đoạn trích nguyên văn (evidence).
// Máy chủ kiểm lại từng đoạn trích có thật trong văn bản (so khớp mờ, cho sai 1-2 ký tự do đọc chữ)
// và gắn trạng thái: ok (khớp), fuzzy (khớp gần đúng), none (không tìm thấy → app để trống, tô đỏ).

export const MAX_TEXT = 6000;

export const MED_SYSTEM = `You extract a medication schedule from OCR text of a Vietnamese prescription, medicine bag or box.
The text may contain OCR mistakes and Vietnamese words such as: Sáng, Trưa, Chiều, Tối, viên, gói, ml, uống, trước ăn, sau ăn, khi cần.
Rules:
- Use ONLY what is written in the text. Never add a drug, strength or dose that is not there. If unsure, leave it out.
- For every slot, drug and as-needed drug copy a short verbatim "evidence" quote (max 80 chars) from the text.
- slot label must be one of: "Sáng","Trưa","Chiều","Tối" or a short custom label from the text. Do not output clock times.
- meal: "before_meal","after_meal","with_meal","empty","bedtime" or null.
- qty is a number per intake; unit is one of: viên, gói, ml, đơn vị, giọt.
- "prn" is for drugs taken only when needed (khi đau, khi sốt, khi cần...).
- days is the number of days of treatment if written, else null. recheck is the follow-up date as YYYY-MM-DD if written, else null.
Reply ONLY with JSON:
{"title":"","days":null,"recheck":null,"slots":[{"label":"","meal":null,"evidence":"","items":[{"name":"","strength":"","qty":1,"unit":"viên","evidence":""}]}],"prn":[{"name":"","instruction":"","evidence":""}]}`;

export type Status = 'ok' | 'fuzzy' | 'none';

export type ParsedItem = { name: string; strength: string | null; qty: number; unit: string; evidence: string; status: Status };
export type ParsedSlot = { label: string; meal: string | null; evidence: string; status: Status; items: ParsedItem[] };
export type ParsedPrn = { name: string; instruction: string | null; evidence: string; status: Status };
export type ParsedPlan = {
  title: string;
  days: number | null;
  recheck: string | null;
  slots: ParsedSlot[];
  prn: ParsedPrn[];
};

const UNITS = ['viên', 'gói', 'ml', 'đơn vị', 'giọt'];
const MEALS = ['before_meal', 'after_meal', 'with_meal', 'empty', 'bedtime'];

/** Chữ thường, bỏ dấu tiếng Việt, mọi ký tự không phải chữ/số thành một khoảng trắng. */
export function normText(s: string): string {
  return s
    .toLowerCase()
    .replace(/đ/g, 'd')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/** Khoảng cách sửa nhỏ nhất để `needle` khớp với MỘT đoạn con bất kỳ của `hay` (Sellers). */
export function approxDistance(needle: string, hay: string): number {
  const m = needle.length;
  if (m === 0) return 0;
  let prev = new Array<number>(m + 1);
  for (let i = 0; i <= m; i++) prev[i] = i;
  let best = m;
  for (let j = 1; j <= hay.length; j++) {
    const cur = new Array<number>(m + 1);
    cur[0] = 0; // đoạn con có thể bắt đầu ở bất kỳ đâu
    for (let i = 1; i <= m; i++) {
      const cost = needle[i - 1] === hay[j - 1] ? 0 : 1;
      cur[i] = Math.min(prev[i - 1] + cost, prev[i] + 1, cur[i - 1] + 1);
    }
    if (cur[m] < best) best = cur[m];
    prev = cur;
  }
  return best;
}

/** Kiểm đoạn trích có thật trong văn bản (đã chuẩn hoá). Đoạn quá ngắn không đủ làm bằng chứng. */
export function checkEvidence(evidence: string, hayNorm: string): Status {
  const e = normText(evidence);
  if (e.length < 4) return 'none';
  if (hayNorm.includes(e)) return 'ok';
  const allowed = e.length >= 20 ? 3 : e.length >= 10 ? 2 : 1;
  return approxDistance(e, hayNorm) <= allowed ? 'fuzzy' : 'none';
}

const RANK: Record<Status, number> = { none: 0, fuzzy: 1, ok: 2 };

const worst =(a: Status, b: Status): Status => (a === 'none' || b === 'none' ? 'none' : a === 'fuzzy' || b === 'fuzzy' ? 'fuzzy' : 'ok');

const str = (v: unknown, max: number): string => (typeof v === 'string' ? v.trim().slice(0, max) : '');

/** Làm sạch đầu ra của mô hình và gắn trạng thái bằng chứng theo văn bản gốc. */
export function cleanMedParse(parsed: unknown, sourceText: string): ParsedPlan {
  const hay = normText(sourceText);
  const o = (parsed ?? {}) as Record<string, unknown>;

  const days = typeof o.days === 'number' && Number.isFinite(o.days) && o.days >= 1 && o.days <= 365 ? Math.round(o.days) : null;
  const recheck = typeof o.recheck === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(o.recheck) && !Number.isNaN(Date.parse(o.recheck)) ? o.recheck : null;

  const slots: ParsedSlot[] = [];
  for (const rs of (Array.isArray(o.slots) ? o.slots : []).slice(0, 8)) {
    const s = (rs ?? {}) as Record<string, unknown>;
    const label = str(s.label, 30);
    if (!label) continue;
    const meal = typeof s.meal === 'string' && MEALS.includes(s.meal) ? s.meal : null;
    const evidence = str(s.evidence, 200);
    const items: ParsedItem[] = [];
    for (const ri of (Array.isArray(s.items) ? s.items : []).slice(0, 12)) {
      const i = (ri ?? {}) as Record<string, unknown>;
      const name = str(i.name, 80);
      if (!name) continue;
      const ev = str(i.evidence, 200);
      const qtyRaw = typeof i.qty === 'number' ? i.qty : Number(i.qty);
      const qty = Number.isFinite(qtyRaw) && qtyRaw > 0 && qtyRaw <= 20 ? qtyRaw : 1;
      const unit = typeof i.unit === 'string' && UNITS.includes(i.unit) ? i.unit : 'viên';
      // Tên thuốc cũng phải có trong văn bản: chặn việc mô hình bịa ra thuốc rồi dán một đoạn trích khác.
      const status = worst(checkEvidence(ev, hay), checkEvidence(name, hay));
      items.push({ name, strength: str(i.strength, 30) || null, qty, unit, evidence: ev, status });
    }
    const status = checkEvidence(evidence, hay);
    // Mô hình hay trả mỗi thuốc một cữ cùng tên ("Sáng" hai lần). Một cữ là MỘT túi, nên gộp theo tên.
    const same = slots.find((x) => normText(x.label) === normText(label));
    if (same) {
      same.items.push(...items);
      same.meal = same.meal === meal ? meal : null; // hai chỉ dẫn ăn uống khác nhau thì để trống cho người kiểm tra
      if (RANK[status] > RANK[same.status]) same.status = status;
      continue;
    }
    slots.push({ label, meal, evidence, status, items });
  }

  const prn: ParsedPrn[] = [];
  for (const rp of (Array.isArray(o.prn) ? o.prn : []).slice(0, 6)) {
    const p = (rp ?? {}) as Record<string, unknown>;
    const name = str(p.name, 80);
    if (!name) continue;
    const ev = str(p.evidence, 200);
    prn.push({
      name,
      instruction: str(p.instruction, 200) || null,
      evidence: ev,
      status: worst(checkEvidence(ev, hay), checkEvidence(name, hay)),
    });
  }

  return { title: str(o.title, 80), days, recheck, slots, prn };
}
