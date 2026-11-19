import { createCipheriv, createDecipheriv, hkdfSync, randomBytes } from 'node:crypto';

// Mã hoá khoá API trước khi lưu vào DB (AES-256-GCM). Hàm thuần, không import nội bộ để kiểm thử độc lập.
// Mục đích: lộ DB (sao lưu, nhân viên, SQL injection) không làm lộ khoá nhà cung cấp; muốn đọc phải có thêm
// biến môi trường KEY_ENCRYPTION_SECRET trên Vercel. Định dạng: `enc:v1:` + base64url(iv(12) | tag(16) | bản mã).
// `aad` (tên nhà cung cấp) gắn bản mã vào đúng chỗ dùng: chép dòng này sang nhà cung cấp khác sẽ giải mã thất bại.

const PREFIX = 'enc:v1:';

export function isEncrypted(stored: string): boolean {
  return stored.startsWith(PREFIX);
}

/** Bí mật mã hoá tối thiểu 32 ký tự (khuyến nghị 32 byte ngẫu nhiên ở dạng base64). */
export function validSecret(secret: string | undefined): secret is string {
  return typeof secret === 'string' && secret.length >= 32;
}

function derive(secret: string): Uint8Array {
  return new Uint8Array(hkdfSync('sha256', secret, 'vg-keybox', 'v1', 32));
}

export function encryptKey(plain: string, secret: string, aad: string): string {
  if (!validSecret(secret)) throw new Error('secret_invalid');
  const iv = randomBytes(12);
  const c = createCipheriv('aes-256-gcm', derive(secret), new Uint8Array(iv));
  c.setAAD(new Uint8Array(Buffer.from(aad)));
  const ct = Buffer.concat([new Uint8Array(c.update(plain, 'utf8')), new Uint8Array(c.final())]);
  const tag = c.getAuthTag();
  return PREFIX + Buffer.concat([new Uint8Array(iv), new Uint8Array(tag), new Uint8Array(ct)]).toString('base64url');
}

/**
 * Giải mã; thử lần lượt các bí mật (hiện tại, rồi bí mật cũ khi đang đổi). Giá trị không mang tiền tố `enc:v1:`
 * là khoá cũ lưu thô: trả nguyên văn. Ném lỗi `secret_missing` / `decrypt_failed`, không bao giờ kèm nội dung khoá.
 */
export function decryptKey(stored: string, secrets: (string | undefined)[], aad: string): string {
  if (!isEncrypted(stored)) return stored;
  const list = secrets.filter(validSecret);
  if (list.length === 0) throw new Error('secret_missing');
  const raw = Buffer.from(stored.slice(PREFIX.length), 'base64url');
  if (raw.length < 12 + 16 + 1) throw new Error('decrypt_failed');
  const iv = new Uint8Array(raw.subarray(0, 12));
  const tag = new Uint8Array(raw.subarray(12, 28));
  const ct = new Uint8Array(raw.subarray(28));
  for (const s of list) {
    try {
      const d = createDecipheriv('aes-256-gcm', derive(s), iv);
      d.setAAD(new Uint8Array(Buffer.from(aad)));
      d.setAuthTag(tag);
      return Buffer.concat([new Uint8Array(d.update(ct)), new Uint8Array(d.final())]).toString('utf8');
    } catch {
      // thử bí mật kế tiếp
    }
  }
  throw new Error('decrypt_failed');
}

/** Che khoá trong log/lỗi: mọi chuỗi giống khoá (sk-…, gsk_…, Bearer …) bị thay bằng dấu sao. */
export function redact(s: string): string {
  return s
    .replace(/\bsk-[A-Za-z0-9_-]{6,}/g, 'sk-***')
    .replace(/\bgsk_[A-Za-z0-9]{6,}/g, 'gsk_***')
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]{8,}/gi, 'Bearer ***');
}
