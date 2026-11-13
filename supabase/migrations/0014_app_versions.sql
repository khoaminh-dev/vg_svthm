-- Tự cập nhật app (Android): app đọc bảng này lúc mở để biết có bản mới không.
-- latest_build / min_supported_build so với versionCode (số sau dấu + trong pubspec).
create table if not exists public.app_versions (
  platform text primary key check (platform in ('android')),
  latest_build integer not null check (latest_build > 0),
  latest_name text not null,
  min_supported_build integer not null default 1 check (min_supported_build > 0),
  apk_url text,
  apk_sha256 text check (apk_sha256 is null or apk_sha256 ~ '^[0-9a-f]{64}$'),
  notes text not null default '',
  updated_at timestamptz not null default now(),
  constraint app_versions_min_le_latest check (min_supported_build <= latest_build)
);

alter table public.app_versions enable row level security;

-- Ai cũng đọc được (app kiểm tra trước cả khi đăng nhập); chỉ service role / SQL editor được ghi.
drop policy if exists "app versions read all" on public.app_versions;
create policy "app versions read all" on public.app_versions
  for select to anon, authenticated using (true);

insert into public.app_versions (platform, latest_build, latest_name, min_supported_build, notes)
values ('android', 1, '1.0.0', 1, '')
on conflict (platform) do nothing;

-- Nơi đặt file APK (công khai để tải không cần đăng nhập). Chỉ service role được upload.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('app-releases', 'app-releases', true, 104857600, array['application/vnd.android.package-archive'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;
