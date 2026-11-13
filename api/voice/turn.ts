import type { VercelRequest, VercelResponse } from '../_lib/vercel-types.js';
import { requireUser, rateLimit } from '../_lib/auth.js';
import { bodyObject } from '../_lib/http.js';
import { dbInsert } from '../_lib/db.js';
import { deepseekChat, elevenScribe, groqJsonChat, groqWhisper, type Msg, type SttResult } from '../_lib/voice/providers.js';
import { INTENT_LIST, honorificOf, norm, step, type Contact, type DState, type Nlu, type NluResult, type Ui } from '../_lib/voice/dm.js';
import { getPolicy } from '../_lib/voice/gate.js';
import { isReliable } from '../_lib/voice/stt_guard.js';

const MAX_AUDIO_B64 = 4_000_000; // ~3MB, dưới giới hạn body của Vercel
const MAX_TEXT = 500;

function str(v: unknown, max: number): string {
  return typeof v === 'string' ? v.slice(0, max) : '';
}

function parseUi(v: unknown): Ui {
  const o = (v && typeof v === 'object' ? v : {}) as Record<string, unknown>;
  const contacts: Contact[] = [];
  if (Array.isArray(o.contacts)) {
    for (const c of o.contacts.slice(0, 60)) {
      if (!c || typeof c !== 'object') continue;
      const r = c as Record<string, unknown>;
      const id = str(r.id, 80);
      const name = str(r.name, 60);
      if (!id || !name) continue;
      contacts.push({
        id, name,
        kind: r.kind === 'group' ? 'group' : 'direct',
        username: str(r.username, 40) || undefined,
        aliases: Array.isArray(r.aliases) ? r.aliases.slice(0, 8).map((a) => str(a, 40)).filter(Boolean) : [],
      });
    }
  }
  return {
    screen: str(o.screen, 40),
    roomId: str(o.room_id, 80) || null,
    contacts,
    honorific: honorificOf(str(o.honorific, 10)),
  };
}

function parseState(v: unknown): DState {
  const o = (v && typeof v === 'object' ? v : {}) as Record<string, unknown>;
  const task = o.task && typeof o.task === 'object' ? (o.task as Record<string, unknown>) : null;
  const slots: Record<string, string> = {};
  if (task?.slots && typeof task.slots === 'object') {
    for (const [k, val] of Object.entries(task.slots as Record<string, unknown>)) {
      if (typeof val === 'string' && k.length <= 30) slots[k] = val.slice(0, 500);
    }
  }
  const intent = task ? str(task.intent, 30) : '';
  const expects = str(o.expects, 12);
  const valid = ['command', 'free_text', 'yes_no', 'choice', 'name', 'none'];
  const choices = Array.isArray(o.choices)
    ? o.choices.slice(0, 5).map((c) => {
        const r = (c ?? {}) as Record<string, unknown>;
        return { id: str(r.id, 80), name: str(r.name, 60) };
      }).filter((c) => c.id && c.name)
    : [];
  return {
    task: intent && INTENT_LIST.includes(intent) ? { intent, slots } : null,
    pending: str(o.pending, 20) || null,
    expects: (valid.includes(expects) ? expects : 'command') as DState['expects'],
    choices,
    aliasPhrase: str(o.alias_phrase, 40) || null,
  };
}

const SYSTEM = `Bạn là bộ hiểu lệnh tiếng Việt cho ứng dụng chăm sóc người cao tuổi. Chỉ trả về JSON:
{"intent": "...", "recipient": "", "content": "", "feature": "", "say": ""}
intent là một trong: send_message (nhắn tin cho ai đó), open_chat (mở khung chat với ai đó), open_feature (mở tính năng: chat | ocr | bp | home), measure_bp (đo/chụp huyết áp), show_bp (xem lịch sử/biểu đồ huyết áp), read_bp (đọc kết quả huyết áp gần nhất), go_back, go_home, help (hỏi làm được gì), chitchat (chào hỏi/hỏi thăm ngắn), unsupported (ngoài khả năng).
- recipient: đúng cụm người nhận như người dùng nói (vd "con trai", "bà Lan"), để trống nếu không nói.
- content: nội dung tin nhắn nếu người dùng đã nói sẵn, KHÔNG gồm phần "nhắn cho ai". Giữ nguyên lời, không bịa.
- feature: chat | ocr | bp | home khi intent là open_feature.
- say: chỉ với chitchat, một câu trả lời rất ngắn, lễ phép. Không đưa lời khuyên y tế.
Không bịa người nhận hay nội dung. Nếu không chắc, chọn unsupported.`;

function parseNlu(text: string): NluResult {
  const o = JSON.parse(text) as Record<string, unknown>;
  return {
    intent: str(o.intent, 30),
    recipient: str(o.recipient, 40),
    content: str(o.content, 500),
    feature: str(o.feature, 20),
    say: str(o.say, 200),
  };
}

type Meter = { nluProvider?: string; failovers: number; ms: number; tokensIn?: number; tokensOut?: number };

function makeNlu(model: string, meter: Meter): Nlu {
  return async (text, ctx) => {
    const messages: Msg[] = [
      { role: 'system', content: SYSTEM },
      { role: 'user', content: `Màn hình hiện tại: ${ctx.ui.screen || 'không rõ'}\nCâu nói: ${text}` },
    ];
    const t0 = Date.now();
    // Groq trước (nhanh), DeepSeek dự phòng. Không dùng Gemini.
    const chain = [
      () => groqJsonChat(messages),
      () => deepseekChat(messages, model),
    ];
    let last: unknown;
    for (const run of chain) {
      try {
        const r = await run();
        const out = parseNlu(r.text);
        meter.nluProvider = r.provider;
        meter.failovers += r.failovers;
        meter.tokensIn = r.tokensIn;
        meter.tokensOut = r.tokensOut;
        meter.ms = Date.now() - t0;
        return out;
      } catch (e) {
        meter.failovers++;
        last = e;
      }
    }
    meter.ms = Date.now() - t0;
    throw last;
  };
}

async function transcribe(audio: Buffer, mime: string, hint: string): Promise<SttResult> {
  try {
    const r = await groqWhisper(audio, mime, hint);
    return r;
  } catch (e1) {
    try {
      const r = await elevenScribe(audio, mime);
      return { ...r, failovers: r.failovers + 1 };
    } catch (e2) {
      throw e2 ?? e1;
    }
  }
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') return res.status(405).end();
  const uid = await requireUser(req, res);
  if (!uid) return;
  const pol = await getPolicy();
  if (!pol.voice_enabled) return res.status(503).json({ error: 'voice_disabled' });
  if (!(await rateLimit(uid, 'voice', pol.turns_per_min, pol.turns_per_day))) return res.status(429).json({ error: 'rate_limited' });

  const body = bodyObject(req);
  if (!body) return res.status(400).json({ error: 'bad_request' });
  const sessionId = str(body.session_id, 60) || 'na';
  const turnNo = Number.isFinite(Number(body.turn_no)) ? Math.max(0, Math.min(9999, Number(body.turn_no))) : 0;
  const ui = parseUi(body.ui);
  const state = parseState(body.state);
  const input = (body.input && typeof body.input === 'object' ? body.input : {}) as Record<string, unknown>;

  const t0 = Date.now();
  const meter: Meter = { failovers: 0, ms: 0 };
  let text = '';
  let stt: { provider: string; confidence?: number; ms: number } | null = null;
  let sttFail = 0;
  let audioMs = 0;
  let outcome = 'ok';
  let lowQuality = false;
  let error: string | undefined;

  try {
    if (typeof input.audio_b64 === 'string' && input.audio_b64) {
      if (input.audio_b64.length > MAX_AUDIO_B64) return res.status(413).json({ error: 'audio_too_large' });
      const audio = Buffer.from(input.audio_b64, 'base64');
      audioMs = Math.max(0, Math.min(60_000, Number(input.duration_ms) || 0));
      const hint = (ui.contacts ?? []).slice(0, 12).map((c) => c.name).join(', ');
      const s0 = Date.now();
      try {
        const r = await transcribe(audio, str(input.mime, 40) || 'audio/mp4', hint);
        text = r.text;
        sttFail = r.failovers;
        stt = { provider: r.provider, confidence: r.confidence, ms: Date.now() - s0 };
        // Nghe không rõ hoặc chữ "bịa" từ tiếng ồn: coi như không nghe thấy để Vy hỏi lại, không hành động.
        if (!isReliable(text, r.confidence)) {
          text = '';
          lowQuality = true;
        }
      } catch (e) {
        outcome = 'error';
        error = `stt:${(e as Error).message}`.slice(0, 120);
      }
    } else {
      text = str(input.text, MAX_TEXT);
    }

    let decision;
    if (outcome === 'error') {
      decision = await step({ text: '', state, ui }, async () => { throw new Error('x'); });
      decision = { ...decision, say: `Con đang nghe chưa được, ${honorificOf(ui.honorific)} thử lại giúp con nhé.`, sayClass: 'other' as const };
    } else {
      if (!norm(text)) outcome = lowQuality ? 'low_confidence' : 'no_speech';
      const model = pol.deepseek_model || 'deepseek-flash';
      decision = await step({ text, state, ui, lowConfidence: (stt?.confidence ?? 1) < 0.45 }, makeNlu(model, meter));
      if (decision.intent === 'error') { outcome = 'error'; error = 'nlu'; }
    }

    // Học bí danh ("con trai" = người này) — ghi phía server cho chắc.
    if (decision.learnAlias && /^[a-z0-9 ]{1,40}$/.test(decision.learnAlias.alias)) {
      try {
        await dbInsert('voice_aliases', { user_id: uid, alias_norm: decision.learnAlias.alias, contact_id: decision.learnAlias.contactId }, 'resolution=merge-duplicates,return=minimal');
      } catch {
        // bỏ qua
      }
    }

    const total = Date.now() - t0;
    void dbInsert('voice_turns', {
      user_id: uid, session_id: sessionId, turn_no: turnNo, intent: decision.intent, action: decision.action, outcome,
      stt_provider: stt?.provider ?? null, nlu_provider: meter.nluProvider ?? null,
      stt_ms: stt?.ms ?? null, nlu_ms: meter.ms || null, total_ms: total, audio_ms: audioMs || null,
      tokens_in: meter.tokensIn ?? null, tokens_out: meter.tokensOut ?? null, stt_conf: stt?.confidence ?? null,
      fallbacks: meter.failovers + sttFail, error: error ?? null,
    }).catch(() => undefined);

    return res.status(200).json({
      transcript: text,
      stt,
      decision: {
        action: decision.action,
        intent: decision.intent,
        task: decision.task,
        pending: decision.pending,
        expects: decision.expects,
        choices: decision.choices,
        say: decision.say,
        say_class: decision.sayClass,
        expects_reply: decision.expectsReply,
        chips: decision.chips,
        alias_phrase: decision.aliasPhrase,
      },
      meta: { total_ms: total, nlu: meter.nluProvider ?? null },
    });
  } catch (e) {
    return res.status(502).json({ error: 'voice_failed', detail: (e as Error).message?.slice(0, 80) });
  }
}
