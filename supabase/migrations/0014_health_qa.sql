-- Lịch sử bác hỏi Vy về sức khoẻ và câu Vy trả lời. Chỉ chính chủ đọc/xoá được.
-- Server (service role) ghi; tự xoá sau 90 ngày bằng api/cron/prune-chat-images.
create table if not exists public.health_qa (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  asked_at   timestamptz not null default now(),
  topic      text not null check (topic in ('general', 'trend', 'risk', 'habit', 'other')),
  question   text not null check (char_length(question) <= 300),
  answer     text not null check (char_length(answer) <= 600),
  level      text check (level in ('low', 'attention', 'high', 'urgent')),
  systolic   smallint,
  diastolic  smallint
);

create index if not exists health_qa_user_time_idx on public.health_qa (user_id, asked_at desc);
create index if not exists health_qa_time_idx on public.health_qa (asked_at);

alter table public.health_qa enable row level security;

create policy "health_qa_select_own" on public.health_qa for select to authenticated using (user_id = auth.uid());
create policy "health_qa_delete_own" on public.health_qa for delete to authenticated using (user_id = auth.uid());

revoke all on public.health_qa from anon, authenticated;
grant select, delete on public.health_qa to authenticated;
