-- Theo dõi huyết áp: mỗi lần đo (từ OCR ảnh máy đo hoặc nhập tay) là một dòng.
-- Phân loại theo AHA 2017 (đơn vị mmHg):
--   crisis  : tâm thu > 180 hoặc tâm trương > 120
--   stage2  : tâm thu >= 140 hoặc tâm trương >= 90
--   stage1  : tâm thu 130-139 hoặc tâm trương 80-89
--   elevated: tâm thu 120-129 và tâm trương < 80
--   normal  : còn lại
create or replace function public.bp_category(sys int, dia int)
returns text language sql immutable parallel safe set search_path = '' as $$
  select case
    when sys > 180 or dia > 120 then 'crisis'
    when sys >= 140 or dia >= 90 then 'stage2'
    when sys >= 130 or dia >= 80 then 'stage1'
    when sys >= 120 then 'elevated'
    else 'normal'
  end
$$;

create table if not exists public.bp_readings (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  systolic      smallint not null check (systolic between 50 and 300),
  diastolic     smallint not null check (diastolic between 30 and 200),
  pulse         smallint check (pulse between 20 and 250),
  measured_at   timestamptz not null default now(),
  source        text not null default 'ocr_ai' check (source in ('ocr_ai', 'ocr_local', 'manual')),
  ocr_record_id uuid references public.ocr_records(id) on delete set null,
  note          text check (char_length(note) <= 500),
  category      text generated always as (public.bp_category(systolic::int, diastolic::int)) stored,
  created_at    timestamptz not null default now(),
  constraint bp_sys_gt_dia check (systolic > diastolic)
);

create index if not exists bp_readings_user_time_idx on public.bp_readings (user_id, measured_at desc);
create index if not exists bp_readings_time_idx on public.bp_readings (measured_at desc);

alter table public.bp_readings enable row level security;

create policy "bp_select_own" on public.bp_readings for select to authenticated using (user_id = auth.uid());
create policy "bp_insert_own" on public.bp_readings for insert to authenticated with check (user_id = auth.uid());
create policy "bp_update_own" on public.bp_readings for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "bp_delete_own" on public.bp_readings for delete to authenticated using (user_id = auth.uid());

revoke all on public.bp_readings from anon;
grant select, insert, update, delete on public.bp_readings to authenticated;
