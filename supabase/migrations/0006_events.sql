-- Nhật ký thao tác người dùng (dùng cho web admin thống kê).
create table if not exists public.events (
  id         bigint generated always as identity primary key,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 60),
  screen     text check (char_length(screen) <= 60),
  props      jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists events_created_idx on public.events (created_at desc);
create index if not exists events_name_idx on public.events (name, created_at desc);
create index if not exists events_user_idx on public.events (user_id, created_at desc);

alter table public.events enable row level security;

-- Người dùng chỉ được ghi sự kiện của chính mình; không ai đọc được qua API công khai
-- (web admin đọc bằng service role).
create policy "events_insert_own" on public.events
  for insert to authenticated with check (user_id = auth.uid());

revoke all on public.events from anon;
revoke select, update, delete on public.events from authenticated;
grant insert on public.events to authenticated;
