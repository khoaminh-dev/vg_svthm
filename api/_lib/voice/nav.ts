/**
 * Điều hướng toàn cục và các việc về thuốc/huyết áp cần luật riêng (kế hoạch docs/KE_HOACH_VY_TONG_THE.md đợt 4, 5).
 * Câu vào đây đã bỏ dấu, chữ thường, đã chuẩn hoá cách nói vùng miền (xem dialect.ts).
 *
 * Lỗi gốc: "mở cộng đồng", "mở thẻ y tế", "mời người thân" chỉ chạy khi màn đang mở tình cờ có đúng điều khiển đó.
 */

export type ScreenKey =
  | 'community'
  | 'profile'
  | 'emergency_card'
  | 'family_invite'
  | 'meds_plans'
  | 'meds_scan'
  | 'health_history'
  | 'health_profile'
  | 'alerts';

const OPEN_VERB = '(?:mo|vao|xem|di den|chuyen den|chuyen sang|quay ve|cho toi xem|cho xem|bat|hien)';
const SCREEN_PREFIX = '(?:muc |trang |man hinh |phan |tab )?';

const SCREENS: [ScreenKey, string][] = [
  ['community', 'cong dong'],
  ['emergency_card', '(?:the (?:y te|khan cap|cap cuu)|ho so y te)'],
  ['family_invite', '(?:(?:moi|them|gioi thieu) nguoi than|ma moi(?: nguoi than)?)'],
  ['meds_scan', '(?:chup|quet) don thuoc|them (?:thuoc|don thuoc)(?: moi)?'],
  ['meds_plans', '(?:lich (?:uong )?thuoc|danh sach thuoc|don thuoc(?: cua toi)?|thuoc cua toi|sua (?:lich|gio) (?:uong )?thuoc|doi gio (?:uong )?thuoc|sua thuoc)'],
  ['health_history', 'lich su (?:suc khoe|kham|danh gia)'],
  ['health_profile', 'ho so suc khoe'],
  ['profile', '(?:ca nhan|trang ca nhan|tai khoan(?: cua toi)?|ho so(?: cua toi)?|cai dat|thong tin cua toi|thiet lap)'],
  ['alerts', '(?:canh bao|thong bao)'],
];

const COMPILED = SCREENS.map(([k, re]) => [k, new RegExp(`^${OPEN_VERB} ${SCREEN_PREFIX}(?:${re})$`)] as const);
// "đổi giờ uống thuốc", "sửa lịch thuốc", "thêm thuốc mới" không cần động từ mở
const BARE = [
  ['meds_scan', /^(?:chup|quet) don thuoc(?: cua toi)?$|^them (?:thuoc|don thuoc)(?: moi)?$/],
  ['meds_plans', /^(?:sua|doi) (?:lich|gio) (?:uong )?thuoc$|^sua thuoc$|^lich (?:uong )?thuoc$/],
  ['family_invite', /^(?:moi|them) nguoi than$/],
] as const;

/** "mở cộng đồng", "mở thẻ y tế", "mời người thân", "sửa lịch thuốc", "chụp đơn thuốc". null nếu không phải. */
export function screenIntent(t: string): ScreenKey | null {
  if (t.split(' ').length > 9) return null;
  for (const [k, re] of BARE) if (re.test(t)) return k;
  for (const [k, re] of COMPILED) if (re.test(t)) return k;
  return null;
}

// ---------- thuốc: bỏ qua cữ ----------

/** "bỏ qua cữ này", "hôm nay không uống cữ này", "cữ này khỏi uống". Hỏi lại trước khi ghi (mức xác nhận 2). */
export function skipDoseQuery(t: string): boolean {
  return /^(?:bo qua|bo) (?:cu|lan|bua) (?:nay|thuoc nay|thuoc)(?: di| nhe)?$|^(?:cu|lan|bua) (?:nay|thuoc nay) (?:khoi|khong|bo qua)(?: uong)?(?: di| nhe)?$|^(?:hom nay|luc nay) (?:khong|khoi) uong (?:cu |lan )?(?:nay|thuoc)(?: di| nhe)?$|^khong uong (?:cu|lan) (?:nay|thuoc nay)$/.test(t);
}

// ---------- lịch sử huyết áp bằng giọng ----------

export type BpHistoryMode = 'yesterday' | 'week_avg' | 'week_max' | 'week_min' | 'recent';

/** "số đo hôm qua", "trung bình huyết áp một tuần", "cao nhất tuần này", "mấy lần đo gần đây". */
export function bpHistoryQuery(t: string): BpHistoryMode | null {
  if (/^(?:huyet ap|so do|ket qua do|lan do)(?: cua toi)? hom qua(?: the nao| bao nhieu)?$|^hom qua (?:toi )?do (?:huyet ap )?(?:bao nhieu|the nao)$|^xem (?:huyet ap|so do|ket qua)(?: cua toi)? hom qua$|^(?:huyet ap|so do) hom qua(?: la)? (?:bao nhieu|gi)$/.test(t)) return 'yesterday';
  if (/(?:trung binh|binh quan)\b.*\b(?:huyet ap|so do)\b.*\b(?:tuan|7 ngay|bay ngay)\b|\bhuyet ap (?:trung binh|binh quan)\b.*\b(?:tuan|7 ngay)\b|\b(?:huyet ap|so do) (?:tuan nay|7 ngay (?:qua|nay)) (?:trung binh|binh quan)/.test(t)) return 'week_avg';
  if (/\b(?:huyet ap|so do) cao nhat\b|\bcao nhat\b.*\b(?:tuan|7 ngay|thang)\b|\blan (?:do )?cao nhat\b/.test(t)) return 'week_max';
  if (/\b(?:huyet ap|so do) thap nhat\b|\bthap nhat\b.*\b(?:tuan|7 ngay|thang)\b|\blan (?:do )?thap nhat\b/.test(t)) return 'week_min';
  if (/^(?:mat|may|3|ba) lan do (?:gan day|gan nhat|vua roi)|^(?:cac|may) (?:lan|so) do (?:gan day|gan nhat|vua roi)|^xem (?:may|cac) lan do (?:gan day|truoc)/.test(t)) return 'recent';
  return null;
}
