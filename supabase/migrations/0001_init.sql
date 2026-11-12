-- Profiles (1-1 với auth.users). id (uuid) chính là user id.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique                -- null với người dùng Google cho tới khi hoàn tất hồ sơ
    check (username ~ '^[a-z0-9_]{3,20}$'),
  display_name text,
  avatar_url text,
  last_seen_at timestamptz,          -- trạng thái online thời gian thực dùng Realtime Presence; cột này lưu lần cuối thấy
  created_at timestamptz not null default now()
);

-- Kiểm tra username còn trống (gọi được khi chưa đăng nhập, để form đăng ký báo lỗi sớm)
create function public.is_username_available(p_username text) returns boolean
language sql security definer set search_path = public stable as $$
  select not exists (select 1 from public.profiles where username = lower(p_username));
$$;
grant execute on function public.is_username_available(text) to anon, authenticated;

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, display_name, avatar_url)
  values (
    new.id,
    lower(new.raw_user_meta_data->>'username'),
    coalesce(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      split_part(new.email, '@', 1)
    ),
    coalesce(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture')
  );
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

-- Ảnh đại diện: bucket công khai, mỗi user chỉ ghi vào thư mục mang id của mình
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true)
on conflict (id) do nothing;

create policy "avatars read" on storage.objects for select
  using (bucket_id = 'avatars');
create policy "avatars write own" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars update own" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- Phòng chat
create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.room_members (
  room_id uuid references public.rooms(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  primary key (room_id, user_id)
);

create table public.messages (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  content text not null,
  created_at timestamptz not null default now()
);
create index on public.messages (room_id, created_at);

-- Kết quả OCR
create table public.ocr_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  raw_text text,
  values jsonb,
  image_path text,
  created_at timestamptz not null default now()
);

-- Row Level Security
alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.messages enable row level security;
alter table public.ocr_records enable row level security;

create function public.is_room_member(r uuid) returns boolean
language sql security definer set search_path = public stable as $$
  select exists (select 1 from room_members where room_id = r and user_id = auth.uid());
$$;

create policy "profiles read" on public.profiles for select to authenticated using (true);
create policy "profiles update own" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy "rooms read member" on public.rooms for select to authenticated using (public.is_room_member(id) or created_by = auth.uid());
create policy "rooms create" on public.rooms for insert to authenticated with check (created_by = auth.uid());

create policy "members read" on public.room_members for select to authenticated using (user_id = auth.uid() or public.is_room_member(room_id));
create policy "members join self" on public.room_members for insert to authenticated with check (user_id = auth.uid());

create policy "messages read member" on public.messages for select to authenticated using (public.is_room_member(room_id));
create policy "messages send member" on public.messages for insert to authenticated with check (user_id = auth.uid() and public.is_room_member(room_id));

create policy "ocr own" on public.ocr_records for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Bật realtime cho tin nhắn
alter publication supabase_realtime add table public.messages;
