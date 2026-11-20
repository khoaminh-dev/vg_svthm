// Cho `node --test` chạy thẳng file .ts: mã chạy thật nhập './x.js' (Vercel tự đổi sang .ts), nên ở đây
// nếu './x.js' không tồn tại thì thử './x.ts'. Dùng: node --import ./_tests/register_ts.mjs --test ...
import { register } from 'node:module';

register(
  'data:text/javascript,' +
    encodeURIComponent(`
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
export async function resolve(specifier, context, nextResolve) {
  if (specifier.startsWith('.') && specifier.endsWith('.js') && context.parentURL) {
    const url = new URL(specifier, context.parentURL);
    if (!existsSync(fileURLToPath(url))) {
      const ts = new URL(specifier.slice(0, -3) + '.ts', context.parentURL);
      if (existsSync(fileURLToPath(ts))) return nextResolve(ts.href, context);
    }
  }
  return nextResolve(specifier, context);
}
`),
  import.meta.url,
);
