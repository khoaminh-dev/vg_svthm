import type { VercelResponse } from '../vercel-types.js';
import { dbSelect } from '../db.js';
import { allow } from '../auth.js';
import { AllKeysFailed, UpstreamError, parseRetryAfter } from '../router.js';
import { redact } from '../secretbox.js';
import { getPolicy } from './gate.js';
import { timedFetch, withKeys } from './keys.js';
import { buildLiveSession, liveAllowed, pickMode, safetyId, validSdp } from './live.js';

// Xử lý `mode: "live_start"` của /api/voice/turn (Đợt A): đổi SDP offer của app lấy SDP answer của OpenAI.
// Khoá OpenAI lấy từ kho khoá (admin thêm, mã hoá trong DB; hoặc biến môi trường), xoay vòng và tự nghỉ khi lỗi.
// Không bao giờ trả nội dung lỗi của OpenAI cho app (có thể chứa một phần khoá).

const CACHE_MS = 20_000;
let usersCache: { at: number; ids: Set<string> } | null = null;

export function invalidateLiveUsers() {
  usersCache = null;
}

async function isLiveUser(uid: string): Promise<boolean> {
  if (liveAllowed(uid)) return true; // dự phòng qua biến môi trường
  if (!usersCache || Date.now() - usersCache.at > CACHE_MS) {
    try {
      const rows = await dbSelect<{ user_id: string }[]>('live_users?select=user_id&limit=500');
      usersCache = { at: Date.now(), ids: new Set(rows.map((r) => r.user_id)) };
    } catch {
      return usersCache?.ids.has(uid) ?? false;
    }
  }
  return usersCache.ids.has(uid);
}

type LiveReply = { session?: { id?: string }; transport?: { sdp?: string } };

export async function startLive(res: VercelResponse, uid: string, body: Record<string, unknown>) {
  const pol = await getPolicy();
  if (!pol.live_enabled) return res.status(503).json({ error: 'live_disabled' }); // công tắc tắt khẩn cấp
  if (!(await isLiveUser(uid))) return res.status(403).json({ error: 'live_not_allowed' });
  if (!validSdp(body.sdp)) return res.status(400).json({ error: 'bad_sdp' });
  // Mỗi phiên mở là tốn tiền (tính cả 15 giây khởi tạo): chặn mở dồn dập, kể cả do lỗi lặp trong app.
  if (!(await allow(`live_start:m:${uid}`, 6, 300)) || !(await allow(`live_start:d:${uid}`, 60, 86_400))) {
    return res.status(429).json({ error: 'live_rate' });
  }

  const mode = pickMode(body.live_mode);
  const hon = typeof body.honorific === 'string' ? body.honorific.slice(0, 10) : '';
  const t0 = Date.now();
  try {
    const { value, failovers } = await withKeys<LiveReply>('openai', async (key) => {
      const r = await timedFetch('https://api.openai.com/v1/live/sessions', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${key}`,
          'Content-Type': 'application/json',
          'OpenAI-Safety-Identifier': safetyId(uid),
        },
        body: JSON.stringify({ session: buildLiveSession(mode, hon), transport: { type: 'webrtc', sdp: body.sdp } }),
      }, 12_000);
      if (!r.ok) {
        const text = redact((await r.text().catch(() => '')).slice(0, 300));
        throw new UpstreamError(r.status, parseRetryAfter(r.headers.get('retry-after')), text);
      }
      return (await r.json()) as LiveReply;
    });
    if (!value.session?.id || !value.transport?.sdp) return res.status(502).json({ error: 'live_bad_response' });
    return res.status(201).json({ session_id: value.session.id, sdp: value.transport.sdp, mode, server_ms: Date.now() - t0, failovers });
  } catch (e) {
    if (e instanceof AllKeysFailed) {
      const none = /^no_openai_key/.test(e.message);
      console.error('live_start keys', none ? 'none' : 'all_failed');
      return res.status(503).json({ error: none ? 'live_not_configured' : 'live_keys_failed' });
    }
    if (e instanceof UpstreamError) {
      console.error('live_start upstream', e.status, redact(e.message).slice(0, 200)); // chỉ log trên server
      return res.status(e.status === 429 ? 429 : 502).json({ error: e.status === 429 ? 'live_busy' : 'live_upstream', status: e.status });
    }
    console.error('live_start error', redact((e as Error).message ?? ''));
    return res.status(502).json({ error: 'live_unreachable' });
  }
}
