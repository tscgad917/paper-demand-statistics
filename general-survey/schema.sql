-- 總務課通用問卷平台：資料表、權限及公開填答 RPC
-- 請在主 Supabase 專案 onebxqajsiqmhfcizaxl 的 SQL Editor 執行一次。
-- 不修改既有庫存、傳票耗材、紙張需求及活動報名資料表。

create extension if not exists pgcrypto;

create or replace function public.is_general_survey_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admin_authorizations a
    where lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and a.is_active = true
  );
$$;

create table if not exists public.general_surveys (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  target_year integer not null,
  public_token uuid not null unique default gen_random_uuid(),
  opens_at timestamptz not null,
  closes_at timestamptz not null,
  is_published boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint general_surveys_dates_check check (closes_at > opens_at)
);

create table if not exists public.general_survey_units (
  survey_id uuid not null references public.general_surveys(id) on delete cascade,
  unit_id integer not null references public.units(id) on delete restrict,
  primary key (survey_id, unit_id)
);

create table if not exists public.general_survey_questions (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.general_surveys(id) on delete cascade,
  sort_order integer not null default 0,
  title text not null,
  description text,
  question_type text not null default 'number'
    check (question_type in ('text','textarea','number','single_choice','multiple_choice','date')),
  is_required boolean not null default false,
  image_path text,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.general_survey_options (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.general_survey_questions(id) on delete cascade,
  sort_order integer not null default 0,
  label text not null,
  value text not null,
  image_path text
);

create table if not exists public.general_survey_submissions (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.general_surveys(id) on delete cascade,
  unit_id integer not null references public.units(id) on delete restrict,
  submitter_name text not null,
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (survey_id, unit_id)
);

create table if not exists public.general_survey_answers (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.general_survey_submissions(id) on delete cascade,
  question_id uuid not null references public.general_survey_questions(id) on delete cascade,
  answer jsonb,
  updated_at timestamptz not null default now(),
  unique (submission_id, question_id)
);

create index if not exists idx_general_surveys_year on public.general_surveys(target_year desc);
create index if not exists idx_general_survey_questions_survey on public.general_survey_questions(survey_id, sort_order);
create index if not exists idx_general_survey_submissions_survey on public.general_survey_submissions(survey_id, unit_id);
create index if not exists idx_general_survey_answers_submission on public.general_survey_answers(submission_id);

alter table public.general_surveys enable row level security;
alter table public.general_survey_units enable row level security;
alter table public.general_survey_questions enable row level security;
alter table public.general_survey_options enable row level security;
alter table public.general_survey_submissions enable row level security;
alter table public.general_survey_answers enable row level security;

drop policy if exists general_surveys_admin_all on public.general_surveys;
create policy general_surveys_admin_all on public.general_surveys
for all to authenticated
using (public.is_general_survey_admin())
with check (public.is_general_survey_admin());

drop policy if exists general_survey_units_admin_all on public.general_survey_units;
create policy general_survey_units_admin_all on public.general_survey_units
for all to authenticated
using (public.is_general_survey_admin())
with check (public.is_general_survey_admin());

drop policy if exists general_survey_questions_admin_all on public.general_survey_questions;
create policy general_survey_questions_admin_all on public.general_survey_questions
for all to authenticated
using (public.is_general_survey_admin())
with check (public.is_general_survey_admin());

drop policy if exists general_survey_options_admin_all on public.general_survey_options;
create policy general_survey_options_admin_all on public.general_survey_options
for all to authenticated
using (public.is_general_survey_admin())
with check (public.is_general_survey_admin());

drop policy if exists general_survey_submissions_admin_all on public.general_survey_submissions;
create policy general_survey_submissions_admin_all on public.general_survey_submissions
for all to authenticated
using (public.is_general_survey_admin())
with check (public.is_general_survey_admin());

drop policy if exists general_survey_answers_admin_all on public.general_survey_answers;
create policy general_survey_answers_admin_all on public.general_survey_answers
for all to authenticated
using (public.is_general_survey_admin())
with check (public.is_general_survey_admin());

grant select, insert, update, delete on public.general_surveys to authenticated;
grant select, insert, update, delete on public.general_survey_units to authenticated;
grant select, insert, update, delete on public.general_survey_questions to authenticated;
grant select, insert, update, delete on public.general_survey_options to authenticated;
grant select, insert, update, delete on public.general_survey_submissions to authenticated;
grant select, insert, update, delete on public.general_survey_answers to authenticated;

-- 品項示意圖片不是社員個資，採公開唯讀圖片桶；只有已登入且獲授權管理員可上傳、修改、刪除。
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('general-survey-images', 'general-survey-images', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
set public = true, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists general_survey_images_admin_insert on storage.objects;
create policy general_survey_images_admin_insert on storage.objects
for insert to authenticated
with check (bucket_id = 'general-survey-images' and public.is_general_survey_admin());

drop policy if exists general_survey_images_admin_update on storage.objects;
create policy general_survey_images_admin_update on storage.objects
for update to authenticated
using (bucket_id = 'general-survey-images' and public.is_general_survey_admin())
with check (bucket_id = 'general-survey-images' and public.is_general_survey_admin());

drop policy if exists general_survey_images_admin_delete on storage.objects;
create policy general_survey_images_admin_delete on storage.objects
for delete to authenticated
using (bucket_id = 'general-survey-images' and public.is_general_survey_admin());

create or replace function public.general_survey_public_info(
  p_token uuid,
  p_unit_id integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_survey public.general_surveys%rowtype;
  v_result jsonb;
begin
  select * into v_survey
  from public.general_surveys
  where public_token = p_token;

  if not found then
    return jsonb_build_object('ok', false, 'message', '找不到此問卷，請確認連結是否正確。');
  end if;

  select jsonb_build_object(
    'ok', true,
    'survey', jsonb_build_object(
      'id', v_survey.id,
      'title', v_survey.title,
      'description', v_survey.description,
      'target_year', v_survey.target_year,
      'opens_at', v_survey.opens_at,
      'closes_at', v_survey.closes_at,
      'is_published', v_survey.is_published
    ),
    'is_open', (
      v_survey.is_published
      and now() >= v_survey.opens_at
      and now() <= v_survey.closes_at
    ),
    'units', coalesce((
      select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name) order by u.id)
      from public.general_survey_units su
      join public.units u on u.id = su.unit_id
      where su.survey_id = v_survey.id
    ), '[]'::jsonb),
    'questions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', q.id,
          'sort_order', q.sort_order,
          'title', q.title,
          'description', q.description,
          'question_type', q.question_type,
          'is_required', q.is_required,
          'image_path', q.image_path,
          'settings', q.settings,
          'options', coalesce((
            select jsonb_agg(jsonb_build_object(
              'id', o.id, 'label', o.label, 'value', o.value,
              'image_path', o.image_path, 'sort_order', o.sort_order
            ) order by o.sort_order)
            from public.general_survey_options o
            where o.question_id = q.id
          ), '[]'::jsonb)
        ) order by q.sort_order, q.created_at
      )
      from public.general_survey_questions q
      where q.survey_id = v_survey.id
    ), '[]'::jsonb),
    'submission', case when p_unit_id is null then null else (
      select jsonb_build_object(
        'submitter_name', s.submitter_name,
        'submitted_at', s.submitted_at,
        'answers', coalesce((
          select jsonb_agg(jsonb_build_object('question_id', a.question_id, 'answer', a.answer))
          from public.general_survey_answers a
          where a.submission_id = s.id
        ), '[]'::jsonb)
      )
      from public.general_survey_submissions s
      where s.survey_id = v_survey.id and s.unit_id = p_unit_id
    ) end
  ) into v_result;

  if p_unit_id is not null and not exists (
    select 1 from public.general_survey_units
    where survey_id = v_survey.id and unit_id = p_unit_id
  ) then
    return jsonb_build_object('ok', false, 'message', '此單位不在本問卷填報範圍內。');
  end if;

  return v_result;
end;
$$;

create or replace function public.general_survey_submit(
  p_token uuid,
  p_unit_id integer,
  p_submitter_name text,
  p_answers jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_survey public.general_surveys%rowtype;
  v_submission_id uuid;
  v_item jsonb;
  v_question_id uuid;
  v_answer jsonb;
begin
  select * into v_survey
  from public.general_surveys
  where public_token = p_token;

  if not found then
    return jsonb_build_object('ok', false, 'message', '找不到此問卷。');
  end if;

  if not v_survey.is_published or now() < v_survey.opens_at or now() > v_survey.closes_at then
    return jsonb_build_object('ok', false, 'message', '目前不在問卷開放填報期間。');
  end if;

  if not exists (
    select 1 from public.general_survey_units
    where survey_id = v_survey.id and unit_id = p_unit_id
  ) then
    return jsonb_build_object('ok', false, 'message', '此單位不在本問卷填報範圍內。');
  end if;

  if nullif(trim(coalesce(p_submitter_name, '')), '') is null then
    return jsonb_build_object('ok', false, 'message', '請填寫填報人姓名。');
  end if;

  if jsonb_typeof(p_answers) <> 'array' then
    return jsonb_build_object('ok', false, 'message', '填報資料格式不正確。');
  end if;

  -- 僅接受本問卷所屬題目，避免任意寫入其他問卷資料。
  for v_item in select value from jsonb_array_elements(p_answers)
  loop
    begin
      v_question_id := (v_item ->> 'question_id')::uuid;
    exception when others then
      return jsonb_build_object('ok', false, 'message', '題目識別資料不正確。');
    end;

    if not exists (
      select 1 from public.general_survey_questions
      where id = v_question_id and survey_id = v_survey.id
    ) then
      return jsonb_build_object('ok', false, 'message', '填報內容包含不屬於本問卷的題目。');
    end if;
  end loop;

  -- 必填題目須有非空答案；數字 0 視為有效答案。
  if exists (
    select 1
    from public.general_survey_questions q
    where q.survey_id = v_survey.id and q.is_required = true
      and not exists (
        select 1
        from jsonb_array_elements(p_answers) a
        where a ->> 'question_id' = q.id::text
          and a ? 'answer'
          and (a -> 'answer') is distinct from 'null'::jsonb
          and (a -> 'answer') <> '""'::jsonb
          and (a -> 'answer') <> '[]'::jsonb
      )
  ) then
    return jsonb_build_object('ok', false, 'message', '尚有必填題目未完成。');
  end if;

  insert into public.general_survey_submissions (survey_id, unit_id, submitter_name, submitted_at)
  values (v_survey.id, p_unit_id, trim(p_submitter_name), now())
  on conflict (survey_id, unit_id)
  do update set submitter_name = excluded.submitter_name, submitted_at = now()
  returning id into v_submission_id;

  delete from public.general_survey_answers where submission_id = v_submission_id;

  for v_item in select value from jsonb_array_elements(p_answers)
  loop
    v_question_id := (v_item ->> 'question_id')::uuid;
    v_answer := v_item -> 'answer';
    insert into public.general_survey_answers (submission_id, question_id, answer)
    values (v_submission_id, v_question_id, v_answer);
  end loop;

  return jsonb_build_object('ok', true, 'message', '填報資料已成功送出。', 'submitted_at', now());
end;
$$;

revoke all on function public.general_survey_public_info(uuid, integer) from public;
revoke all on function public.general_survey_submit(uuid, integer, text, jsonb) from public;
grant execute on function public.general_survey_public_info(uuid, integer) to anon, authenticated;
grant execute on function public.general_survey_submit(uuid, integer, text, jsonb) to anon, authenticated;

