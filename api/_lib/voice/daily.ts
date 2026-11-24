/**
 * Việc hằng ngày và kịch bản an toàn trả lời bằng luật, không gọi LLM (kế hoạch docs/KE_HOACH_VY_TONG_THE.md đợt 1, 3):
 * giờ, ngày, thời tiết, nhắc giờ, cỡ chữ, tâm sự, ngưỡng huyết áp, thuốc nguy hiểm.
 *
 * Nguyên tắc: không chẩn đoán, không khuyên liều thuốc; chuyện nguy hiểm thì chỉ hướng dẫn gọi bác sĩ/dược sĩ/115.
 * Mọi câu vào đây là câu đã bỏ dấu, chữ thường (đầu ra của `norm` + `dialect`).
 */

export type DailyResult =
  | { kind: 'say'; say: string; chips?: string[]; important?: boolean }
  | { kind: 'intent'; intent: string; content: string };

const cap = (h: string) => (h ? `${h[0].toUpperCase()}${h.slice(1)}` : 'Bác');

// ---------- thời gian (giờ Việt Nam, không phụ thuộc múi giờ máy chủ) ----------

const VN_OFFSET_MS = 7 * 3600 * 1000;
const WEEKDAYS = ['chủ nhật', 'thứ hai', 'thứ ba', 'thứ tư', 'thứ năm', 'thứ sáu', 'thứ bảy'];

/** Các thành phần ngày giờ theo giờ Việt Nam của một thời điểm. */
export function vnParts(now: Date): { y: number; mo: number; d: number; h: number; mi: number; wd: number } {
  const v = new Date(now.getTime() + VN_OFFSET_MS);
  return { y: v.getUTCFullYear(), mo: v.getUTCMonth() + 1, d: v.getUTCDate(), h: v.getUTCHours(), mi: v.getUTCMinutes(), wd: v.getUTCDay() };
}

/** "9 giờ 5 phút sáng", "12 giờ trưa", "7 giờ 30 phút tối". */
export function spokenTime(h: number, mi: number): string {
  const h12 = h % 12 === 0 ? 12 : h % 12;
  const part = h < 5 ? 'đêm' : h < 11 ? 'sáng' : h < 13 ? 'trưa' : h < 18 ? 'chiều' : h < 22 ? 'tối' : 'đêm';
  const m = mi === 0 ? '' : mi === 30 ? ' rưỡi' : ` ${mi} phút`;
  return `${h12} giờ${m} ${part}`;
}

const TIME_Q = /^(?:bay gio |luc nay |ban |con |vy )?(?:la )?(?:may gio|gio may)(?: roi| ru| the| vay| day| nhi| a)*$|^xem gio$|^cho (?:toi|bac|con|minh) (?:biet|hoi) (?:may )?gio$/;
const DATE_Q = /^(?:hom nay |bay gio )?(?:la )?(?:thu may|thu bao nhieu|ngay may|ngay bao nhieu|ngay thang may|ngay thang bao nhieu)(?: roi| vay| the| nhi| a)*$|^hom nay la (?:thu|ngay) (?:may|bao nhieu)(?: vay| the| nhi)?$|^(?:bay gio|hom nay) la ngay (?:may|bao nhieu)/;
const WEATHER_Q = /\b(?:thoi tiet|nhiet do|troi (?:co )?(?:mua|nang|lanh|nong|ret)|co (?:mua|nang) khong|du bao)\b/;

// ---------- nhắc giờ ----------

export type ParsedReminder = { at: number; what: string } | { need: 'time' };

const PRON = new Set(['toi', 'bac', 'con', 'minh', 'co', 'chu', 'ong', 'ba']);
const LEAD_DROP = new Set(['nhe', 'nha', 'giup', 'dum', 'gium', 'voi', 'luc', 'vao', 'khoang', 'la', 'cho', 'thi', 'a', 'ne', 'khi', 'den', 'luc', 'toi']);
const TRAIL_DROP = new Set(['nhe', 'nha', 'a', 'ne', 'giup', 'dum', 'gium', 'voi', 'nghen', 'nhen', 'luc', 'vao', 'khoang']);
const PERIOD = new Set(['sang', 'trua', 'chieu', 'toi', 'dem']);
const ALARM_WORDS = ['dat', 'cai', 'hen', 'bao', 'thuc', 'gio'];

const fold = (w: string) => w.toLowerCase().replace(/đ/g, 'd').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]/g, '');

/**
 * "nhắc tôi 8 giờ đi khám", "nhắc tôi đo huyết áp lúc 8 giờ", "nhắc tôi sau 30 phút uống thuốc", "đặt báo thức 6 giờ sáng".
 * Làm trên câu GỐC (có dấu) để tên việc đọc ra đúng; trả về thời điểm tuyệt đối (ms) và việc cần nhắc.
 * null nếu không phải lệnh nhắc. "nhạc" và "nhắc" bỏ dấu giống nhau nên cần đúng chữ "nhắc" có dấu (hoặc có giờ rõ ràng);
 * "bảo con gái gọi lại" là nhắn tin, không phải nhắc giờ (chỉ "báo thức" mới tính).
 */
export function parseReminder(orig: string, now: Date): ParsedReminder | null {
  const tok = orig.trim().split(/\s+/).filter(Boolean);
  const nt = tok.map(fold);
  if (tok.length < 2) return null;
  const alarm = (nt[0] === 'bao' && nt[1] === 'thuc') || (['dat', 'cai', 'hen'].includes(nt[0]) && (nt[1] === 'bao' || nt[1] === 'gio'));
  const diacriticRemind = tok[0].toLowerCase() === 'nhắc';
  const plainRemind = nt[0] === 'nhac' && PRON.has(nt[1] ?? '');
  if (!alarm && !diacriticRemind && !plainRemind) return null;
  // "Hẹn giờ tắt nhạc sau 30 phút" là hẹn giờ tắt video đang phát, không phải nhắc việc.
  if (nt[0] === 'hen' && ['tat', 'dung'].includes(nt[2] ?? '')) return null;
  if (nt[0] === 'nhac' && ['lai', 'nho'].includes(nt[1] ?? '')) return null; // "nhắc lại", "nhắc nhở"

  const used = new Array<boolean>(tok.length).fill(false);
  if (alarm) {
    for (let i = 0; i < 3 && i < nt.length && ALARM_WORDS.includes(nt[i]); i++) used[i] = true;
  } else {
    used[0] = true;
    if (PRON.has(nt[1] ?? '')) used[1] = true;
  }

  const vn = vnParts(now);
  let dayOffset = 0;
  let dayExplicit = false;
  let period: string | null = null;
  let h: number | null = null;
  let mi = 0;
  let relativeMs: number | null = null;

  const isNum = (w: string | undefined) => !!w && /^\d{1,3}$/.test(w);
  for (let i = 0; i < nt.length; i++) {
    const w = nt[i];
    if (used[i]) continue;
    if (w === 'mai' || (w === 'ngay' && nt[i + 1] === 'mai')) {
      dayOffset = 1; dayExplicit = true; used[i] = true;
      if (w === 'ngay') used[i + 1] = true;
    } else if (w === 'ngay' && nt[i + 1] === 'kia') {
      dayOffset = 2; dayExplicit = true; used[i] = used[i + 1] = true;
    } else if (w === 'hom' && nt[i + 1] === 'nay') {
      dayExplicit = true; used[i] = used[i + 1] = true;
    } else if (PERIOD.has(w)) {
      // "8 giờ sáng", "sáng 8 giờ", "chiều nay": chỉ tính là buổi khi đi liền giờ hoặc "nay"; "tôi" là đại từ.
      const nearHour = nt[i - 1] === 'gio' || isNum(nt[i - 1]) || isNum(nt[i + 1]) || /^\d{1,2}h/.test(nt[i - 1] ?? '') || /^\d{1,2}h/.test(nt[i + 1] ?? '');
      if (nearHour || (nt[i + 1] === 'nay' && (w !== 'toi' || tok[i].toLowerCase() === 'tối'))) {
        period = w; used[i] = true;
        if (nt[i + 1] === 'nay') { used[i + 1] = true; dayExplicit = true; }
      }
    }
  }

  // Tương đối: "sau 30 phút", "30 phút nữa", "nửa tiếng nữa", "sau 2 tiếng", "một tiếng nữa"
  for (let i = 0; i < nt.length && relativeMs === null; i++) {
    if (nt[i] === 'nua' && nt[i + 1] === 'tieng') {
      relativeMs = 30 * 60000;
      used[i] = used[i + 1] = true;
      if (nt[i + 2] === 'nua') used[i + 2] = true;
      if (nt[i - 1] === 'sau') used[i - 1] = true;
      break;
    }
    const n = isNum(nt[i]) ? Number(nt[i]) : nt[i] === 'mot' ? 1 : nt[i] === 'hai' ? 2 : null;
    const unit = nt[i + 1];
    if (n !== null && (unit === 'phut' || unit === 'tieng') && (nt[i - 1] === 'sau' || nt[i + 2] === 'nua')) {
      relativeMs = n * (unit === 'phut' ? 60000 : 3600000);
      used[i] = used[i + 1] = true;
      if (nt[i - 1] === 'sau') used[i - 1] = true;
      if (nt[i + 2] === 'nua') used[i + 2] = true;
    }
  }

  if (relativeMs === null) {
    for (let i = 0; i < nt.length; i++) {
      if (used[i]) continue;
      const m = nt[i].match(/^(\d{1,2})h(\d{2})?$/);
      if (m) {
        h = Number(m[1]); mi = m[2] ? Number(m[2]) : 0; used[i] = true;
        break;
      }
      if (/^\d{1,2}$/.test(nt[i]) && nt[i + 1] === 'gio') {
        h = Number(nt[i]); used[i] = used[i + 1] = true;
        const a = nt[i + 2];
        if (a === 'ruoi') { mi = 30; used[i + 2] = true; }
        else if (a && /^\d{1,2}$/.test(a) && Number(a) < 60) {
          mi = Number(a); used[i + 2] = true;
          if (nt[i + 3] === 'phut') used[i + 3] = true;
        }
        break;
      }
    }
  }

  const hasTime = relativeMs !== null || h !== null;
  if (!hasTime) return alarm || diacriticRemind ? { need: 'time' } : null;

  let at: number;
  if (relativeMs !== null) {
    at = now.getTime() + relativeMs;
  } else {
    let hh = h!;
    if (hh > 23 || mi > 59) return { need: 'time' };
    if (period === 'chieu' || period === 'toi') { if (hh < 12) hh += 12; }
    else if (period === 'dem') { if (hh >= 6 && hh < 12) hh += 12; else if (hh === 12) hh = 0; }
    else if (period === 'trua') { if (hh >= 1 && hh <= 4) hh += 12; }
    else if (period === 'sang') { if (hh === 12) hh = 0; }
    const at0 = (add: number, hour: number) => Date.UTC(vn.y, vn.mo - 1, vn.d + add, hour, mi) - VN_OFFSET_MS;
    if (dayExplicit || period || hh > 12) {
      at = at0(dayOffset, hh);
      if (!dayExplicit && at <= now.getTime()) at = at0(1, hh);
    } else {
      // Không nói buổi: lấy lần sắp tới gần nhất (8 giờ → 8h sáng hoặc 8h tối).
      const cands = [at0(0, hh), at0(0, (hh + 12) % 24), at0(1, hh)].filter((x) => x > now.getTime()).sort((x, y) => x - y);
      at = cands[0];
    }
  }

  // Việc cần nhắc = các từ chưa dùng, gọt đệm hai đầu.
  const rest = tok.map((w, i) => ({ w, n: nt[i], used: used[i] })).filter((x) => !x.used);
  while (rest.length && (LEAD_DROP.has(rest[0].n) || PRON.has(rest[0].n))) rest.shift();
  while (rest.length && TRAIL_DROP.has(rest[rest.length - 1].n)) rest.pop();
  const what = rest.map((x) => x.w).join(' ').trim();
  return { at, what: what || 'việc cần làm' };
}

// ---------- cỡ chữ ----------

const FONT_UP = /\b(?:tang|phong to|to hon|lon hon|to len|lon len) (?:co )?chu\b|\bchu (?:to|lon) (?:len|hon|them)\b|\bco chu (?:to|lon) (?:hon|len)\b|\bchu (?:nho|be) qua\b|\bkhong (?:doc|thay) (?:duoc|ro) chu\b/;
const FONT_DOWN = /\b(?:giam|thu nho|nho hon|be hon) (?:co )?chu\b|\bchu (?:nho|be) (?:lai|bot|hon)\b|\bco chu (?:nho|be) (?:hon|lai)\b|\bchu to qua\b/;

// ---------- ngưỡng huyết áp ----------

const BP_THRESHOLD_Q = /huyet ap.*\b(?:bao nhieu|may)\b.*\b(?:la|thi) (?:cao|thap|binh thuong|nguy hiem|on|tot|duoc|bi)\b|\b(?:cao|thap|binh thuong|nguy hiem) (?:la|thi) (?:bao nhieu|may)\b|huyet ap (?:binh thuong|cao|thap) la (?:bao nhieu|may)|muc huyet ap (?:binh thuong|tot|nguy hiem)/;
const BP_WHEN_Q = /\b(?:nen|phai|can) do huyet ap (?:luc nao|khi nao|may lan|vao luc nao)|do huyet ap (?:luc nao|khi nao|may lan|vao gio nao) (?:thi )?(?:tot|dung|duoc|nen)|khi nao (?:nen )?do huyet ap|toi nen do (?:luc nao|khi nao)|bao lau do huyet ap mot lan/;

export const BP_THRESHOLD_SAY = (h: string) =>
  `Theo chuẩn của Hội Tim mạch Hoa Kỳ: huyết áp bình thường là dưới 120 trên 80. Từ 130 trên 80 trở lên là bắt đầu tăng huyết áp, từ 140 trên 90 là tăng huyết áp rõ. Trên 180 trên 120 là rất nguy hiểm, ${h} cần gọi bác sĩ hoặc 115 ngay. Đây chỉ là mức chung, mức phù hợp riêng với ${h} thì ${h} hỏi bác sĩ ạ.`;

export const BP_WHEN_SAY = (h: string) =>
  `${cap(h)} nên đo mỗi ngày hai lần: buổi sáng sau khi ngủ dậy, trước khi ăn và uống thuốc, và buổi tối trước khi ngủ. Trước khi đo ngồi nghỉ yên 5 phút, đo hai lần cách nhau một phút ạ.`;

// ---------- thuốc nguy hiểm: chỉ hướng dẫn, không khuyên liều ----------

const MED_OVERDOSE = /\b(?:uong|nuot) (?:nham|nhieu|du|thua|qua lieu|gap doi|gap hai|hai lan|2 lan|hai vien|2 vien|them)\b|\buong nham thuoc\b|\b(?:qua|vuot) lieu\b|\buong lo\b.*\b(?:2|hai) lan\b|\buong (?:thuoc )?(?:2|hai) lan\b/;
const MED_MISSED = /\b(?:quen|lo|bo lo|bo quen|bo) (?:mat )?(?:uong )?(?:thuoc|cu thuoc|lieu)\b|\bchua uong (?:thuoc )?(?:tu |hom )?(?:qua|hom qua|sang nay|trua nay|toi qua)|\buong thuoc tre\b|\buong bu\b/;
const MED_RUNOUT = /\b(?:het|sap het|con it|can mua|khong con) thuoc\b|\bthuoc (?:het|sap het|con it) (?:roi|ru)?\b/;
const MED_STOP = /\b(?:ngung|dung|bo|khong uong) (?:uong )?thuoc(?: huyet ap| tim| tieu duong| nua)?\b|\bco the (?:ngung|bo) thuoc\b|\bkhong can (?:uong )?thuoc (?:nua)?\b/;
const MED_INFO = /\b(?:tac dung phu|thuoc nay (?:uong|dung) (?:the nao|ra sao|nhu the nao)|uong thuoc (?:luc nao|khi nao|truoc hay sau an)|thuoc nay de lam gi|thuoc nay tri (?:gi|benh gi))\b/;

export const MED_SAY = {
  overdose: (h: string) =>
    `Dạ, ${h} đừng tự xử lý ạ. ${cap(h)} gọi ngay bác sĩ hoặc dược sĩ để hỏi. Nếu thấy chóng mặt, buồn nôn, tim đập nhanh, khó thở hay mệt lả thì gọi 115 ngay. Con gọi 115 giúp ${h} nhé?`,
  missed: (h: string) =>
    `Dạ, ${h} đừng uống gấp đôi để bù ạ. ${cap(h)} hỏi bác sĩ hoặc dược sĩ thuốc này quên một cữ thì làm sao. Con sẽ nhắc ${h} đúng giờ ở các cữ sau.`,
  runout: (h: string) =>
    `Dạ, ${h} sắp hết thuốc thì nên đi khám hoặc mua thuốc theo đơn sớm, đừng tự bỏ thuốc ạ. Con nhắn cho người thân giúp ${h} nhé?`,
  stop: (h: string) =>
    `Dạ, ${h} đừng tự ý ngưng hay bỏ thuốc ạ, nhất là thuốc huyết áp. Dù thấy khoẻ hơn cũng cần hỏi bác sĩ trước. Con nhắn người thân hoặc gọi giúp ${h} nhé?`,
  info: (h: string) =>
    `Dạ, con không tư vấn thuốc được ạ. ${cap(h)} xem hướng dẫn trên đơn hoặc hỏi bác sĩ, dược sĩ. Con có thể đọc lịch uống thuốc của ${h} nếu ${h} muốn.`,
};

// ---------- tâm sự, danh tính, khen ----------

const NAME_Q = /^(?:ban|co|em|vy) (?:la ai|ten (?:gi|la gi))$|^ten (?:ban|co|em|vy) la gi$|^ban la ai$|^(?:ai|ban) (?:la ai|ten gi)$/;
const AGE_Q = /^(?:ban|co|em|vy) (?:bao nhieu|may) tuoi$|^(?:ban|co|em) (?:la )?(?:nguoi|may) (?:that|khong)\b/;
const HOW_ARE_YOU = /^(?:ban|co|em|vy) (?:co )?(?:khoe|vui) khong$|^(?:ban|vy) the nao$/;
// Không nhận "hay quá" trơn: khi đang nghe nhạc đó là lời khen BÀI HÁT (lưu bài yêu thích), không phải khen Vy.
const PRAISE = /^(?:ban|vy|co|em) (?:gioi|tuyet|hay|thong minh|gioi qua|tot) (?:qua|lam|that|ghe)?$/;
const LOVE = /^(?:toi|bac|con) (?:thuong|yeu|quy|thich) (?:ban|vy|co|em)(?: lam| qua)?$/;
const JOKE = /^(?:ke|noi|doc) (?:cho toi nghe )?(?:mot |1 )?(?:chuyen )?(?:cuoi|vui|tieu lam)(?: di| nhe| cho toi nghe)?$|^(?:ke|noi) chuyen cuoi/;
const STORY = /^(?:ke|doc|noi) (?:cho toi nghe )?(?:mot |1 )?(?:chuyen|truyen|cau chuyen)(?: di| nhe| cho toi nghe| gi do)?$/;
const HELP_ME = /^(?:giup (?:toi|bac|con|minh)(?: voi)?|giup voi|toi can (?:giup|giup do)(?: voi)?|bac can giup|nho giup)$/;

/** Gợi ý chạm được sau mỗi câu "không hiểu": các việc Vy làm thật sự. */
export const UNSUPPORTED_CHIPS = ['Đo huyết áp', 'Mở nhạc xưa', 'Đọc tin nhắn'];

/**
 * Trả lời việc hằng ngày/an toàn bằng luật. [t0] là câu đã chuẩn hoá (chưa gọt đệm), [orig] là câu gốc có dấu.
 * null nếu không phải việc này (để các luật khác và LLM xử lý).
 */
export function dailyReply(t0: string, orig: string, hon: string, now: Date): DailyResult | null {
  const t = t0.trim();
  if (!t) return null;
  const h = hon || 'bác';

  // Giờ, ngày, thứ
  if (TIME_Q.test(t)) {
    const p = vnParts(now);
    return { kind: 'say', say: `Dạ, bây giờ là ${spokenTime(p.h, p.mi)} ạ.` };
  }
  if (DATE_Q.test(t)) {
    const p = vnParts(now);
    return { kind: 'say', say: `Dạ, hôm nay là ${WEEKDAYS[p.wd]}, ngày ${p.d} tháng ${p.mo} năm ${p.y} ạ.` };
  }
  if (WEATHER_Q.test(t)) {
    return {
      kind: 'say',
      say: `Dạ, con chưa xem được thời tiết ạ. ${cap(h)} xem dự báo trên ti vi hoặc mở ứng dụng thời tiết trên máy giúp con nhé.`,
    };
  }

  // Nhắc giờ, báo thức
  const rem = parseReminder(orig, now);
  if (rem) {
    if ('need' in rem) {
      return {
        kind: 'say',
        say: `Dạ, ${h} muốn con nhắc lúc mấy giờ ạ? ${cap(h)} nói cả giờ và việc, ví dụ: nhắc tôi 8 giờ sáng mai đi khám.`,
      };
    }
    return { kind: 'intent', intent: 'set_reminder', content: `${rem.at}|${rem.what}` };
  }

  // Cỡ chữ
  if (FONT_UP.test(t)) return { kind: 'intent', intent: 'adjust_setting', content: 'font_up' };
  if (FONT_DOWN.test(t)) return { kind: 'intent', intent: 'adjust_setting', content: 'font_down' };

  // Huyết áp: kiến thức chung (không đọc số đo của người dùng)
  if (BP_THRESHOLD_Q.test(t)) return { kind: 'say', say: BP_THRESHOLD_SAY(h), important: true };
  if (BP_WHEN_Q.test(t)) return { kind: 'say', say: BP_WHEN_SAY(h), chips: ['Đo huyết áp'] };

  // Thuốc nguy hiểm
  if (MED_OVERDOSE.test(t)) return { kind: 'say', say: MED_SAY.overdose(h), chips: ['Gọi 115', 'Không cần'], important: true };
  if (MED_STOP.test(t)) return { kind: 'say', say: MED_SAY.stop(h), chips: ['Nhắn người thân', 'Không cần'], important: true };
  // "Hôm nay tôi có quên uống thuốc cữ nào không" là câu HỎI về lịch (đọc cữ quá giờ), không phải "tôi vừa quên uống".
  const asksQuestion = /\bco\b.*\b(?:khong|chua)\b|\bnao khong\b|\bkhong$/.test(t);
  if (!asksQuestion && MED_MISSED.test(t)) return { kind: 'say', say: MED_SAY.missed(h), chips: ['Xem cữ thuốc'], important: true };
  if (MED_RUNOUT.test(t)) return { kind: 'say', say: MED_SAY.runout(h), chips: ['Nhắn người thân', 'Không cần'], important: true };
  if (MED_INFO.test(t)) return { kind: 'say', say: MED_SAY.info(h), chips: ['Xem cữ thuốc'], important: true };

  // Tâm sự, danh tính
  if (NAME_Q.test(t)) {
    return { kind: 'say', say: `Dạ, con là Vy, trợ lý của ${h} ạ. Con giúp ${h} nhắn tin, gọi điện, đo huyết áp, nhắc uống thuốc, mở nhạc và hỏi giờ giấc.` };
  }
  if (AGE_Q.test(t)) return { kind: 'say', say: `Dạ, con là trợ lý trên điện thoại nên không có tuổi ạ. Con luôn sẵn sàng giúp ${h}.` };
  if (HOW_ARE_YOU.test(t)) return { kind: 'say', say: `Dạ, con khoẻ ạ, cảm ơn ${h} đã hỏi. Hôm nay ${h} thấy trong người thế nào ạ?` };
  if (PRAISE.test(t)) return { kind: 'say', say: `Dạ, con cảm ơn ${h} ạ. Có gì ${h} cứ nói, con giúp liền.` };
  if (LOVE.test(t)) return { kind: 'say', say: `Dạ, con cảm ơn ${h} nhiều ạ. Con ở đây khi ${h} cần.` };
  if (JOKE.test(t)) return { kind: 'intent', intent: 'play_video', content: 'hài kịch' };
  if (STORY.test(t)) return { kind: 'intent', intent: 'play_video', content: 'truyện đêm khuya' };
  if (HELP_ME.test(t)) {
    return {
      kind: 'say',
      say: `Dạ, ${h} cần giúp gì ạ? Nếu nguy hiểm ${h} nói "cứu tôi", con báo ngay ạ.`,
      chips: ['Gọi 115', 'Nhắn tin', 'Đo huyết áp'],
      important: true,
    };
  }
  return null;
}
