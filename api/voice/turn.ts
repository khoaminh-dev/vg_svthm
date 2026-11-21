import type { VercelRequest, VercelResponse } from '../_lib/vercel-types.js';
import { requireUser, rateLimitParallel } from '../_lib/auth.js';
import { bodyObject } from '../_lib/http.js';
import { dbInsert } from '../_lib/db.js';
import { deepseekChat, elevenScribe, groqJsonChat, groqWhisper, type Msg, type SttResult } from '../_lib/voice/providers.js';
import { INTENT_LIST, UI_INTENTS, honorificOf, norm, step, type Contact, type DState, type Nlu, type NluResult, type Refine, type Ui } from '../_lib/voice/dm.js';
import { REFINE_SYSTEM, acceptRefined, ensureEnd, finishMessage } from '../_lib/voice/msg_refine.js';
import { parseUiContext } from '../_lib/voice/ui_cmd.js';
import { failCode } from '../_lib/voice/llm_body.js';
import { getPolicy } from '../_lib/voice/gate.js';
import { isReliable } from '../_lib/voice/stt_guard.js';
import { answerHealth } from '../_lib/voice/health_voice.js';
import { topicOf } from '../_lib/voice/health_say.js';
import { startLive } from '../_lib/voice/live_start.js';

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
    context: parseUiContext(o.context),
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
    task: intent && (INTENT_LIST.includes(intent) || UI_INTENTS.includes(intent)) ? { intent, slots } : null,
    pending: str(o.pending, 20) || null,
    expects: (valid.includes(expects) ? expects : 'command') as DState['expects'],
    choices,
    aliasPhrase: str(o.alias_phrase, 40) || null,
  };
}

const SYSTEM = `Bạn là bộ hiểu lệnh tiếng Việt cho ứng dụng chăm sóc người cao tuổi. Chỉ trả về JSON:
{"intent": "...", "recipient": "", "content": "", "feature": "", "say": ""}
intent là một trong: send_message (nhắn tin cho ai đó), open_chat (mở khung chat với ai đó), open_feature (mở tính năng: chat | ocr | bp | fun | home; fun là mục Giải trí/YouTube), measure_bp (đo/chụp huyết áp), show_bp (xem lịch sử/biểu đồ huyết áp), read_bp (đọc kết quả huyết áp gần nhất), record_bp (người dùng đọc số huyết áp vừa đo để ghi lại, ví dụ "huyết áp 130 trên 80 mạch 72"; content là "tâm thu,tâm trương,mạch"), read_messages (đọc tin nhắn mới, có tin nhắn không), call_contact (gọi điện cho ai đó; recipient là người cần gọi, hoặc 115), read_meds (hỏi lịch uống thuốc: hôm nay/tối nay uống thuốc gì, cữ thuốc kế tiếp, mấy giờ uống thuốc; KHÔNG dùng khi người dùng nói đã uống rồi), health_status (hỏi về tình trạng sức khoẻ, xu hướng huyết áp, nguy cơ của chính mình, hoặc hỏi y khoa chung; content là một trong general, trend, risk, habit, other), play_video (xem/nghe video, bài hát, nhạc trên YouTube; từ khoá tìm đặt vào content), video_control (điều khiển video đang phát: content là một trong pause, play, next, previous, louder, quieter), go_back, go_home, help (hỏi làm được gì), chitchat (chào hỏi/hỏi thăm ngắn), unsupported (ngoài khả năng).
- recipient: đúng cụm người nhận như người dùng nói (vd "con trai", "bà Lan"), để trống nếu không nói.
- content: nội dung tin nhắn nếu người dùng đã nói sẵn, KHÔNG gồm phần "nhắn cho ai". Giữ nguyên lời, không bịa.
- feature: chat | ocr | bp | fun | home khi intent là open_feature.
- content với health_status: general (tình trạng chung) | trend (dạo này, tuần này) | risk (nguy cơ, có nguy hiểm không) | habit (đo mấy lần) | other (triệu chứng, ăn uống, thuốc).
- content với play_video: chỉ từ khoá cần tìm (tên bài, ca sĩ, chủ đề), bỏ chữ "mở/cho nghe/xem".
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

type Meter = { nluProvider?: string; failovers: number; ms: number; tokensIn?: number; tokensOut?: number; nluFail?: string; refineMs?: number; refine?: 'ai' | 'rule' };

function makeNlu(model: string, meter: Meter): Nlu {
  return async (text, ctx) => {
    const messages: Msg[] = [
      { role: 'system', content: SYSTEM },
      { role: 'user', content: `Màn hình hiện tại: ${ctx.ui.screen || 'không rõ'}\nCâu nói: ${text}` },
    ];
    const t0 = Date.now();
    // Groq trước (nhanh), DeepSeek dự phòng. Không dùng Gemini.
    // Groq hạn 3,5 giây (p95 bình thường < 1 giây): treo thì sang DeepSeek sớm thay vì chờ 8 giây.
    const chain: [string, () => Promise<{ text: string; provider: string; failovers: number; tokensIn?: number; tokensOut?: number }>][] = [
      ['groq', () => groqJsonChat(messages, 300, 3500)],
      ['deepseek', () => deepseekChat(messages, model, 300, 8000)],
    ];
    let last: unknown;
    for (const [pname, run] of chain) {
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
        meter.nluFail = meter.nluFail ? `${meter.nluFail},${failCode(pname, e)}` : failCode(pname, e);
        last = e;
      }
    }
    meter.ms = Date.now() - t0;
    throw last;
  };
}

/** Chuẩn hoá tin nhắn bằng Groq (hạn 1,8 giây). Chỉ nhận kết quả khi qua kiểm tra luật; không thì dùng bản gọt bằng luật. */
function makeRefine(meter: Meter): Refine {
  return async ({ content, recipient, verb }) => {
    const rule = finishMessage(content, recipient, verb === 'hoi' ? 'hoi' : undefined);
    const t0 = Date.now();
    try {
      const messages: Msg[] = [
        { role: 'system', content: REFINE_SYSTEM },
        { role: 'user', content: JSON.stringify({ 'nội dung': content, 'người nhận': recipient, 'động từ': verb === 'hoi' ? 'hỏi' : verb === 'bao' ? 'bảo' : verb === 'noi' ? 'nói' : '' }) },
      ];
      const r = await groqJsonChat(messages, 250, 1800, process.env.GROQ_REFINE_MODEL);
      const out = str((JSON.parse(r.text) as Record<string, unknown>).text, 500).trim();
      meter.refineMs = Date.now() - t0;
      if (out && acceptRefined(content, out, recipient)) {
        meter.refine = 'ai';
        return ensureEnd(out);
      }
    } catch {
      // Groq lỗi/quá hạn: dùng bản luật
    }
    meter.refineMs = Date.now() - t0;
    meter.refine = 'rule';
    return rule;
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
  const tStart = Date.now();
  // Xác thực và đọc chính sách độc lập nhau → chạy song song (trước đây nối đuôi nhau).
  const [uid, pol] = await Promise.all([requireUser(req, res), getPolicy()]);
  if (!uid) return;
  const authMs = Date.now() - tStart;
  if (!pol.voice_enabled) return res.status(503).json({ error: 'voice_disabled' });
  // Thử nghiệm Vy Live (chỉ tài khoản được phép): tạo phiên GPT-Live, không đi qua luồng Vy thường.
  const early = bodyObject(req);
  if (early?.mode === 'live_start') return startLive(res, uid, early);
  const r0 = Date.now();
  if (!(await rateLimitParallel(uid, 'voice', pol.turns_per_min, pol.turns_per_day))) return res.status(429).json({ error: 'rate_limited' });
  const rlMs = Date.now() - r0;

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
  let healthMs = 0;
  let stepMs = 0;

  try {
    if (typeof input.audio_b64 === 'string' && input.audio_b64) {
      if (input.audio_b64.length > MAX_AUDIO_B64) return res.status(413).json({ error: 'audio_too_large' });
      const audio = Buffer.from(input.audio_b64, 'base64');
      audioMs = Math.max(0, Math.min(60_000, Number(input.duration_ms) || 0));
      // Gợi ý cho nhận dạng: từ khoá lệnh + tên trong danh bạ (tên riêng và từ như "nhắn", "huyết áp" hay bị nghe nhầm).
      const hint = ['Vy', 'nhắn tin', 'huyết áp', ...(ui.contacts ?? []).slice(0, 12).map((c) => c.name)].join(', ');
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
      const d0 = Date.now();
      decision = await step({ text, state, ui, lowConfidence: (stt?.confidence ?? 1) < 0.45 }, makeNlu(model, meter), makeRefine(meter));
      stepMs = Date.now() - d0;
      if (decision.intent === 'error') { outcome = 'error'; error = 'nlu'; }
      // Câu hỏi về sức khoẻ: server tự đọc số liệu của người dùng rồi dựng câu từ khuôn, không qua mô hình.
      if (decision.intent === 'health_status' && decision.action === 'execute') {
        const hon = honorificOf(ui.honorific);
        const h0 = Date.now();
        try {
          const h = await answerHealth(uid, topicOf(decision.task?.slots.content), hon, text);
          decision = { ...decision, action: 'answer', say: h.say, sayClass: h.sayClass, task: null, expects: 'none', expectsReply: false, chips: [] };
          healthMs = Date.now() - h0;
        } catch (e) {
          console.error(e);
          decision = { ...decision, action: 'answer', say: `Con đang trục trặc một chút, ${hon} thử lại sau nhé.`, sayClass: 'other', task: null, expects: 'none', expectsReply: false, chips: [] };
          outcome = 'error';
          error = 'health';
        }
      }
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
    // Số đo từng khâu (ms) — chỉ số, không chứa lời người dùng. App chép vào props sự kiện voice_turn.
    const timings = {
      auth_ms: authMs, rate_ms: rlMs, stt_ms: stt?.ms ?? 0, nlu_ms: meter.ms, dm_ms: Math.max(0, stepMs - meter.ms - healthMs - (meter.refineMs ?? 0)), refine_ms: meter.refineMs ?? 0, refine: meter.refine ?? '',
      health_ms: healthMs, server_ms: Date.now() - tStart, fast: meter.nluProvider ? 0 : 1, nlu_fail: meter.nluFail ?? '',
    };
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
      meta: { total_ms: total, nlu: meter.nluProvider ?? null, timings },
    });
  } catch (e) {
    return res.status(502).json({ error: 'voice_failed', detail: (e as Error).message?.slice(0, 80) });
  }
}
