-- Stage 1 contract: atomically record an answer once. XP and scheduling remain
-- untouched until their rules and write path are implemented in a later stage.
create function public.record_answer(
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
  v_session public.training_sessions%rowtype;
  v_card public.cards%rowtype;
  v_existing public.answer_history%rowtype;
  v_inserted_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_event_id is null or p_session_id is null or p_card_id is null
     or p_is_correct is null or p_hints_used is null
     or p_hints_used not between 0 and 2
     or (p_answer_duration_ms is not null and p_answer_duration_ms < 0) then
    raise exception 'Invalid answer payload' using errcode = '22023';
  end if;

  -- Existing event IDs are immutable. This also makes retries safe after a
  -- network timeout, while detecting reuse of an ID with different content.
  select * into v_existing from public.answer_history where id = p_event_id;
  if found then
    if v_existing.user_id = v_user_id
       and v_existing.session_id = p_session_id
       and v_existing.card_id = p_card_id
       and v_existing.is_correct = p_is_correct
       and v_existing.hints_used = p_hints_used
       and v_existing.answer_duration_ms is not distinct from p_answer_duration_ms then
      return p_event_id;
    end if;
    raise exception 'Answer event ID already used' using errcode = '23505';
  end if;

  select * into v_session from public.training_sessions
    where user_id = v_user_id and id = p_session_id for update;
  if not found then
    raise exception 'Active training session not found' using errcode = '22023';
  end if;

  -- A concurrent first request may have committed while this call waited for
  -- the session lock. Check again before rejecting a now-completed session.
  select * into v_existing from public.answer_history where id = p_event_id;
  if found then
    if v_existing.user_id = v_user_id
       and v_existing.session_id = p_session_id
       and v_existing.card_id = p_card_id
       and v_existing.is_correct = p_is_correct
       and v_existing.hints_used = p_hints_used
       and v_existing.answer_duration_ms is not distinct from p_answer_duration_ms then
      return p_event_id;
    end if;
    raise exception 'Answer event ID already used' using errcode = '23505';
  end if;
  if v_session.status <> 'active' then
    raise exception 'Active training session not found' using errcode = '22023';
  end if;

  select * into v_card from public.cards
    where user_id = v_user_id and id = p_card_id and deleted_at is null
    for share;
  if not found then
    raise exception 'Card not found' using errcode = '22023';
  end if;
  perform 1 from public.topics
    where user_id = v_user_id and id = v_card.topic_id and deleted_at is null
    for share;
  if not found then
    raise exception 'Active topic not found' using errcode = '22023';
  end if;
  if v_session.topic_id is not null and v_session.topic_id <> v_card.topic_id then
    raise exception 'Card is outside the training topic' using errcode = '22023';
  end if;
  if (p_hints_used >= 1 and nullif(btrim(v_card.hint_1), '') is null)
     or (p_hints_used = 2 and nullif(btrim(v_card.hint_2), '') is null) then
    raise exception 'Hint count exceeds available hints' using errcode = '22023';
  end if;

  insert into public.answer_history (
    id, user_id, card_id, session_id, mode, is_correct, hints_used, answer_duration_ms
  ) values (
    p_event_id, v_user_id, p_card_id, p_session_id, v_session.mode,
    p_is_correct, p_hints_used, p_answer_duration_ms
  ) on conflict (id) do nothing returning id into v_inserted_id;

  if v_inserted_id is null then
    -- Concurrent retry: the unique index waited for the first transaction.
    select * into v_existing from public.answer_history where id = p_event_id;
    if not found then
      raise exception 'Concurrent answer is not visible; retry the request' using errcode = '40001';
    end if;
    if v_existing.user_id = v_user_id
       and v_existing.session_id = p_session_id
       and v_existing.card_id = p_card_id
       and v_existing.is_correct = p_is_correct
       and v_existing.hints_used = p_hints_used
       and v_existing.answer_duration_ms is not distinct from p_answer_duration_ms then
      return p_event_id;
    end if;
    raise exception 'Answer event ID already used' using errcode = '23505';
  end if;

  return v_inserted_id;
end;
$$;

revoke all on function public.record_answer(uuid, uuid, uuid, boolean, integer, integer) from public, anon, authenticated;
grant execute on function public.record_answer(uuid, uuid, uuid, boolean, integer, integer) to authenticated;
comment on function public.record_answer(uuid, uuid, uuid, boolean, integer, integer)
  is 'Stage 1: idempotent answer history insert only. Does not update XP, progress, or achievements.';
