/**
 * Chuẩn hoá cách nói vùng miền và biến thể về cách nói chuẩn TRƯỚC khi so luật (kế hoạch docs/KE_HOACH_VY_TONG_THE.md mục 5.1).
 * Lỗi gốc: người dùng miền Nam nói "coi thời sự" mà không luật nào biết "coi" = "xem" nên câu rơi sang LLM và bị mở nhầm Giải trí.
 *
 * Đầu vào đã bỏ dấu, chữ thường, một dấu cách giữa các từ (đầu ra của `norm`). Chỉ dùng để HIỂU ý định;
 * nội dung tin nhắn gửi đi luôn lấy từ câu gốc, không đi qua đây.
 * Mỗi luật phải đủ hẹp để không đổi nghĩa câu thường: có kiểm thử riêng từng cặp (api/_tests/dialect.test.ts).
 */

const RULES: [RegExp, string][] = [
  // Động từ xem/nghe
  [/\bcoi thu\b/g, 'xem'],
  [/\bxem thu\b/g, 'xem'],
  [/\bnghe thu\b/g, 'nghe'],
  [/\bcoi\b/g, 'xem'],
  // Đại từ và phủ định
  // "tui" = "tôi" (miền Nam) nhưng bỏ dấu thì trùng "túi" (túi thuốc): chỉ đổi khi đi trước một động từ/trạng từ của người nói.
  [/\btui (?=muon|can|thich|khong|se|dang|vua|bi|nho|dau|met|moi|hay|da|co|chua|phai|xem|nghe|mo|bat|goi|nhan|doc|di|ve)\b/g, 'toi '],
  [/\bcho tui\b/g, 'cho toi'],
  [/\b(?:hok|ko|hem)\b/g, 'khong'],
  // "hông" chỉ khi đứng sau đại từ (tránh "máy hỏng", "màu hồng")
  [/(^|\b(?:toi|bac|con|co|chu|minh|vy)\s)hong\b/g, '$1khong'],
  // Giới từ
  [/\b(?:dzo|zo)\b/g, 'vao'],
  // Từ chỉ thời gian
  [/\bbua nay\b/g, 'hom nay'],
  [/\bbua hom\b/g, 'hom truoc'],
  [/\bhoi nay\b/g, 'luc nay'],
  [/\bhoi sang\b/g, 'sang nay'],
  [/\bhoi toi\b/g, 'toi qua'],
  // Từ đệm cuối câu miền Nam
  [/\s+(?:nghen|nhen|hen|nhoe|nghe nha)$/g, ''],
  // "giùm" = "dùm" = "hộ" (bộ lọc đệm đã bỏ "dum")
  [/\bgium\b/g, 'dum'],
];

/** Đưa câu đã bỏ dấu về cách nói chuẩn. Không đổi gì nếu không có từ vùng miền. */
export function dialect(t: string): string {
  let s = t;
  for (const [re, to] of RULES) s = s.replace(re, to);
  return s.replace(/\s+/g, ' ').trim();
}
