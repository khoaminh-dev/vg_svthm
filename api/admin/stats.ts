import type { VercelRequest, VercelResponse } from '@vercel/node';
import { dbGet, requireAdmin } from '../_lib/admin.js';

type Ev = { user_id: string; name: string; screen: string | null; props: Record<string, unknown>; created_at: string };
type Prof = { id: string; username: string | null; display_name: string | null; created_at: string; last_seen_at: string | null };

const DAY = 86_400_000;

function top(map: Map<string, number>, n = 20) {
  return [...map.entries()].sort((a, b) => b[1] - a[1]).slice(0, n).map(([key, count]) => ({ key, count }));
}
function inc(map: Map<string, number>, k: string) {
  map.set(k, (map.get(k) ?? 0) + 1);
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (!requireAdmin(req, res)) return;
  const days = Math.min(Math.max(Number(req.query.days) || 14, 1), 90);
  const since = new Date(Date.now() - days * DAY).toISOString();
  try {
    const [events, profiles] = await Promise.all([
      dbGet<Ev[]>(`events?select=user_id,name,screen,props,created_at&created_at=gte.${since}&order=created_at.desc&limit=20000`),
      dbGet<Prof[]>('profiles?select=id,username,display_name,created_at,last_seen_at&order=created_at.desc&limit=1000'),
    ]);
    const who = new Map(profiles.map((p) => [p.id, p.username ? `@${p.username}` : (p.display_name ?? p.id.slice(0, 8))]));

    const byName = new Map<string, number>();
    const byScreen = new Map<string, number>();
    const byDay = new Map<string, number>();
    const byUser = new Map<string, number>();
    const byFeature = new Map<string, number>();
    const u24 = new Set<string>();
    const u7 = new Set<string>();
    const now = Date.now();
    let e24 = 0;

    for (const e of events) {
      const t = Date.parse(e.created_at);
      inc(byName, e.name);
      if (e.name === 'screen_view' && e.screen) inc(byScreen, e.screen);
      if (e.name === 'tap_feature') inc(byFeature, String(e.props?.feature ?? '?'));
      inc(byDay, e.created_at.slice(0, 10));
      inc(byUser, who.get(e.user_id) ?? e.user_id.slice(0, 8));
      if (now - t < DAY) { e24++; u24.add(e.user_id); }
      if (now - t < 7 * DAY) u7.add(e.user_id);
    }

    const daily: { day: string; count: number }[] = [];
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(now - i * DAY).toISOString().slice(0, 10);
      daily.push({ day: d, count: byDay.get(d) ?? 0 });
    }

    res.status(200).json({
      days,
      totals: {
        users: profiles.length,
        events: events.length,
        events24h: e24,
        activeUsers24h: u24.size,
        activeUsers7d: u7.size,
      },
      byName: top(byName, 30),
      byScreen: top(byScreen),
      byFeature: top(byFeature),
      topUsers: top(byUser, 10),
      daily,
      recent: events.slice(0, 50).map((e) => ({
        at: e.created_at, user: who.get(e.user_id) ?? e.user_id.slice(0, 8), name: e.name, screen: e.screen, props: e.props,
      })),
      users: profiles.map((p) => ({
        username: p.username, name: p.display_name, joined: p.created_at, lastSeen: p.last_seen_at,
      })),
    });
  } catch (e) {
    const m = e instanceof Error ? e.message : 'error';
    res.status(m === 'service_key_missing' ? 500 : 502).json({ error: m });
  }
}
