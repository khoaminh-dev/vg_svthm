// Hàm thuần (không import) của lớp gọi LLM, để kiểm thử độc lập.

/** Thân yêu cầu Groq. Mô hình gpt-oss "suy nghĩ" bằng chính số token trả lời: để mặc định (medium) thì ~180/300 token bị
 *  dùng cho suy nghĩ, JSON dễ bị cắt cụt → lỗi phân tích → rơi sang DeepSeek (chậm hơn ~1,8 giây). Hạ mức suy nghĩ + nới trần token. */
export function groqBody(messages: { role: string; content: string }[], maxTokens: number, model: string, withReasoning = true): Record<string, unknown> {
  const oss = /gpt-oss/.test(model);
  return {
    model,
    messages,
    temperature: 0,
    max_tokens: oss ? Math.max(maxTokens, 600) : maxTokens,
    response_format: { type: 'json_object' },
    ...(oss && withReasoning ? { reasoning_effort: 'low' } : {}),
  };
}

/** Mã lỗi ngắn (không chứa nội dung người dùng) để biết vì sao Groq phải nhường DeepSeek. */
export function failCode(p: string, e: unknown): string {
  const st = (e as { status?: number })?.status;
  if (typeof st === 'number') return `${p}:${st}`;
  if (e instanceof SyntaxError) return `${p}:parse`;
  const m = String((e as Error)?.message ?? '');
  if (/abort/i.test(m)) return `${p}:timeout`;
  if (/all_/.test(m) || /no_/.test(m)) return `${p}:keys`;
  return `${p}:err`;
}

