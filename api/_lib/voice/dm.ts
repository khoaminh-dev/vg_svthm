// Bộ não hội thoại: nhận câu nói (đã chuyển thành chữ) + trạng thái hiện tại → quyết định bước kế tiếp.
// Nguyên tắc: LLM chỉ "hiểu" (intent + slot thô). Việc đủ/thiếu slot, hỏi lại, xác nhận, phân giải người nhận
// đều do code ở đây quyết định để chắc chắn và kiểm thử được. Xem docs/VOICE_AGENT.md mục 4.

export type Expect = 'command' | 'free_text' | 'yes_no' | 'choice' | 'name' | 'none';
export type Contact = { id: string; kind: 'direct' | 'group'; name: string; username?: string; aliases?: string[] };
export type Ui = { screen?: string; roomId?: string | null; contacts?: Contact[]; honorific?: string };
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
  help: (h: string) => `Con giúp ${h} nhắn tin, đo huyết áp và xem lịch sử huyết áp ạ.`,
  unsupported: (h: string) => `Việc này con chưa làm được. Con giúp ${h} nhắn tin hoặc đo huyết áp nhé?`,
  emergency: (h: string) => `${h} hãy gọi 115 hoặc nhờ người thân ngay nhé. Nếu thấy nguy hiểm, đừng chờ ạ.`,
  trouble: (h: string) => `Con đang trục trặc một chút, ${h} thử lại sau nhé.`,
  confirmHint: (h: string) => `${h} nói "gửi" hoặc "sửa" giúp con nhé.`,
  askFeatureMissing: (h: string) => `Dạ, ${h} muốn mở phần nào ạ?`,
};

/** Toàn bộ câu cố định (theo từng cách xưng hô) — dùng để chứng thực "câu tĩnh" ở /voice/tts và tạo cache dùng chung. */
export function staticTexts(): Set<string> {
  const out = new Set<string>();
  for (const h of HONORIFICS) {
    for (const f of [S.askRecipient, S.askContent, S.askName, S.notHeard, S.help, S.unsupported, S.trouble, S.confirmHint, S.askFeatureMissing]) {
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
const YES = /^(co|co a|vang|da|u|uh|um|dung|dung roi|gui|gui di|gui nhe|gui di nhe|gui luon|ok|okay|duoc|dong y|chuan|chinh xac|ung)( a| nhe| di| roi| nha)?$/;
const NO = /^(khong|khong phai|sai|sai roi|chua|khong dung|khong gui)( a| roi)?$/;
const EDIT_PREFIX = /^((khong phai|khong|sai roi|nham roi)\s*)?((sua lai|sua|nhan lai|doi thanh)(\s+(la|thanh))?\s*)?(?=\S|$)/;
const REPEAT = /(doc lai|nhac lai|nghe lai|noi lai|lap lai)/;

function matchPrefixWords(t: string, re: RegExp): number {
  const m = t.match(re);
  const s = m ? m[0].trim() : '';
  return s ? s.split(' ').length : 0;
}

const FEATURE_WORDS: Record<string, string> = {
  chat: 'chat', 'tin nhan': 'chat', 'tro chuyen': 'chat',
  ocr: 'ocr', 'so lieu': 'ocr', 'doc so lieu': 'ocr',
  'huyet ap': 'bp', home: 'home', 'trang chu': 'home',
};
export function featureOf(s: string): string {
  const n = norm(s);
  if (FEATURE_WORDS[n]) return FEATURE_WORDS[n];
  for (const [k, v] of Object.entries(FEATURE_WORDS)) if (n.includes(k)) return v;
  return '';
}

/** Lệnh ngắn, rõ ràng không cần gọi LLM (tiết kiệm tiền + giảm độ trễ). */
function fastIntent(t: string): { intent: string; feature?: string } | null {
  if (/^(ve )?(trang chu|man hinh chinh)$/.test(t) || /^ve trang chu/.test(t)) return { intent: 'go_home' };
  if (/^(quay lai|tro lai|lui lai)( a| nhe)?$/.test(t)) return { intent: 'go_back' };
  if (/(xem|mo).*(lich su|bieu do).*(huyet ap)/.test(t) || /^(xem|mo) huyet ap$/.test(t)) return { intent: 'show_bp' };
  if (/(huyet ap).*(bao nhieu|gan nhat|hom nay|vua do)/.test(t) || /(doc|cho biet).*(huyet ap)/.test(t)) return { intent: 'read_bp' };
  if (/\b(do|chup|doc)\b.*\b(huyet ap|may do)\b/.test(t) || /^do huyet ap/.test(t)) return { intent: 'measure_bp' };
  if (/^(mo|vao|xem) (tin nhan|chat|tro chuyen)( a| nhe)?$/.test(t)) return { intent: 'open_feature', feature: 'chat' };
  if (/^(mo|vao|chup|quet) (ocr|doc so lieu|so lieu)( a| nhe)?$/.test(t)) return { intent: 'open_feature', feature: 'ocr' };
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
  measure_bp: [], show_bp: [], read_bp: [], go_back: [], go_home: [], help: [], chitchat: [],
};
const NEEDS_CONFIRM = new Set(['send_message']);
export const INTENT_LIST = [...Object.keys(REQUIRED), 'unsupported'];

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
  // 2) hủy
  if (CANCEL.test(t)) return mk({ action: 'cancel', say: S.cancelled() });
  if (REPEAT.test(t) && t.split(' ').length <= 4) return mk({ action: 'repeat', say: '' });

  let task: Task | null = state.task ? { intent: state.task.intent, slots: { ...state.task.slots } } : null;
  let learnAlias: Decision['learnAlias'];
  let aliasPhrase = state.aliasPhrase ?? null;

  // 3) đang chờ xác nhận
  if (expects === 'yes_no' && task) {
    if (YES.test(t) && !input.lowConfidence) {
      return mk({ action: 'execute', intent: task.intent, task, say: S.sentOk() });
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
      return mk({ action: 'cancel', say: S.cancelled() });
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

  // 7) lệnh mới: luật nhanh → LLM
  const fast = fastIntent(t);
  let nluOut: NluResult | null = null;
  if (fast) {
    nluOut = { intent: fast.intent, recipient: '', content: '', feature: fast.feature ?? '', say: '' };
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
    const f = featureOf(nluOut.feature || '');
    if (f) task.slots.feature = f;
  }
  return progress(task, ui, hon, contacts, null, undefined);
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
    return mk({ action: 'ask', intent, task, pending: 'content', expects: 'free_text', say: S.askContent(hon), expectsReply: true, aliasPhrase, learnAlias });
  }
  if (need.includes('feature') && !task.slots.feature) {
    return mk({ action: 'ask', intent, task, pending: 'feature', expects: 'command', say: S.askFeatureMissing(hon), expectsReply: true, chips: ['Tin nhắn', 'Huyết áp', 'Đọc số liệu'] });
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
  const say = intent === 'read_bp' ? '' : S.opened();
  return mk({ action: 'execute', intent, task, say, learnAlias });
}
