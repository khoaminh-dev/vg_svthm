/**
 * Vy cho người thân (vai trò Gia đình): hỏi về cha/mẹ đang theo dõi (kế hoạch docs/KE_HOACH_VY_TONG_THE.md đợt 6).
 * Chỉ nhận khi `ui.context.role === 'family'`; việc của chính người hỏi ("huyết áp của tôi") vẫn đi đường cũ.
 * Câu vào đây đã bỏ dấu, chữ thường, đã chuẩn hoá cách nói vùng miền.
 *
 * Quyền xem (health, meds_view, alerts) do app kiểm tra theo từng người trước khi đọc, máy chủ chỉ hiểu ý.
 */

export type FamilyTopic = 'bp' | 'meds' | 'overall' | 'alerts';

const SELF = new Set(['toi', 'minh', 'tui', 'em', 'con', 'chau', 'bac', 'anh', 'chi']);
const NOT_PERSON = new Set(['hom nay', 'hom qua', 'gan day', 'dao nay', 'tuan nay', 'bay gio', 'luc nay', 'sang nay', 'toi nay', 'nhu the nao', 'the nao', 'ra sao']);

/** Chủ thể là người khác (mẹ, ba, tên riêng...), không phải chính người nói. */
function subjectOf(raw: string): string | null {
  const s = raw
    .trim()
    .replace(/\b(hom nay|gan nhat|gan day|the nao|bao nhieu|ra sao|sao roi|the|cua|chua|roi|khong|a|nhe|nha|di|vay|nhi)\b/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!s || s.length < 2 || s.split(' ').length > 3) return null;
  if (SELF.has(s) || NOT_PERSON.has(s)) return null;
  return s;
}

const BP_A = /^(?:huyet ap|so do|ket qua do|do huyet ap)(?: cua)? (.{2,30})$/;
const BP_B = /^(.{2,30}?) (?:da )?do huyet ap(?: chua| hom nay chua| roi chua| roi khong)?$/;
const MEDS_A = /^(.{2,30}?) (?:da )?(?:uong|dung) thuoc(?: chua| roi chua| hom nay chua| sang nay chua| roi khong| hom nay)?$/;
const MEDS_B = /^(?:thuoc|lich thuoc|lich uong thuoc) (?:cua )(.{2,30})$/;
const OVERALL_A = /^(.{2,30}?) (?:co )?(?:on|khoe)(?: khong| chua| hom nay khong)$/;
const OVERALL_B = /^(?:tinh hinh|tinh trang|suc khoe|moi viec) (?:cua )(.{2,30})$/;
const ALERTS = /^(?:xem )?canh bao(?: moi| gan day| hom nay)?(?: gi)?(?: khong)?$|^co canh bao (?:gi |nao )?(?:moi )?(?:khong)?$|^co chuyen gi (?:khong|xay ra|khong on)$|^co ai can giup (?:khong|gi)$/;

/** "huyết áp của mẹ", "mẹ uống thuốc chưa", "mẹ có ổn không", "xem cảnh báo". null nếu không phải câu hỏi về người thân. */
export function familyQuery(t: string): { topic: FamilyTopic; subject: string } | null {
  if (ALERTS.test(t)) return { topic: 'alerts', subject: '' };
  let m: RegExpMatchArray | null;
  if ((m = t.match(MEDS_A)) ?? (m = t.match(MEDS_B))) {
    const s = subjectOf(m[1]);
    if (s) return { topic: 'meds', subject: s };
  }
  if ((m = t.match(BP_A)) ?? (m = t.match(BP_B))) {
    const s = subjectOf(m[1]);
    if (s) return { topic: 'bp', subject: s };
  }
  if ((m = t.match(OVERALL_A)) ?? (m = t.match(OVERALL_B))) {
    const s = subjectOf(m[1]);
    if (s) return { topic: 'overall', subject: s };
  }
  return null;
}
