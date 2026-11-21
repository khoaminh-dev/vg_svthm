import type { VercelRequest, VercelResponse } from './vercel-types.js';
import { requireFreshAdmin } from './admin.js';
import { dbInsert, dbPatch, dbSelect } from './db.js';
import { audit } from './audit.js';
import { newExpiry, parsePlan, validUuid } from './plans.js';
import { invalidateLiveUsers } from './voice/live_start.js';

// Quản lý gói Vy Live: các gói đang bán, đơn chờ xác nhận thanh toán, cấp tay, hướng dẫn thanh toán.
// Xác nhận thanh toán và sửa gói là thao tác nhạy cảm: cần đăng nhập admin mới (≤ 15 phút).

type Sub = {
  id: string; payer_id: string; plan_id: string | null; plan_name: string; price_vnd: number; days: number; order_code: string;
  status: string; admin_note: string; created_at: string; confirmed_at: string | null; expires_at: string | null;
};
type Named = { id: string; username: string | null; display_name: string | null };

const labelOf = (n: Named | undefined, id: string) => (n?.username ? `@${n.username}` : n?.display_name ?? id.slice(0, 8));

export async function plansOverview() {
  const plans = await dbSelect<Record<string, unknown>[]>('plans?select=*&order=sort.asc,price_vnd.asc');
  const subs = await dbSelect<Sub[]>('subscriptions?select=*&order=created_at.desc&limit=100');
  const note = await dbSelect<{ pay_note: string }[]>('plan_settings?select=pay_note&id=eq.1');
  const ids = [...new Set(subs.map((s) => s.payer_id))];
  const names = ids.length ? await dbSelect<Named[]>(`profiles?select=id,username,display_name&id=in.(${ids.join(',')})`) : [];
  const now = Date.now();
  return {
    plans,
    payNote: note[0]?.pay_note ?? '',
    subs: subs.map((s) => ({
      id: s.id, who: labelOf(names.find((x) => x.id === s.payer_id), s.payer_id), plan: s.plan_name, price: s.price_vnd, days: s.days,
      code: s.order_code, status: s.status === 'active' && s.expires_at && Date.parse(s.expires_at) <= now ? 'expired' : s.status,
      createdAt: s.created_at, confirmedAt: s.confirmed_at, expiresAt: s.expires_at, note: s.admin_note,
    })),
  };
}

async function payerExpiry(payer: string): Promise<Date | null> {
  const rows = await dbSelect<{ expires_at: string | null }[]>(
    `subscriptions?select=expires_at&payer_id=eq.${payer}&status=eq.active&order=expires_at.desc&limit=1`,
  );
  return rows[0]?.expires_at ? new Date(rows[0].expires_at) : null;
}

export const PLAN_ACTIONS = ['confirm_sub', 'cancel_sub', 'grant_sub', 'save_plan', 'set_pay_note'];

/** Xử lý một thao tác gói do settings.ts chuyển tới (đã qua requireAdmin). Mọi thao tác ở đây đều nhạy cảm. */
export async function handlePlanAction(req: VercelRequest, res: VercelResponse, b: Record<string, unknown>, action: string): Promise<unknown> {
  try {
    if (!requireFreshAdmin(req, res)) return;

    if (action === 'confirm_sub') {
      const id = b.id;
      if (!validUuid(id)) return res.status(400).json({ error: 'bad_id' });
      const rows = await dbSelect<Sub[]>(`subscriptions?select=*&id=eq.${id}`);
      const s = rows[0];
      if (!s) return res.status(404).json({ error: 'not_found' });
      if (s.status !== 'pending') return res.status(409).json({ error: 'not_pending' });
      const now = new Date();
      const exp = newExpiry(now, s.days, await payerExpiry(s.payer_id));
      await dbPatch('subscriptions', `id=eq.${id}&status=eq.pending`, {
        status: 'active', confirmed_at: now.toISOString(), expires_at: exp.toISOString(),
        admin_note: String(b.note ?? '').trim().slice(0, 200),
      });
      invalidateLiveUsers();
      await audit(req, 'sub_confirm', s.order_code, { plan: s.plan_name, days: s.days, price: s.price_vnd, until: exp.toISOString() });
      return res.status(200).json({ ok: true, ...(await plansOverview()) });
    }

    if (action === 'cancel_sub') {
      const id = b.id;
      if (!validUuid(id)) return res.status(400).json({ error: 'bad_id' });
      const rows = await dbSelect<Sub[]>(`subscriptions?select=*&id=eq.${id}`);
      const s = rows[0];
      if (!s) return res.status(404).json({ error: 'not_found' });
      if (s.status !== 'pending' && s.status !== 'active') return res.status(409).json({ error: 'not_open' });
      await dbPatch('subscriptions', `id=eq.${id}`, { status: 'cancelled', admin_note: String(b.note ?? '').trim().slice(0, 200) });
      invalidateLiveUsers();
      await audit(req, 'sub_cancel', s.order_code, { was: s.status });
      return res.status(200).json({ ok: true, ...(await plansOverview()) });
    }

    if (action === 'grant_sub') {
      // Cấp gói tay (tặng, đền bù, người thử): tạo đơn đã xác nhận ngay.
      const username = String(b.username ?? '').trim().replace(/^@/, '').toLowerCase();
      if (!/^[a-z0-9_.]{2,30}$/.test(username)) return res.status(400).json({ error: 'bad_username' });
      const days = Number(b.days);
      if (!Number.isInteger(days) || days < 1 || days > 3660) return res.status(400).json({ error: 'bad_value', field: 'days' });
      const found = await dbSelect<{ id: string }[]>(`profiles?select=id&username=eq.${encodeURIComponent(username)}`);
      if (!found[0]) return res.status(404).json({ error: 'user_not_found' });
      const now = new Date();
      const exp = newExpiry(now, days, await payerExpiry(found[0].id));
      const code = 'VGT' + Math.random().toString(36).slice(2, 8).toUpperCase();
      await dbInsert('subscriptions', {
        payer_id: found[0].id, plan_name: 'Cấp tay', price_vnd: 0, days, order_code: code, status: 'active',
        confirmed_at: now.toISOString(), expires_at: exp.toISOString(), admin_note: String(b.note ?? '').trim().slice(0, 200),
      });
      invalidateLiveUsers();
      await audit(req, 'sub_grant', `@${username}`, { days, until: exp.toISOString() });
      return res.status(200).json({ ok: true, ...(await plansOverview()) });
    }

    if (action === 'save_plan') {
      const p = parsePlan(b);
      if (!p.ok) return res.status(400).json({ error: 'bad_value', field: p.field });
      if (b.id === undefined || b.id === null || b.id === '') {
        await dbInsert('plans', p.plan);
        await audit(req, 'plan_add', p.plan.name, { price: p.plan.price_vnd, days: p.plan.days, active: p.plan.active });
      } else {
        if (!validUuid(b.id)) return res.status(400).json({ error: 'bad_id' });
        await dbPatch('plans', `id=eq.${b.id}`, p.plan);
        await audit(req, 'plan_edit', p.plan.name, { price: p.plan.price_vnd, days: p.plan.days, active: p.plan.active });
      }
      return res.status(200).json({ ok: true, ...(await plansOverview()) });
    }

    if (action === 'set_pay_note') {
      const t = String(b.pay_note ?? '').trim();
      if (t.length < 1 || t.length > 600) return res.status(400).json({ error: 'bad_value', field: 'pay_note' });
      await dbPatch('plan_settings', 'id=eq.1', { pay_note: t });
      await audit(req, 'pay_note_set');
      return res.status(200).json({ ok: true, ...(await plansOverview()) });
    }

    res.status(400).json({ error: 'bad_action' });
    return;
  } catch (e) {
    const m = e instanceof Error ? e.message : 'error';
    return res.status(m === 'service_key_missing' ? 500 : 502).json({ error: m });
  }
}
