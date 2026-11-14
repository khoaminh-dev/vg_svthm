-- Hồ sơ sức khoẻ (nhập một lần) và lịch sử đánh giá nguy cơ tự động sau mỗi lần đo huyết áp.
-- Mô hình chạy trên server (api/health-risk); app chỉ ghi hồ sơ và đọc kết quả.

create table if not exists public.health_profile (
  user_id           uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  birth_year        smallint not null check (birth_year between 1900 and 2100),
  sex               text not null check (sex in ('male', 'female')),
  -- null = "không rõ"
  has_hypertension  boolean,
  has_heart_disease boolean,
  is_smoker         boolean,
  on_bp_meds        boolean,
  has_diabetes      boolean,
  had_stroke        boolean,
  consented_at      timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

alter table public.health_profile enable row level security;
create policy "hp_select_own" on public.health_profile for select to authenticated using (user_id = auth.uid());
create policy "hp_insert_own" on public.health_profile for insert to authenticated with check (user_id = auth.uid());
create policy "hp_update_own" on public.health_profile for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "hp_delete_own" on public.health_profile for delete to authenticated using (user_id = auth.uid());
revoke all on public.health_profile from anon;
grant select, insert, update, delete on public.health_profile to authenticated;

create table if not exists public.health_assessments (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  reading_id  uuid references public.bp_readings(id) on delete set null,
  level       text not null check (level in ('low', 'attention', 'high', 'urgent')),
  stroke_p    real not null,
  heart_p     real not null,
  details     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists health_assessments_user_time_idx on public.health_assessments (user_id, created_at desc);

alter table public.health_assessments enable row level security;
-- Chỉ server (service role) ghi; người dùng chỉ đọc và xoá của mình.
create policy "ha_select_own" on public.health_assessments for select to authenticated using (user_id = auth.uid());
create policy "ha_delete_own" on public.health_assessments for delete to authenticated using (user_id = auth.uid());
revoke all on public.health_assessments from anon;
grant select, delete on public.health_assessments to authenticated;
