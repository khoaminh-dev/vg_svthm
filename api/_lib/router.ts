import { KeyPool } from './keypool.js';

export class UpstreamError extends Error {
  constructor(public status: number, public retryAfterMs?: number, message?: string) {
    super(message ?? `Upstream error ${status}`);
  }
}

export class AllKeysFailed extends Error {
  constructor(msg = 'Tất cả key đều đang lỗi hoặc hết quota') {
    super(msg);
  }
}

/** Thử lần lượt các key trong pool cho tới khi một key thành công. */
export async function withKeyFailover<T>(
  pool: KeyPool,
  call: (key: string) => Promise<T>,
): Promise<T> {
  for (let i = 0; i < pool.size; i++) {
    const k = pool.next();
    if (!k) break;
    try {
      return await call(k.key);
    } catch (e) {
      if (!(e instanceof UpstreamError)) throw e;
      if (e.status === 401 || e.status === 403) pool.cooldown(k, 60 * 60_000);
      else if (e.status === 429) pool.cooldown(k, e.retryAfterMs ?? 60_000);
      else if (e.status >= 500) pool.cooldown(k, 30_000);
      else throw e; // lỗi 4xx khác là lỗi của request, không đổi key
    }
  }
  throw new AllKeysFailed();
}

/** Thử lần lượt các nhà cung cấp (mỗi nhà cung cấp đã có failover key riêng). */
export async function withProviderFallback<T>(
  providers: Array<() => Promise<T>>,
): Promise<T> {
  let last: unknown;
  for (const p of providers) {
    try {
      return await p();
    } catch (e) {
      last = e;
      if (!(e instanceof AllKeysFailed) && !(e instanceof UpstreamError)) throw e;
    }
  }
  throw last ?? new AllKeysFailed();
}

export function parseRetryAfter(h: string | null): number | undefined {
  if (!h) return undefined;
  const s = Number(h);
  return Number.isFinite(s) ? s * 1000 : undefined;
}
