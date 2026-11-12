import type { IncomingMessage } from 'node:http';

// Kiểu tối thiểu cho handler Vercel. Tự khai báo để không phải kéo gói `@vercel/node`
// (chỉ dùng cho kiểu, nhưng kéo theo cả chuỗi công cụ build có lỗ hổng npm audit).
export interface VercelRequest extends IncomingMessage {
  query: Record<string, string | string[] | undefined>;
  body: unknown;
}

export interface VercelResponse {
  status(code: number): VercelResponse;
  json(body: unknown): VercelResponse;
  send(body: unknown): VercelResponse;
  end(): VercelResponse;
  setHeader(name: string, value: string): VercelResponse;
}
