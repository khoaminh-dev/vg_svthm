import type { VercelRequest } from './vercel-types.js';
import { clientIp, ipHash } from './admin.js';
import { dbInsert } from './db.js';

/** Ghi nhật ký thao tác admin. Không bao giờ chứa khoá API (chỉ dấu vân tay 8 ký tự). Lỗi ghi không chặn thao tác nhưng được log. */
export async function audit(req: VercelRequest, action: string, target?: string, detail: Record<string, unknown> = {}): Promise<void> {
  try {
    await dbInsert('admin_audit', {
      actor: (process.env.ADMIN_USER ?? 'admin').slice(0, 60),
      ip_hash: ipHash(clientIp(req)),
      action: action.slice(0, 60),
      target: target ? target.slice(0, 120) : null,
      detail,
    });
  } catch (e) {
    console.error('audit_failed', action, (e as Error).message);
  }
}
