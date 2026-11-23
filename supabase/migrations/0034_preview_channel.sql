-- Kênh bản thử: chỉ tài khoản trong preview_testers thấy dòng 'android_preview'.
alter table public.app_versions drop constraint if exists app_versions_platform_check;
alter table public.app_versions add constraint app_versions_platform_check
  check (platform in ('android', 'android_preview'));

create table if not exists public.preview_testers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.preview_testers enable row level security;
drop policy if exists "tester sees self" on public.preview_testers;
create policy "tester sees self" on public.preview_testers
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "app versions read all" on public.app_versions;
create policy "app versions read all" on public.app_versions
  for select to anon, authenticated using (
    platform = 'android'
    or exists (select 1 from public.preview_testers t where t.user_id = auth.uid())
  );

insert into public.app_versions (platform, latest_build, latest_name, min_supported_build, notes)
values ('android_preview', 1, '0.0.0', 1, '')
on conflict (platform) do nothing;

insert into public.preview_testers (user_id)
values ('1fcbcfef-5669-4fbe-86b2-8f0f655b5e34')
on conflict do nothing;
