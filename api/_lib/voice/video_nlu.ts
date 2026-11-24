/**
 * Hiểu yêu cầu giải trí bằng luật (miễn phí, không gọi mô hình): chủ đề ("mở cải lương", "nghe kinh Phật"),
 * câu chung chung ("mở cái gì vui vui", "hôm nay có gì hay"), tâm trạng ("chán quá"), giấc ngủ ("mở gì cho dễ ngủ").
 * Mọi chuỗi vào đây đã bỏ dấu, chữ thường, đã gọt đệm (xem `tidy` trong dm.ts).
 *
 * Nguyên tắc (kế hoạch docs/KE_HOACH_VY_GIAI_TRI.md): làm trước, hỏi sau; câu hỏi tối đa một câu có gợi ý chạm được.
 */

export type VideoIntent =
  | { kind: 'play'; query: string }
  | { kind: 'ask'; tag: 'general' | 'open' | 'mood' | 'music' | 'sleep'; say: (hon: string) => string; chips: string[] };

const NOT_VIDEO = /\b(tin nhan|nhan tin|huyet ap|chat|ocr|trang chu|so lieu|nhan cho|gui cho|thuoc|goi cho|goi dien)\b/;

const VERB =
  '(?:mo|bat|phat|vao|xem|nghe|tim|tap|doc|cho (?:toi |con |bac |co |chu |me |ba )?(?:nghe|xem))';

/** Chủ đề: `q` là từ khoá có dấu đưa đi tìm (khớp nút trên màn Giải trí); null = giữ nguyên chữ đã nói. */
type Topic = { re: string; q: string | null; withRest?: string };

const TOPICS: Topic[] = [
  // nhạc theo thể loại
  { re: 'nhac xua', q: 'nhạc xưa' },
  { re: 'nhac vang', q: 'nhạc vàng' },
  { re: 'nhac tru tinh', q: 'nhạc trữ tình' },
  { re: 'nhac que huong', q: 'nhạc quê hương' },
  { re: 'nhac (?:cach mang|do)', q: 'nhạc cách mạng' },
  { re: 'nhac thieu nhi', q: 'nhạc thiếu nhi' },
  { re: 'nhac (?:khong loi|hoa tau|piano|guitar)', q: 'nhạc không lời' },
  { re: 'nhac (?:ru ngu|de ngu|cho ngu|ngu)', q: 'nhạc ru ngủ' },
  { re: 'nhac (?:thien|thu gian|nhe nhang|nhe)', q: 'nhạc thiền' },
  { re: 'nhac trinh(?: cong son)?', q: 'nhạc Trịnh Công Sơn' },
  { re: 'bolero', q: 'bolero' },
  // thư giãn, tập luyện
  { re: 'thien', q: 'thiền thư giãn' },
  { re: '(?:bai tap )?(?:duong sinh|the duc)|tap duong sinh|tap the duc', q: 'bài tập dưỡng sinh người lớn tuổi' },
  { re: 'yoga', q: 'yoga cho người cao tuổi' },
  { re: 'khi cong|thai cuc(?: quyen)?', q: 'thái cực quyền người cao tuổi' },
  // sân khấu, hài, phim
  { re: 'cai luong', q: 'cải lương' },
  { re: 'tuong(?: co)?', q: 'tuồng cổ' },
  { re: 'cheo(?: co)?', q: 'chèo cổ' },
  { re: '(?:hai kich|hai huoc|tieu pham|hai)', q: 'hài kịch' },
  { re: 'phim (?:bo|truyen|viet nam|xua|co trang|kiem hiep)', q: null },
  { re: '(?:phim )?hoat hinh', q: 'phim hoạt hình thiếu nhi' },
  { re: 'karaoke', q: 'karaoke nhạc xưa', withRest: 'karaoke' },
  // tin tức, thể thao
  { re: '(?:tin tuc|thoi su|ban tin)', q: 'tin tức' },
  { re: '(?:bong da|da banh)', q: 'bóng đá' },
  { re: '(?:v league|ngoai hang anh|world cup)', q: null },
  // kinh, truyện, đài
  { re: 'kinh (?:a di da|quan the am|bat nha|dia tang|pho mon|kim cang|lang nghiem)', q: null },
  { re: '(?:kinh phat|tung kinh|kinh)', q: 'kinh Phật' },
  { re: '(?:truyen dem khuya|truyen)', q: 'truyện đêm khuya', withRest: 'truyện' },
  { re: '(?:sach noi|doc sach)', q: 'sách nói' },
  { re: '(?:dai phat thanh|radio|dai tieng noi viet nam|vov|dai)', q: 'đài phát thanh VOV' },
  { re: '(?:nau an|day nau an|mon ngon)', q: 'dạy nấu ăn món ngon' },
];

const MEDIA_HEAD = /^(?:bai hat|ca khuc|chuong trinh|video|clip|kenh|youtube|bai(?! tap))\s+/;

const ASK_GENERAL = {
  say: (h: string) => `Dạ, ${h} muốn nghe nhạc, xem hài hay nghe tin tức ạ?`,
  chips: ['Nhạc xưa', 'Hài kịch', 'Tin tức'],
};
const ASK_MOOD = {
  say: (h: string) => `Dạ, cho ${h} khuây khoả, con mở hài kịch, nhạc xưa hay thiền thư giãn ạ?`,
  chips: ['Hài kịch', 'Nhạc xưa', 'Thiền thư giãn'],
};
const ASK_MUSIC = {
  say: (h: string) => `Dạ, ${h} muốn nghe nhạc xưa, nhạc trữ tình hay nhạc không lời ạ?`,
  chips: ['Nhạc xưa', 'Nhạc trữ tình', 'Nhạc không lời'],
};
const ASK_SLEEP = {
  say: (h: string) => `Dạ, cho ${h} dễ ngủ, con mở nhạc ru ngủ, truyện đêm khuya hay thiền thư giãn ạ?`,
  chips: ['Nhạc ru ngủ', 'Truyện đêm khuya', 'Thiền thư giãn'],
};

/** "mở cái gì vui vui", "nghe gì đó", "xem gì hay hay": có động từ nhưng chưa nói gì cụ thể. */
const GENERIC = /\b(cai gi|gi do|gi di|gi cung duoc|gi hay|gi vui|gi cho (?:vui|do|khuay)|tuy y|tuy ban|bat ky|cai nao cung duoc)\b/;
/** "hôm nay có gì hay", "có gì xem không". */
const OPEN_Q =
  /^(?:hom nay |bay gio |toi nay |sang nay )?(?:co|con) (?:gi|chuong trinh gi|phim gi|nhac gi|bai gi|video gi)(?: (?:hay|moi|vui|xem|nghe|de xem|de nghe))*(?: khong| nhi| a)?$/;

const MOOD = /(?:^|\s)(?:buon(?! (?:ngu|cuoi))|chan(?= (?:qua|lam|ghe|vay|doi|roi|thiet)|$)|co don|nho nha|khong vui)(?:\s|$)/;
const BODY_BEFORE_CHAN = /\b(?:dau|nhuc|moi|sung|te|run|bai|liet|gay|bong)\s+(?:\w+\s+)?chan\b/;
const SLEEP_WISH = /\b(?:ru ngu|de ngu|cho ngu|ngu ngon|giac ngu)\b/;
const SLEEP_TROUBLE = /\b(?:mat ngu|kho ngu|khong ngu duoc|tran troc)\b/;

const strip = (s: string) => s.trim().replace(/\s+/g, ' ');
const plain = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').toLowerCase();

function topicOf(body: string): string | null {
  for (const tp of TOPICS) {
    const m = body.match(new RegExp(`^(${tp.re})(?:\\s+(.+))?$`));
    if (!m) continue;
    let rest = strip(m[2] ?? '');
    const head = tp.q ?? strip(m[1]);
    // "thiền thư giãn", "tiểu phẩm hài": phần đuôi đã nằm trong chủ đề thì đừng nối thêm.
    if (rest && plain(head).includes(rest)) rest = '';
    const q = rest ? `${tp.withRest ?? head} ${rest}` : head;
    return q.trim();
  }
  return null;
}

export function videoIntent(t: string): VideoIntent | null {
  if (NOT_VIDEO.test(t)) return null;
  const words = t.split(' ').length;
  if (words > 14) return null;

  // 1) động từ + chủ đề: "mở cải lương Lệ Thủy", "nghe kinh Phật", "tập dưỡng sinh", "cho nghe nhạc xưa"
  const v = t.match(new RegExp(`^${VERB}\\s+(.+)$`));
  if (v) {
    let body = strip(v[1]).replace(/^cho (?:toi|bac|con|co|chu|me|ba)\s+/, '');
    body = body.replace(MEDIA_HEAD, '');
    // Chỉ bỏ "cái" trong "cái gì"; "cải lương" không dấu cũng là "cai luong".
    body = body.replace(/^cai\s+(?=gi\b)/, '').replace(/^(?:nhung|may|mot)\s+/, '');
    // "dừng/thôi/tắt" kiểu đuôi: bỏ đệm cuối
    body = body.replace(/\s+(?:di|nhe|nha|a|ne|nao|voi|luon|ngay|len|giup (?:toi|con))$/, '');
    const topic = topicOf(body);
    if (topic) return { kind: 'play', query: topic };

    // 2) động từ + giấc ngủ: "mở gì cho dễ ngủ", "cho nghe cái gì ru ngủ"
    if (SLEEP_WISH.test(body)) return { kind: 'play', query: 'nhạc ru ngủ' };

    // 3) động từ + chung chung: "mở cái gì vui vui", "nghe gì đó", "xem gì hay hay"
    if (GENERIC.test(body) || /^gi(?:\s+\w+){0,3}$/.test(body)) {
      if (MOOD.test(t) && !BODY_BEFORE_CHAN.test(t)) return { kind: 'ask', tag: 'mood', ...ASK_MOOD };
      return { kind: 'ask', tag: 'general', ...ASK_GENERAL };
    }
  }

  // 4) câu hỏi mở: "hôm nay có gì hay", "có gì xem không"
  if (OPEN_Q.test(t)) return { kind: 'ask', tag: 'open', ...ASK_GENERAL };

  // 5) khó ngủ (không nói động từ): hỏi chọn nhạc ru ngủ/truyện/thiền
  if (SLEEP_TROUBLE.test(t) && words <= 9) return { kind: 'ask', tag: 'sleep', ...ASK_SLEEP };

  // 6) tâm trạng: "chán quá", "buồn quá, mở cái gì đi", "buồn quá mở nhạc"
  if (words <= 10 && MOOD.test(t) && !BODY_BEFORE_CHAN.test(t)) {
    if (/\b(hai|cuoi)\b/.test(t) && /\b(mo|bat|cho nghe|cho xem|xem|nghe)\b/.test(t)) return { kind: 'play', query: 'hài kịch' };
    if (/\bnhac\b/.test(t)) return { kind: 'ask', tag: 'music', ...ASK_MUSIC };
    return { kind: 'ask', tag: 'mood', ...ASK_MOOD };
  }
  return null;
}

// ---------- trí nhớ nghe/xem (đợt 4) ----------

/** Thói quen app đã nhớ trên máy và gửi lên mỗi lượt. */
export type Habit = { top: string; topics: string[]; resume: string; last: string };

const RECALL_VERB = '(?:mo|nghe|phat|bat|cho nghe|xem)';
const ARTICLE = '(?: (?:cai|bai|video|nhac|phim|bai hat))?';
const TIME_PHRASE =
  '(?:vua (?:nghe|roi|xem)(?: xong)?|luc nay(?: toi (?:nghe|xem))?|(?:ngay )?hom (?:qua|truoc)(?: toi (?:nghe|xem))?|truoc do|truoc day|cu)';

const RE_LAST = new RegExp(`^${RECALL_VERB}(?: lai)?${ARTICLE} ${TIME_PHRASE}$`);
const RE_FAVORITE = new RegExp(
  `^${RECALL_VERB}(?: lai)?(?: (?:nhung |may )?(?:bai|nhac|cai|bai hat))? (?:(?:toi|bac|con|co|chu|ong|ba) )?(?:hay thich|da thich|thich nhat|thich|yeu thich|da luu|hay nghe nhat)$`,
);
const RE_HABIT = new RegExp(
  `^${RECALL_VERB}(?: lai)?(?: (?:bai|nhac|cai|video|bai hat))? (?:(?:toi|bac|con|co|chu) )?(?:hay nghe|hay xem|nhu hom qua|nhu luc nay|nhu cu|nhu moi khi|nhu moi ngay|nhu moi|nhu thuong le|nhu thuong)$`,
);
const RE_RESUME = /^(?:(?:mo|nghe|xem|phat|bat) tiep(?: tuc)?|tiep tuc (?:xem|nghe|phim|bai|tap|truyen))(?: (?:bai|phim|tap|truyen|vo|cai luong|kinh|video|clip))?(?: (?:dang (?:xem|nghe) do|hom qua|luc nay|do|vua roi|toi dang (?:xem|nghe)))*$/;

const MUSIC_TOPIC = /(nhac|bolero|trinh|ca khuc|bai hat|karaoke|tru tinh)/;
const plainText = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').toLowerCase();

/** "mở lại bài lúc nãy" (@last), "xem tiếp" (@resume), "bài tôi thích" (@favorite), "như mọi khi" (@habit). */
export function videoRecall(t: string, playerOpen: boolean): '@last' | '@resume' | '@favorite' | '@habit' | null {
  if (NOT_VIDEO.test(t)) return null;
  if (RE_FAVORITE.test(t)) return '@favorite';
  if (RE_HABIT.test(t)) return '@habit';
  if (RE_LAST.test(t)) return '@last';
  // Đang phát thì "nghe tiếp/xem tiếp" là phát tiếp (điều khiển), không phải mở bài khác.
  if (!playerOpen && RE_RESUME.test(t)) return '@resume';
  return null;
}

const RE_LIKE = /^(?:bai nay (?:rat )?hay(?: lam| qua| day)?|hay (?:qua|lam)|thich bai nay|toi thich bai nay|luu bai nay|nho bai nay|them vao yeu thich)(?: a| nhe| nha| qua| lam| day| di)*$/;
const RE_DISLIKE =
  /^(?:khong thich(?: bai nay| cai nay)?|bai nay (?:do|chan|khong hay|nhat|kho nghe|kho chiu)|chan bai nay|bo bai nay|dung mo bai nay nua|khong nghe bai nay nua|khong muon nghe bai nay)(?: a| nhe| nha| qua| lam| di| nua)*$/;

/** Khen/chê bài đang phát ("bài này hay", "không thích bài này"). Chỉ có nghĩa khi đang có video phát. */
export function videoFeedback(t: string): 'like' | 'dislike' | null {
  if (RE_LIKE.test(t)) return 'like';
  if (RE_DISLIKE.test(t)) return 'dislike';
  return null;
}

/** Chủ đề nên mở khi người dùng chỉ nói muốn nghe/xem (không nêu gì): lấy từ thói quen. Nói "nhạc" thì chỉ nhận chủ đề là nhạc. */
export function habitTopicFor(habit: Habit | undefined, wantsMusic: boolean): string | null {
  if (!habit) return null;
  const list = habit.topics.length ? habit.topics : habit.top ? [habit.top] : [];
  const pick = wantsMusic ? list.find((x) => MUSIC_TOPIC.test(plainText(x))) : list[0];
  return pick || null;
}

/** Gợi ý chạm được: chủ đề người dùng hay nghe lên trước, bù bằng gợi ý mặc định cho đủ 3. */
export function personalChips(defaults: string[], habit: Habit | undefined): string[] {
  const cap = (x: string) => x.charAt(0).toUpperCase() + x.slice(1);
  const out: string[] = [];
  for (const x of [...(habit?.topics ?? []).slice(0, 2).map(cap), ...defaults]) {
    if (!out.some((y) => plainText(y) === plainText(x))) out.push(x);
    if (out.length === 3) break;
  }
  return out;
}
