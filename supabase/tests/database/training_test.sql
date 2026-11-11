begin;
create extension if not exists pgtap with schema extensions;
select plan(40);

insert into auth.users (id, email) values
  ('11000000-0000-4000-8000-000000000021', 'cards-training-owner@example.test'),
  ('11000000-0000-4000-8000-000000000022', 'cards-training-other@example.test');
insert into public.topics (id, user_id, title) values
  ('22000000-0000-4000-8000-000000000021', '11000000-0000-4000-8000-000000000021', 'Training topic'),
  ('22000000-0000-4000-8000-000000000022', '11000000-0000-4000-8000-000000000022', 'Other topic');
insert into public.cards (id, user_id, topic_id, question, answer, hint_1, hint_2) values
  ('33000000-0000-4000-8000-000000000021', '11000000-0000-4000-8000-000000000021', '22000000-0000-4000-8000-000000000021', 'A', 'A', 'Hint one', 'Hint two'),
  ('33000000-0000-4000-8000-000000000022', '11000000-0000-4000-8000-000000000021', '22000000-0000-4000-8000-000000000021', 'B', 'B', null, null),
  ('33000000-0000-4000-8000-000000000023', '11000000-0000-4000-8000-000000000022', '22000000-0000-4000-8000-000000000022', 'Other', 'Other', null, null);

select ok(not has_table_privilege('authenticated', 'public.training_attempts', 'INSERT'), 'browser cannot create attempts');
select ok(not has_table_privilege('authenticated', 'public.training_attempts', 'UPDATE'), 'browser cannot update attempts');
select ok(not has_table_privilege('authenticated', 'public.training_sessions', 'INSERT'), 'browser cannot insert sessions');
select ok(not has_table_privilege('authenticated', 'public.answer_history', 'INSERT'), 'browser cannot insert answers');
select ok(not has_table_privilege('authenticated', 'public.card_progress', 'UPDATE'), 'browser cannot update progress');
select ok(not has_table_privilege('authenticated', 'public.user_achievements', 'INSERT'), 'browser cannot award achievements');
select ok(not has_function_privilege('anon', 'public.start_training_session(uuid,text)', 'EXECUTE'), 'anon cannot start training');
select ok(has_function_privilege('authenticated', 'public.record_answer(uuid,uuid,uuid,boolean,integer,integer,uuid)', 'EXECUTE'), 'authenticated can call guarded answer RPC');

select set_config('request.jwt.claim.sub', '11000000-0000-4000-8000-000000000021', true);
select set_config('test.session', public.start_training_session('22000000-0000-4000-8000-000000000021', 'spaced')::text, true);
select is(public.start_training_session('22000000-0000-4000-8000-000000000021', 'spaced')::text,
  current_setting('test.session'), 'start resumes existing active session');
select throws_ok(
  $$select public.record_answer('66000000-0000-4000-8000-000000000029',
    current_setting('test.session')::uuid, '33000000-0000-4000-8000-000000000021',
    true, 0, null, (select id from public.training_attempts
      where session_id = current_setting('test.session')::uuid order by position limit 1))$$,
  '22023', 'Active issued attempt required', 'queued card cannot be answered before issuance');
select set_config('test.empty_mistakes', public.start_training_session('22000000-0000-4000-8000-000000000021', 'mistakes')::text, true);
select is((public.next_training_attempt(current_setting('test.empty_mistakes')::uuid) ->> 'total')::integer,
  0, 'mistakes is empty before any spaced errors');
select public.finish_training_session(current_setting('test.empty_mistakes')::uuid, 'completed');
select set_config('test.first', public.next_training_attempt(current_setting('test.session')::uuid)::text, true);
select is((current_setting('test.first')::jsonb ->> 'total')::integer, 2, 'spaced snapshots two new cards');
select is((public.next_training_attempt(current_setting('test.session')::uuid) -> 'attempt' ->> 'attempt_id'),
  (current_setting('test.first')::jsonb -> 'attempt' ->> 'attempt_id'), 'next is idempotent while attempt is issued');
select throws_ok(
  $$select public.record_answer('66000000-0000-4000-8000-000000000021',
    current_setting('test.session')::uuid, '33000000-0000-4000-8000-000000000022',
    true, 0, null, (current_setting('test.first')::jsonb -> 'attempt' ->> 'attempt_id')::uuid)$$,
  '22023', 'Attempt not found', 'cannot answer a card other than the issued one');
select is(public.record_answer(
  '66000000-0000-4000-8000-000000000021', current_setting('test.session')::uuid,
  '33000000-0000-4000-8000-000000000021', true, 1, 1000,
  (current_setting('test.first')::jsonb -> 'attempt' ->> 'attempt_id')::uuid),
  '66000000-0000-4000-8000-000000000021'::uuid, 'spaced answer stored');
select is(public.record_answer(
  '66000000-0000-4000-8000-000000000021', current_setting('test.session')::uuid,
  '33000000-0000-4000-8000-000000000021', true, 1, 1000,
  (current_setting('test.first')::jsonb -> 'attempt' ->> 'attempt_id')::uuid),
  '66000000-0000-4000-8000-000000000021'::uuid, 'exact retry returns same event');
select throws_ok(
  $$select public.record_answer('66000000-0000-4000-8000-000000000024',
    current_setting('test.session')::uuid, '33000000-0000-4000-8000-000000000021',
    true, 1, 1000, (current_setting('test.first')::jsonb -> 'attempt' ->> 'attempt_id')::uuid)$$,
  '23505', 'Attempt already answered', 'different event UUID cannot answer same attempt');
select ok((select next_review_at = last_reviewed_at + interval '1 day'
  from public.card_progress where card_id = '33000000-0000-4000-8000-000000000021'), 'first correct interval is one day');

select set_config('test.second', public.next_training_attempt(current_setting('test.session')::uuid)::text, true);
select is((current_setting('test.second')::jsonb -> 'attempt' -> 'card' ->> 'id'),
  '33000000-0000-4000-8000-000000000022', 'finite session moves to next card');
select public.record_answer(
  '66000000-0000-4000-8000-000000000022', current_setting('test.session')::uuid,
  '33000000-0000-4000-8000-000000000022', false, 0, null,
  (current_setting('test.second')::jsonb -> 'attempt' ->> 'attempt_id')::uuid);
select ok((select status = 'learning' and consecutive_correct = 0 and total_incorrect = 1
    and next_review_at = last_reviewed_at + interval '10 minutes'
  from public.card_progress where card_id = '33000000-0000-4000-8000-000000000022'), 'incorrect answer schedules ten minutes');
select is((public.next_training_attempt(current_setting('test.session')::uuid) ->> 'total')::integer,
  2, 'spaced does not immediately requeue incorrect card');
select public.finish_training_session(current_setting('test.session')::uuid, 'completed');
select set_config('test.not_due', public.start_training_session('22000000-0000-4000-8000-000000000021', 'spaced')::text, true);
select is((public.next_training_attempt(current_setting('test.not_due')::uuid) ->> 'total')::integer,
  0, 'spaced excludes cards whose next review is in the future');
select public.finish_training_session(current_setting('test.not_due')::uuid, 'completed');
select is(public.record_answer(
  '66000000-0000-4000-8000-000000000021', current_setting('test.session')::uuid,
  '33000000-0000-4000-8000-000000000021', true, 1, 1000,
  (current_setting('test.first')::jsonb -> 'attempt' ->> 'attempt_id')::uuid),
  '66000000-0000-4000-8000-000000000021'::uuid, 'exact retry works after completion');

select set_config('test.mistakes', public.start_training_session('22000000-0000-4000-8000-000000000021', 'mistakes')::text, true);
select set_config('test.mistake_attempt', public.next_training_attempt(current_setting('test.mistakes')::uuid)::text, true);
select is((current_setting('test.mistake_attempt')::jsonb ->> 'total')::integer, 1, 'mistakes snapshots cards with total_incorrect > 0');
select public.record_answer(
  '66000000-0000-4000-8000-000000000023', current_setting('test.mistakes')::uuid,
  '33000000-0000-4000-8000-000000000022', false, 0, null,
  (current_setting('test.mistake_attempt')::jsonb -> 'attempt' ->> 'attempt_id')::uuid);
select ok((select total_incorrect = 1 from public.card_progress
  where card_id = '33000000-0000-4000-8000-000000000022'), 'mistakes answer leaves progress unchanged');
select public.finish_training_session(current_setting('test.mistakes')::uuid, 'completed');

select set_config('test.infinite', public.start_training_session('22000000-0000-4000-8000-000000000021', 'infinite')::text, true);
select set_config('test.infinite_first', public.next_training_attempt(current_setting('test.infinite')::uuid)::text, true);
select public.record_answer(
  '66000000-0000-4000-8000-000000000025', current_setting('test.infinite')::uuid,
  (current_setting('test.infinite_first')::jsonb -> 'attempt' -> 'card' ->> 'id')::uuid,
  true, 0, null, (current_setting('test.infinite_first')::jsonb -> 'attempt' ->> 'attempt_id')::uuid);
select set_config('test.infinite_second', public.next_training_attempt(current_setting('test.infinite')::uuid)::text, true);
select isnt((current_setting('test.infinite_first')::jsonb -> 'attempt' -> 'card' ->> 'id'),
  (current_setting('test.infinite_second')::jsonb -> 'attempt' -> 'card' ->> 'id'), 'infinite avoids immediate repeat');
select ok((select total_correct = 1 from public.card_progress
  where card_id = '33000000-0000-4000-8000-000000000021'), 'infinite answer leaves spaced progress unchanged');
select public.finish_training_session(current_setting('test.infinite')::uuid, 'abandoned');
select throws_ok(
  $$select public.record_answer('66000000-0000-4000-8000-000000000026',
    current_setting('test.infinite')::uuid,
    (current_setting('test.infinite_second')::jsonb -> 'attempt' -> 'card' ->> 'id')::uuid,
    true, 0, null, (current_setting('test.infinite_second')::jsonb -> 'attempt' ->> 'attempt_id')::uuid)$$,
  '22023', 'Active issued attempt required', 'new answer rejected after cancellation');

-- Force due dates only inside this rolled-back local test transaction.
do $intervals$
declare
  v_session uuid;
  v_attempt jsonb;
  v_expected interval;
  v_progress public.card_progress%rowtype;
  i integer;
begin
  for i in 2..5 loop
    update public.card_progress set next_review_at = clock_timestamp() - interval '1 second'
      where user_id = '11000000-0000-4000-8000-000000000021'
        and card_id = '33000000-0000-4000-8000-000000000021';
    v_session := public.start_training_session('22000000-0000-4000-8000-000000000021', 'spaced');
    v_attempt := public.next_training_attempt(v_session);
    if v_attempt -> 'attempt' -> 'card' ->> 'id' <> '33000000-0000-4000-8000-000000000021' then
      raise exception 'Expected due card A at streak %', i;
    end if;
    perform public.record_answer(gen_random_uuid(), v_session,
      '33000000-0000-4000-8000-000000000021', true, 0, null,
      (v_attempt -> 'attempt' ->> 'attempt_id')::uuid);
    select * into v_progress from public.card_progress
      where user_id = '11000000-0000-4000-8000-000000000021'
        and card_id = '33000000-0000-4000-8000-000000000021';
    v_expected := case i when 2 then interval '3 days'
      when 3 then interval '7 days' when 4 then interval '14 days'
      else interval '30 days' end;
    if v_progress.consecutive_correct <> i
       or v_progress.next_review_at <> v_progress.last_reviewed_at + v_expected
       or v_progress.status <> (case when i >= 5 then 'mastered' else 'learning' end) then
      raise exception 'Incorrect spaced transition at streak %', i;
    end if;
    perform public.finish_training_session(v_session, 'completed');
  end loop;
end
$intervals$;
select pass('streaks 2–5 schedule 3, 7, 14 and 30 days and reach mastered');
select is((select status from public.card_progress where card_id = '33000000-0000-4000-8000-000000000021'),
  'mastered', 'card reaches mastered');

update public.card_progress set next_review_at = clock_timestamp() - interval '1 second'
  where card_id = '33000000-0000-4000-8000-000000000021';
select set_config('test.reset_session', public.start_training_session('22000000-0000-4000-8000-000000000021', 'spaced')::text, true);
select set_config('test.reset_attempt', public.next_training_attempt(current_setting('test.reset_session')::uuid)::text, true);
select public.record_answer(gen_random_uuid(), current_setting('test.reset_session')::uuid,
  '33000000-0000-4000-8000-000000000021', false, 0, null,
  (current_setting('test.reset_attempt')::jsonb -> 'attempt' ->> 'attempt_id')::uuid);
select ok((select status = 'learning' and consecutive_correct = 0 and total_incorrect = 1
  from public.card_progress where card_id = '33000000-0000-4000-8000-000000000021'), 'wrong answer resets mastered to learning');

insert into public.topics (id, user_id, title)
  values ('22000000-0000-4000-8000-000000000024',
    '11000000-0000-4000-8000-000000000021', 'Empty topic');
select set_config('test.empty_topic', public.start_training_session('22000000-0000-4000-8000-000000000024', 'spaced')::text, true);
select is((public.next_training_attempt(current_setting('test.empty_topic')::uuid) ->> 'total')::integer,
  0, 'empty topic produces no attempt');
select is((public.get_training_stats() ->> 'answers')::integer, 9, 'stats count real answers in active content');
select is((public.get_training_stats() ->> 'learning')::integer, 2, 'stats count learning cards');
select ok((select bool_and(xp_awarded = 0) from public.answer_history
  where user_id = '11000000-0000-4000-8000-000000000021'), 'answers award no XP');
select ok((select bool_and(completion_xp = 0) from public.training_sessions
  where user_id = '11000000-0000-4000-8000-000000000021'), 'sessions award no XP');
update public.cards set deleted_at = clock_timestamp()
  where id = '33000000-0000-4000-8000-000000000022';
select is((public.get_training_stats() ->> 'answers')::integer, 7, 'stats exclude history for deleted card');
select is((public.get_training_stats() ->> 'learning')::integer, 1, 'stats exclude deleted card progress');

set local role authenticated;
set local request.jwt.claim.sub = '11000000-0000-4000-8000-000000000022';
select is((select count(*)::integer from public.training_attempts
  where user_id = '11000000-0000-4000-8000-000000000021'), 0, 'other user cannot read attempts');
select throws_ok(
  $$select public.start_training_session('22000000-0000-4000-8000-000000000021', 'spaced')$$,
  '22023', 'Active topic not found', 'other user cannot start session on owner topic');

select * from finish();
rollback;
