-- Stage 4.5: topic -> section -> category -> card. Existing cards remain unsectioned.
-- Old public RPC names and signatures remain available; the new start RPC has
-- a distinct name to avoid ambiguous PostgreSQL/PostgREST overload resolution.
begin;

alter table public.cards add column section text;
alter table public.cards add constraint cards_section_length
  check (section is null or char_length(section) <= 160);
revoke update (section) on table public.cards from authenticated;

create index cards_owner_topic_section_category_difficulty_active_idx
  on public.cards (user_id, topic_id, btrim(section), btrim(category), difficulty, created_at)
  where deleted_at is null;

-- Normalized settings treat older sessions, which lack section keys, as all sections.
create or replace function app_private.normalized_training_filters(p_settings jsonb)
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'section_mode', coalesce(p_settings ->> 'section_mode', 'all'),
    'section', p_settings ->> 'section',
    'category_mode', coalesce(p_settings ->> 'category_mode', 'all'),
    'category', p_settings ->> 'category',
    'difficulty', p_settings ->> 'difficulty'
  );
$$;

create function app_private.card_matches_training_scope(
  p_section text,
  p_category text,
  p_difficulty text,
  p_settings jsonb
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select coalesce(
    (
      case coalesce(p_settings ->> 'section_mode', 'all')
        when 'all' then true
        when 'unsectioned' then nullif(btrim(p_section), '') is null
        when 'named' then btrim(p_section) = (p_settings ->> 'section')
        else false
      end
    ) and app_private.card_matches_training_filters(p_category, p_difficulty, p_settings),
    false
  );
$$;
revoke all on function app_private.card_matches_training_scope(text,text,text,jsonb)
  from public, anon, authenticated;

-- The existing answer RPC inserts into answer_history. This trigger extends
-- its validation without changing either record_answer signature or interval logic.
create or replace function app_private.require_answer_training_filters()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_settings jsonb;
  v_section text;
  v_category text;
  v_difficulty text;
begin
  select settings into v_settings from public.training_sessions
    where id = new.session_id and user_id = new.user_id;
  select section, category, difficulty into v_section, v_category, v_difficulty
    from public.cards where id = new.card_id and user_id = new.user_id;
  if v_settings is null or not app_private.card_matches_training_scope(
    v_section, v_category, v_difficulty, v_settings
  ) then
    raise exception 'Card no longer matches session filters' using errcode = '22023';
  end if;
  return new;
end;
$$;

create function public.start_section_training_session(
  p_topic_id uuid,
  p_mode text,
  p_section_mode text,
  p_section text,
  p_category_mode text,
  p_category text,
  p_difficulty text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_section text;
  v_category text;
  v_settings jsonb;
  v_existing public.training_sessions%rowtype;
  v_session_id uuid;
  v_now timestamptz := clock_timestamp();
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_topic_id is null or p_mode is null or p_mode not in ('spaced', 'infinite', 'mistakes')
     or p_section_mode is null or p_section_mode not in ('all', 'named', 'unsectioned')
     or p_category_mode is null or p_category_mode not in ('all', 'named', 'uncategorized')
     or (p_difficulty is not null and p_difficulty not in ('easy', 'medium', 'hard')) then
    raise exception 'Invalid training filters' using errcode = '22023';
  end if;
  if p_section_mode = 'named' then
    v_section := nullif(btrim(p_section), '');
    if v_section is null or char_length(v_section) > 160 then
      raise exception 'Invalid training section' using errcode = '22023';
    end if;
  elsif p_section is not null then
    raise exception 'Section value requires named mode' using errcode = '22023';
  end if;
  if p_category_mode = 'named' then
    v_category := nullif(btrim(p_category), '');
    if v_category is null or char_length(v_category) > 160 then
      raise exception 'Invalid training category' using errcode = '22023';
    end if;
  elsif p_category is not null then
    raise exception 'Category value requires named mode' using errcode = '22023';
  end if;
  v_settings := jsonb_build_object(
    'section_mode', p_section_mode, 'section', v_section,
    'category_mode', p_category_mode, 'category', v_category,
    'difficulty', p_difficulty
  );

  perform 1 from public.topics
    where id = p_topic_id and user_id = v_user_id and deleted_at is null for share;
  if not found then raise exception 'Active topic not found' using errcode = '22023'; end if;

  select * into v_existing from public.training_sessions
    where user_id = v_user_id and topic_id = p_topic_id
      and mode = p_mode and status = 'active' for update;
  if found then
    return jsonb_build_object(
      'session_id', v_existing.id,
      'filters', app_private.normalized_training_filters(v_existing.settings),
      'conflict', app_private.normalized_training_filters(v_existing.settings) <> v_settings
    );
  end if;

  -- The selected section and group must exist among this owner's active cards.
  -- Difficulty may leave a valid scope with no eligible cards.
  if p_section_mode <> 'all' then
    perform 1 from public.cards c
      where c.user_id = v_user_id and c.topic_id = p_topic_id and c.deleted_at is null
        and ((p_section_mode = 'named' and btrim(c.section) = v_section)
          or (p_section_mode = 'unsectioned' and nullif(btrim(c.section), '') is null))
      limit 1;
    if not found then raise exception 'Active section not found' using errcode = '22023'; end if;
  end if;
  if p_category_mode <> 'all' then
    perform 1 from public.cards c
      where c.user_id = v_user_id and c.topic_id = p_topic_id and c.deleted_at is null
        and app_private.card_matches_training_scope(c.section, c.category, c.difficulty,
          v_settings - 'difficulty')
      limit 1;
    if not found then raise exception 'Active category not found' using errcode = '22023'; end if;
  end if;

  insert into public.training_sessions (user_id, topic_id, mode, settings, started_at)
    values (v_user_id, p_topic_id, p_mode, v_settings, v_now)
    on conflict (user_id, topic_id, mode)
      where status = 'active' and topic_id is not null
      do nothing returning id into v_session_id;
  if v_session_id is null then
    select * into v_existing from public.training_sessions
      where user_id = v_user_id and topic_id = p_topic_id
        and mode = p_mode and status = 'active' for update;
    if not found then raise exception 'Concurrent session start; retry' using errcode = '40001'; end if;
    return jsonb_build_object(
      'session_id', v_existing.id,
      'filters', app_private.normalized_training_filters(v_existing.settings),
      'conflict', app_private.normalized_training_filters(v_existing.settings) <> v_settings
    );
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
        and app_private.card_matches_training_scope(c.section, c.category, c.difficulty, v_settings)
        and (
          (p_mode = 'spaced' and (p.card_id is null or p.status = 'new' or p.next_review_at <= v_now))
          or (p_mode = 'mistakes' and p.total_incorrect > 0)
        )
    ) eligible;
  end if;
  return jsonb_build_object('session_id', v_session_id, 'filters', v_settings, 'conflict', false);
end;
$$;

-- Exact historical signature delegates to the new operation with all sections.
create or replace function public.start_filtered_training_session(
  p_topic_id uuid,
  p_mode text,
  p_category_mode text,
  p_category text,
  p_difficulty text
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select public.start_section_training_session(
    p_topic_id, p_mode, 'all', null, p_category_mode, p_category, p_difficulty
  );
$$;

create or replace function public.next_training_attempt(p_session_id uuid)
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
        where c.user_id = v_user_id and c.topic_id = v_session.topic_id
          and c.deleted_at is null
          and app_private.card_matches_training_scope(c.section, c.category, c.difficulty, v_session.settings)
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
                and app_private.card_matches_training_scope(c.section, c.category, c.difficulty, v_session.settings)
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

  if v_attempt.id is not null then
    select * into v_card from public.cards
      where id = v_attempt.card_id and user_id = v_user_id
        and topic_id = v_session.topic_id and deleted_at is null
        and app_private.card_matches_training_scope(section, category, difficulty, v_session.settings)
      for share;
    if not found then
      update public.training_attempts set status = 'skipped'
        where id = v_attempt.id and user_id = v_user_id;
      return public.next_training_attempt(p_session_id);
    end if;
  end if;

  select count(*)::integer, count(*) filter (where status = 'answered')::integer
    into v_total, v_answered from public.training_attempts
    where user_id = v_user_id and session_id = p_session_id and status <> 'skipped';
  select count(*) filter (where is_correct)::integer,
         count(*) filter (where not is_correct)::integer
    into v_correct, v_incorrect from public.answer_history
    where user_id = v_user_id and session_id = p_session_id;

  return jsonb_build_object(
    'session_id', p_session_id, 'mode', v_session.mode,
    'filters', app_private.normalized_training_filters(v_session.settings),
    'total', case when v_session.mode = 'infinite' then null else v_total end,
    'viewed', v_answered, 'correct', v_correct, 'incorrect', v_incorrect,
    'attempt', case when v_attempt.id is null then null else jsonb_build_object(
      'attempt_id', v_attempt.id, 'position', v_attempt.position,
      'issued_at', v_attempt.issued_at,
      'card', jsonb_build_object(
        'id', v_card.id, 'section', v_card.section, 'category', v_card.category, 'question', v_card.question,
        'context', v_card.context, 'answer', v_card.answer,
        'hint_1', v_card.hint_1, 'hint_2', v_card.hint_2,
        'difficulty', v_card.difficulty, 'code', v_card.code
      )
    ) end
  );
end;
$$;

revoke all on function public.start_section_training_session(uuid,text,text,text,text,text,text)
  from public, anon, authenticated;
grant execute on function public.start_section_training_session(uuid,text,text,text,text,text,text)
  to authenticated;

notify pgrst, 'reload schema';
commit;
