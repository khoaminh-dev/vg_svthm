import type { VercelRequest, VercelResponse } from '../_lib/vercel-types.js';
import { dbPatch, dbSelect, storageRemove } from '../_lib/db.js';

// Chạy hằng ngày (vercel.json → crons): xóa file ảnh chat quá 90 ngày khỏi Storage rồi đánh dấu "đã hết hạn"
// trên tin nhắn. Làm bằng API chứ không bằng SQL vì xóa dòng trong storage.objects không xóa file thật.
const DAYS = 90;
const BATCH = 200;
const MAX_BATCHES = 10;

type Row = { id: number; image_path: string };

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // Vercel Cron tự gửi "Authorization: Bearer $CRON_SECRET" khi có biến môi trường CRON_SECRET.
  const secret = process.env.CRON_SECRET;
  if (secret && req.headers.authorization !== `Bearer ${secret}`) {
    res.status(401).json({ error: 'unauthorized' });
    return;
  }
  const cutoff = new Date(Date.now() - DAYS * 86_400_000).toISOString();
  let expired = 0;
  try {
    for (let i = 0; i < MAX_BATCHES; i++) {
      const rows = await dbSelect<Row[]>(
        `messages?select=id,image_path&image_path=not.is.null&created_at=lt.${encodeURIComponent(cutoff)}&order=created_at.asc&limit=${BATCH}`,
      );
      if (!rows.length) break;
      // Xóa file trước: nếu lỗi thì tin nhắn còn nguyên đường dẫn và ngày mai thử lại, không mất dấu file.
      await storageRemove('chat-images', rows.map((r) => r.image_path));
      await dbPatch('messages', `id=in.(${rows.map((r) => r.id).join(',')})`, {
        image_path: null,
        image_expired_at: new Date().toISOString(),
      });
      expired += rows.length;
      if (rows.length < BATCH) break;
    }
    res.status(200).json({ ok: true, expired });
  } catch (e) {
    const m = e instanceof Error ? e.message : 'error';
    res.status(502).json({ error: m, expired });
  }
}
