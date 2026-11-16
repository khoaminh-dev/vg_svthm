// Gửi thông báo đẩy (FCM HTTP v1). Được gọi từ trigger trong cơ sở dữ liệu (xem migration 0019), không gọi từ app.
// Bí mật: FCM_SERVICE_ACCOUNT_B64 (khoá tài khoản dịch vụ Firebase, base64) và PUSH_SECRET (khớp với Vault).

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const PUSH_SECRET = Deno.env.get('PUSH_SECRET') ?? '';
const SA = JSON.parse(atob(Deno.env.get('FCM_SERVICE_ACCOUNT_B64') ?? 'e30=')) as {
  project_id?: string;
  client_email?: string;
  private_key?: string;
};

const CHANNEL = 'viegrand_default';

function dbHeaders(): Record<string, string> {
  const h: Record<string, string> = { apikey: SERVICE_KEY, 'Content-Type': 'application/json' };
  if (!SERVICE_KEY.startsWith('sb_')) h.Authorization = `Bearer ${SERVICE_KEY}`;
  return h;
}

async function select<T>(path: string): Promise<T> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers: dbHeaders() });
  if (!r.ok) throw new Error(`db_${r.status}`);
  return (await r.json()) as T;
}

async function deleteTokens(tokens: string[]) {
  if (!tokens.length) return;
  const list = tokens.map((t) => `"${t}"`).join(',');
  await fetch(`${SUPABASE_URL}/rest/v1/device_tokens?token=in.(${encodeURIComponent(list)})`, {
    method: 'DELETE',
    headers: dbHeaders(),
  });
}

// ---------- OAuth2 từ khoá tài khoản dịch vụ ----------

function b64url(buf: ArrayBuffer | string): string {
  const bytes = typeof buf === 'string' ? new TextEncoder().encode(buf) : new Uint8Array(buf);
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

let cached: { token: string; exp: number } | null = null;

async function accessToken(): Promise<string> {
  if (cached && cached.exp > Date.now() + 60_000) return cached.token;
  const now = Math.floor(Date.now() / 1000);
  const head = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(
    JSON.stringify({
      iss: SA.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );
  const pem = (SA.private_key ?? '').replace(/-----[A-Z ]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${head}.${claim}`));
  const jwt = `${head}.${claim}.${b64url(sig)}`;
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }),
  });
  if (!r.ok) throw new Error(`oauth_${r.status}`);
  const j = (await r.json()) as { access_token: string; expires_in: number };
  cached = { token: j.access_token, exp: Date.now() + j.expires_in * 1000 };
  return cached.token;
}

type Msg = { title: string; body: string; data: Record<string, string> };

/** Gửi một thông báo; trả về true nếu mã thiết bị đã hết hiệu lực (cần xoá). */
async function sendOne(token: string, access: string, m: Msg): Promise<boolean> {
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${SA.project_id}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: {
        token,
        notification: { title: m.title, body: m.body },
        data: m.data,
        android: { priority: 'HIGH', notification: { channel_id: CHANNEL, sound: 'default' } },
      },
    }),
  });
  if (r.ok) return false;
  const t = await r.text();
  return r.status === 404 || t.includes('UNREGISTERED') || t.includes('INVALID_ARGUMENT');
}

async function sendAll(targets: { token: string; msg: Msg }[]) {
  if (!targets.length) return { sent: 0, removed: 0 };
  const access = await accessToken();
  const dead: string[] = [];
  let sent = 0;
  const queue = [...targets];
  const worker = async () => {
    for (let t = queue.shift(); t; t = queue.shift()) {
      try {
        if (await sendOne(t.token, access, t.msg)) dead.push(t.token);
        else sent++;
      } catch {
        // bỏ qua lỗi mạng của một thiết bị
      }
    }
  };
  await Promise.all(Array.from({ length: 8 }, worker));
  await deleteTokens(dead);
  return { sent, removed: dead.length };
}

type Prefs = {
  user_id: string;
  messages: boolean;
  updates: boolean;
  show_text: boolean;
  family_alerts?: boolean;
  dose_alerts?: boolean;
  digest?: boolean;
  quiet_start?: string | null;
  quiet_end?: string | null;
};

async function prefsFor(userIds: string[]): Promise<Map<string, Prefs>> {
  const m = new Map<string, Prefs>();
  if (!userIds.length) return m;
  const rows = await select<Prefs[]>(`push_prefs?user_id=in.(${userIds.join(',')})&select=user_id,messages,updates,show_text,family_alerts,dose_alerts,digest,quiet_start,quiet_end`);
  for (const p of rows) m.set(p.user_id, p);
  return m;
}

async function handleMessage(b: Record<string, unknown>) {
  const roomId = String(b.room_id ?? '');
  const senderId = String(b.sender_id ?? '');
  if (!roomId || !senderId) return { skipped: 'bad_request' };

  const [members, room, sender] = await Promise.all([
    select<{ user_id: string }[]>(`room_members?room_id=eq.${roomId}&select=user_id`),
    select<{ name: string; type: string }[]>(`rooms?id=eq.${roomId}&select=name,type&limit=1`),
    select<{ display_name: string | null; username: string | null }[]>(`profiles?id=eq.${senderId}&select=display_name,username&limit=1`),
  ]);
  const others = members.map((m) => m.user_id).filter((id) => id !== senderId);
  if (!others.length) return { sent: 0 };

  const [tokens, prefs] = await Promise.all([
    select<{ token: string; user_id: string }[]>(`device_tokens?user_id=in.(${others.join(',')})&select=token,user_id`),
    prefsFor(others),
  ]);

  const who = sender[0]?.display_name?.trim() || sender[0]?.username || 'Người thân';
  const isGroup = room[0]?.type !== 'direct';
  const title = isGroup ? `${who} · ${room[0]?.name ?? 'Phòng chat'}` : who;
  const hasImage = b.has_image === true;
  const text = String(b.content ?? '').trim();

  const targets: { token: string; msg: Msg }[] = [];
  for (const t of tokens) {
    const p = prefs.get(t.user_id);
    if (p && !p.messages) continue;
    const body = p?.show_text && (text || hasImage)
      ? (hasImage && !text ? 'Đã gửi một ảnh' : text.slice(0, 120))
      : hasImage ? 'Đã gửi một ảnh' : 'Có tin nhắn mới';
    targets.push({ token: t.token, msg: { title, body, data: { type: 'message', room_id: roomId } } });
  }
  return sendAll(targets);
}

async function handleUpdate(b: Record<string, unknown>) {
  const name = String(b.name ?? '');
  const tokens = await select<{ token: string; user_id: string }[]>('device_tokens?select=token,user_id&limit=5000');
  const ids = [...new Set(tokens.map((t) => t.user_id))];
  const prefs = new Map<string, Prefs>();
  for (let i = 0; i < ids.length; i += 100) {
    for (const [k, v] of await prefsFor(ids.slice(i, i + 100))) prefs.set(k, v);
  }
  const targets = tokens
    .filter((t) => prefs.get(t.user_id)?.updates !== false)
    .map((t) => ({
      token: t.token,
      msg: { title: 'Viegrand có bản mới', body: name ? `Bản ${name} đã sẵn sàng. Bấm để cập nhật.` : 'Bấm để cập nhật.', data: { type: 'update' } },
    }));
  return sendAll(targets);
}

type Prof = { id: string; display_name: string | null; username: string | null };

async function nameOf(id: string): Promise<string> {
  const r = await select<Prof[]>(`profiles?id=eq.${id}&select=id,display_name,username&limit=1`);
  return r[0]?.display_name?.trim() || r[0]?.username || 'Người thân';
}

async function tokensOf(userIds: string[]) {
  if (!userIds.length) return [] as { token: string; user_id: string }[];
  return select<{ token: string; user_id: string }[]>(`device_tokens?user_id=in.(${userIds.join(',')})&select=token,user_id`);
}

// Huyết áp từ 180/120: báo mọi người chăm sóc đang hoạt động và có quyền nhận cảnh báo.
async function handleBpAlert(b: Record<string, unknown>) {
  const owner = String(b.owner_id ?? '');
  if (!owner) return { skipped: 'bad_request' };
  const links = await select<{ carer_id: string; perms: Record<string, boolean> }[]>(
    `family_links?owner_id=eq.${owner}&status=eq.active&select=carer_id,perms`,
  );
  const carers = links.filter((l) => l.perms?.alerts === true).map((l) => l.carer_id);
  if (!carers.length) return { sent: 0 };
  const [name, tokens, prefs] = await Promise.all([nameOf(owner), tokensOf(carers), prefsFor(carers)]);
  const sys = Number(b.systolic ?? 0);
  const dia = Number(b.diastolic ?? 0);
  const targets = tokens
    .filter((t) => prefs.get(t.user_id)?.family_alerts !== false)
    .map((t) => ({
      token: t.token,
      msg: {
        title: `Huyết áp của ${name} rất cao`,
        body: `${sys}/${dia} mmHg. Bấm để xem và gọi ngay.`,
        data: { type: 'family_alert', owner_id: owner },
      },
    }));
  return sendAll(targets);
}

async function handleLink(b: Record<string, unknown>) {
  const owner = String(b.owner_id ?? '');
  const carer = String(b.carer_id ?? '');
  if (!owner || !carer) return { skipped: 'bad_request' };
  const ev = String(b.event ?? '');
  const [ownerName, carerName] = await Promise.all([nameOf(owner), nameOf(carer)]);
  if (ev === 'joined') {
    const tokens = await tokensOf([owner]);
    return sendAll(tokens.map((t) => ({
      token: t.token,
      msg: { title: 'Có người theo dõi sức khoẻ của bác', body: `${carerName} vừa được xem số liệu sức khoẻ của bác. Bác gỡ được trong Hồ sơ.`, data: { type: 'family_link' } },
    })));
  }
  if (ev === 'revoked') {
    const byOwner = b.by_owner === true;
    const tokens = await tokensOf([byOwner ? carer : owner]);
    const body = byOwner ? `${ownerName} đã ngừng chia sẻ số liệu sức khoẻ với bạn.` : `${carerName} đã ngừng theo dõi bác.`;
    return sendAll(tokens.map((t) => ({ token: t.token, msg: { title: 'Liên kết gia đình đã thay đổi', body, data: { type: 'family_link' } } })));
  }
  return { skipped: 'event' };
}

async function handleNudge(b: Record<string, unknown>) {
  const owner = String(b.owner_id ?? '');
  const carer = String(b.carer_id ?? '');
  if (!owner || !carer) return { skipped: 'bad_request' };
  const [carerName, tokens] = await Promise.all([nameOf(carer), tokensOf([owner])]);
  return sendAll(tokens.map((t) => ({
    token: t.token,
    msg: { title: `${carerName} nhờ bác đo huyết áp`, body: 'Bác bấm vào đây để chụp máy đo huyết áp nhé.', data: { type: 'nudge' } },
  })));
}

async function handleMedsChanged(b: Record<string, unknown>) {
  const owner = String(b.owner_id ?? '');
  const carer = String(b.carer_id ?? '');
  if (!owner || !carer) return { skipped: 'bad_request' };
  const [carerName, tokens] = await Promise.all([nameOf(carer), tokensOf([owner])]);
  return sendAll(tokens.map((t) => ({
    token: t.token,
    msg: { title: `${carerName} vừa đổi lịch uống thuốc của bác`, body: 'Bác mở Viegrand để xem lịch mới nhé.', data: { type: 'meds' } },
  })));
}

// ---------- Giai đoạn 4: lưới an toàn, SOS, tóm tắt, nhắc hẹn ----------

/** Giờ yên tĩnh của người nhận (theo múi giờ của họ). Chỉ áp cho thông báo thường, KHÔNG áp cho SOS và huyết áp rất cao. */
function inQuiet(p: Prefs | undefined, tz: string | undefined, now = new Date()): boolean {
  if (!p?.quiet_start || !p?.quiet_end) return false;
  let hm: string;
  try {
    hm = new Intl.DateTimeFormat('en-GB', { timeZone: tz || 'Asia/Ho_Chi_Minh', hour: '2-digit', minute: '2-digit', hour12: false }).format(now);
  } catch {
    return false;
  }
  const cur = hm.slice(0, 5);
  const a = p.quiet_start.slice(0, 5);
  const b = p.quiet_end.slice(0, 5);
  if (a === b) return false;
  return a < b ? cur >= a && cur < b : cur >= a || cur < b; // qua nửa đêm: 22:00-06:00
}

async function tzOf(userIds: string[]): Promise<Map<string, string>> {
  const m = new Map<string, string>();
  if (!userIds.length) return m;
  const rows = await select<{ id: string; timezone: string | null }[]>(`profiles?id=in.(${userIds.join(',')})&select=id,timezone`);
  for (const r of rows) if (r.timezone) m.set(r.id, r.timezone);
  return m;
}

/** Con đang liên kết với `owner` và có đủ các quyền trong `perms`. */
async function carersOf(owner: string, perms: string[]): Promise<string[]> {
  const links = await select<{ carer_id: string; perms: Record<string, boolean> }[]>(
    `family_links?owner_id=eq.${owner}&status=eq.active&select=carer_id,perms`,
  );
  return links.filter((l) => perms.every((k) => l.perms?.[k] === true)).map((l) => l.carer_id);
}

const hhmm = (iso: string, tz: string) => {
  try {
    return new Intl.DateTimeFormat('en-GB', { timeZone: tz, hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date(iso));
  } catch {
    return '';
  }
};

type DoseRef = { label: string; at: string };
const dosesOf = (b: Record<string, unknown>): DoseRef[] =>
  (Array.isArray(b.doses) ? b.doses : [])
    .map((d) => ({ label: String((d as DoseRef).label ?? ''), at: String((d as DoseRef).at ?? '') }))
    .filter((d) => d.label);

// Quá 15 phút chưa uống: nhắc lại cho chính cha mẹ. Không bao giờ nói "uống bù".
async function handleDoseNudge(b: Record<string, unknown>) {
  const owner = String(b.owner_id ?? '');
  const doses = dosesOf(b);
  if (!owner || !doses.length) return { skipped: 'bad_request' };
  const tokens = await tokensOf([owner]);
  const bags = doses.map((d) => `túi ${d.label}`).join(', ');
  return sendAll(tokens.map((t) => ({
    token: t.token,
    msg: { title: 'Đã quá giờ uống thuốc', body: `Bác chưa bấm "Đã uống" cho ${bags}. Bác uống rồi thì bấm xác nhận nhé.`, data: { type: 'meds' } },
  })));
}

// Quá 45 phút: báo con có quyền alerts + meds_view, tôn trọng "báo khi quên thuốc" và giờ yên tĩnh.
async function handleDoseMissed(b: Record<string, unknown>) {
  const owner = String(b.owner_id ?? '');
  const doses = dosesOf(b);
  if (!owner || !doses.length) return { skipped: 'bad_request' };
  const carers = await carersOf(owner, ['alerts', 'meds_view']);
  if (!carers.length) return { sent: 0 };
  const [name, tokens, prefs, tz, ownerTz] = await Promise.all([nameOf(owner), tokensOf(carers), prefsFor(carers), tzOf(carers), tzOf([owner])]);
  const oz = ownerTz.get(owner) ?? 'Asia/Ho_Chi_Minh';
  const what = doses.map((d) => `túi ${d.label}${d.at ? ` (${hhmm(d.at, oz)})` : ''}`).join(', ');
  return sendAll(
    tokens
      .filter((t) => prefs.get(t.user_id)?.dose_alerts !== false && !inQuiet(prefs.get(t.user_id), tz.get(t.user_id)))
      .map((t) => ({
        token: t.token,
        msg: { title: `${name} chưa uống thuốc`, body: `${what} vẫn chưa uống sau 45 phút. Bấm để xem và gọi.`, data: { type: 'family_alert', owner_id: owner } },
      })),
  );
}

// SOS: mọi con có alerts, bất kể tuỳ chọn thông báo hay giờ yên tĩnh.
async function handleSos(b: Record<string, unknown>) {
  const owner = String(b.owner_id ?? '');
  const sosId = String(b.sos_id ?? '');
  if (!owner || !sosId) return { skipped: 'bad_request' };
  const carers = await carersOf(owner, ['alerts']);
  if (!carers.length) return { sent: 0 };
  const [name, tokens] = await Promise.all([nameOf(owner), tokensOf(carers)]);
  return sendAll(tokens.map((t) => ({
    token: t.token,
    msg: { title: `SOS: ${name} cần giúp`, body: `${name} vừa bấm nút SOS. Bấm để xem và gọi ngay.`, data: { type: 'sos', sos_id: sosId, owner_id: owner } },
  })));
}

async function handleSosAck(b: Record<string, unknown>) {
  const owner = String(b.owner_id ?? '');
  const sosId = String(b.sos_id ?? '');
  if (!owner || !sosId) return { skipped: 'bad_request' };
  const carers = await carersOf(owner, ['alerts']);
  const ownerName = await nameOf(owner);
  const data = { type: 'sos', sos_id: sosId, owner_id: owner };
  if (b.event === 'cancelled') {
    const tokens = await tokensOf(carers);
    return sendAll(tokens.map((t) => ({
      token: t.token,
      msg: { title: `${ownerName} đã huỷ SOS`, body: 'Bấm nhầm hoặc đã ổn. Bạn vẫn có thể gọi hỏi thăm.', data },
    })));
  }
  const carer = String(b.carer_id ?? '');
  if (!carer) return { skipped: 'bad_request' };
  const carerName = await nameOf(carer);
  const others = carers.filter((c) => c !== carer);
  const [carerTokens, ownerTokens] = await Promise.all([tokensOf(others), tokensOf([owner])]);
  return sendAll([
    ...carerTokens.map((t) => ({
      token: t.token,
      msg: { title: `${carerName} đã nhận SOS của ${ownerName}`, body: 'Đã có người nhận, bạn không cần gọi trùng.', data },
    })),
    ...ownerTokens.map((t) => ({
      token: t.token,
      msg: { title: `${carerName} đã nhận được tin của bác`, body: `${carerName} sẽ liên lạc với bác ngay.`, data },
    })),
  ]);
}

// Tóm tắt cuối ngày: chỉ con đã bật, không gửi trong giờ yên tĩnh.
async function handleDigest(b: Record<string, unknown>) {
  const owner = String(b.owner_id ?? '');
  const text = String(b.text ?? '');
  if (!owner || !text) return { skipped: 'bad_request' };
  const carers = await carersOf(owner, ['alerts']);
  if (!carers.length) return { sent: 0 };
  const [name, tokens, prefs, tz] = await Promise.all([nameOf(owner), tokensOf(carers), prefsFor(carers), tzOf(carers)]);
  return sendAll(
    tokens
      .filter((t) => prefs.get(t.user_id)?.digest === true && !inQuiet(prefs.get(t.user_id), tz.get(t.user_id)))
      .map((t) => ({ token: t.token, msg: { title: `${name} hôm nay`, body: text, data: { type: 'family_alert', owner_id: owner } } })),
  );
}

// Sắp hết túi / sắp tái khám: cho cha mẹ và con có meds_view.
async function handleMedReminder(b: Record<string, unknown>) {
  const owner = String(b.owner_id ?? '');
  if (!owner) return { skipped: 'bad_request' };
  const title = String(b.title ?? 'đơn thuốc');
  const recheck = b.kind === 'recheck';
  const carers = await carersOf(owner, ['meds_view']);
  const [name, ownerTokens, carerTokens, prefs, tz] = await Promise.all([nameOf(owner), tokensOf([owner]), tokensOf(carers), prefsFor(carers), tzOf(carers)]);
  const ownerMsg: Msg = recheck
    ? { title: 'Sắp đến ngày tái khám', body: `Còn 2 ngày nữa là đến hẹn tái khám (${title}). Bác nhớ đi khám nhé.`, data: { type: 'meds' } }
    : { title: 'Sắp hết thuốc', body: `${title}: còn 3 túi nữa là hết. Bác nhờ con hoặc đến nhà thuốc lấy thêm nhé.`, data: { type: 'meds' } };
  const carerMsg: Msg = recheck
    ? { title: `${name} sắp đến ngày tái khám`, body: `Còn 2 ngày nữa (${title}).`, data: { type: 'family_alert', owner_id: owner } }
    : { title: `${name} sắp hết thuốc`, body: `${title}: còn 3 túi.`, data: { type: 'family_alert', owner_id: owner } };
  return sendAll([
    ...ownerTokens.map((t) => ({ token: t.token, msg: ownerMsg })),
    ...carerTokens
      .filter((t) => prefs.get(t.user_id)?.dose_alerts !== false && !inQuiet(prefs.get(t.user_id), tz.get(t.user_id)))
      .map((t) => ({ token: t.token, msg: carerMsg })),
  ]);
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method', { status: 405 });
  if (!PUSH_SECRET || req.headers.get('x-push-secret') !== PUSH_SECRET) return new Response('unauthorized', { status: 401 });
  try {
    const b = (await req.json()) as Record<string, unknown>;
    const out =
      b.type === 'update' ? await handleUpdate(b)
      : b.type === 'message' ? await handleMessage(b)
      : b.type === 'bp_alert' ? await handleBpAlert(b)
      : b.type === 'family_link' ? await handleLink(b)
      : b.type === 'nudge' ? await handleNudge(b)
      : b.type === 'meds_changed' ? await handleMedsChanged(b)
      : b.type === 'dose_nudge' ? await handleDoseNudge(b)
      : b.type === 'dose_missed' ? await handleDoseMissed(b)
      : b.type === 'sos' ? await handleSos(b)
      : b.type === 'sos_ack' ? await handleSosAck(b)
      : b.type === 'digest' ? await handleDigest(b)
      : b.type === 'med_reminder' ? await handleMedReminder(b)
      : { skipped: 'type' };
    return new Response(JSON.stringify(out), { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: String((e as Error).message) }), { status: 500 });
  }
});
