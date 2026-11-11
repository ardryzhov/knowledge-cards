begin;
create extension if not exists pgtap with schema extensions;
select plan(30);

insert into auth.users (id, email) values
  ('11000000-0000-4000-8000-000000000051', 'filters-owner@example.test'),
  ('11000000-0000-4000-8000-000000000052', 'filters-other@example.test');
insert into public.topics (id, user_id, title) values
  ('22000000-0000-4000-8000-000000000051', '11000000-0000-4000-8000-000000000051', 'Разработка'),
  ('22000000-0000-4000-8000-000000000052', '11000000-0000-4000-8000-000000000051', 'DevOps'),
  ('22000000-0000-4000-8000-000000000053', '11000000-0000-4000-8000-000000000052', 'Other');
insert into public.cards (id, user_id, topic_id, category, question, answer, difficulty) values
  ('33000000-0000-4000-8000-000000000051', '11000000-0000-4000-8000-000000000051', '22000000-0000-4000-8000-000000000051', 'Многопоточность', 'Hard thread', 'A', 'hard'),
  ('33000000-0000-4000-8000-000000000052', '11000000-0000-4000-8000-000000000051', '22000000-0000-4000-8000-000000000051', 'Многопоточность', 'Easy thread', 'A', 'easy'),
  ('33000000-0000-4000-8000-000000000053', '11000000-0000-4000-8000-000000000051', '22000000-0000-4000-8000-000000000051', null, 'Null', 'A', 'medium'),
  ('33000000-0000-4000-8000-000000000054', '11000000-0000-4000-8000-000000000051', '22000000-0000-4000-8000-000000000051', '', 'Empty', 'A', 'medium'),
  ('33000000-0000-4000-8000-000000000055', '11000000-0000-4000-8000-000000000051', '22000000-0000-4000-8000-000000000051', '   ', 'Spaces', 'A', 'medium'),
  ('33000000-0000-4000-8000-000000000056', '11000000-0000-4000-8000-000000000051', '22000000-0000-4000-8000-000000000051', 'C++ / JVM & Kafka', 'Special', 'A', 'hard'),
  ('33000000-0000-4000-8000-000000000057', '11000000-0000-4000-8000-000000000051', '22000000-0000-4000-8000-000000000052', 'Многопоточность', 'Other topic', 'A', 'hard'),
  ('33000000-0000-4000-8000-000000000058', '11000000-0000-4000-8000-000000000052', '22000000-0000-4000-8000-000000000053', 'Многопоточность', 'Other owner', 'A', 'hard');

select ok(has_function_privilege('authenticated', 'public.start_filtered_training_session(uuid,text,text,text,text)', 'EXECUTE'), 'authenticated can start filtered session');
select ok(not has_function_privilege('anon', 'public.start_filtered_training_session(uuid,text,text,text,text)', 'EXECUTE'), 'anonymous cannot start filtered session');
select ok(not has_function_privilege('authenticated', 'app_private.card_matches_training_filters(text,text,jsonb)', 'EXECUTE'), 'private filter helper is not callable by browser');
select ok(not has_table_privilege('authenticated', 'public.training_sessions', 'UPDATE'), 'browser cannot change immutable session settings');

select set_config('request.jwt.claim.sub', '11000000-0000-4000-8000-000000000051', true);
select set_config('test.filtered', public.start_filtered_training_session(
  '22000000-0000-4000-8000-000000000051', 'spaced', 'named', ' Многопоточность ', 'hard')::text, true);
select is(current_setting('test.filtered')::jsonb -> 'filters' ->> 'category', 'Многопоточность', 'named filter is normalized');
select is((public.next_training_attempt((current_setting('test.filtered')::jsonb ->> 'session_id')::uuid) ->> 'total')::integer, 1, 'spaced snapshot applies category, difficulty and topic');
select is((public.start_filtered_training_session('22000000-0000-4000-8000-000000000051', 'spaced', 'named', 'Многопоточность', 'hard') ->> 'conflict')::boolean, false, 'same filters resume without conflict');
select is((public.start_filtered_training_session('22000000-0000-4000-8000-000000000051', 'spaced', 'named', 'Многопоточность', 'easy') ->> 'conflict')::boolean, true, 'different filters return conflict');
select is((public.start_filtered_training_session('22000000-0000-4000-8000-000000000051', 'spaced', 'named', 'Многопоточность', 'easy') ->> 'session_id'), current_setting('test.filtered')::jsonb ->> 'session_id', 'conflicting start keeps one active session');
select set_config('test.attempt', public.next_training_attempt((current_setting('test.filtered')::jsonb ->> 'session_id')::uuid)::text, true);
select throws_ok($$select public.record_answer('66000000-0000-4000-8000-000000000059',
  (current_setting('test.filtered')::jsonb ->> 'session_id')::uuid,
  '33000000-0000-4000-8000-000000000052', true, 0, null,
  (current_setting('test.attempt')::jsonb -> 'attempt' ->> 'attempt_id')::uuid)$$,
  '22023', 'Attempt not found', 'arbitrary card cannot bypass issued filtered attempt');
select is(public.record_answer('66000000-0000-4000-8000-000000000051',
  (current_setting('test.filtered')::jsonb ->> 'session_id')::uuid,
  '33000000-0000-4000-8000-000000000051', true, 0, null,
  (current_setting('test.attempt')::jsonb -> 'attempt' ->> 'attempt_id')::uuid),
  '66000000-0000-4000-8000-000000000051'::uuid, 'filtered answer is stored');
select is(public.record_answer('66000000-0000-4000-8000-000000000051',
  (current_setting('test.filtered')::jsonb ->> 'session_id')::uuid,
  '33000000-0000-4000-8000-000000000051', true, 0, null,
  (current_setting('test.attempt')::jsonb -> 'attempt' ->> 'attempt_id')::uuid),
  '66000000-0000-4000-8000-000000000051'::uuid, 'filtered answer retry is idempotent');
select ok((select total_correct = 1 from public.card_progress where card_id = '33000000-0000-4000-8000-000000000051'), 'retry does not double spaced progress');
select public.finish_training_session((current_setting('test.filtered')::jsonb ->> 'session_id')::uuid, 'completed');
select set_config('test.not_due', public.start_filtered_training_session('22000000-0000-4000-8000-000000000051', 'spaced', 'named', 'Многопоточность', 'hard')::text, true);
select is((public.next_training_attempt((current_setting('test.not_due')::jsonb ->> 'session_id')::uuid) ->> 'total')::integer, 0, 'filtered spaced excludes not-due card');
select public.finish_training_session((current_setting('test.not_due')::jsonb ->> 'session_id')::uuid, 'completed');

insert into public.card_progress (user_id, card_id, status, total_incorrect, next_review_at)
  values ('11000000-0000-4000-8000-000000000051', '33000000-0000-4000-8000-000000000052', 'learning', 1, clock_timestamp() - interval '1 minute');
select set_config('test.mistakes', public.start_filtered_training_session('22000000-0000-4000-8000-000000000051', 'mistakes', 'named', 'Многопоточность', 'easy')::text, true);
select set_config('test.mistakes_attempt', public.next_training_attempt((current_setting('test.mistakes')::jsonb ->> 'session_id')::uuid)::text, true);
select is((current_setting('test.mistakes_attempt')::jsonb ->> 'total')::integer, 1, 'mistakes applies category and difficulty to incorrect cards');
select public.record_answer('66000000-0000-4000-8000-000000000053',
  (current_setting('test.mistakes')::jsonb ->> 'session_id')::uuid,
  '33000000-0000-4000-8000-000000000052', false, 0, null,
  (current_setting('test.mistakes_attempt')::jsonb -> 'attempt' ->> 'attempt_id')::uuid);
select ok((select count(*) = 1 from public.answer_history where session_id = (current_setting('test.mistakes')::jsonb ->> 'session_id')::uuid), 'filtered mistakes answer is in history');
select ok((select total_incorrect = 1 from public.card_progress where card_id = '33000000-0000-4000-8000-000000000052'), 'mistakes does not change global spaced progress');
select public.finish_training_session((current_setting('test.mistakes')::jsonb ->> 'session_id')::uuid, 'completed');

select set_config('test.blank', public.start_filtered_training_session('22000000-0000-4000-8000-000000000051', 'spaced', 'uncategorized', null, 'medium')::text, true);
select is((public.next_training_attempt((current_setting('test.blank')::jsonb ->> 'session_id')::uuid) ->> 'total')::integer, 3, 'null, empty and spaces are one uncategorized group');
select public.finish_training_session((current_setting('test.blank')::jsonb ->> 'session_id')::uuid, 'completed');
select set_config('test.special', public.start_filtered_training_session('22000000-0000-4000-8000-000000000051', 'infinite', 'named', 'C++ / JVM & Kafka', 'hard')::text, true);
select set_config('test.special_attempt', public.next_training_attempt((current_setting('test.special')::jsonb ->> 'session_id')::uuid)::text, true);
select is((current_setting('test.special_attempt')::jsonb -> 'attempt' -> 'card' ->> 'id'), '33000000-0000-4000-8000-000000000056', 'special category is filtered on server');
select public.record_answer('66000000-0000-4000-8000-000000000054',
  (current_setting('test.special')::jsonb ->> 'session_id')::uuid,
  '33000000-0000-4000-8000-000000000056', true, 0, null,
  (current_setting('test.special_attempt')::jsonb -> 'attempt' ->> 'attempt_id')::uuid);
select is((public.next_training_attempt((current_setting('test.special')::jsonb ->> 'session_id')::uuid) -> 'attempt' -> 'card' ->> 'id'),
  '33000000-0000-4000-8000-000000000056', 'infinite repeats only filtered card when it is the sole candidate');
select ok((select count(*) = 0 from public.card_progress where card_id = '33000000-0000-4000-8000-000000000056'), 'infinite leaves spaced progress untouched');
select public.finish_training_session((current_setting('test.special')::jsonb ->> 'session_id')::uuid, 'abandoned');
select set_config('test.deleted', public.start_filtered_training_session('22000000-0000-4000-8000-000000000051', 'infinite', 'named', 'C++ / JVM & Kafka', 'hard')::text, true);
select public.next_training_attempt((current_setting('test.deleted')::jsonb ->> 'session_id')::uuid);
update public.cards set deleted_at = clock_timestamp() where id = '33000000-0000-4000-8000-000000000056';
select ok((public.next_training_attempt((current_setting('test.deleted')::jsonb ->> 'session_id')::uuid) -> 'attempt') = 'null'::jsonb,
  'deleted issued card is skipped');
select public.finish_training_session((current_setting('test.deleted')::jsonb ->> 'session_id')::uuid, 'abandoned');
select set_config('test.empty_difficulty', public.start_filtered_training_session('22000000-0000-4000-8000-000000000051', 'spaced', 'named', 'Многопоточность', 'medium')::text, true);
select is((public.next_training_attempt((current_setting('test.empty_difficulty')::jsonb ->> 'session_id')::uuid) ->> 'total')::integer, 0, 'valid category with no cards of difficulty is empty');
select public.finish_training_session((current_setting('test.empty_difficulty')::jsonb ->> 'session_id')::uuid, 'completed');
select throws_ok($$select public.start_filtered_training_session('22000000-0000-4000-8000-000000000051', 'spaced', 'named', 'Unknown', null)$$, '22023', 'Active category not found', 'nonexistent category rejected');
select throws_ok($$select public.start_filtered_training_session('22000000-0000-4000-8000-000000000051', 'spaced', 'named', '  ', null)$$, '22023', 'Invalid training category', 'blank named category rejected');

select set_config('test.changed', public.start_filtered_training_session('22000000-0000-4000-8000-000000000051', 'spaced', 'named', 'Многопоточность', 'easy')::text, true);
select set_config('test.changed_attempt', public.next_training_attempt((current_setting('test.changed')::jsonb ->> 'session_id')::uuid)::text, true);
update public.cards set category = 'Java Core' where id = '33000000-0000-4000-8000-000000000052';
select throws_ok($$select public.record_answer('66000000-0000-4000-8000-000000000052',
  (current_setting('test.changed')::jsonb ->> 'session_id')::uuid,
  '33000000-0000-4000-8000-000000000052', true, 0, null,
  (current_setting('test.changed_attempt')::jsonb -> 'attempt' ->> 'attempt_id')::uuid)$$,
  '22023', 'Card no longer matches session filters', 'changed category cannot be answered');
select is((public.next_training_attempt((current_setting('test.changed')::jsonb ->> 'session_id')::uuid) ->> 'total')::integer, 0, 'changed issued card is skipped');
select ok((select count(*) = 0 from public.answer_history
  where session_id = (current_setting('test.changed')::jsonb ->> 'session_id')::uuid), 'failed answer has no partial history');

set local role authenticated;
set local request.jwt.claim.sub = '11000000-0000-4000-8000-000000000052';
select throws_ok($$select public.start_filtered_training_session('22000000-0000-4000-8000-000000000051', 'spaced', 'named', 'Многопоточность', 'hard')$$,
  '22023', 'Active topic not found', 'other user cannot train on owner topic');
select is((select count(*)::integer from public.training_sessions where user_id = '11000000-0000-4000-8000-000000000051'), 0, 'RLS hides owner sessions');
select * from finish();
rollback;
