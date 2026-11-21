// Chuẩn hoá nội dung tin nhắn trước khi gửi: SỬA CHUẨN CÂU, KHÔNG VIẾT LẠI.
// Mô hình (Groq) chỉ được viết hoa, thêm dấu câu, sửa lỗi nhận dạng rõ ràng, bỏ từ đệm đầu câu. Kết quả của mô hình luôn bị
// kiểm bằng luật ([acceptRefined]); không qua thì dùng bản gọt bằng luật ([finishMessage]). Tin gửi đi không bao giờ do mô hình tự do quyết.

import { cleanContent, lev, norm } from './dm.js';

const LEAD_FILLER = new Set(['o', 'u', 'um', 'uhm', 'uh', 'a', 'e', 'hm', 'hmm', 'er', 'ah', 'ua']);
const NEGATION = ['khong', 'chua', 'dung', 'khoi', 'chang', 'dau'];
const QUESTION_END = new Set(['chua', 'khong', 'nhi', 'sao', 'gi', 'nao', 'ai', 'dau', 'ha', 'the']);

function tokens(s: string): string[] {
  return norm(s).split(' ').filter(Boolean);
}

function lowerFirst(s: string): string {
  return s ? s.charAt(0).toLowerCase() + s.slice(1) : s;
}

function upperFirst(s: string): string {
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : s;
}

/** Thêm dấu kết câu nếu thiếu: "?" khi câu kết thúc kiểu hỏi, còn lại ".". */
export function ensureEnd(s: string): string {
  const t = s.trim();
  if (!t || /[.?!…]$/.test(t)) return t;
  const last = tokens(t).at(-1) ?? '';
  return t + (QUESTION_END.has(last) ? '?' : '.');
}

/** Bản gọt bằng luật (không mô hình): bỏ từ đệm đầu, gọn khoảng trắng, viết hoa, thêm dấu kết câu.
 *  verb "hoi" (hỏi): tin là câu hỏi gửi cho người nhận → "Hải ăn cơm chưa?". */
export function finishMessage(raw: string, recipient: string, verb?: string): string {
  let t = cleanContent(raw).replace(/\s+([,.?!])/g, '$1').trim();
  // bỏ từ đệm đầu câu ("ừ", "ờ") kể cả khi có dấu
  const first = tokens(t)[0] ?? '';
  if (LEAD_FILLER.has(first) && tokens(t).length > 1) t = cleanContent(t.split(/\s+/).slice(1).join(' '));
  if (!t) return raw.trim();
  if (verb === 'hoi' && recipient.trim()) {
    const name = upperFirst(recipient.trim());
    t = `${name} ${lowerFirst(t)}`;
    t = t.replace(/[.!…]+$/, '');
    return /\?$/.test(t) ? t : `${t}?`;
  }
  return ensureEnd(upperFirst(t));
}

/** Kết quả của mô hình có đáng tin không? Chỉ nhận khi giữ đủ từ ngữ, số, phủ định; không thêm ý lạ; không dài bất thường. */
export function acceptRefined(raw: string, out: string, recipient = ''): boolean {
  const o = out.trim();
  if (!o || o.length > 500 || /[\n\r{}<>]/.test(o)) return false;
  const rt = tokens(raw).filter((t) => !LEAD_FILLER.has(t));
  const ot = tokens(o);
  if (!rt.length || !ot.length) return false;
  const same = (a: string, b: string) => a === b || (a.length >= 4 && b.length >= 4 && lev(a, b) <= 1);
  // số (giờ, ngày, số điện thoại...) phải y nguyên
  const digits = (s: string) => (norm(s).match(/\d+/g) ?? []).join(',');
  if (digits(raw) !== digits(o)) return false;
  // đủ từ ngữ
  const covered = rt.filter((t) => ot.some((x) => same(x, t))).length;
  if (rt.length <= 3 ? covered < rt.length : covered / rt.length < 0.85) return false;
  // giữ phủ định (đổi nghĩa là lỗi nặng nhất)
  for (const n of NEGATION) if (rt.includes(n) && !ot.includes(n)) return false;
  // không thêm ý lạ (cho phép tên người nhận)
  const allowed = tokens(recipient);
  const extra = ot.filter((x) => !rt.some((t) => same(x, t)) && !allowed.some((a) => same(x, a)));
  if (extra.length > Math.max(1, Math.floor(rt.length * 0.2))) return false;
  if (o.length > raw.length * 1.5 + recipient.length + 6) return false;
  return true;
}

export const REFINE_SYSTEM = `Bạn chuẩn hoá một tin nhắn tiếng Việt vừa được nhận dạng từ giọng nói. Chỉ trả JSON {"text": "..."}.
Việc DUY NHẤT được làm:
1. Viết hoa chữ đầu câu và tên riêng; thêm dấu câu (. , ?) cho đúng.
2. Sửa lỗi dấu hoặc chính tả RÕ RÀNG do nhận dạng giọng nói.
3. Bỏ từ đệm vô nghĩa ở đầu câu (ờ, ừm, à) và từ lặp do ngập ngừng.
TUYỆT ĐỐI KHÔNG: thêm ý, bớt ý, đổi nghĩa, đổi từ xưng hô hay ngôi, đổi số/giờ/tên, dịch, viết lại hay diễn giải bằng lời khác.
Không chắc thì trả lại nguyên văn. Giữ nguyên cách nói của người dùng.
Nếu có "động từ" là hỏi: tin là câu hỏi gửi cho người nhận, bắt đầu bằng tên người nhận rồi tới câu hỏi, kết thúc bằng "?".
Ví dụ:
{"nội dung": "mai bác về đến nhà lúc ba giờ", "người nhận": "Lan", "động từ": ""} → {"text": "Mai bác về đến nhà lúc ba giờ."}
{"nội dung": "ừm hôm nay bác hơi mệt mệt", "người nhận": "Lan", "động từ": ""} → {"text": "Hôm nay bác hơi mệt."}
{"nội dung": "ăn cơm chưa", "người nhận": "Hải", "động từ": "hỏi"} → {"text": "Hải ăn cơm chưa?"}
{"nội dung": "con nhớ uống thuốc nha", "người nhận": "Hải", "động từ": "bảo"} → {"text": "Con nhớ uống thuốc nha."}`;
