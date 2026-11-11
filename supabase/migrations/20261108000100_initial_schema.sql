-- Knowledge Cards: owner-scoped schema. Apply with Supabase migrations.
create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;

create function app_private.touch_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Row locks serialize creation/restoration with concurrent soft deletion.
create function app_private.require_active_topic_for_card()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.deleted_at is null then
    perform 1 from public.topics t
      where t.user_id = new.user_id and t.id = new.topic_id and t.deleted_at is null
      for share;
    if not found then
      raise exception 'Active topic required for card' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create function app_private.require_active_topic_for_session()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.status = 'active' and new.topic_id is not null then
    perform 1 from public.topics t
      where t.user_id = new.user_id and t.id = new.topic_id and t.deleted_at is null
      for share;
    if not found then
      raise exception 'Active topic required for session' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create function app_private.require_active_card()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform 1 from public.cards c
    join public.topics t on t.user_id = c.user_id and t.id = c.topic_id
    where c.user_id = new.user_id and c.id = new.card_id
      and c.deleted_at is null and t.deleted_at is null
    for share of c, t;
  if not found then
    raise exception 'Active card and topic required' using errcode = '23514';
  end if;
  return new;
end;
$$;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete restrict,
  display_name text,
  timezone text not null default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length check (display_name is null or char_length(display_name) <= 120),
  constraint profiles_timezone_length check (char_length(timezone) between 1 and 100)
);

create table public.topics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  title text not null,
  description text,
  color text not null default 'green',
  icon text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint topics_owner_id_unique unique (user_id, id),
  constraint topics_title_valid check (char_length(btrim(title)) between 1 and 120),
  constraint topics_description_length check (description is null or char_length(description) <= 240),
  constraint topics_color_valid check (color in ('green', 'blue', 'amber')),
  constraint topics_icon_length check (icon is null or char_length(icon) <= 100)
);

create table public.cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  topic_id uuid not null,
  category text,
  question text not null,
  context text,
  answer text not null,
  hint_1 text,
  hint_2 text,
  difficulty text not null default 'medium',
  code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint cards_owner_id_unique unique (user_id, id),
  constraint cards_topic_owner_fk foreign key (user_id, topic_id) references public.topics(user_id, id) on delete restrict,
  constraint cards_question_not_blank check (char_length(btrim(question)) > 0),
  constraint cards_answer_not_blank check (char_length(btrim(answer)) > 0),
  constraint cards_difficulty_valid check (difficulty in ('easy', 'medium', 'hard')),
  constraint cards_category_length check (category is null or char_length(category) <= 160)
);

create table public.card_progress (
  user_id uuid not null references auth.users(id) on delete restrict,
  card_id uuid not null,
  consecutive_correct integer not null default 0,
  total_correct integer not null default 0,
  total_incorrect integer not null default 0,
  status text not null default 'new',
  last_reviewed_at timestamptz,
  next_review_at timestamptz,
  mastered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, card_id),
  constraint card_progress_card_owner_fk foreign key (user_id, card_id) references public.cards(user_id, id) on delete restrict,
  constraint card_progress_counts_valid check (consecutive_correct >= 0 and total_correct >= 0 and total_incorrect >= 0),
  constraint card_progress_status_valid check (status in ('new', 'learning', 'mastered'))
);

create table public.training_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  topic_id uuid,
  mode text not null,
  status text not null default 'active',
  settings jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  completion_xp integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint training_sessions_owner_id_unique unique (user_id, id),
  constraint training_sessions_topic_owner_fk foreign key (user_id, topic_id) references public.topics(user_id, id) on delete restrict,
  constraint training_sessions_mode_valid check (mode in ('spaced', 'infinite', 'mistakes')),
  constraint training_sessions_status_valid check (status in ('active', 'completed', 'abandoned')),
  constraint training_sessions_settings_object check (jsonb_typeof(settings) = 'object'),
  constraint training_sessions_completion_xp_valid check (completion_xp >= 0),
  constraint training_sessions_finish_valid check (finished_at is null or finished_at >= started_at)
);

create table public.answer_history (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete restrict,
  card_id uuid not null,
  session_id uuid not null,
  mode text not null,
  is_correct boolean not null,
  hints_used smallint not null,
  answer_duration_ms integer,
  xp_awarded integer not null default 0,
  answered_at timestamptz not null default now(),
  constraint answer_history_card_owner_fk foreign key (user_id, card_id) references public.cards(user_id, id) on delete restrict,
  constraint answer_history_session_owner_fk foreign key (user_id, session_id) references public.training_sessions(user_id, id) on delete restrict,
  constraint answer_history_mode_valid check (mode in ('spaced', 'infinite', 'mistakes')),
  constraint answer_history_hints_valid check (hints_used between 0 and 2),
  constraint answer_history_duration_valid check (answer_duration_ms is null or answer_duration_ms >= 0),
  constraint answer_history_xp_valid check (xp_awarded >= 0)
);

create table public.user_achievements (
  user_id uuid not null references auth.users(id) on delete restrict,
  code text not null,
  unlocked_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  primary key (user_id, code),
  constraint user_achievements_code_valid check (char_length(btrim(code)) between 1 and 80)
);

create index topics_owner_active_order_idx on public.topics (user_id, sort_order, created_at) where deleted_at is null;
create index cards_owner_topic_active_idx on public.cards (user_id, topic_id, created_at) where deleted_at is null;
create index card_progress_owner_due_idx on public.card_progress (user_id, next_review_at) where next_review_at is not null;
create index training_sessions_owner_started_idx on public.training_sessions (user_id, started_at desc);
create index answer_history_owner_answered_idx on public.answer_history (user_id, answered_at desc);
create index answer_history_owner_card_answered_idx on public.answer_history (user_id, card_id, answered_at desc);
create index answer_history_owner_session_idx on public.answer_history (user_id, session_id);
create index user_achievements_owner_unlocked_idx on public.user_achievements (user_id, unlocked_at desc);

create trigger profiles_updated_at before update on public.profiles for each row execute function app_private.touch_updated_at();
create trigger topics_updated_at before update on public.topics for each row execute function app_private.touch_updated_at();
create trigger cards_updated_at before update on public.cards for each row execute function app_private.touch_updated_at();
create trigger card_progress_updated_at before update on public.card_progress for each row execute function app_private.touch_updated_at();
create trigger training_sessions_updated_at before update on public.training_sessions for each row execute function app_private.touch_updated_at();
create trigger cards_require_active_topic before insert or update of user_id, topic_id, deleted_at on public.cards
  for each row execute function app_private.require_active_topic_for_card();
create trigger sessions_require_active_topic before insert or update of user_id, topic_id, status on public.training_sessions
  for each row execute function app_private.require_active_topic_for_session();
create trigger progress_require_active_card before insert or update on public.card_progress
  for each row execute function app_private.require_active_card();
create trigger answers_require_active_card before insert on public.answer_history
  for each row execute function app_private.require_active_card();

alter table public.profiles enable row level security;
alter table public.topics enable row level security;
alter table public.cards enable row level security;
alter table public.card_progress enable row level security;
alter table public.training_sessions enable row level security;
alter table public.answer_history enable row level security;
alter table public.user_achievements enable row level security;

revoke all on table public.profiles, public.topics, public.cards, public.card_progress,
  public.training_sessions, public.answer_history, public.user_achievements from public, anon, authenticated;

grant select on table public.profiles, public.topics, public.cards, public.card_progress,
  public.training_sessions, public.answer_history, public.user_achievements to authenticated;
grant insert on table public.profiles, public.topics, public.cards to authenticated;
grant update (display_name, timezone) on table public.profiles to authenticated;
grant update (title, description, color, icon, sort_order) on table public.topics to authenticated;
grant update (topic_id, category, question, context, answer, hint_1, hint_2, difficulty, code) on table public.cards to authenticated;

create policy profiles_select_owner on public.profiles for select to authenticated using ((select auth.uid()) = user_id);
create policy profiles_insert_owner on public.profiles for insert to authenticated with check ((select auth.uid()) = user_id);
create policy profiles_update_owner on public.profiles for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy topics_select_owner on public.topics for select to authenticated using ((select auth.uid()) = user_id);
create policy topics_insert_owner on public.topics for insert to authenticated with check ((select auth.uid()) = user_id);
create policy topics_update_owner on public.topics for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy cards_select_owner on public.cards for select to authenticated using ((select auth.uid()) = user_id);
create policy cards_insert_owner on public.cards for insert to authenticated with check ((select auth.uid()) = user_id);
create policy cards_update_owner on public.cards for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy card_progress_select_owner on public.card_progress for select to authenticated using ((select auth.uid()) = user_id);
create policy training_sessions_select_owner on public.training_sessions for select to authenticated using ((select auth.uid()) = user_id);
create policy answer_history_select_owner on public.answer_history for select to authenticated using ((select auth.uid()) = user_id);
create policy user_achievements_select_owner on public.user_achievements for select to authenticated using ((select auth.uid()) = user_id);

-- Progress, sessions, answer history, and awards are read-only to browser roles.
-- Stage 2 will add narrowly scoped write RPCs; never expose direct client writes.

-- Soft deletion and restoration have their own owner-checked operations. A
-- restored topic makes its non-deleted cards available again; cards deleted
-- individually must be restored separately after their topic is active.
create function public.soft_delete_topic(p_topic_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user_id uuid := auth.uid(); v_id uuid;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  update public.topics set deleted_at = clock_timestamp()
    where user_id = v_user_id and id = p_topic_id and deleted_at is null
    returning id into v_id;
  if v_id is null then
    select id into v_id from public.topics where user_id = v_user_id and id = p_topic_id;
  end if;
  if v_id is null then raise exception 'Topic not found' using errcode = 'P0002'; end if;
  return v_id;
end;
$$;

create function public.restore_topic(p_topic_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user_id uuid := auth.uid(); v_id uuid;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  update public.topics set deleted_at = null
    where user_id = v_user_id and id = p_topic_id and deleted_at is not null
    returning id into v_id;
  if v_id is null then
    select id into v_id from public.topics where user_id = v_user_id and id = p_topic_id;
  end if;
  if v_id is null then raise exception 'Topic not found' using errcode = 'P0002'; end if;
  return v_id;
end;
$$;

create function public.soft_delete_card(p_card_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user_id uuid := auth.uid(); v_id uuid;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  update public.cards set deleted_at = clock_timestamp()
    where user_id = v_user_id and id = p_card_id and deleted_at is null
    returning id into v_id;
  if v_id is null then
    select id into v_id from public.cards where user_id = v_user_id and id = p_card_id;
  end if;
  if v_id is null then raise exception 'Card not found' using errcode = 'P0002'; end if;
  return v_id;
end;
$$;

create function public.restore_card(p_card_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user_id uuid := auth.uid(); v_id uuid; v_topic_active boolean;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  update public.cards set deleted_at = null
    where user_id = v_user_id and id = p_card_id and deleted_at is not null
    returning id into v_id;
  if v_id is null then
    select c.id, t.deleted_at is null into v_id, v_topic_active
      from public.cards c join public.topics t on t.user_id = c.user_id and t.id = c.topic_id
      where c.user_id = v_user_id and c.id = p_card_id;
    if v_id is not null and not v_topic_active then
      raise exception 'Active topic required for card' using errcode = '23514';
    end if;
  end if;
  if v_id is null then raise exception 'Card not found' using errcode = 'P0002'; end if;
  return v_id;
end;
$$;

revoke all on function public.soft_delete_topic(uuid), public.restore_topic(uuid),
  public.soft_delete_card(uuid), public.restore_card(uuid) from public, anon, authenticated;
grant execute on function public.soft_delete_topic(uuid), public.restore_topic(uuid),
  public.soft_delete_card(uuid), public.restore_card(uuid) to authenticated;
