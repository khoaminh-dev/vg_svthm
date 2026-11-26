import test from 'node:test';
import assert from 'node:assert/strict';

process.env.SUPABASE_URL = 'https://example.supabase.co';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'sb_secret_test';
const KEY = 'demo-key-0123456789-abcdefghij';
process.env.ALERT_API_KEY = KEY;

const { keyOk, keyFrom, parseAlert } = await import('../_lib/alert.ts');
const handler = (await import('../alert/trigger.ts')).default;

test('keyOk: đúng khoá, sai khoá, thiếu khoá, khoá ngắn', () => {
  assert.equal(keyOk(KEY, KEY), true);
  assert.equal(keyOk('khac-khac-khac-khac-khac-khac', KEY), false);
  assert.equal(keyOk(undefined, KEY), false);
  assert.equal(keyOk(KEY, undefined), false);
  assert.equal(keyOk('ngan', 'ngan'), false, 'khoá dưới 24 ký tự không bao giờ hợp lệ');
});

test('keyOk: nhiều khoá cách nhau dấu phẩy (xoay khoá)', () => {
  const two = `${KEY}, second-key-0123456789-abcdefgh`;
  assert.equal(keyOk('second-key-0123456789-abcdefgh', two), true);
  assert.equal(keyOk(KEY, two), true);
});

test('keyFrom: x-alert-key hoặc Bearer', () => {
  assert.equal(keyFrom({ 'x-alert-key': ' abc ' }), 'abc');
  assert.equal(keyFrom({ authorization: 'Bearer xyz' }), 'xyz');
  assert.equal(keyFrom({ authorization: 'Basic xyz' }), undefined);
  assert.equal(keyFrom({}), undefined);
});

test('parseAlert: mặc định hợp lý và tự sinh event_id', () => {
  const r = parseAlert({});
  assert.ok(r.ok);
  if (!r.ok) return;
  assert.equal(r.v.kind, 'danger');
  assert.equal(r.v.source, 'api');
  assert.match(r.v.eventId, /^auto-/);
  assert.equal(r.v.labels, null);
  assert.equal(r.v.dry, false);
});

test('parseAlert: nội dung đầy đủ, rút gọn khoảng trắng và cắt độ dài', () => {
  const r = parseAlert({
    event_id: 'cam1-2026-11-26T10:00:00',
    source: 'roi_monitor',
    kind: 'fall',
    message: '  Phát   hiện   ngã  '.padEnd(500, 'x'),
    camera: 'Phòng ngủ',
    targets: ['me', 'me', 'ba-noi'],
    dry_run: true,
  });
  assert.ok(r.ok);
  if (!r.ok) return;
  assert.equal(r.v.message.length, 200);
  assert.ok(r.v.message.startsWith('Phát hiện ngã'));
  assert.deepEqual(r.v.labels, ['me', 'ba-noi']);
  assert.equal(r.v.dry, true);
  assert.equal(r.v.camera, 'Phòng ngủ');
});

test('parseAlert: các trường sai đều bị từ chối bằng mã rõ ràng', () => {
  const bad = (b: unknown, error: string) => {
    const r = parseAlert(b as Record<string, unknown> | null);
    assert.equal(r.ok, false);
    if (!r.ok) assert.equal(r.error, error);
  };
  bad(null, 'bad_json');
  bad({ kind: 'bom' }, 'bad_kind');
  bad({ kind: 5 }, 'bad_kind');
  bad({ source: 'Có Dấu' }, 'bad_source');
  bad({ event_id: 'x' }, 'bad_event_id');
  bad({ event_id: 'co khoang trang' }, 'bad_event_id');
  bad({ message: 123 }, 'bad_message');
  bad({ camera: {} }, 'bad_camera');
  bad({ targets: 'me' }, 'bad_targets');
  bad({ targets: [] }, 'bad_targets');
  bad({ targets: ['ME'] }, 'bad_targets');
  bad({ targets: ["a'; drop"] }, 'bad_targets');
  bad({ targets: Array.from({ length: 11 }, (_, i) => `t${i}x`) }, 'bad_targets');
  bad({ dry_run: 'yes' }, 'bad_dry_run');
});

// ---------- handler ----------

type Res = { code: number; body: unknown; headers: Record<string, string> };
function run(opts: { method?: string; key?: string; body?: unknown }): Promise<Res> {
  return new Promise((resolve) => {
    const out: Res = { code: 0, body: null, headers: {} };
    const res: any = {
      status(c: number) { out.code = c; return res; },
      json(b: unknown) { out.body = b; resolve(out); return res; },
      setHeader(k: string, v: string) { out.headers[k] = v; return res; },
    };
    const req: any = {
      method: opts.method ?? 'POST',
      headers: opts.key ? { 'x-alert-key': opts.key } : {},
      body: opts.body ?? {},
    };
    void handler(req, res);
  });
}

function stubRpc(reply: unknown, status = 200) {
  const calls: { url: string; body: any }[] = [];
  const real = globalThis.fetch;
  globalThis.fetch = (async (url: string, init: any) => {
    calls.push({ url, body: JSON.parse(init.body) });
    return new Response(JSON.stringify(reply), { status, headers: { 'Content-Type': 'application/json' } });
  }) as typeof fetch;
  return { calls, restore: () => { globalThis.fetch = real; } };
}

test('handler: sai phương thức / thiếu khoá / sai khoá', async () => {
  assert.equal((await run({ method: 'GET', key: KEY })).code, 405);
  assert.equal((await run({})).code, 401);
  assert.equal((await run({ key: 'sai-sai-sai-sai-sai-sai-sai' })).code, 401);
});

test('handler: chưa cấu hình ALERT_API_KEY thì tắt hẳn (503), kể cả khi có gửi khoá', async () => {
  const saved = process.env.ALERT_API_KEY;
  delete process.env.ALERT_API_KEY;
  try {
    assert.equal((await run({ key: KEY })).code, 503);
  } finally {
    process.env.ALERT_API_KEY = saved;
  }
});

test('handler: nội dung sai → 400, không gọi cơ sở dữ liệu', async () => {
  const s = stubRpc({});
  try {
    const r = await run({ key: KEY, body: { kind: 'bom' } });
    assert.equal(r.code, 400);
    assert.deepEqual(r.body, { error: 'bad_kind' });
    assert.equal(s.calls.length, 0);
  } finally {
    s.restore();
  }
});

test('handler: gửi thành công, truyền đúng tham số vào demo_alert_fire', async () => {
  const s = stubRpc({ ok: true, id: 'abc', recipients: 2, labels: ['me', 'mom'] });
  try {
    const r = await run({ key: KEY, body: { event_id: 'evt-000001', kind: 'fall', message: 'Ngã', camera: 'P1', source: 'roi_monitor' } });
    assert.equal(r.code, 200);
    assert.equal((r.body as any).recipients, 2);
    assert.equal((r.body as any).event_id, 'evt-000001');
    assert.equal(r.headers['Cache-Control'], 'no-store');
    assert.equal(s.calls.length, 1);
    assert.ok(s.calls[0].url.endsWith('/rest/v1/rpc/demo_alert_fire'));
    assert.deepEqual(s.calls[0].body, {
      p_event_id: 'evt-000001', p_source: 'roi_monitor', p_kind: 'fall', p_message: 'Ngã', p_camera: 'P1', p_labels: null, p_dry: false,
    });
  } finally {
    s.restore();
  }
});

test('handler: dry_run chỉ báo sẽ gửi cho ai', async () => {
  const s = stubRpc({ ok: true, dry: true, recipients: 1, labels: ['me'] });
  try {
    const r = await run({ key: KEY, body: { dry_run: true } });
    assert.equal(r.code, 200);
    assert.equal(s.calls[0].body.p_dry, true);
  } finally {
    s.restore();
  }
});

test('handler: không có tài khoản hợp lệ → 404; bắn dồn → 429; lỗi máy chủ dữ liệu → 502', async () => {
  let s = stubRpc({ ok: false, error: 'no_target', recipients: 0 });
  try { assert.equal((await run({ key: KEY, body: { targets: ['la-nao'] } })).code, 404); } finally { s.restore(); }
  s = stubRpc({ ok: false, error: 'cooldown', retry_after: 10 });
  try { assert.equal((await run({ key: KEY })).code, 429); } finally { s.restore(); }
  s = stubRpc({ message: 'boom' }, 500);
  try {
    const r = await run({ key: KEY });
    assert.equal(r.code, 502);
    assert.deepEqual(r.body, { error: 'upstream' });
  } finally { s.restore(); }
});

test('handler: gọi lại cùng event_id trả duplicate, không báo lỗi', async () => {
  const s = stubRpc({ ok: true, duplicate: true, recipients: 0 });
  try {
    const r = await run({ key: KEY, body: { event_id: 'evt-000001' } });
    assert.equal(r.code, 200);
    assert.equal((r.body as any).duplicate, true);
  } finally {
    s.restore();
  }
});

// ---------- /api/alert/status ----------

const statusHandler = (await import('../alert/status.ts')).default;
function runStatus(opts: { method?: string; key?: string; query?: Record<string, string> }): Promise<Res> {
  return new Promise((resolve) => {
    const out: Res = { code: 0, body: null, headers: {} };
    const res: any = {
      status(c: number) { out.code = c; return res; },
      json(b: unknown) { out.body = b; resolve(out); return res; },
      setHeader(k: string, v: string) { out.headers[k] = v; return res; },
    };
    void statusHandler({ method: opts.method ?? 'GET', headers: opts.key ? { 'x-alert-key': opts.key } : {}, query: opts.query ?? {} } as any, res);
  });
}

test('eventIdOf: chỉ nhận event_id hợp lệ', async () => {
  const { eventIdOf } = await import('../_lib/alert.ts');
  assert.equal(eventIdOf('roi-12345'), 'roi-12345');
  assert.equal(eventIdOf(['roi-12345', 'x']), 'roi-12345');
  assert.equal(eventIdOf('x'), null);
  assert.equal(eventIdOf("a b c d e f"), null);
  assert.equal(eventIdOf(undefined), null);
});

test('status: phương thức, khoá, event_id', async () => {
  assert.equal((await runStatus({ method: 'POST', key: KEY })).code, 405);
  assert.equal((await runStatus({ query: { event_id: 'roi-12345' } })).code, 401);
  assert.equal((await runStatus({ key: KEY })).code, 400);
  assert.equal((await runStatus({ key: KEY, query: { event_id: "x'; drop" } })).code, 400);
});

test('status: chờ nhận, đã nhận, không thấy, lỗi dữ liệu', async () => {
  let s = stubRpc({ ok: true, event_id: 'roi-12345', state: 'pending', acked: false, recipients: 2 });
  try {
    const r = await runStatus({ key: KEY, query: { event_id: 'roi-12345' } });
    assert.equal(r.code, 200);
    assert.equal((r.body as any).acked, false);
    assert.deepEqual(s.calls[0].body, { p_event_id: 'roi-12345' });
    assert.ok(s.calls[0].url.endsWith('/rest/v1/rpc/demo_alert_status'));
  } finally { s.restore(); }
  s = stubRpc({ ok: true, state: 'acked', acked: true, acked_by: 'me' });
  try { assert.equal(((await runStatus({ key: KEY, query: { event_id: 'roi-12345' } })).body as any).state, 'acked'); } finally { s.restore(); }
  s = stubRpc({ ok: false, error: 'not_found' });
  try { assert.equal((await runStatus({ key: KEY, query: { event_id: 'roi-12345' } })).code, 404); } finally { s.restore(); }
  s = stubRpc({}, 500);
  try { assert.equal((await runStatus({ key: KEY, query: { event_id: 'roi-12345' } })).code, 502); } finally { s.restore(); }
});
