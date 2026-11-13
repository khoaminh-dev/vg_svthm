// Truy cập PostgREST của Supabase bằng service role (chỉ dùng phía server).
function conf() {
  const base = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!base || !key) throw new Error('service_key_missing');
  const headers: Record<string, string> = { apikey: key, 'Content-Type': 'application/json' };
  // Key mới `sb_secret_...` không phải JWT: chỉ gửi qua `apikey`.
  if (!key.startsWith('sb_')) headers.Authorization = `Bearer ${key}`;
  return { base, headers };
}

export async function dbSelect<T>(path: string): Promise<T> {
  const { base, headers } = conf();
  const r = await fetch(`${base}/rest/v1/${path}`, { headers });
  if (!r.ok) throw new Error(`db_${r.status}`);
  return (await r.json()) as T;
}

export async function dbInsert(table: string, row: unknown, prefer = 'return=minimal'): Promise<void> {
  const { base, headers } = conf();
  const r = await fetch(`${base}/rest/v1/${table}`, {
    method: 'POST',
    headers: { ...headers, Prefer: prefer },
    body: JSON.stringify(row),
  });
  if (!r.ok) throw new Error(`db_${r.status}`);
}

export async function dbPatch(table: string, filter: string, patch: unknown): Promise<void> {
  const { base, headers } = conf();
  const r = await fetch(`${base}/rest/v1/${table}?${filter}`, {
    method: 'PATCH',
    headers: { ...headers, Prefer: 'return=minimal' },
    body: JSON.stringify(patch),
  });
  if (!r.ok) throw new Error(`db_${r.status}`);
}

export async function dbDelete(table: string, filter: string): Promise<void> {
  const { base, headers } = conf();
  const r = await fetch(`${base}/rest/v1/${table}?${filter}`, { method: 'DELETE', headers });
  if (!r.ok) throw new Error(`db_${r.status}`);
}

export async function dbRpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { base, headers } = conf();
  const r = await fetch(`${base}/rest/v1/rpc/${fn}`, { method: 'POST', headers, body: JSON.stringify(args) });
  if (!r.ok) throw new Error(`db_${r.status}`);
  return (await r.json()) as T;
}

/** Tải một object trong Storage (service role). Trả null nếu không có. */
export async function storageGet(bucket: string, path: string): Promise<Buffer | null> {
  const { base, headers } = conf();
  const r = await fetch(`${base}/storage/v1/object/${bucket}/${path}`, { headers });
  if (r.status === 404 || r.status === 400) return null;
  if (!r.ok) throw new Error(`storage_${r.status}`);
  return Buffer.from(await r.arrayBuffer());
}

/** Xóa nhiều file trong một bucket (file không tồn tại thì bỏ qua). */
export async function storageRemove(bucket: string, paths: string[]): Promise<void> {
  if (!paths.length) return;
  const { base, headers } = conf();
  const r = await fetch(`${base}/storage/v1/object/${bucket}`, {
    method: 'DELETE',
    headers,
    body: JSON.stringify({ prefixes: paths }),
  });
  if (!r.ok) throw new Error(`storage_${r.status}`);
}

export async function storagePut(bucket: string, path: string, body: Buffer, contentType: string): Promise<void> {
  const { base, headers } = conf();
  const h = { ...headers, 'Content-Type': contentType, 'x-upsert': 'true' };
  const r = await fetch(`${base}/storage/v1/object/${bucket}/${path}`, { method: 'POST', headers: h, body: new Uint8Array(body) });
  if (!r.ok) throw new Error(`storage_${r.status}`);
}
