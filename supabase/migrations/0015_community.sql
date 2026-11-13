-- Cờ tính năng chung (bật/tắt từ xa, không cần phát hành app mới).
create table if not exists public.app_flags (
  key text primary key,
  enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.app_flags enable row level security;
create policy "flags read" on public.app_flags for select to authenticated using (true);

-- Màn "Cộng đồng" dùng để gỡ lỗi trong đợt thử nghiệm: tắt bằng
--   update public.app_flags set enabled = false where key = 'community';
insert into public.app_flags (key, enabled) values ('community', true)
on conflict (key) do nothing;

-- Danh sách người dùng cho màn Cộng đồng (chỉ trả về khi cờ đang bật).
create or replace function public.community_users(p_query text default '', p_limit int default 100)
returns table (id uuid, username text, display_name text, avatar_url text)
language sql security definer set search_path = public stable as $$
  select p.id, p.username, p.display_name, p.avatar_url
  from public.profiles p
  where exists (select 1 from public.app_flags f where f.key = 'community' and f.enabled)
    and auth.uid() is not null
    and p.id <> auth.uid()
    and p.username is not null
    and (coalesce(p_query, '') = ''
         or p.username ilike '%' || replace(replace(p_query, '%', ''), '_', '\_') || '%'
         or p.display_name ilike '%' || replace(replace(p_query, '%', ''), '_', '\_') || '%')
  order by p.created_at desc
  limit least(greatest(p_limit, 1), 200);
$$;
revoke all on function public.community_users(text, int) from public, anon;
grant execute on function public.community_users(text, int) to authenticated;
