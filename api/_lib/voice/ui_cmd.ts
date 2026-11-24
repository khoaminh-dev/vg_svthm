import { dialect } from './dialect.js';

// Người lái màn hình, phía não: ghép lời nói với các điều khiển và danh sách CÓ THẬT đang hiện trên màn hình của người dùng.
// Quy tắc (xem docs/VY_LIVE_SAN_PHAM_KE_HOACH.md mục 13.2, 13.3):
//  - Chỉ làm việc với `controls`/`lists` mà app đã gửi lên (không bịa điều khiển).
//  - Hộp thoại đang mở che màn phía sau: chỉ ghép với điều khiển của hộp thoại.
//  - Mức xác nhận nằm trên điều khiển (0 làm ngay, 1 làm rồi đọc lại, 2 hỏi lại, 3 người dùng tự bấm). Mức 3 KHÔNG BAO GIỜ được trả về để bấm.
//  - Luật mờ trước (số thứ tự, nhãn, từ đồng nghĩa); không gọi mô hình ở đây.

export type UiLevel = 0 | 1 | 2 | 3;
export type UiKind = 'button' | 'toggle' | 'tab' | 'field' | 'item';

export type UiControl = {
  id: string;
  label: string;
  aliases: string[];
  kind: UiKind;
  level: UiLevel;
  enabled: boolean;
  /** Chỉ có với công tắc: đang bật hay tắt. */
  value?: boolean;
  /** Câu Vy nói sau khi làm xong (mỗi việc nói đúng việc đó). */
  say?: string;
};

export type UiList = { id: string; title: string; items: { n: number; title: string }[] };

export type UiContext = {
  role: 'elder' | 'family' | '';
  route: string;
  dialog: { id: string; title: string; controls: UiControl[] } | null;
  controls: UiControl[];
  lists: UiList[];
  player: { open: boolean; playing: boolean };
  /** Thói quen nghe/xem do app gửi (đã nhớ trên máy): chủ đề hay nghe, bài đang xem dở, bài vừa nghe. Có thể vắng. */
  habit?: { top: string; topics: string[]; resume: string; last: string };
};

export type UiCmd =
  | { kind: 'invoke'; control: UiControl; set?: boolean }
  | { kind: 'choose'; list: UiList; n: number }
  | { kind: 'refuse'; control: UiControl; why: 'level3' | 'disabled' | 'already' }
  | { kind: 'ambiguous'; options: UiControl[] }
  | { kind: 'out_of_range'; list: UiList; n: number };

const MAX_CONTROLS = 60;
const MAX_LISTS = 3;
const MAX_ITEMS = 10;

function s(v: unknown, max: number): string {
  return typeof v === 'string' ? v.slice(0, max) : '';
}

/** Viết thường, bỏ dấu, gộp khoảng trắng (cùng quy tắc với `norm` của dm.ts; chép lại để khỏi phụ thuộc vòng). */
export function nz(x: string): string {
  return x
    .toLowerCase()
    .replace(/đ/g, 'd')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9 ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function parseControl(v: unknown): UiControl | null {
  if (!v || typeof v !== 'object') return null;
  const r = v as Record<string, unknown>;
  const id = s(r.id, 60);
  const label = s(r.label, 60);
  if (!id || !label) return null;
  const kinds: UiKind[] = ['button', 'toggle', 'tab', 'field', 'item'];
  const kind = kinds.includes(r.kind as UiKind) ? (r.kind as UiKind) : 'button';
  const lv = Number(r.level);
  // Không rõ mức thì coi là mức CAO NHẤT (người dùng tự bấm): thiên về an toàn.
  const level = (lv === 0 || lv === 1 || lv === 2 || lv === 3 ? lv : 3) as UiLevel;
  const c: UiControl = {
    id,
    label,
    aliases: Array.isArray(r.aliases) ? r.aliases.slice(0, 10).map((a) => s(a, 60)).filter(Boolean) : [],
    kind,
    level,
    enabled: r.enabled !== false,
  };
  if (typeof r.value === 'boolean') c.value = r.value;
  const say = s(r.say, 120);
  if (say) c.say = say;
  return c;
}

/** Kiểm tra và cắt gọn `ui.context` do app gửi lên. Trả về undefined nếu không có hoặc hỏng. */
export function parseUiContext(v: unknown): UiContext | undefined {
  if (!v || typeof v !== 'object') return undefined;
  const o = v as Record<string, unknown>;
  const controls = Array.isArray(o.controls)
    ? o.controls.slice(0, MAX_CONTROLS).map(parseControl).filter((c): c is UiControl => !!c)
    : [];
  const lists: UiList[] = [];
  if (Array.isArray(o.lists)) {
    for (const l of o.lists.slice(0, MAX_LISTS)) {
      if (!l || typeof l !== 'object') continue;
      const r = l as Record<string, unknown>;
      const id = s(r.id, 60);
      if (!id || !Array.isArray(r.items)) continue;
      const items = r.items.slice(0, MAX_ITEMS).map((it, i) => {
        const q = (it ?? {}) as Record<string, unknown>;
        return { n: Number(q.n) > 0 ? Math.floor(Number(q.n)) : i + 1, title: s(q.title, 80) };
      }).filter((it) => it.title);
      if (items.length) lists.push({ id, title: s(r.title, 60), items });
    }
  }
  let dialog: UiContext['dialog'] = null;
  if (o.dialog && typeof o.dialog === 'object') {
    const d = o.dialog as Record<string, unknown>;
    const id = s(d.id, 60);
    if (id) {
      dialog = {
        id,
        title: s(d.title, 80),
        controls: Array.isArray(d.controls)
          ? d.controls.slice(0, 12).map(parseControl).filter((c): c is UiControl => !!c)
          : [],
      };
    }
  }
  const p = (o.player && typeof o.player === 'object' ? o.player : {}) as Record<string, unknown>;
  let habit: UiContext['habit'];
  if (o.habit && typeof o.habit === 'object') {
    const h = o.habit as Record<string, unknown>;
    const topics = Array.isArray(h.topics) ? h.topics.map((x) => s(x, 40)).filter(Boolean).slice(0, 3) : [];
    const top = s(h.top, 40) || topics[0] || '';
    habit = { top, topics: top && !topics.includes(top) ? [top, ...topics].slice(0, 3) : topics, resume: s(h.resume, 80), last: s(h.last, 80) };
    if (!habit.top && !habit.resume && !habit.last) habit = undefined;
  }
  return {
    role: o.role === 'elder' || o.role === 'family' ? o.role : '',
    route: s(o.route, 60),
    dialog,
    controls,
    lists,
    player: { open: p.open === true, playing: p.playing === true },
    ...(habit ? { habit } : {}),
  };
}

// ---------- gọt lời nói ----------

const PRON = '(toi|bac|co|chu|ong|ba|anh|chi|em|con)';
const LEAD = new RegExp(`^((u|um|uhm|uh|o|a|da|vang|roi|the|thi|ma|vay|nao|ok|okay|nay|vy oi|vy|lam on|cho ${PRON}|giup ${PRON}|${PRON} muon|${PRON} can)\\s+)+`);
const TRAIL = new RegExp(`(\\s+(cho ${PRON}|giup ${PRON}|de ${PRON} (xem|nghe)|di|nhe|nha|a|ne|nao|voi|luon|ngay|duoc khong|dum|len|giup|do|day))+$`);

function tidyText(t: string): string {
  const r = t.replace(LEAD, '').replace(TRAIL, '').trim();
  return r || t;
}

// ---------- số thứ tự ----------

// Số đếm tiếng Việt dễ trùng nghĩa sau khi bỏ dấu (sáu/sau, năm/nam, tư/tu, đầu/đau): đổi sang chữ số TRƯỚC khi bỏ dấu.
const W = (w: string) => new RegExp(`(?<![\p{L}\p{N}])${w}(?![\p{L}\p{N}])`, 'gu');
const DIACRITIC_NUMS: [RegExp, string][] = [
  [W('sáu'), '6'], [W('bảy'), '7'], [W('tám'), '8'], [W('chín'), '9'], [W('mười'), '10'],
  [W('năm'), '5'], [W('bốn'), '4'], [W('tư'), '4'],
];
const ORD_WORDS: Record<string, number> = { nhat: 1, dau: 1, 'dau tien': 1, 'tren cung': 1, mot: 1, hai: 2, ba: 3 };
const ORD_ALT = '(dau tien|tren cung|duoi cung|cuoi cung|cuoi|chot|nhat|dau|mot|hai|ba|[0-9]{1,2})';
/** "… trong danh sách", "ở trên màn hình": chỉ chỉ chỗ, không phải nội dung. */
const ORD_TAIL = /\s+(?:trong|o|tren|ben|cua) (?:danh sach|ket qua|list|trang|man hinh|nhung cai nay|may cai nay)(?: do| nay| kia| tren)?$/;
/** "tôi muốn", "cho tôi": đệm đầu câu. */
const ORD_LEAD = /^(?:toi |minh )?(?:muon|can|thich|nho) /;
const ORD_NOUN = '(?:cai|bai|video|clip|so|muc|ket qua|bai hat|phim|nguoi|dong|tin|ten)';
const ORD_VERB = '(?:mo|phat|chon|bam|xem|nghe|cho nghe|cho xem|bat|lay)';
const ORD_RE = new RegExp(`^(${ORD_VERB} )?(${ORD_NOUN} )?(thu |so )?${ORD_ALT}(?: do| nay| di| nhe)?$`);

/** "cái thứ hai", "số 3", "bài đầu tiên", "bài cuối": số thứ tự trong danh sách; null nếu không phải.
 *  Chữ dễ nhầm với từ thường ("đầu", "nhất", "cuối") chỉ nhận khi đi kèm danh từ/động từ/"thứ", để câu như "đau" không chọn nhầm. */
function ordinalOf(t: string): number | 'last' | null {
  let m = t.match(ORD_RE);
  if (!m) {
    // "tôi muốn xem video đầu tiên trong danh sách": gọt đệm đầu và phần chỉ chỗ rồi thử lại.
    const s = t.replace(ORD_LEAD, '').replace(ORD_TAIL, '').trim();
    if (s !== t) m = s.match(ORD_RE);
  }
  if (!m) return null;
  const w = m[4];
  const anchored = !!(m[1] || m[2] || m[3]);
  if (w === 'duoi cung') return 'last';
  if (w === 'cuoi' || w === 'cuoi cung' || w === 'chot') return anchored || w === 'cuoi cung' ? 'last' : null;
  if (/^[0-9]+$/.test(w)) return Number(w);
  if (w === 'dau' || w === 'nhat') return anchored ? 1 : null;
  return ORD_WORDS[w] ?? null;
}

/** Số thứ tự nằm đâu đó trong câu (dùng khi nội dung đã bị coi nhầm là từ khoá tìm): "đầu tiên", "thứ ba", "số 5", "cuối", "trên cùng". */
export function ordinalFromText(t: string): number | 'last' | null {
  if (/\b(cuoi cung|cuoi|duoi cung|chot)\b/.test(t)) return 'last';
  const m = t.match(/\b(?:thu|so) (nhat|hai|ba|[0-9]{1,2})\b/);
  if (m) return m[1] === 'nhat' ? 1 : m[1] === 'hai' ? 2 : m[1] === 'ba' ? 3 : Number(m[1]);
  if (/\b(dau tien|tren cung|dau)\b/.test(t)) return 1;
  return null;
}

// ---------- ghép nhãn ----------

function lev(a: string, b: string): number {
  const m = a.length, n = b.length;
  if (!m) return n;
  if (!n) return m;
  let prev = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) {
    const cur = [i];
    for (let j = 1; j <= n; j++) {
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return prev[n];
}

/** Điểm khớp 0..1 giữa cụm người dùng nói và một điều khiển (nhãn + từ đồng nghĩa). */
export function scoreControl(phrase: string, c: UiControl): number {
  const p = nz(phrase);
  if (!p) return 0;
  let best = 0;
  for (const name of [c.label, ...c.aliases]) {
    const n = nz(name);
    if (!n) continue;
    let sc = 0;
    // Chỉ nhận: đúng nguyên cụm, cụm nói chứa trọn tên, hoặc sai một ký tự (nghe nhầm). KHÔNG nhận khớp một phần
    // (nói "huyết áp" không được bấm nhầm nút "Đo huyết áp"); cách gọi khác phải khai báo trong `aliases`.
    if (n === p) sc = 1;
    else if (n.length >= 4 && ` ${p} `.includes(` ${n} `)) sc = 0.9;
    else if (n.length >= 6 && lev(n, p) <= 1) sc = 0.75;
    if (sc > best) best = sc;
  }
  return best;
}

const ON_VERBS = ['bat', 'mo', 'hien', 'cho phep'];
const OFF_VERBS = ['tat', 'dong', 'an', 'khong hien', 'ngung'];
const VERB_RE = /^(bam vao|bam|chon|bat|tat|mo|vao|dong|hien|an|ngung|xem|cho toi xem|cho xem|doi|cho phep|khong hien)\s+(?:nut |muc |cong tac |phan |tab |man hinh |trang )?(.+)$/;

type Match = { control: UiControl; score: number };

function bestMatches(phrase: string, pool: UiControl[]): Match[] {
  return pool
    .map((control) => ({ control, score: scoreControl(phrase, control) }))
    .filter((m) => m.score >= 0.75)
    .sort((a, b) => b.score - a.score);
}

/** Câu nói → việc cần làm trên màn hình hiện có, hoặc null nếu không khớp (để các luật khác xử lý). */
export function resolveUiCommand(text: string, ctx: UiContext): UiCmd | null {
  let raw = text.toLowerCase().replace(/nhấn/g, 'bấm');
  for (const [re, to] of DIACRITIC_NUMS) raw = raw.replace(re, to);
  const t0 = dialect(nz(raw));
  if (!t0) return null;
  // Gọt từ đệm có thể xoá nhầm một phần nhãn ("đã uống" mất "đã", "ở lại" mất "ở"): thử câu gốc trước, rồi câu đã gọt.
  const tidied = tidyText(t0);
  const first = resolveNormalized(t0, ctx);
  if (first || tidied === t0) return first;
  return resolveNormalized(tidied, ctx);
}

function resolveNormalized(t: string, ctx: UiContext): UiCmd | null {

  // 1) Hộp thoại che màn phía sau: chỉ ghép với điều khiển của hộp thoại.
  const scope = ctx.dialog ? ctx.dialog.controls : ctx.controls;

  // 2) Số thứ tự trong danh sách đang hiện ("cái thứ hai", "số 3", "bài đầu"). Hộp thoại mở thì không chọn danh sách phía sau.
  if (!ctx.dialog && ctx.lists.length) {
    const o = ordinalOf(t);
    if (o !== null) {
      const noun = /\b(bai|video|clip|phim)\b/.test(t) ? 'video' : '';
      const list = (noun && ctx.lists.find((l) => nz(`${l.id} ${l.title}`).includes(noun))) || ctx.lists[0];
      const n = o === 'last' ? list.items.length : o;
      if (n < 1 || n > list.items.length) return { kind: 'out_of_range', list, n };
      return { kind: 'choose', list, n };
    }
  }

  // 3) Có động từ + nhãn: "bấm đã uống", "bật chữ phụ đề", "mở huyết áp".
  let verb = '';
  let phrase = t;
  const vm = t.match(VERB_RE);
  if (vm) {
    verb = vm[1] === 'bam vao' ? 'bam' : vm[1];
    phrase = vm[2].trim();
  }
  const whole = bestMatches(t, scope).filter((m) => m.score >= 0.95);
  // Khớp trọn cả câu ("đồng ý" khớp nút Đồng ý) thì chữ đầu câu không phải động từ ("đồng" ≠ "đóng").
  if (whole.length) verb = '';
  let ms = whole;
  if (!ms.length && vm) ms = bestMatches(phrase, scope);
  // Không có động từ: chỉ nhận khi KHỚP ĐÚNG nhãn/từ đồng nghĩa (tránh bắt nhầm câu nói thường).
  if (!vm && !whole.length) return null;
  if (!ms.length) return null;

  const top = ms[0];
  const rivals = ms.filter((m) => m.control.id !== top.control.id && top.score - m.score < 0.06);
  if (rivals.length) return { kind: 'ambiguous', options: [top.control, ...rivals.map((r) => r.control)].slice(0, 3) };

  const c = top.control;
  if (c.level === 3) return { kind: 'refuse', control: c, why: 'level3' };
  if (!c.enabled) return { kind: 'refuse', control: c, why: 'disabled' };

  // "tắt nhạc", "dừng", "đóng"... không phải lệnh bấm một nút thường (video có luật riêng ở dm.ts).
  if (c.kind !== 'toggle' && OFF_VERBS.includes(verb)) return null;

  if (c.kind === 'toggle') {
    // Công tắc: cần biết bật hay tắt (động từ), không đoán.
    const on = ON_VERBS.includes(verb);
    const off = OFF_VERBS.includes(verb);
    if (!on && !off) return null;
    const want = on;
    if (c.value === want) return { kind: 'refuse', control: c, why: 'already' };
    return { kind: 'invoke', control: c, set: want };
  }
  return { kind: 'invoke', control: c };
}
