-- Multiple section selection; historical RPC signature and session index stay unchanged.
begin;

create or replace function app_private.card_matches_training_scope(
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
        when 'multi' then exists (
          select 1 from jsonb_array_elements_text((p_settings ->> 'section')::jsonb) selected(name)
          where selected.name = coalesce(nullif(btrim(p_section), ''), '')
        )
        else false
      end
    ) and app_private.card_matches_training_filters(p_category, p_difficulty, p_settings),
    false
  );
$$;
revoke all on function app_private.card_matches_training_scope(text,text,text,jsonb)
  from public, anon, authenticated;

create or replace function public.start_section_training_session(
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
  v_sections jsonb;
  v_category text;
  v_settings jsonb;
  v_existing public.training_sessions%rowtype;
  v_session_id uuid;
  v_now timestamptz := clock_timestamp();
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_topic_id is null or p_mode is null or p_mode not in ('spaced', 'infinite', 'mistakes')
     or p_section_mode is null or p_section_mode not in ('all', 'named', 'unsectioned', 'multi')
     or p_category_mode is null or p_category_mode not in ('all', 'named', 'uncategorized')
     or (p_difficulty is not null and p_difficulty not in ('easy', 'medium', 'hard')) then
    raise exception 'Invalid training filters' using errcode = '22023';
  end if;
  if p_section_mode = 'named' then
    v_section := nullif(btrim(p_section), '');
    if v_section is null or char_length(v_section) > 160 then
      raise exception 'Invalid training section' using errcode = '22023';
    end if;
  elsif p_section_mode = 'multi' then
    if p_section is null or char_length(p_section) > 12000 then
      raise exception 'Invalid training sections' using errcode = '22023';
    end if;
    begin
      v_sections := p_section::jsonb;
    exception when invalid_text_representation then
      raise exception 'Invalid training sections' using errcode = '22023';
    end;
    if jsonb_typeof(v_sections) <> 'array' then
      raise exception 'Invalid training sections' using errcode = '22023';
    end if;
    if jsonb_array_length(v_sections) not between 2 and 64 or exists (
         select 1 from jsonb_array_elements(v_sections) item
         where jsonb_typeof(item.value) <> 'string'
           or char_length(btrim(item.value #>> '{}')) > 160
       ) then
      raise exception 'Invalid training sections' using errcode = '22023';
    end if;
    select jsonb_agg(name order by name)::text into v_section
      from (select distinct btrim(value) as name
        from jsonb_array_elements_text(v_sections) value) normalized;
    if jsonb_array_length(v_section::jsonb) < 2 then
      raise exception 'Select at least two distinct sections' using errcode = '22023';
    end if;
  elsif p_section is not null then
    raise exception 'Section value requires named or multi mode' using errcode = '22023';
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
  if p_section_mode in ('named', 'unsectioned') then
    perform 1 from public.cards c
      where c.user_id = v_user_id and c.topic_id = p_topic_id and c.deleted_at is null
        and ((p_section_mode = 'named' and btrim(c.section) = v_section)
          or (p_section_mode = 'unsectioned' and nullif(btrim(c.section), '') is null))
      limit 1;
    if not found then raise exception 'Active section not found' using errcode = '22023'; end if;
  end if;
  if p_section_mode = 'multi' and exists (
    select 1 from jsonb_array_elements_text(v_section::jsonb) selected(name)
    where not exists (
      select 1 from public.cards c
      where c.user_id = v_user_id and c.topic_id = p_topic_id and c.deleted_at is null
        and coalesce(nullif(btrim(c.section), ''), '') = selected.name
    )
  ) then
    raise exception 'Active section not found' using errcode = '22023';
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

revoke all on function public.start_section_training_session(uuid,text,text,text,text,text,text)
  from public, anon;
grant execute on function public.start_section_training_session(uuid,text,text,text,text,text,text)
  to authenticated;

commit;
