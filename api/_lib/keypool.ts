// Key pool: round-robin + cooldown cho từng key.
// Trạng thái nằm trong bộ nhớ của function instance (đủ cho prototype).
export type KeyState = { key: string; cooldownUntil: number };

export class KeyPool {
  private keys: KeyState[];
  private cursor: number;

  constructor(raw: string | undefined) {
    this.keys = (raw ?? '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean)
      .map((key) => ({ key, cooldownUntil: 0 }));
    this.cursor = Math.floor(Math.random() * Math.max(this.keys.length, 1));
  }

  get size() {
    return this.keys.length;
  }

  /** Lấy key kế tiếp không còn cooldown, hoặc null nếu hết. */
  next(): KeyState | null {
    const now = Date.now();
    for (let i = 0; i < this.keys.length; i++) {
      const idx = (this.cursor + i) % this.keys.length;
      const k = this.keys[idx];
      if (k.cooldownUntil <= now) {
        this.cursor = (idx + 1) % this.keys.length;
        return k;
      }
    }
    return null;
  }

  cooldown(k: KeyState, ms: number) {
    k.cooldownUntil = Date.now() + ms;
  }
}
