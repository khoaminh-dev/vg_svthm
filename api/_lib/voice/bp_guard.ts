/**
 * Luật cứng cho lời khuyên huyết áp (chuẩn AHA/ACC): sau số đo cao thì NGỒI YÊN nghỉ 5 phút rồi đo lại.
 * Gắng sức (đi lại, vận động) làm huyết áp tăng, nên không bao giờ được khuyên.
 * Lời do mô hình tự sinh mà nói về huyết áp kèm lời khuyên cấm sẽ bị thay bằng câu an toàn.
 */

/** Câu an toàn duy nhất thay cho lời khuyên cấm. */
export const BP_SAFE_REST = (hon: string): string =>
  `Nếu số đo hơi cao, ${hon} ngồi yên, tựa lưng, không nói chuyện trong 5 phút rồi mình đo lại nhé. ${hon[0].toUpperCase()}${hon.slice(1)} đừng đi lại hay vận động trước khi đo.`;

const strip = (s: string): string =>
  s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/đ/g, 'd');

const BP_TOPIC = /huyet ap|do lai|so do|tam thu|tam truong|mmhg/;

// Lời khuyên hành vi bị cấm quanh chuyện huyết áp. Chuỗi đã bỏ dấu, chữ thường.
const FORBIDDEN = [
  /\bdi (bo|lai|vong|dao|loanh quanh|nhieu)\b/,
  /\bvan dong\b/,
  /\btap (the duc|luyen|nhe)\b/,
  /\bchay (bo|nhay)\b/,
  /\bleo (cau thang|doc)\b/,
  /\bhoat dong (nhe|manh)\b/,
  /\b(uong|giam|ngung|bo|doi|tang) (them )?(thuoc|lieu)\b/,
  /\bdung day\b/,
];

const NEGATION = /(dung|khong|chua nen|tranh|cam|han che)\s+(tu\s+)?(\S+\s+){0,4}$/;

/** Lời khuyên có nói về huyết áp và chứa nội dung bị cấm (câu phủ định như "đừng đi lại" thì hợp lệ). */
export function violatesBpAdvice(text: string): boolean {
  const t = strip(text);
  if (!BP_TOPIC.test(t)) return false;
  return FORBIDDEN.some((re) => {
    const g = new RegExp(re.source, 'g');
    for (const m of t.matchAll(g)) {
      const before = t.slice(Math.max(0, (m.index ?? 0) - 32), m.index ?? 0);
      if (!NEGATION.test(before)) return true;
    }
    return false;
  });
}

/** Trả lại [text] nếu hợp lệ, ngược lại là câu an toàn. [onBlock] để ghi sự kiện `voice_bp_unscripted`. */
export function guardBpSay(text: string, hon: string, onBlock?: (original: string) => void): string {
  if (!violatesBpAdvice(text)) return text;
  onBlock?.(text);
  return BP_SAFE_REST(hon);
}
