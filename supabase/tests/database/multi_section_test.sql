begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

insert into auth.users (id, email) values
  ('11000000-0000-4000-8000-000000000091', 'multi-owner@example.test'),
  ('11000000-0000-4000-8000-000000000092', 'multi-other@example.test');
insert into public.topics (id, user_id, title) values
  ('22000000-0000-4000-8000-000000000091', '11000000-0000-4000-8000-000000000091', 'Backend'),
  ('22000000-0000-4000-8000-000000000092', '11000000-0000-4000-8000-000000000091', 'Other direction'),
  ('22000000-0000-4000-8000-000000000093', '11000000-0000-4000-8000-000000000092', 'Other owner');
insert into public.cards (id, user_id, topic_id, section, category, question, answer, difficulty) values
  ('33000000-0000-4000-8000-000000000091', '11000000-0000-4000-8000-000000000091', '22000000-0000-4000-8000-000000000091', '01-a', 'Shared', 'A?', 'A', 'hard'),
  ('33000000-0000-4000-8000-000000000092', '11000000-0000-4000-8000-000000000091', '22000000-0000-4000-8000-000000000091', '02-b', 'Shared', 'B?', 'B', 'hard'),
  ('33000000-0000-4000-8000-000000000093', '11000000-0000-4000-8000-000000000091', '22000000-0000-4000-8000-000000000091', '03-c', 'Shared', 'C?', 'C', 'hard'),
  ('33000000-0000-4000-8000-000000000094', '11000000-0000-4000-8000-000000000091', '22000000-0000-4000-8000-000000000091', null, 'Shared', 'No section?', 'N', 'hard'),
  ('33000000-0000-4000-8000-000000000095', '11000000-0000-4000-8000-000000000091', '22000000-0000-4000-8000-000000000092', '01-a', 'Shared', 'Other direction?', 'O', 'hard'),
  ('33000000-0000-4000-8000-000000000096', '11000000-0000-4000-8000-000000000092', '22000000-0000-4000-8000-000000000093', '01-a', 'Shared', 'Other owner?', 'O', 'hard');

select ok(has_function_privilege('authenticated', 'public.start_section_training_session(uuid,text,text,text,text,text,text)', 'EXECUTE'), 'authenticated user can call existing RPC');
select ok(not has_function_privilege('anon', 'public.start_section_training_session(uuid,text,text,text,text,text,text)', 'EXECUTE'), 'anonymous cannot start session');
select ok(not has_function_privilege('authenticated', 'app_private.card_matches_training_scope(text,text,text,jsonb)', 'EXECUTE'), 'scope helper remains private');
select set_config('request.jwt.claim.sub', '11000000-0000-4000-8000-000000000091', true);

select throws_ok($$select public.start_section_training_session('22000000-0000-4000-8000-000000000091', 'spaced', 'multi', '[]', 'all', null, null)$$,
  '22023', 'Invalid training sections', 'empty multi selection rejected');
select throws_ok($$select public.start_section_training_session('22000000-0000-4000-8000-000000000091', 'spaced', 'multi', '["01-a","01-a"]', 'all', null, null)$$,
  '22023', 'Select at least two distinct sections', 'duplicate-only selection rejected');
select throws_ok($$select public.start_section_training_session('22000000-0000-4000-8000-000000000091', 'spaced', 'multi', '["01-a","missing"]', 'all', null, null)$$,
  '22023', 'Active section not found', 'every selected section must exist');
select throws_ok($$select public.start_section_training_session('22000000-0000-4000-8000-000000000091', 'spaced', 'multi', 'not-json', 'all', null, null)$$,
  '22023', 'Invalid training sections', 'malformed JSON rejected');
select set_config('test.multi', public.start_section_training_session(
  '22000000-0000-4000-8000-000000000091', 'spaced', 'multi', '["02-b","01-a"]',
  'named', 'Shared', 'hard')::text, true);
select is((current_setting('test.multi')::jsonb -> 'filters' ->> 'section_mode'), 'multi', 'multi scope fixed in session');
select ok((current_setting('test.multi')::jsonb -> 'filters' ->> 'section')::jsonb = '["01-a","02-b"]'::jsonb,
  'section order normalized on server');
select set_config('test.multi_next', public.next_training_attempt((current_setting('test.multi')::jsonb ->> 'session_id')::uuid)::text, true);
select is((current_setting('test.multi_next')::jsonb ->> 'total')::integer, 2, 'spaced queues only two selected sections');
select is((current_setting('test.multi_next')::jsonb -> 'attempt' -> 'card' ->> 'id'),
  '33000000-0000-4000-8000-000000000091', 'first card belongs to selected section');
select is((public.start_section_training_session('22000000-0000-4000-8000-000000000091',
  'spaced', 'multi', '["01-a","02-b"]', 'named', 'Shared', 'hard') ->> 'conflict')::boolean,
  false, 'same sections in different order resume session');
select is((public.start_section_training_session('22000000-0000-4000-8000-000000000091',
  'spaced', 'multi', '["01-a","03-c"]', 'named', 'Shared', 'hard') ->> 'conflict')::boolean,
  true, 'different section selection reports conflict');
select throws_ok($$select public.record_answer('66000000-0000-4000-8000-000000000093',
  (current_setting('test.multi')::jsonb ->> 'session_id')::uuid,
  '33000000-0000-4000-8000-000000000093', true, 0, null,
  (current_setting('test.multi_next')::jsonb -> 'attempt' ->> 'attempt_id')::uuid)$$,
  '22023', 'Attempt not found', 'unselected card cannot be answered with selected attempt');
select is(public.record_answer('66000000-0000-4000-8000-000000000091',
  (current_setting('test.multi')::jsonb ->> 'session_id')::uuid,
  '33000000-0000-4000-8000-000000000091', true, 0, null,
  (current_setting('test.multi_next')::jsonb -> 'attempt' ->> 'attempt_id')::uuid),
  '66000000-0000-4000-8000-000000000091'::uuid, 'selected spaced answer saved');
select is((select total_correct from public.card_progress where card_id = '33000000-0000-4000-8000-000000000091'),
  1, 'global spaced progress updated');
select set_config('test.multi_second', public.next_training_attempt((current_setting('test.multi')::jsonb ->> 'session_id')::uuid)::text, true);
select is((current_setting('test.multi_second')::jsonb -> 'attempt' -> 'card' ->> 'id'),
  '33000000-0000-4000-8000-000000000092', 'second selected section is issued');
select public.finish_training_session((current_setting('test.multi')::jsonb ->> 'session_id')::uuid, 'completed');

select set_config('test.infinite', public.start_section_training_session(
  '22000000-0000-4000-8000-000000000091', 'infinite', 'multi', '["01-a","03-c"]', 'all', null, null)::text, true);
select is((public.next_training_attempt((current_setting('test.infinite')::jsonb ->> 'session_id')::uuid) -> 'attempt' -> 'card' ->> 'id'),
  '33000000-0000-4000-8000-000000000091', 'infinite respects multi sections');
select public.finish_training_session((current_setting('test.infinite')::jsonb ->> 'session_id')::uuid, 'abandoned');

insert into public.card_progress (user_id, card_id, status, total_incorrect)
  values ('11000000-0000-4000-8000-000000000091', '33000000-0000-4000-8000-000000000092', 'learning', 1);
select set_config('test.mistakes', public.start_section_training_session(
  '22000000-0000-4000-8000-000000000091', 'mistakes', 'multi', '["01-a","02-b"]', 'all', null, null)::text, true);
select is((public.next_training_attempt((current_setting('test.mistakes')::jsonb ->> 'session_id')::uuid) -> 'attempt' -> 'card' ->> 'id'),
  '33000000-0000-4000-8000-000000000092', 'mistakes uses selected sections and recorded errors');
select public.finish_training_session((current_setting('test.mistakes')::jsonb ->> 'session_id')::uuid, 'completed');
select is((select total_incorrect from public.card_progress where card_id = '33000000-0000-4000-8000-000000000092'),
  1, 'mistakes session leaves spaced progress intact');
select set_config('test.unsectioned', public.start_section_training_session(
  '22000000-0000-4000-8000-000000000091', 'infinite', 'multi', '["","03-c"]', 'all', null, null)::text, true);
select ok((public.next_training_attempt((current_setting('test.unsectioned')::jsonb ->> 'session_id')::uuid)
  -> 'attempt' -> 'card' ->> 'id') in
  ('33000000-0000-4000-8000-000000000093', '33000000-0000-4000-8000-000000000094'),
  'unsectioned cards can be included with a named section');

set local role authenticated;
set local request.jwt.claim.sub = '11000000-0000-4000-8000-000000000092';
select throws_ok($$select public.start_section_training_session('22000000-0000-4000-8000-000000000091',
  'spaced', 'multi', '["01-a","02-b"]', 'all', null, null)$$,
  '22023', 'Active topic not found', 'other user cannot start multi session on owner topic');

select * from finish();
rollback;
