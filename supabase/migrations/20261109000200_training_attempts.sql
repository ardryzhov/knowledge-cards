-- Stage 3. Every display of a card has one server-issued attempt.
begin;

create table public.training_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  session_id uuid not null,
  card_id uuid not null,
  position integer not null,
  status text not null default 'queued',
  event_id uuid unique,
  created_at timestamptz not null default now(),
  issued_at timestamptz,
  answered_at timestamptz,
  constraint training_attempts_owner_id_unique unique (user_id, id),
  constraint training_attempts_session_card_position_unique unique (session_id, position),
  constraint training_attempts_session_owner_fk foreign key (user_id, session_id)
    references public.training_sessions(user_id, id) on delete restrict,
  constraint training_attempts_card_owner_fk foreign key (user_id, card_id)
    references public.cards(user_id, id) on delete restrict,
  constraint training_attempts_position_positive check (position > 0),
  constraint training_attempts_status_valid check (status in ('queued', 'issued', 'answered', 'skipped')),
  constraint training_attempts_answer_state_valid check (
    (status = 'answered' and event_id is not null and issued_at is not null and answered_at is not null)
    or (status <> 'answered' and event_id is null and answered_at is null)
  )
);

create unique index training_attempts_one_issued_idx
  on public.training_attempts(session_id) where status = 'issued';
create index training_attempts_owner_session_position_idx
  on public.training_attempts(user_id, session_id, position);
create index training_attempts_owner_card_idx
  on public.training_attempts(user_id, card_id);
create unique index training_sessions_one_active_topic_mode_idx
  on public.training_sessions(user_id, topic_id, mode)
  where status = 'active' and topic_id is not null;

alter table public.answer_history add column attempt_id uuid;
alter table public.answer_history add constraint answer_history_attempt_unique unique (attempt_id);
alter table public.answer_history add constraint answer_history_attempt_owner_fk
  foreign key (user_id, attempt_id) references public.training_attempts(user_id, id) on delete restrict;

alter table public.training_attempts enable row level security;
revoke all on table public.training_attempts from public, anon, authenticated;
grant select on table public.training_attempts to authenticated;
create policy training_attempts_select_owner on public.training_attempts
  for select to authenticated using ((select auth.uid()) = user_id);

-- The original six-argument RPC is retained as a compatibility wrapper below.
-- The new seven-argument overload identifies a specific server-issued attempt.
create function public.record_answer(
  p_event_id uuid,
  p_session_id uuid,
  p_card_id uuid,
  p_is_correct boolean,
  p_hints_used integer,
  p_answer_duration_ms integer,
  p_attempt_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_session public.training_sessions%rowtype;
  v_attempt public.training_attempts%rowtype;
  v_card public.cards%rowtype;
  v_existing public.answer_history%rowtype;
  v_now timestamptz;
  v_progress public.card_progress%rowtype;
  v_streak integer;
  v_interval interval;
  v_inserted_id uuid;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_event_id is null or p_session_id is null or p_card_id is null or p_attempt_id is null
     or p_is_correct is null or p_hints_used is null or p_hints_used not between 0 and 2
     or (p_answer_duration_ms is not null and p_answer_duration_ms < 0) then
    raise exception 'Invalid answer payload' using errcode = '22023';
  end if;

  -- Every session operation takes this lock first. It serializes answer,
  -- issuance and completion, including concurrent requests from multiple tabs.
  select * into v_session from public.training_sessions
    where id = p_session_id and user_id = v_user_id for update;
  if not found then raise exception 'Training session not found' using errcode = '22023'; end if;
  select * into v_attempt from public.training_attempts
    where id = p_attempt_id and user_id = v_user_id
      and session_id = p_session_id and card_id = p_card_id for update;
  if not found then raise exception 'Attempt not found' using errcode = '22023'; end if;

  if v_attempt.status = 'answered' then
    select * into v_existing from public.answer_history
      where attempt_id = p_attempt_id and user_id = v_user_id;
    if found and v_existing.id = p_event_id
       and v_existing.session_id = p_session_id
       and v_existing.card_id = p_card_id
       and v_existing.is_correct = p_is_correct
       and v_existing.hints_used = p_hints_used
       and v_existing.answer_duration_ms is not distinct from p_answer_duration_ms then
      return p_event_id;
    end if;
    raise exception 'Attempt already answered' using errcode = '23505';
  end if;
  if v_session.status <> 'active' or v_attempt.status <> 'issued' then
    raise exception 'Active issued attempt required' using errcode = '22023';
  end if;

  select * into v_card from public.cards
    where id = p_card_id and user_id = v_user_id
      and topic_id = v_session.topic_id and deleted_at is null for share;
  if not found then raise exception 'Active card not found' using errcode = '22023'; end if;
  perform 1 from public.topics where id = v_session.topic_id
    and user_id = v_user_id and deleted_at is null for share;
  if not found then raise exception 'Active topic not found' using errcode = '22023'; end if;
  if (p_hints_used >= 1 and nullif(btrim(v_card.hint_1), '') is null)
     or (p_hints_used = 2 and nullif(btrim(v_card.hint_2), '') is null) then
    raise exception 'Hint count exceeds available hints' using errcode = '22023';
  end if;

  v_now := clock_timestamp();
  insert into public.answer_history
    (id, user_id, card_id, session_id, attempt_id, mode, is_correct, hints_used, answer_duration_ms, answered_at)
  values
    (p_event_id, v_user_id, p_card_id, p_session_id, p_attempt_id,
     v_session.mode, p_is_correct, p_hints_used, p_answer_duration_ms, v_now)
  on conflict (id) do nothing returning id into v_inserted_id;
  if v_inserted_id is null then
    raise exception 'Answer event ID already used' using errcode = '23505';
  end if;

  if v_session.mode = 'spaced' then
    insert into public.card_progress (user_id, card_id)
      values (v_user_id, p_card_id) on conflict (user_id, card_id) do nothing;
    select * into v_progress from public.card_progress
      where user_id = v_user_id and card_id = p_card_id for update;
    if p_is_correct then
      v_streak := v_progress.consecutive_correct + 1;
      v_interval := case
        when v_streak = 1 then interval '1 day'
        when v_streak = 2 then interval '3 days'
        when v_streak = 3 then interval '7 days'
        when v_streak = 4 then interval '14 days'
        else interval '30 days' end;
      update public.card_progress set
        consecutive_correct = v_streak,
        total_correct = total_correct + 1,
        status = case when v_streak >= 5 then 'mastered' else 'learning' end,
        last_reviewed_at = v_now,
        next_review_at = v_now + v_interval,
        mastered_at = case when v_streak >= 5 then coalesce(mastered_at, v_now) else null end
      where user_id = v_user_id and card_id = p_card_id;
    else
      update public.card_progress set
        consecutive_correct = 0,
        total_incorrect = total_incorrect + 1,
        status = 'learning',
        last_reviewed_at = v_now,
        next_review_at = v_now + interval '10 minutes',
        mastered_at = null
      where user_id = v_user_id and card_id = p_card_id;
    end if;
  end if;

  update public.training_attempts set
    status = 'answered', event_id = p_event_id, answered_at = v_now
    where id = p_attempt_id and user_id = v_user_id;
  return p_event_id;
end;
$$;

create or replace function public.record_answer(
  p_event_id uuid,
  p_session_id uuid,
  p_card_id uuid,
  p_is_correct boolean,
  p_hints_used integer,
  p_answer_duration_ms integer default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_attempt_id uuid;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  -- Exact retries can still be resolved after another attempt is issued or
  -- after completion. New calls bind to the sole currently issued attempt.
  select attempt_id into v_attempt_id from public.answer_history
    where id = p_event_id and user_id = v_user_id;
  if v_attempt_id is null then
    select id into v_attempt_id from public.training_attempts
      where user_id = v_user_id and session_id = p_session_id
        and card_id = p_card_id and status = 'issued';
  end if;
  if v_attempt_id is null then
    raise exception 'Active issued attempt required' using errcode = '22023';
  end if;
  return public.record_answer(
    p_event_id, p_session_id, p_card_id, p_is_correct,
    p_hints_used, p_answer_duration_ms, v_attempt_id
  );
end;
$$;

create function public.start_training_session(p_topic_id uuid, p_mode text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_session_id uuid;
  v_now timestamptz := clock_timestamp();
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_topic_id is null or p_mode is null or p_mode not in ('spaced', 'infinite', 'mistakes') then
    raise exception 'Invalid session request' using errcode = '22023';
  end if;
  perform 1 from public.topics
    where id = p_topic_id and user_id = v_user_id and deleted_at is null for share;
  if not found then raise exception 'Active topic not found' using errcode = '22023'; end if;

  insert into public.training_sessions (user_id, topic_id, mode, started_at)
    values (v_user_id, p_topic_id, p_mode, v_now)
    on conflict (user_id, topic_id, mode)
      where status = 'active' and topic_id is not null
      do nothing returning id into v_session_id;
  if v_session_id is null then
    select id into v_session_id from public.training_sessions
      where user_id = v_user_id and topic_id = p_topic_id
        and mode = p_mode and status = 'active' for update;
    if v_session_id is null then
      raise exception 'Concurrent session start; retry' using errcode = '40001';
    end if;
    return v_session_id;
  end if;

  if p_mode in ('spaced', 'mistakes') then
    insert into public.training_attempts (user_id, session_id, card_id, position)
    select v_user_id, v_session_id, eligible.id,
      row_number() over (order by eligible.created_at, eligible.id)::integer
    from (
      select c.id, c.created_at
      from public.cards c
      left join public.card_progress p on p.user_id = c.user_id and p.card_id = c.id
      where c.user_id = v_user_id and c.topic_id = p_topic_id and c.deleted_at is null
        and (
          (p_mode = 'spaced' and (p.card_id is null or p.status = 'new' or p.next_review_at <= v_now))
          or (p_mode = 'mistakes' and p.total_incorrect > 0)
        )
    ) eligible;
  end if;
  return v_session_id;
end;
$$;

create function public.next_training_attempt(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_session public.training_sessions%rowtype;
  v_attempt public.training_attempts%rowtype;
  v_card public.cards%rowtype;
  v_last_card uuid;
  v_card_id uuid;
  v_total integer;
  v_answered integer;
  v_correct integer;
  v_incorrect integer;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_session_id is null then raise exception 'Session ID required' using errcode = '22023'; end if;
  select * into v_session from public.training_sessions
    where id = p_session_id and user_id = v_user_id for update;
  if not found or v_session.status <> 'active' then
    raise exception 'Active training session not found' using errcode = '22023';
  end if;
  perform 1 from public.topics where id = v_session.topic_id
    and user_id = v_user_id and deleted_at is null for share;
  if not found then raise exception 'Active topic not found' using errcode = '22023'; end if;

  select * into v_attempt from public.training_attempts
    where user_id = v_user_id and session_id = p_session_id and status = 'issued'
    for update;
  if not found then
    if v_session.mode = 'infinite' then
      select card_id into v_last_card from public.training_attempts
        where user_id = v_user_id and session_id = p_session_id
        order by position desc limit 1;
      select c.id into v_card_id from public.cards c
        where c.user_id = v_user_id and c.topic_id = v_session.topic_id and c.deleted_at is null
        order by
          case when c.id = v_last_card then 1 else 0 end,
          (select count(*) from public.training_attempts a
            where a.user_id = v_user_id and a.session_id = p_session_id and a.card_id = c.id),
          c.created_at, c.id
        limit 1;
      if v_card_id is not null then
        insert into public.training_attempts (user_id, session_id, card_id, position, status, issued_at)
        values (
          v_user_id, p_session_id, v_card_id,
          (select count(*)::integer + 1 from public.training_attempts where session_id = p_session_id),
          'issued', clock_timestamp()
        ) returning * into v_attempt;
      end if;
    else
      update public.training_attempts a set status = 'skipped'
        where a.user_id = v_user_id and a.session_id = p_session_id and a.status = 'queued'
          and not exists (
            select 1 from public.cards c
              where c.id = a.card_id and c.user_id = v_user_id
                and c.topic_id = v_session.topic_id and c.deleted_at is null
          );
      select * into v_attempt from public.training_attempts
        where user_id = v_user_id and session_id = p_session_id and status = 'queued'
        order by position limit 1 for update;
      if found then
        update public.training_attempts set status = 'issued', issued_at = clock_timestamp()
          where id = v_attempt.id returning * into v_attempt;
      end if;
    end if;
  end if;

  select count(*)::integer, count(*) filter (where status = 'answered')::integer
    into v_total, v_answered from public.training_attempts
    where user_id = v_user_id and session_id = p_session_id and status <> 'skipped';
  select count(*) filter (where is_correct)::integer,
         count(*) filter (where not is_correct)::integer
    into v_correct, v_incorrect from public.answer_history
    where user_id = v_user_id and session_id = p_session_id;

  if v_attempt.id is not null then
    select * into v_card from public.cards
      where id = v_attempt.card_id and user_id = v_user_id
        and topic_id = v_session.topic_id and deleted_at is null for share;
    if not found then
      update public.training_attempts set status = 'skipped'
        where id = v_attempt.id and user_id = v_user_id;
      return public.next_training_attempt(p_session_id);
    end if;
  end if;

  return jsonb_build_object(
    'session_id', p_session_id, 'mode', v_session.mode,
    'total', case when v_session.mode = 'infinite' then null else v_total end,
    'viewed', v_answered, 'correct', v_correct, 'incorrect', v_incorrect,
    'attempt', case when v_attempt.id is null then null else jsonb_build_object(
      'attempt_id', v_attempt.id, 'position', v_attempt.position,
      'issued_at', v_attempt.issued_at,
      'card', jsonb_build_object(
        'id', v_card.id, 'category', v_card.category, 'question', v_card.question,
        'context', v_card.context, 'answer', v_card.answer,
        'hint_1', v_card.hint_1, 'hint_2', v_card.hint_2,
        'difficulty', v_card.difficulty, 'code', v_card.code
      )
    ) end
  );
end;
$$;

create function public.finish_training_session(p_session_id uuid, p_status text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_user_id uuid := auth.uid(); v_session public.training_sessions%rowtype;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_session_id is null or p_status is null or p_status not in ('completed', 'abandoned') then
    raise exception 'Invalid session completion' using errcode = '22023';
  end if;
  select * into v_session from public.training_sessions
    where id = p_session_id and user_id = v_user_id for update;
  if not found then raise exception 'Training session not found' using errcode = '22023'; end if;
  if v_session.status = p_status then return p_session_id; end if;
  if v_session.status <> 'active' then
    raise exception 'Session already closed' using errcode = '22023';
  end if;
  update public.training_attempts set status = 'skipped'
    where user_id = v_user_id and session_id = p_session_id and status in ('queued', 'issued');
  update public.training_sessions set status = p_status, finished_at = clock_timestamp()
    where id = p_session_id and user_id = v_user_id;
  return p_session_id;
end;
$$;

create function public.get_training_stats()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_total integer;
  v_correct integer;
  v_incorrect integer;
  v_learning integer;
  v_mastered integer;
  v_due integer;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  select count(*)::integer,
         count(*) filter (where h.is_correct)::integer,
         count(*) filter (where not h.is_correct)::integer
    into v_total, v_correct, v_incorrect
    from public.answer_history h
    join public.cards c on c.id = h.card_id and c.user_id = v_user_id and c.deleted_at is null
    join public.topics t on t.id = c.topic_id and t.user_id = v_user_id and t.deleted_at is null
    where h.user_id = v_user_id;
  select count(*) filter (where p.status = 'learning')::integer,
         count(*) filter (where p.status = 'mastered')::integer,
         count(*) filter (
           where p.card_id is null or p.status = 'new' or p.next_review_at <= clock_timestamp()
         )::integer
    into v_learning, v_mastered, v_due
    from public.cards c
    join public.topics t on t.id = c.topic_id and t.user_id = v_user_id and t.deleted_at is null
    left join public.card_progress p on p.card_id = c.id and p.user_id = v_user_id
    where c.user_id = v_user_id and c.deleted_at is null;
  return jsonb_build_object(
    'answers', v_total, 'correct', v_correct, 'incorrect', v_incorrect,
    'learning', v_learning, 'mastered', v_mastered, 'due', v_due
  );
end;
$$;

revoke all on function
  public.record_answer(uuid,uuid,uuid,boolean,integer,integer),
  public.record_answer(uuid,uuid,uuid,boolean,integer,integer,uuid),
  public.start_training_session(uuid,text),
  public.next_training_attempt(uuid),
  public.finish_training_session(uuid,text),
  public.get_training_stats()
from public, anon, authenticated;
grant execute on function
  public.record_answer(uuid,uuid,uuid,boolean,integer,integer),
  public.record_answer(uuid,uuid,uuid,boolean,integer,integer,uuid),
  public.start_training_session(uuid,text),
  public.next_training_attempt(uuid),
  public.finish_training_session(uuid,text),
  public.get_training_stats()
to authenticated;

commit;
