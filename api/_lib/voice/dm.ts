// Bộ não hội thoại: nhận câu nói (đã chuyển thành chữ) + trạng thái hiện tại → quyết định bước kế tiếp.
// Nguyên tắc: LLM chỉ "hiểu" (intent + slot thô). Việc đủ/thiếu slot, hỏi lại, xác nhận, phân giải người nhận
// đều do code ở đây quyết định để chắc chắn và kiểm thử được. Xem docs/VOICE_AGENT.md mục 4.

import { resolveUiCommand, type UiContext, type UiControl } from './ui_cmd.js';

export type Expect = 'command' | 'free_text' | 'yes_no' | 'choice' | 'name' | 'none';
export type Contact = { id: string; kind: 'direct' | 'group'; name: string; username?: string; aliases?: string[] };
export type Ui = { screen?: string; roomId?: string | null; contacts?: Contact[]; honorific?: string; context?: UiContext };
export type Task = { intent: string; slots: Record<string, string> };
export type DState = {
  task?: Task | null;
  pending?: string | null;
  expects?: Expect;
  choices?: { id: string; name: string }[];
  aliasPhrase?: string | null; // cụm quan hệ đang hỏi ("con trai") để học bí danh
};
export type SayClass = 'static' | 'emergency' | 'important' | 'other';
export type Action = 'ask' | 'confirm' | 'execute' | 'answer' | 'cancel' | 'unsupported' | 'repeat';
export type Decision = {
  action: Action;
  intent: string | null;
  task: Task | null;
  pending: string | null;
  expects: Expect;
  choices: { id: string; name: string }[];
  say: string;
  sayClass: SayClass;
  expectsReply: boolean;
  chips: string[];
  aliasPhrase: string | null;
  learnAlias?: { alias: string; contactId: string };
};

export type NluResult = {
  intent: string;
  recipient: string;
  content: string;
  feature: string;
  say: string;
};
export type Nlu = (text: string, ctx: { state: DState; ui: Ui; honorific: string }) => Promise<NluResult>;

// ---------- chuẩn hoá chữ ----------

/** Viết thường, bỏ dấu, bỏ ký tự lạ, gộp khoảng trắng — dùng để so khớp không phân biệt dấu. */
export function norm(s: string): string {
  return s
    .toLowerCase()
    .replace(/đ/g, 'd')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9 ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

const FILLERS = /^(a|a a|u|um|uhm|o|e|ờ|à|ừm|ờm)\s+/i;

export function cleanContent(s: string): string {
  let t = s.trim().replace(/\s+/g, ' ');
  while (FILLERS.test(t)) t = t.replace(FILLERS, '');
  if (!t) return '';
  return t.charAt(0).toUpperCase() + t.slice(1);
}

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

// ---------- câu nói của Vy ----------

const HONORIFICS = ['bác', 'cô', 'chú', 'ông', 'bà', 'anh', 'chị'];
export function honorificOf(h?: string): string {
  return h && HONORIFICS.includes(h) ? h : 'bác';
}

const S = {
  askRecipient: (h: string) => `Dạ, ${h} muốn nhắn cho ai ạ?`,
  askContent: (h: string) => `Dạ, ${h} muốn nhắn gì ạ?`,
  askName: (h: string) => `Dạ, ${h} nói tên người đó trong danh bạ giúp con nhé.`,
  sentOk: () => 'Dạ, con gửi rồi ạ.',
  cancelled: () => 'Dạ, con hủy rồi ạ.',
  notHeard: (h: string) => `Con chưa nghe rõ, ${h} nói lại giúp con nhé.`,
  opened: () => 'Dạ, con mở rồi ạ.',
  help: (h: string) => `Con giúp ${h} nhắn tin, đo huyết áp, xem lịch sử huyết áp, nói về tình trạng sức khoẻ và mở video, nhạc trên YouTube ạ.`,
  unsupported: (h: string) => `Việc này con chưa làm được. Con giúp ${h} nhắn tin hoặc đo huyết áp nhé?`,
  emergency: (h: string) => `${h} hãy gọi 115 hoặc nhờ người thân ngay nhé. Nếu thấy nguy hiểm, đừng chờ ạ.`,
  trouble: (h: string) => `Con đang trục trặc một chút, ${h} thử lại sau nhé.`,
  confirmHint: (h: string) => `${h} nói "gửi" hoặc "sửa" giúp con nhé.`,
  askFeatureMissing: (h: string) => `Dạ, ${h} muốn mở phần nào ạ?`,
  askVideo: (h: string) => `Dạ, ${h} muốn xem hoặc nghe gì ạ?`,
};

/** Toàn bộ câu cố định (theo từng cách xưng hô) — dùng để chứng thực "câu tĩnh" ở /voice/tts và tạo cache dùng chung. */
export function staticTexts(): Set<string> {
  const out = new Set<string>();
  for (const h of HONORIFICS) {
    for (const f of [S.askRecipient, S.askContent, S.askName, S.notHeard, S.help, S.unsupported, S.trouble, S.confirmHint, S.askFeatureMissing, S.askVideo]) {
      out.add(f(h));
    }
  }
  out.add(S.sentOk());
  out.add(S.cancelled());
  out.add(S.opened());
  return out;
}

export function emergencyTexts(): Set<string> {
  return new Set(HONORIFICS.map((h) => S.emergency(h)));
}

// ---------- luật cứng (chạy trước LLM) ----------

const EMERGENCY = /\b(dau nguc|kho tho|bat tinh|ngat xiu|te liet|cap cuu|chay mau|nga roi|tim dap nhanh|met lam|choang vang)\b/;
const CANCEL = /^(thoi|huy|dung|dung lai|bo di|thoi khong|khong gui nua|khong can nua)( a| nhe| di| roi)?$/;
const YES = /^(co|co a|vang|da|u|uh|um|dung|dung roi|luu|luu di|ghi|ghi di|gui|gui di|gui nhe|gui di nhe|gui luon|ok|okay|duoc|dong y|chuan|chinh xac|ung)( a| nhe| di| roi| nha)?$/;
const NO = /^(khong|khong phai|sai|sai roi|chua|khong dung|khong gui)( a| roi)?$/;
const EDIT_PREFIX = /^((khong phai|khong|sai roi|nham roi)\s*)?((sua lai|sua|nhan lai|doi thanh)(\s+(la|thanh))?\s*)?(?=\S|$)/;
const REPEAT = /(doc lai|nhac lai|nghe lai|noi lai|lap lai)/;

function matchPrefixWords(t: string, re: RegExp): number {
  const m = t.match(re);
  const s = m ? m[0].trim() : '';
  return s ? s.split(' ').length : 0;
}

/** Người dùng NÓI RÕ muốn báo SOS ("gọi SOS", "báo SOS", "kích hoạt SOS"); t đã bỏ dấu.
 *  Chỉ nói "SOS" trơn hoặc "bấm SOS" thì KHÔNG tính (có thể là nhắc tới nút): khi đó con trỏ chỉ vào nút. */
export function sosExplicit(t: string): boolean {
  return /^(goi|bao|kich hoat|phat|goi bao|bam goi) (nut )?sos( di| nhe| ngay| giup toi| giup con)*$/.test(t);
}

const FEATURE_WORDS: Record<string, string> = {
  chat: 'chat', 'tin nhan': 'chat', 'tro chuyen': 'chat',
  ocr: 'ocr', 'so lieu': 'ocr', 'doc so lieu': 'ocr',
  'huyet ap': 'bp', home: 'home', 'trang chu': 'home',
  'giai tri': 'fun', youtube: 'fun', fun: 'fun',
};
export function featureOf(s: string): string {
  const n = norm(s);
  if (FEATURE_WORDS[n]) return FEATURE_WORDS[n];
  for (const [k, v] of Object.entries(FEATURE_WORDS)) if (n.includes(k)) return v;
  return '';
}

const NOT_VIDEO = /\b(tin nhan|nhan tin|huyet ap|chat|ocr|trang chu|so lieu|nhan cho|gui cho)\b/;

/** "mở bài Nối vòng tay lớn", "cho nghe nhạc xưa", "phát video con mèo": lấy phần từ khoá tìm video; null nếu không phải. */
export function videoQuery(t: string): string | null {
  if (NOT_VIDEO.test(t)) return null;
  const m = t.match(/^(mo|phat|bat|cho (?:toi |con )?(?:nghe|xem)|nghe|xem)\s+(?:(bai hat|ca khuc|bai|video|clip|nhac|phim|youtube)\s+)?(.{2,80})$/);
  if (!m) return null;
  const verb = m[1];
  const media = m[2];
  // "mở X" / "xem X" trần trụi dễ nhầm với lệnh khác: cần thêm từ chỉ video/nhạc.
  if (!media && (verb === 'mo' || verb === 'xem')) return null;
  const rest = (media === 'nhac' ? `nhac ${m[3]}` : m[3]).replace(/\s+(tren )?(youtube|you tube)$/, '').trim();
  return rest.length >= 2 ? rest : null;
}

/** Lệnh điều khiển video đang phát: "dừng", "bài khác", "nhỏ đi"... (t đã bỏ dấu); trả về tên hành động hoặc null. */
export function videoControl(t: string): string | null {
  const tail = '( a| nhe| di| chut| giup con| giup toi)*';
  const rules: [RegExp, string][] = [
    [new RegExp(`^(tam dung|dung lai|dung|ngung|tat nhac|tat video)${tail}$`), 'pause'],
    [new RegExp(`^(tiep tuc|phat tiep|phat lai|bat lai)${tail}$`), 'play'],
    [new RegExp(`^(bai khac|bai tiep theo|bai tiep|bai ke tiep|video khac|video tiep theo|chuyen bai|qua bai|bai sau)${tail}$`), 'next'],
    [new RegExp(`^(bai truoc|bai vua roi|video truoc)${tail}$`), 'previous'],
    [new RegExp(`^(to len|to hon|lon len|lon hon|tang am luong|tang tieng|nghe khong ro)${tail}$`), 'louder'],
    [new RegExp(`^(nho di|nho lai|nho hon|giam am luong|giam tieng)${tail}$`), 'quieter'],
  ];
  for (const [re, action] of rules) if (re.test(t)) return action;
  return null;
}

/** Số đo huyết áp đọc từ lời nói (t đã bỏ dấu): "huyết áp 130 trên 80 mạch 72", "cao 130 thấp 80", "130 trên 80".
 *  `ok:false` khi có số nhưng vô lý (để hỏi lại, không ghi bậy). null khi không phải câu nhập số đo. */
export type BpParse = { ok: true; sys: number; dia: number; pulse?: number } | { ok: false };
export function parseBp(t: string): BpParse | null {
  const hasContext = /\b(huyet ap|vua do|do duoc|ghi|luu|nhap|tam thu|tam truong|so do)\b/.test(t) || /\b\d{2,3} tren \d{2,3}\b/.test(t);
  if (!hasContext) return null;
  let rest = t;
  let pulse: number | undefined;
  const pm = rest.match(/\b(?:mach|nhip tim|nhip)\s*(?:la\s*)?(\d{2,3})\b/);
  if (pm) {
    pulse = Number(pm[1]);
    rest = rest.replace(pm[0], ' ');
  }
  let sys: number | undefined;
  let dia: number | undefined;
  const words = rest.match(/\b(?:cao|tam thu)\D{0,12}?(\d{2,3})\D{1,20}?(?:thap|tam truong)\D{0,12}?(\d{2,3})\b/);
  if (words) {
    sys = Number(words[1]);
    dia = Number(words[2]);
  } else {
    const m = rest.match(/\b(\d{2,3})\s*(?:tren|va|voi)?\s+(\d{2,3})\b/) ?? rest.match(/\b(\d{2,3})\s*tren\s*(\d{2,3})\b/);
    if (m) {
      sys = Number(m[1]);
      dia = Number(m[2]);
    }
  }
  if (sys === undefined || dia === undefined) return null;
  if (sys < 70 || sys > 260 || dia < 40 || dia > 160 || sys <= dia) return { ok: false };
  if (pulse !== undefined && (pulse < 30 || pulse > 220)) pulse = undefined;
  return { ok: true, sys, dia, pulse };
}

/** Người nhận cuộc gọi ("gọi cho con trai", "gọi điện cho cô Lan", "gọi 115"); chỉ nhận khi có "điện/cho/đến/tới" hoặc số.
 *  Trả về cụm tên (có thể rỗng nếu chỉ nói "gọi điện"), hoặc null nếu không phải lệnh gọi. t đã bỏ dấu. */
export function callTarget(t: string): string | null {
  if (/\bvideo\b/.test(t)) return null;
  let m = t.match(/^goi (?:dien )?(?:thoai )?(?:cho|den|toi) (.+)$/);
  if (!m) m = t.match(/^goi dien(?: thoai)?(?: cho)?\s*(.*)$/);
  if (!m) m = t.match(/^(?:goi|bam may goi) (115|113|114)$/);
  if (!m) return null;
  return m[1].replace(/\s+(di|nhe|nha|a|giup toi|giup con|cho toi|cho con|ngay|luon)$/g, '').trim();
}

/** Câu HỎI về lịch uống thuốc ("tối nay tôi phải uống thuốc gì", "mấy giờ uống thuốc", "cữ thuốc kế tiếp"); t đã bỏ dấu.
 *  Chỉ nhận câu hỏi, KHÔNG nhận câu khẳng định như "tôi uống thuốc rồi" (đó là báo đã uống) hay "mở thuốc" (mở màn). */
export function medsQuery(t: string): boolean {
  if (/^(cu|lan|dot) (ke tiep|tiep theo)$/.test(t)) return true; // "cữ kế tiếp" (cữ chỉ nói về thuốc)
  if (!/\bthuoc\b/.test(t)) return false;
  if (/\b(roi|chua uong|het thuoc|mua thuoc|doi thuoc|bo thuoc|dung thuoc|doc don|don thuoc|tac dung|phu|liet)\b/.test(t)) return false;
  if (/^(mo|vao|xem|chuyen (sang|qua|den)|chup|quet|them|sua) /.test(t)) return false;
  if (/\b(uong thuoc|thuoc)\b.*\b(gi|nao|may gio|bao gio|khi nao|luc nao|chua|the nao)\b/.test(t)) return true;
  if (/\b(may gio|bao gio|khi nao|luc nao|gio nao)\b.*\b(uong thuoc|thuoc)\b/.test(t)) return true;
  if (/\b(uong|phai uong)\b.*\bthuoc\b.*\b(hom nay|toi nay|sang nay|trua nay|chieu nay)\b/.test(t)) return true;
  if (/\b(hom nay|toi nay|sang nay|trua nay|chieu nay)\b.*\b(uong|phai uong)\b.*\bthuoc\b/.test(t)) return true;
  if (/^(cu |lan |dot )?(thuoc|lich thuoc|cu thuoc)( (hom nay|toi nay|sang nay|trua nay|chieu nay|ke tiep|tiep theo))+$/.test(t)) return true;
  if (/\b(cu|lan|dot)\b( thuoc)? (ke tiep|tiep theo)\b/.test(t)) return true;
  return false;
}

/** Câu hỏi về tình trạng sức khoẻ của chính người nói (t đã bỏ dấu): trả về loại câu hỏi hoặc null. */
export function healthTopic(t: string): string | null {
  if (/(nguy co|dot quy|tim mach|co nguy hiem khong|nguy hiem khong)/.test(t)) return 'risk';
  if (/(tuan nay|thang nay|may ngay qua|dao nay).*(do|chup).*(may lan|bao nhieu lan)/.test(t) || /\bdo (may|bao nhieu) lan\b/.test(t)) return 'habit';
  if (/(huyet ap).*(dao nay|tuan nay|may ngay|xu huong|tang khong|giam khong|on dinh|the nao|sao roi|ra sao|co sao khong)/.test(t) || /(dao nay|tuan nay).*(huyet ap)/.test(t)) return 'trend';
  if (/(tinh trang|suc khoe).*(cua toi|cua con|hien tai|hom nay|the nao|ra sao|sao roi)/.test(t) || /^(suc khoe|tinh trang) (cua )?(toi|con)/.test(t) || /^(toi|con) (co )?khoe khong/.test(t)) return 'general';
  if (/(dau dau|chong mat|mat ngu|uong thuoc gi|an gi (tot|co loi)|co sao khong|bi benh gi|benh gi)/.test(t)) return 'other';
  return null;
}

/** Lệnh ngắn, rõ ràng không cần gọi LLM (tiết kiệm tiền + giảm độ trễ). */
type Fast = { intent: string; feature?: string; content?: string; recipient?: string; say?: string };

const SEND_VERB = /^(nhan tin|nhan|gui tin nhan|gui tin|gui)( cho| den)?$/;
const SEND_SEP = new Set(['rang', 'la', 'noi', 'nhe']);

/** "nhắn cho con trai là mai bác về", "nhắn tin cho Lan", "nhắn tin": tách người nhận/nội dung bằng luật, không gọi LLM.
 *  Chỉ nhận khi phần người nhận khớp danh bạ hoặc là cách gọi họ hàng; còn lại để LLM xử lý như cũ. */
export function fastSend(orig: string, contacts: Contact[], roomId?: string | null): Fast | null {
  const words = orig.trim().split(/\s+/).filter(Boolean);
  const nw = words.map(norm);
  if (nw.some((w) => !w || w.includes(' '))) return null;
  if (nw.join(' ') === 'nhan tin' || nw.join(' ') === 'gui tin nhan' || nw.join(' ') === 'gui tin') return { intent: 'send_message' };
  // động từ: 1–3 từ đầu (+ "cho"/"đến")
  let i = 0;
  let verbEnd = -1;
  for (let k = 1; k <= 4 && k < nw.length; k++) {
    if (SEND_VERB.test(nw.slice(0, k).join(' '))) verbEnd = k;
  }
  if (verbEnd < 0) return null;
  i = verbEnd;
  let sep = -1;
  for (let k = i + 1; k < nw.length && k <= i + 4; k++) {
    if (SEND_SEP.has(nw[k])) { sep = k; break; }
  }
  const rEnd = sep >= 0 ? sep : nw.length;
  if (rEnd - i < 1 || rEnd - i > 4) return null;
  const recipient = words.slice(i, rEnd).join(' ');
  const rr = resolveRecipient(recipient, contacts, roomId);
  if (rr.kind === 'none' && !isKinship(recipient)) return null;
  const content = sep >= 0 ? words.slice(sep + 1).join(' ') : '';
  if (sep >= 0 && content.length < 2) return null;
  return { intent: 'send_message', recipient, content };
}

const GREETING = /^(xin chao|chao|alo|hello|hi)( vy| co vy| em vy| ban| con)?( a| nhe)?$|^vy( oi)?( a)?$/;
const THANKS = /^(cam on|cam on vy|cam on con|cam on em)( nhieu| a| nhe| lam)*$/;
const NOT_SUPPORTED = /^(goi video|thoi tiet|may gio|bay gio la may gio|hom nay (la )?(thu|ngay) may|dat bao thuc|bao thuc)/;

const PRON = '(toi|bac|co|chu|ong|ba|anh|chi|em|con)';
const LEAD_FILLER = new RegExp(`^((u|um|uhm|uh|o|a|da|vang|roi|the|thi|ma|vay|nao|ok|okay|nay|vy oi|vy|lam on|cho ${PRON}|giup ${PRON}|${PRON} muon|${PRON} can)\\s+)+`);
const TRAIL_FILLER = new RegExp(`(\\s+(cho ${PRON}|giup ${PRON}|de ${PRON} (xem|nghe)|di|nhe|nha|a|ne|nao|voi|luon|ngay|duoc khong|dum))+$`);

/** Lời nói thật hay thừa đệm/đuôi ("ừ rồi mở màn hình huyết áp cho bác đi"): gọt về lệnh gọn trước khi so luật nhanh.
 *  Chỉ dùng cho luật nhanh; nội dung tin nhắn và phần gửi vẫn dùng câu gốc. t đã bỏ dấu. */
export function tidy(t: string): string {
  let s = t.replace(LEAD_FILLER, '').replace(TRAIL_FILLER, '').trim();
  // "mở cho tôi bài nhạc xưa" → "mở bài nhạc xưa"; "mở màn hình huyết áp" → "mở huyết áp"
  s = s.replace(new RegExp(`^(mo|bat|phat|nghe|xem|cho) cho ${PRON}\\s+`), '$1 ');
  s = s.replace(/^(mo|vao|xem|chuyen (?:sang|qua|den)) (?:man hinh|trang|phan|muc|tab) /, '$1 ');
  return s || t;
}

function fastIntent(t0: string, orig: string, contacts: Contact[], roomId: string | null | undefined, hon: string): Fast | null {
  // gọi điện: kiểm tra trước các luật "không hỗ trợ"
  const callee = callTarget(t0);
  if (callee !== null) return { intent: 'call_contact', recipient: callee };
  if (GREETING.test(t0)) return { intent: 'chitchat', say: `Dạ, con chào ${hon} ạ. ${hon[0].toUpperCase()}${hon.slice(1)} cần con giúp gì ạ?` };
  if (THANKS.test(t0)) return { intent: 'chitchat', say: 'Dạ, không có gì ạ.' };
  if (NOT_SUPPORTED.test(t0)) return { intent: 'unsupported' };
  const send = fastSend(orig, contacts, roomId);
  if (send) return send;
  const t = tidy(t0);
  if (/^(ve )?(trang chu|man hinh chinh)$/.test(t) || /^ve trang chu/.test(t)) return { intent: 'go_home' };
  if (/^(quay lai|tro lai|lui lai)( a| nhe)?$/.test(t)) return { intent: 'go_back' };
  if (/(xem|mo|vao).*(lich su|bieu do).*(huyet ap)/.test(t) || /^(xem|mo|vao|chuyen (sang|qua|den)) (theo doi )?huyet ap$/.test(t)) return { intent: 'show_bp' };
  if (/(huyet ap).*(bao nhieu|gan nhat|hom nay|vua do)/.test(t) || /(doc|cho biet).*(huyet ap)/.test(t)) return { intent: 'read_bp' };
  const bp = parseBp(t);
  if (bp) {
    if (!bp.ok) return { intent: 'chitchat', say: `Dạ, con nghe số đo chưa hợp lý. ${cap(hon)} đọc lại số huyết áp giúp con nhé.` };
    return { intent: 'record_bp', content: `${bp.sys},${bp.dia},${bp.pulse ?? ''}` };
  }
  if (/^(doc|nghe|cho nghe|xem) (tin nhan|tin)( moi| gan day| vua toi)?$|^(co|con) tin (nhan )?(moi )?(nao|khong)$|^ai (vua )?(nhan|gui)( tin)?( cho (toi|bac|con|co|chu))?$/.test(t))
    return { intent: 'read_messages' };
  if (medsQuery(t)) return { intent: 'read_meds' };
  const hs = healthTopic(t);
  if (hs) return { intent: 'health_status', content: hs };
  if (/\b(do|chup|doc)\b.*\b(huyet ap|may do)\b/.test(t) || /^do huyet ap/.test(t)) return { intent: 'measure_bp' };
  if (/^(mo|vao|xem) (tin nhan|chat|tro chuyen)( a| nhe)?$/.test(t)) return { intent: 'open_feature', feature: 'chat' };
  if (/^(mo|vao|chup|quet) (ocr|doc so lieu|so lieu)( a| nhe)?$/.test(t)) return { intent: 'open_feature', feature: 'ocr' };
  if (/^(mo|vao) (giai tri|youtube)( a| nhe)?$/.test(t)) return { intent: 'open_feature', feature: 'fun' };
  const ctl = videoControl(t);
  if (ctl) return { intent: 'video_control', content: ctl };
  const video = videoQuery(t);
  if (video) return { intent: 'play_video', content: video };
  if (/(giup|lam duoc gi|huong dan|biet lam gi|co the lam)/.test(t) && t.split(' ').length <= 8) return { intent: 'help' };
  return null;
}

// ---------- phân giải người nhận ----------

type Resolve = { kind: 'one'; contact: Contact } | { kind: 'many'; list: Contact[] } | { kind: 'none' };

const KINSHIP = /^(con trai|con gai|con|chau|chau trai|chau gai|bo|ba|me|mam|vo|chong|anh|chi|em|ong|ba noi|ba ngoai|cu|co|chu|bac|di|duong|cau|mo)$/;

export function isKinship(phrase: string): boolean {
  const n = norm(phrase);
  return KINSHIP.test(n) || /^(con|chau) (trai|gai|ut|dau|re)$/.test(n);
}

export function resolveRecipient(phrase: string, contacts: Contact[], roomId?: string | null): Resolve {
  const p = norm(phrase);
  if (!p) {
    const cur = roomId ? contacts.find((c) => c.id === roomId) : undefined;
    return cur ? { kind: 'one', contact: cur } : { kind: 'none' };
  }
  // 1) bí danh đã học
  const byAlias = contacts.filter((c) => (c.aliases ?? []).some((a) => norm(a) === p));
  if (byAlias.length === 1) return { kind: 'one', contact: byAlias[0] };
  if (byAlias.length > 1) return { kind: 'many', list: byAlias };
  // 2) khớp chính xác tên / username
  const exact = contacts.filter((c) => norm(c.name) === p || (c.username && norm(c.username) === p));
  if (exact.length === 1) return { kind: 'one', contact: exact[0] };
  if (exact.length > 1) return { kind: 'many', list: exact };
  // 3) khớp một phần theo từ / sai khác nhỏ (nghe nhầm)
  const scored = contacts
    .map((c) => {
      const names = [norm(c.name), c.username ? norm(c.username) : ''].filter(Boolean);
      let best = 99;
      for (const nm of names) {
        if (nm.includes(p) || p.includes(nm)) best = Math.min(best, 0);
        for (const tok of nm.split(' ')) {
          const lim = tok.length <= 4 ? 1 : 2;
          for (const pt of p.split(' ')) {
            const d = lev(tok, pt);
            if (d <= lim) best = Math.min(best, d);
          }
        }
        best = Math.min(best, lev(nm, p) <= (nm.length <= 5 ? 1 : 2) ? lev(nm, p) : 99);
      }
      return { c, best };
    })
    .filter((x) => x.best < 99)
    .sort((a, b) => a.best - b.best);
  if (!scored.length) return { kind: 'none' };
  const top = scored.filter((x) => x.best === scored[0].best);
  return top.length === 1 ? { kind: 'one', contact: top[0].c } : { kind: 'many', list: top.map((x) => x.c) };
}

// ---------- registry ----------

const REQUIRED: Record<string, string[]> = {
  send_message: ['recipient', 'content'],
  open_chat: ['recipient'],
  open_feature: ['feature'],
  play_video: ['content'],
  video_control: ['content'],
  measure_bp: [], show_bp: [], read_bp: [], read_meds: [], record_bp: [], read_messages: [], call_contact: [], health_status: [], go_back: [], go_home: [], help: [], chitchat: [],
};
const NEEDS_CONFIRM = new Set(['send_message', 'record_bp']);
export const INTENT_LIST = [...Object.keys(REQUIRED), 'unsupported'];
/** Ý định do bộ ghép với màn hình tạo ra (không nằm trong INTENT_LIST để mô hình không tự chọn). Có thể quay lại trong `state.task` khi chờ xác nhận. */
export const UI_INTENTS = ['invoke_control', 'choose_item', 'point_control', 'sos_start'];

function mk(p: Partial<Decision> & Pick<Decision, 'action' | 'say'>): Decision {
  return {
    intent: null, task: null, pending: null, expects: 'none', choices: [], sayClass: 'static',
    expectsReply: false, chips: [], aliasPhrase: null, ...p,
  };
}

const ORD: Record<string, number> = { mot: 0, '1': 0, dau: 0, nhat: 0, hai: 1, '2': 1, sau: 1, ba: 2, '3': 2 };

// ---------- bước hội thoại ----------

export async function step(
  input: { text: string; state: DState; ui: Ui; lowConfidence?: boolean },
  nlu: Nlu,
): Promise<Decision> {
  const { text, state, ui } = input;
  const hon = honorificOf(ui.honorific);
  const contacts = ui.contacts ?? [];
  const t = norm(text);
  const expects = state.expects ?? 'command';

  if (!t) return mk({ action: 'ask', say: S.notHeard(hon), expects: expects === 'none' ? 'command' : expects, expectsReply: true, task: state.task ?? null, pending: state.pending ?? null, choices: state.choices ?? [], aliasPhrase: state.aliasPhrase ?? null });

  // 1) khẩn cấp (không áp dụng khi đang đọc nội dung tin nhắn)
  if (expects !== 'free_text' && EMERGENCY.test(t)) {
    return mk({ action: 'answer', intent: 'emergency', say: S.emergency(hon), sayClass: 'emergency', chips: [] });
  }
  // 1b) có hộp thoại đang mở trên màn hình: "đồng ý"/"huỷ"/"ở lại" là nút của hộp thoại, không phải việc đang dở
  if (ui.context?.dialog) {
    const d = uiDecision(text, ui.context, hon);
    if (d) return d;
  }
  // 1c) "đúng rồi" và "dừng" cùng thành "dung" khi bỏ dấu: đang chờ xác nhận thì xét chữ CÓ DẤU, để "đúng rồi" luôn là đồng ý.
  if (expects === 'yes_no' && state.task && !input.lowConfidence && /^đúng( rồi| ạ| vậy| nhé)?[.!]?$/i.test(text.trim())) {
    const tk: Task = { intent: state.task.intent, slots: { ...state.task.slots } };
    return mk({ action: 'execute', intent: tk.intent, task: tk, say: doneSay(tk) });
  }
  // 2) hủy
  if (CANCEL.test(t)) return mk({ action: 'cancel', say: S.cancelled() });
  if (REPEAT.test(t) && t.split(' ').length <= 4) return mk({ action: 'repeat', say: '' });

  let task: Task | null = state.task ? { intent: state.task.intent, slots: { ...state.task.slots } } : null;
  let learnAlias: Decision['learnAlias'];
  let aliasPhrase = state.aliasPhrase ?? null;

  // 3) đang chờ xác nhận
  if (expects === 'yes_no' && task) {
    if (YES.test(t) && !input.lowConfidence) {
      return mk({ action: 'execute', intent: task.intent, task, say: doneSay(task) });
    }
    const editWords = matchPrefixWords(t, EDIT_PREFIX);
    if (editWords > 0 && task.intent === 'send_message') {
      const rest = text.trim().split(/\s+/).slice(editWords).join(' ');
      const content = cleanContent(rest.replace(/^(la|rang|nhu sau)\b[:, ]*/i, ''));
      if (content.length >= 2) {
        task.slots.content = content;
        return progress(task, ui, hon, contacts, aliasPhrase, learnAlias);
      }
    }
    if (NO.test(t) || editWords > 0) {
      if (task.intent === 'send_message') {
        delete task.slots.content;
        return mk({ action: 'ask', intent: task.intent, task, pending: 'content', expects: 'free_text', say: S.askContent(hon), expectsReply: true });
      }
      return mk({ action: 'cancel', say: task.intent === 'record_bp' ? `Dạ, con chưa ghi. ${cap(hon)} đọc lại số đo giúp con nhé.` : S.cancelled() });
    }
    // Trả lời khác ("gửi cho Lan đi"...): để NLU xử lý như lệnh mới.
    task = null;
  }

  // 4) đang chờ nội dung tin nhắn: toàn bộ câu là nội dung, KHÔNG phân loại ý định
  if (expects === 'free_text' && task && state.pending) {
    const content = cleanContent(text);
    if (content.length < 1) return mk({ action: 'ask', say: S.notHeard(hon), expects: 'free_text', expectsReply: true, task, pending: state.pending });
    task.slots[state.pending] = content;
    return progress(task, ui, hon, contacts, aliasPhrase, learnAlias);
  }

  // 5) đang chờ chọn người nhận
  if (expects === 'choice' && task && (state.choices ?? []).length) {
    const ch = state.choices!;
    let pick = ch.find((c) => norm(c.name) === t || t.includes(norm(c.name)));
    if (!pick) {
      const w = t.split(' ').find((x) => x in ORD);
      if (w !== undefined && ORD[w] < ch.length) pick = ch[ORD[w]];
    }
    if (pick) {
      const c = contacts.find((x) => x.id === pick!.id);
      if (c) {
        setRecipient(task, c);
        if (aliasPhrase) { learnAlias = { alias: norm(aliasPhrase), contactId: c.id }; aliasPhrase = null; }
        return progress(task, ui, hon, contacts, aliasPhrase, learnAlias);
      }
    }
    return mk({ action: 'ask', intent: task.intent, task, expects: 'choice', choices: ch, say: choiceSay(hon, ch), sayClass: 'other', expectsReply: true, chips: ch.map((c) => c.name) });
  }

  // 6) đang chờ tên người nhận (ví dụ "con trai bác tên là gì")
  if (expects === 'name' && task) {
    const r = resolveRecipient(text, contacts);
    if (r.kind === 'one') {
      setRecipient(task, r.contact);
      if (aliasPhrase) { learnAlias = { alias: norm(aliasPhrase), contactId: r.contact.id }; aliasPhrase = null; }
      return progress(task, ui, hon, contacts, aliasPhrase, learnAlias);
    }
    if (r.kind === 'many') return askChoice(task, r.list, hon, aliasPhrase);
    return mk({ action: 'ask', intent: task.intent, task, pending: 'recipient', expects: 'name', say: noContactSay(hon, text), sayClass: 'other', expectsReply: true, aliasPhrase, chips: contacts.slice(0, 4).map((c) => c.name) });
  }

  // 6a) SOS nói rõ: bắt đầu đếm ngược 5 giây có nút Huỷ ở app (người thật khởi động; Vy không tự bắt đầu). Bản app cũ chỉ đọc câu hướng dẫn.
  if (sosExplicit(t)) {
    const task: Task = { intent: 'sos_start', slots: {} };
    return mk({
      action: 'execute', intent: 'sos_start', task, sayClass: 'important',
      say: `Dạ, ${hon} giữ nút SOS màu đỏ ở dưới màn hình giúp con nhé.`,
    });
  }

  // 6b) màn hình thật: ghép với điều khiển/danh sách đang hiện (hộp thoại che màn sau)
  if (ui.context) {
    const d = uiDecision(text, ui.context, hon);
    if (d) return d;
  }

  // 7) lệnh mới: luật nhanh → LLM
  const fast = fastIntent(t, text, contacts, ui.roomId, hon);
  let nluOut: NluResult | null = null;
  if (fast) {
    let content = fast.content ?? '';
    if (fast.intent === 'play_video' && content) {
      // Lấy lại cụm có dấu từ câu gốc để tìm trên YouTube chính xác hơn (nếu khớp với bản không dấu).
      const orig = text.trim().split(/\s+/).slice(-content.split(' ').length).join(' ');
      if (norm(orig) === content) content = orig;
    }
    nluOut = { intent: fast.intent, recipient: fast.recipient ?? '', content, feature: fast.feature ?? '', say: fast.say ?? '' };
  } else {
    try {
      nluOut = await nlu(text, { state, ui, honorific: hon });
    } catch {
      return mk({ action: 'answer', intent: 'error', say: S.trouble(hon) });
    }
  }
  const intent = INTENT_LIST.includes(nluOut.intent) ? nluOut.intent : 'unsupported';

  if (intent === 'unsupported') return mk({ action: 'unsupported', intent, say: S.unsupported(hon) });
  if (intent === 'help') return mk({ action: 'answer', intent, say: S.help(hon) });
  if (intent === 'chitchat') {
    const say = (nluOut.say || '').trim().slice(0, 200) || S.help(hon);
    return mk({ action: 'answer', intent, say, sayClass: 'other' });
  }

  task = { intent, slots: {} };
  if (nluOut.recipient) task.slots.recipient_text = nluOut.recipient.slice(0, 40);
  if (nluOut.content) task.slots.content = cleanContent(nluOut.content.slice(0, 500));
  if (intent === 'open_feature') {
    // Mô hình đôi khi chọn "mở một mục" mà quên nói mục nào: lấy từ chính câu người dùng thay vì hỏi lại.
    const f = featureOf(nluOut.feature || '') || featureOf(text);
    if (f) task.slots.feature = f;
  }
  return progress(task, ui, hon, contacts, null, undefined);
}

function cap(h: string): string {
  return `${h[0].toUpperCase()}${h.slice(1)}`;
}

/** Câu Vy nói khi xong một việc đã được xác nhận. */
function doneSay(task: Task): string {
  if (task.intent === 'send_message') return S.sentOk();
  if (task.intent === 'record_bp') return 'Dạ, con ghi rồi ạ.';
  return task.slots.say || S.opened();
}

function actPhrase(c: UiControl, set?: boolean): string {
  if (c.kind === 'toggle') return `${set ? 'bật' : 'tắt'} ${c.label}`;
  if (c.kind === 'tab') return `mở ${c.label}`;
  return `bấm ${c.label}`;
}

function controlSay(c: UiControl, set: boolean | undefined, hon: string): string {
  // `{hon}` trong câu của nút được thay bằng cách xưng hô của người dùng ("Dạ, con ghi {hon} đã uống rồi ạ.").
  if (c.say) return c.say.replaceAll('{hon}', hon);
  if (c.kind === 'toggle') return `Dạ, con ${set ? 'bật' : 'tắt'} ${c.label} rồi ạ.`;
  if (c.kind === 'tab') return `Dạ, con mở ${c.label} rồi ạ.`;
  return `Dạ, con bấm ${c.label} rồi ạ.`;
}

/** Biến kết quả ghép màn hình thành quyết định. Mức xác nhận: 0/1 làm ngay, 2 hỏi lại, 3 không bao giờ bấm. */
export function uiDecision(text: string, ctx: UiContext, hon: string): Decision | null {
  const cmd = resolveUiCommand(text, ctx);
  if (!cmd) return null;
  switch (cmd.kind) {
    case 'choose': {
      const it = cmd.list.items[cmd.n - 1];
      const task: Task = { intent: 'choose_item', slots: { list_id: cmd.list.id, n: String(cmd.n), title: it.title.slice(0, 80) } };
      return mk({ action: 'execute', intent: 'choose_item', task, say: `Dạ, con mở ${it.title.slice(0, 60)} ạ.`, sayClass: 'other' });
    }
    case 'out_of_range':
      return mk({ action: 'answer', intent: 'choose_item', say: `Dạ, con chỉ thấy ${cmd.list.items.length} mục thôi ạ. ${cap(hon)} chọn lại giúp con nhé.`, sayClass: 'other' });
    case 'ambiguous': {
      const names = cmd.options.map((o) => o.label);
      return mk({
        action: 'ask', intent: 'invoke_control', expects: 'command', expectsReply: true,
        say: `Dạ, ${hon} muốn ${names.slice(0, -1).join(', ')} hay ${names[names.length - 1]} ạ?`,
        sayClass: 'other', chips: names,
      });
    }
    case 'refuse': {
      const c = cmd.control;
      if (cmd.why === 'level3') {
        // Mức 3: Vy KHÔNG bấm. App chỉ làm một việc là con trỏ chỉ vào nút (khung sáng); bản app cũ chỉ đọc câu nói.
        const task: Task = { intent: 'point_control', slots: { target_id: c.id, label: c.label.slice(0, 60) } };
        return mk({ action: 'execute', intent: 'point_control', task, say: `Dạ, nút ${c.label} ${hon} tự bấm giúp con nhé. Con không bấm thay được ạ.`, sayClass: 'important' });
      }
      if (cmd.why === 'already') {
        return mk({ action: 'answer', intent: 'refuse_control', say: `Dạ, ${c.label} đang ${c.value ? 'bật' : 'tắt'} rồi ạ.`, sayClass: 'other' });
      }
      return mk({ action: 'answer', intent: 'refuse_control', say: `Dạ, nút ${c.label} bây giờ chưa bấm được ạ.`, sayClass: 'other' });
    }
    case 'invoke': {
      const c = cmd.control;
      const slots: Record<string, string> = { control_id: c.id, label: c.label.slice(0, 60), say: controlSay(c, cmd.set, hon).slice(0, 200) };
      if (cmd.set !== undefined) slots.set = cmd.set ? '1' : '0';
      const task: Task = { intent: 'invoke_control', slots };
      if (c.level === 2) {
        return mk({
          action: 'confirm', intent: 'invoke_control', task, expects: 'yes_no', expectsReply: true,
          say: `${cap(hon)} muốn ${actPhrase(c, cmd.set)}, đúng không ạ?`, sayClass: 'important', chips: ['Đồng ý', 'Hủy'],
        });
      }
      return mk({ action: 'execute', intent: 'invoke_control', task, say: controlSay(c, cmd.set, hon), sayClass: 'other' });
    }
  }
}

function setRecipient(task: Task, c: Contact) {
  task.slots.room_id = c.id;
  task.slots.recipient_name = c.name;
  task.slots.recipient_kind = c.kind;
  delete task.slots.recipient_text;
}

function choiceSay(hon: string, ch: { name: string }[]) {
  const names = ch.slice(0, 3).map((c) => c.name);
  return `${hon[0].toUpperCase()}${hon.slice(1)} muốn chọn ${names.slice(0, -1).join(', ')}${names.length > 1 ? ' hay ' : ''}${names[names.length - 1]} ạ?`;
}
function noContactSay(hon: string, name: string) {
  return `Dạ, con chưa thấy ${name.trim().slice(0, 30)} trong danh sách của ${hon}. ${hon[0].toUpperCase()}${hon.slice(1)} nói lại tên giúp con nhé.`;
}

function askChoice(task: Task, list: Contact[], hon: string, aliasPhrase: string | null): Decision {
  const ch = list.slice(0, 3).map((c) => ({ id: c.id, name: c.name }));
  return mk({ action: 'ask', intent: task.intent, task, pending: 'recipient', expects: 'choice', choices: ch, say: choiceSay(hon, ch), sayClass: 'other', expectsReply: true, chips: ch.map((c) => c.name), aliasPhrase });
}

/** Sau khi có thêm thông tin: tính slot còn thiếu và quyết định hỏi / xác nhận / thực hiện. */
function progress(
  task: Task,
  ui: Ui,
  hon: string,
  contacts: Contact[],
  aliasPhrase: string | null,
  learnAlias: Decision['learnAlias'],
): Decision {
  const intent = task.intent;
  const need = REQUIRED[intent] ?? [];

  // người nhận
  if (need.includes('recipient') && !task.slots.room_id) {
    const phrase = task.slots.recipient_text ?? '';
    const r = resolveRecipient(phrase, contacts, ui.roomId);
    if (r.kind === 'one') {
      setRecipient(task, r.contact);
    } else if (r.kind === 'many') {
      return askChoice(task, r.list, hon, aliasPhrase);
    } else if (!phrase) {
      return mk({ action: 'ask', intent, task, pending: 'recipient', expects: 'name', say: S.askRecipient(hon), expectsReply: true, chips: contacts.slice(0, 4).map((c) => c.name), aliasPhrase });
    } else if (isKinship(phrase)) {
      return mk({ action: 'ask', intent, task, pending: 'recipient', expects: 'name', say: S.askName(hon), expectsReply: true, aliasPhrase: phrase, chips: contacts.slice(0, 4).map((c) => c.name) });
    } else {
      return mk({ action: 'ask', intent, task, pending: 'recipient', expects: 'name', say: noContactSay(hon, phrase), sayClass: 'other', expectsReply: true, aliasPhrase, chips: contacts.slice(0, 4).map((c) => c.name) });
    }
  }
  // nội dung
  if (need.includes('content') && !task.slots.content) {
    return mk({
      action: 'ask', intent, task, pending: 'content', expects: 'free_text',
      say: intent === 'play_video' ? S.askVideo(hon) : S.askContent(hon),
      expectsReply: true, aliasPhrase, learnAlias,
      chips: intent === 'play_video' ? ['Nhạc xưa', 'Tin tức', 'Cải lương'] : [],
    });
  }
  if (need.includes('feature') && !task.slots.feature) {
    return mk({ action: 'ask', intent, task, pending: 'feature', expects: 'command', say: S.askFeatureMissing(hon), expectsReply: true, chips: ['Tin nhắn', 'Huyết áp', 'Giải trí'] });
  }

  if (intent === 'record_bp') {
    const [sys, dia, pulse] = (task.slots.content ?? '').split(',');
    task.slots.systolic = sys ?? '';
    task.slots.diastolic = dia ?? '';
    task.slots.pulse = pulse ?? '';
    const pl = pulse ? `, mạch ${pulse}` : '';
    return mk({
      action: 'confirm', intent, task, expects: 'yes_no', expectsReply: true,
      say: `Con ghi huyết áp ${sys} trên ${dia}${pl}. ${cap(hon)} nói đúng không ạ?`,
      sayClass: 'important', chips: ['Lưu', 'Sửa', 'Hủy'],
    });
  }
  if (NEEDS_CONFIRM.has(intent)) {
    const name = task.slots.recipient_name ?? '';
    const content = task.slots.content ?? '';
    return mk({
      action: 'confirm', intent, task, expects: 'yes_no', expectsReply: true,
      say: `Con gửi cho ${name}: ${content} ${hon[0].toUpperCase()}${hon.slice(1)} gửi nhé?`,
      sayClass: 'important', chips: ['Gửi', 'Sửa', 'Hủy'], learnAlias,
    });
  }
  const say = ['read_bp', 'read_meds', 'read_messages', 'call_contact'].includes(intent) ? '' : S.opened();
  return mk({ action: 'execute', intent, task, say, learnAlias });
}
