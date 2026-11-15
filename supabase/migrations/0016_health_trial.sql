-- Đợt thử nghiệm đánh giá nguy cơ trên người thật.
-- 1) Đồng ý tham gia nghiên cứu (hỏi riêng, rút lại được bất cứ lúc nào). null = chưa hỏi.
alter table public.health_profile
  add column if not exists research_consent boolean,
  add column if not exists research_consent_at timestamptz;

-- 2) Phản hồi của người dùng về từng kết quả: đúng / chưa đúng / không rõ. Chỉ ghi được khi đã đồng ý nghiên cứu.
create table if not exists public.health_feedback (
  id            bigint generated always as identity primary key,
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  assessment_id uuid not null references public.health_assessments(id) on delete cascade,
  verdict       text not null check (verdict in ('right', 'wrong', 'unsure')),
  level         text check (level in ('low', 'attention', 'high', 'urgent')),
  note          text check (char_length(note) <= 300),
  created_at    timestamptz not null default now(),
  unique (user_id, assessment_id)
);
create index if not exists health_feedback_time_idx on public.health_feedback (created_at desc);

alter table public.health_feedback enable row level security;

create policy "hf_select_own" on public.health_feedback for select to authenticated using (user_id = auth.uid());
create policy "hf_delete_own" on public.health_feedback for delete to authenticated using (user_id = auth.uid());
create policy "hf_insert_own" on public.health_feedback for insert to authenticated with check (
  user_id = auth.uid()
  and exists (select 1 from public.health_profile p where p.user_id = auth.uid() and p.research_consent is true)
);
create policy "hf_update_own" on public.health_feedback for update to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.health_profile p where p.user_id = auth.uid() and p.research_consent is true)
  );

revoke all on public.health_feedback from anon, authenticated;
grant select, insert, update, delete on public.health_feedback to authenticated;

-- 3) Thống kê đợt thử nghiệm cho admin. Chỉ tính người đã đồng ý, mỗi người lấy kết quả mới nhất để không
--    bị người đo nhiều lần làm lệch. Không trả về tên hay id người dùng.
create or replace function public.admin_health_trial(p_days int default 30)
returns jsonb language plpgsql security definer set search_path = '' stable as $$
declare
  d int := least(greatest(coalesce(p_days, 30), 1), 365);
  since timestamptz := now() - make_interval(days => d);
  yr int := extract(year from now())::int;
  res jsonb;
begin
  with
  c as (
    select user_id, birth_year, has_hypertension, has_heart_disease, is_smoker, has_diabetes, had_stroke
    from public.health_profile where research_consent is true
  ),
  la as (
    select distinct on (a.user_id) a.user_id, a.level, (yr - c.birth_year) as age
    from public.health_assessments a join c on c.user_id = a.user_id
    where a.created_at >= since
    order by a.user_id, a.created_at desc
  ),
  fb as (
    select f.* from public.health_feedback f join c on c.user_id = f.user_id where f.created_at >= since
  )
  select jsonb_build_object(
    'days', d,
    'consenting', (select count(*) from c),
    'withResult', (select count(*) from la),
    'assessments', (select count(*) from public.health_assessments a join c on c.user_id = a.user_id where a.created_at >= since),
    'byLevel', (select coalesce(jsonb_agg(jsonb_build_object('key', level, 'count', n)), '[]'::jsonb)
                from (select level, count(*) n from la group by level) x),
    'byAge', (select coalesce(jsonb_agg(jsonb_build_object(
                'key', band, 'total', total, 'low', low, 'attention', att, 'high', hi, 'urgent', urg) order by band), '[]'::jsonb)
              from (
                select case when age < 50 then '1) dưới 50' when age < 60 then '2) 50-59' when age < 70 then '3) 60-69'
                            when age < 80 then '4) 70-79' else '5) từ 80' end as band,
                       count(*) total,
                       count(*) filter (where level = 'low') low,
                       count(*) filter (where level = 'attention') att,
                       count(*) filter (where level = 'high') hi,
                       count(*) filter (where level = 'urgent') urg
                from la group by 1) y),
    'factors', (select jsonb_build_object(
                  'hypertension', count(*) filter (where has_hypertension),
                  'heartDisease', count(*) filter (where has_heart_disease),
                  'diabetes', count(*) filter (where has_diabetes),
                  'smoker', count(*) filter (where is_smoker),
                  'hadStroke', count(*) filter (where had_stroke)) from c),
    'feedback', jsonb_build_object(
      'total', (select count(*) from fb),
      'right', (select count(*) from fb where verdict = 'right'),
      'wrong', (select count(*) from fb where verdict = 'wrong'),
      'unsure', (select count(*) from fb where verdict = 'unsure'),
      'byLevel', (select coalesce(jsonb_agg(jsonb_build_object(
                    'key', level, 'right', r, 'wrong', w, 'unsure', u)), '[]'::jsonb)
                  from (select level,
                               count(*) filter (where verdict = 'right') r,
                               count(*) filter (where verdict = 'wrong') w,
                               count(*) filter (where verdict = 'unsure') u
                        from fb where level is not null group by level) z),
      'notes', (select coalesce(jsonb_agg(jsonb_build_object('at', created_at, 'level', level, 'note', note)), '[]'::jsonb)
                from (select created_at, level, note from fb
                      where verdict = 'wrong' and note is not null and note <> ''
                      order by created_at desc limit 20) n)
    )
  ) into res;
  return res;
end $$;
revoke all on function public.admin_health_trial(int) from public, anon, authenticated;
grant execute on function public.admin_health_trial(int) to service_role;
