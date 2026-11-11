begin;
create extension if not exists pgtap with schema extensions;
select plan(35);

insert into auth.users (id, email) values
  ('11000000-0000-4000-8000-000000000081', 'sections-owner@example.test'),
  ('11000000-0000-4000-8000-000000000082', 'sections-other@example.test');
insert into public.topics (id, user_id, title) values
  ('22000000-0000-4000-8000-000000000081', '11000000-0000-4000-8000-000000000081', 'Backend'),
  ('22000000-0000-4000-8000-000000000082', '11000000-0000-4000-8000-000000000081', 'Analysis'),
  ('22000000-0000-4000-8000-000000000083', '11000000-0000-4000-8000-000000000082', 'Other');
insert into public.cards (id, user_id, topic_id, section, category, question, answer, difficulty) values
  ('33000000-0000-4000-8000-000000000081', '11000000-0000-4000-8000-000000000081', '22000000-0000-4000-8000-000000000081', '01-java-core', 'Типы и ссылки', 'Java hard', 'A', 'hard'),
  ('33000000-0000-4000-8000-000000000082', '11000000-0000-4000-8000-000000000081', '22000000-0000-4000-8000-000000000081', '01-java-core', 'Типы и ссылки', 'Java easy', 'A', 'easy'),
  ('33000000-0000-4000-8000-000000000083', '11000000-0000-4000-8000-000000000081', '22000000-0000-4000-8000-000000000081', '02-collections-generics', 'Типы и ссылки', 'Collections hard', 'A', 'hard'),
  ('33000000-0000-4000-8000-000000000084', '11000000-0000-4000-8000-000000000081', '22000000-0000-4000-8000-000000000081', null, 'Legacy', 'Null section', 'A', 'medium'),
  ('33000000-0000-4000-8000-000000000085', '11000000-0000-4000-8000-000000000081', '22000000-0000-4000-8000-000000000081', '', null, 'Blank section', 'A', 'medium'),
  ('33000000-0000-4000-8000-000000000086', '11000000-0000-4000-8000-000000000081', '22000000-0000-4000-8000-000000000081', '   ', '   ', 'Spaces section', 'A', 'medium'),
  ('33000000-0000-4000-8000-000000000087', '11000000-0000-4000-8000-000000000081', '22000000-0000-4000-8000-000000000081', '03-стримы & API', 'C++ / JVM', 'Special', 'A', 'hard'),
  ('33000000-0000-4000-8000-000000000088', '11000000-0000-4000-8000-000000000081', '22000000-0000-4000-8000-000000000082', '01-java-core', 'Типы и ссылки', 'Other topic', 'A', 'hard'),
  ('33000000-0000-4000-8000-000000000089', '11000000-0000-4000-8000-000000000082', '22000000-0000-4000-8000-000000000083', '01-java-core', 'Типы и ссылки', 'Other owner', 'A', 'hard');

select ok(has_function_privilege('authenticated', 'public.start_section_training_session(uuid,text,text,text,text,text,text)', 'EXECUTE'), 'owner may start scoped session');
select ok(not has_function_privilege('anon', 'public.start_section_training_session(uuid,text,text,text,text,text,text)', 'EXECUTE'), 'anonymous cannot start scoped session');
select ok(not has_function_privilege('authenticated', 'app_private.card_matches_training_scope(text,text,text,jsonb)', 'EXECUTE'), 'browser cannot call private scope helper');
select ok(not has_column_privilege('authenticated', 'public.cards', 'section', 'UPDATE'), 'browser cannot change card section');
select ok(not has_table_privilege('authenticated', 'public.training_attempts', 'INSERT'), 'browser cannot issue attempts');
select ok(not has_table_privilege('authenticated', 'public.answer_history', 'INSERT'), 'browser cannot bypass answer RPC');

select set_config('request.jwt.claim.sub', '11000000-0000-4000-8000-000000000081', true);
select set_config('test.scope', public.start_section_training_session(
  '22000000-0000-4000-8000-000000000081', 'spaced', 'named', ' 01-java-core ',
  'named', ' Типы и ссылки ', 'hard')::text, true);
select is(current_setting('test.scope')::jsonb -> 'filters' ->> 'section', '01-java-core', 'section identifier is normalized but preserved');
select is((select settings ->> 'section' from public.training_sessions
  where id = (current_setting('test.scope')::jsonb ->> 'session_id')::uuid), '01-java-core', 'section filter stored in session');
select set_config('test.first', public.next_training_attempt((current_setting('test.scope')::jsonb ->> 'session_id')::uuid)::text, true);
select is((current_setting('test.first')::jsonb ->> 'total')::integer, 1, 'spaced filters section, group, difficulty, topic and owner');
select is((current_setting('test.first')::jsonb -> 'attempt' -> 'card' ->> 'id'), '33000000-0000-4000-8000-000000000081', 'only Java Core hard card issued');
select is((public.start_section_training_session('22000000-0000-4000-8000-000000000081', 'spaced', 'named', '01-java-core', 'named', 'Типы и ссылки', 'hard') ->> 'conflict')::boolean,
  false, 'same scope resumes session');
select is((public.start_section_training_session('22000000-0000-4000-8000-000000000081', 'spaced', 'named', '02-collections-generics', 'named', 'Типы и ссылки', 'hard') ->> 'conflict')::boolean,
  true, 'same mode with different section reports conflict');
select throws_ok($$select public.record_answer('66000000-0000-4000-8000-000000000089',
  (current_setting('test.scope')::jsonb ->> 'session_id')::uuid,
  '33000000-0000-4000-8000-000000000083', true, 0, null,
  (current_setting('test.first')::jsonb -> 'attempt' ->> 'attempt_id')::uuid)$$,
  '22023', 'Attempt not found', 'arbitrary card in another section cannot be answered');
select is(public.record_answer('66000000-0000-4000-8000-000000000081',
  (current_setting('test.scope')::jsonb ->> 'session_id')::uuid,
  '33000000-0000-4000-8000-000000000081', true, 0, null,
  (current_setting('test.first')::jsonb -> 'attempt' ->> 'attempt_id')::uuid),
  '66000000-0000-4000-8000-000000000081'::uuid, 'scoped spaced answer recorded');
select is(public.record_answer('66000000-0000-4000-8000-000000000081',
  (current_setting('test.scope')::jsonb ->> 'session_id')::uuid,
  '33000000-0000-4000-8000-000000000081', true, 0, null,
  (current_setting('test.first')::jsonb -> 'attempt' ->> 'attempt_id')::uuid),
  '66000000-0000-4000-8000-000000000081'::uuid, 'scoped retry is idempotent');
select ok((select total_correct = 1 from public.card_progress where card_id = '33000000-0000-4000-8000-000000000081'), 'retry does not double progress');
select public.finish_training_session((current_setting('test.scope')::jsonb ->> 'session_id')::uuid, 'completed');
select set_config('test.not_due', public.start_section_training_session('22000000-0000-4000-8000-000000000081', 'spaced', 'named', '01-java-core', 'named', 'Типы и ссылки', 'hard')::text, true);
select is((public.next_training_attempt((current_setting('test.not_due')::jsonb ->> 'session_id')::uuid) ->> 'total')::integer, 0, 'not-due card stays out of scoped spaced');
select public.finish_training_session((current_setting('test.not_due')::jsonb ->> 'session_id')::uuid, 'completed');
update public.cards set section = '02-collections-generics' where id = '33000000-0000-4000-8000-000000000081';
select is(public.record_answer('66000000-0000-4000-8000-000000000081',
  (current_setting('test.scope')::jsonb ->> 'session_id')::uuid,
  '33000000-0000-4000-8000-000000000081', true, 0, null,
  (current_setting('test.first')::jsonb -> 'attempt' ->> 'attempt_id')::uuid),
  '66000000-0000-4000-8000-000000000081'::uuid, 'exact retry survives later section change');
select set_config('test.empty_difficulty', public.start_section_training_session('22000000-0000-4000-8000-000000000081', 'spaced', 'named', '01-java-core', 'named', 'Типы и ссылки', 'medium')::text, true);
select is((public.next_training_attempt((current_setting('test.empty_difficulty')::jsonb ->> 'session_id')::uuid) ->> 'total')::integer,
  0, 'existing group with no cards of selected difficulty is empty');
select public.finish_training_session((current_setting('test.empty_difficulty')::jsonb ->> 'session_id')::uuid, 'completed');

select set_config('test.unsectioned', public.start_section_training_session('22000000-0000-4000-8000-000000000081', 'spaced', 'unsectioned', null, 'all', null, 'medium')::text, true);
select is((public.next_training_attempt((current_setting('test.unsectioned')::jsonb ->> 'session_id')::uuid) ->> 'total')::integer, 3, 'null, empty and spaces section remain available');
select public.finish_training_session((current_setting('test.unsectioned')::jsonb ->> 'session_id')::uuid, 'completed');
select set_config('test.ungrouped', public.start_section_training_session('22000000-0000-4000-8000-000000000081', 'spaced', 'unsectioned', null, 'uncategorized', null, 'medium')::text, true);
select is((public.next_training_attempt((current_setting('test.ungrouped')::jsonb ->> 'session_id')::uuid) ->> 'total')::integer, 2, 'null and spaces group are one ungrouped scope');
select public.finish_training_session((current_setting('test.ungrouped')::jsonb ->> 'session_id')::uuid, 'completed');
select set_config('test.special', public.start_section_training_session('22000000-0000-4000-8000-000000000081', 'infinite', 'named', '03-стримы & API', 'named', 'C++ / JVM', 'hard')::text, true);
select set_config('test.special_attempt', public.next_training_attempt((current_setting('test.special')::jsonb ->> 'session_id')::uuid)::text, true);
select is((current_setting('test.special_attempt')::jsonb -> 'attempt' -> 'card' ->> 'id'), '33000000-0000-4000-8000-000000000087', 'special Cyrillic section and group work in infinite');
select public.record_answer('66000000-0000-4000-8000-000000000087',
  (current_setting('test.special')::jsonb ->> 'session_id')::uuid,
  '33000000-0000-4000-8000-000000000087', true, 0, null,
  (current_setting('test.special_attempt')::jsonb -> 'attempt' ->> 'attempt_id')::uuid);
select ok((select count(*) = 0 from public.card_progress where card_id = '33000000-0000-4000-8000-000000000087'), 'infinite does not change spaced progress');
select public.finish_training_session((current_setting('test.special')::jsonb ->> 'session_id')::uuid, 'abandoned');

insert into public.card_progress (user_id, card_id, status, total_incorrect, next_review_at)
  values ('11000000-0000-4000-8000-000000000081', '33000000-0000-4000-8000-000000000082', 'learning', 1, clock_timestamp() - interval '1 second');
select set_config('test.mistakes', public.start_section_training_session('22000000-0000-4000-8000-000000000081', 'mistakes', 'named', '01-java-core', 'named', 'Типы и ссылки', 'easy')::text, true);
select set_config('test.mistake_attempt', public.next_training_attempt((current_setting('test.mistakes')::jsonb ->> 'session_id')::uuid)::text, true);
select is((current_setting('test.mistake_attempt')::jsonb ->> 'total')::integer, 1, 'mistakes respects section, group and difficulty');
select public.record_answer('66000000-0000-4000-8000-000000000082',
  (current_setting('test.mistakes')::jsonb ->> 'session_id')::uuid,
  '33000000-0000-4000-8000-000000000082', false, 0, null,
  (current_setting('test.mistake_attempt')::jsonb -> 'attempt' ->> 'attempt_id')::uuid);
select ok((select total_incorrect = 1 from public.card_progress where card_id = '33000000-0000-4000-8000-000000000082'), 'mistakes leaves spaced schedule unchanged');
select public.finish_training_session((current_setting('test.mistakes')::jsonb ->> 'session_id')::uuid, 'completed');

select set_config('test.changed', public.start_section_training_session('22000000-0000-4000-8000-000000000081', 'spaced', 'named', '01-java-core', 'named', 'Типы и ссылки', 'easy')::text, true);
select set_config('test.changed_attempt', public.next_training_attempt((current_setting('test.changed')::jsonb ->> 'session_id')::uuid)::text, true);
update public.cards set section = '02-collections-generics' where id = '33000000-0000-4000-8000-000000000082';
select throws_ok($$select public.record_answer('66000000-0000-4000-8000-000000000083',
  (current_setting('test.changed')::jsonb ->> 'session_id')::uuid,
  '33000000-0000-4000-8000-000000000082', true, 0, null,
  (current_setting('test.changed_attempt')::jsonb -> 'attempt' ->> 'attempt_id')::uuid)$$,
  '22023', 'Card no longer matches session filters', 'moved issued card cannot be answered');
select is((public.next_training_attempt((current_setting('test.changed')::jsonb ->> 'session_id')::uuid) ->> 'total')::integer, 0, 'moved issued card is skipped');
select ok((select count(*) = 0 from public.answer_history where session_id = (current_setting('test.changed')::jsonb ->> 'session_id')::uuid), 'failed answer leaves no partial history');
select throws_ok($$select public.start_section_training_session('22000000-0000-4000-8000-000000000081', 'infinite', 'named', 'missing', 'all', null, null)$$,
  '22023', 'Active section not found', 'unknown section rejected');
select is((public.start_filtered_training_session('22000000-0000-4000-8000-000000000081', 'infinite', 'all', null, null) -> 'filters' ->> 'section_mode'),
  'all', 'old filtered RPC remains an all-section entry point');
select set_config('test.old_session', public.start_training_session('22000000-0000-4000-8000-000000000082', 'infinite')::text, true);
select is((public.start_section_training_session('22000000-0000-4000-8000-000000000082', 'infinite', 'all', null, 'all', null, null) ->> 'session_id'),
  current_setting('test.old_session'), 'new RPC resumes a pre-section session');
select is((public.start_section_training_session('22000000-0000-4000-8000-000000000082', 'infinite', 'all', null, 'all', null, null) ->> 'conflict')::boolean,
  false, 'pre-section all-content session has no false conflict');
select is((public.next_training_attempt(current_setting('test.old_session')::uuid) -> 'attempt' -> 'card' ->> 'id'),
  '33000000-0000-4000-8000-000000000088', 'pre-section session can issue sectioned cards');
select public.finish_training_session(current_setting('test.old_session')::uuid, 'abandoned');

set local role authenticated;
set local request.jwt.claim.sub = '11000000-0000-4000-8000-000000000082';
select throws_ok($$select public.start_section_training_session('22000000-0000-4000-8000-000000000081', 'spaced', 'named', '01-java-core', 'all', null, null)$$,
  '22023', 'Active topic not found', 'other user cannot start owner session');
select is((select count(*)::integer from public.training_sessions where user_id = '11000000-0000-4000-8000-000000000081'), 0, 'RLS hides owner sessions');
select * from finish();
rollback;
