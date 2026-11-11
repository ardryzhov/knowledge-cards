begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

-- Test users and rows exist only inside this rolled-back transaction.
insert into auth.users (id, email) values
  ('11000000-0000-4000-8000-000000000001', 'cards-rls-owner@example.test'),
  ('11000000-0000-4000-8000-000000000002', 'cards-rls-other@example.test');

insert into public.profiles (user_id) values
  ('11000000-0000-4000-8000-000000000001'),
  ('11000000-0000-4000-8000-000000000002');
insert into public.topics (id, user_id, title) values
  ('22000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'Owner topic'),
  ('22000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000002', 'Other topic');
insert into public.cards (id, user_id, topic_id, question, answer) values
  ('33000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', '22000000-0000-4000-8000-000000000001', 'Q1', 'A1'),
  ('33000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000002', '22000000-0000-4000-8000-000000000002', 'Q2', 'A2');
insert into public.card_progress (user_id, card_id) values
  ('11000000-0000-4000-8000-000000000001', '33000000-0000-4000-8000-000000000001'),
  ('11000000-0000-4000-8000-000000000002', '33000000-0000-4000-8000-000000000002');
insert into public.training_sessions (id, user_id, topic_id, mode) values
  ('44000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', '22000000-0000-4000-8000-000000000001', 'spaced'),
  ('44000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000002', '22000000-0000-4000-8000-000000000002', 'spaced');
insert into public.answer_history (id, user_id, card_id, session_id, mode, is_correct, hints_used) values
  ('55000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', '33000000-0000-4000-8000-000000000001', '44000000-0000-4000-8000-000000000001', 'spaced', true, 0),
  ('55000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000002', '33000000-0000-4000-8000-000000000002', '44000000-0000-4000-8000-000000000002', 'spaced', true, 0);
insert into public.training_attempts (id, user_id, session_id, card_id, position, status, issued_at) values
  ('77000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001',
   '44000000-0000-4000-8000-000000000001', '33000000-0000-4000-8000-000000000001', 1, 'issued', now());
insert into public.user_achievements (user_id, code) values
  ('11000000-0000-4000-8000-000000000001', 'FIRST_STEP'),
  ('11000000-0000-4000-8000-000000000002', 'FIRST_STEP');

select ok((select count(*) = 7 from pg_class where oid in (
  'public.profiles'::regclass, 'public.topics'::regclass, 'public.cards'::regclass,
  'public.card_progress'::regclass, 'public.training_sessions'::regclass,
  'public.answer_history'::regclass, 'public.user_achievements'::regclass
) and relrowsecurity), 'RLS enabled on all seven user tables');

select ok(not has_table_privilege('anon', 'public.profiles', 'SELECT'), 'anon cannot read profiles');
select ok(not has_table_privilege('anon', 'public.topics', 'SELECT'), 'anon cannot read topics');
select ok(not has_table_privilege('anon', 'public.cards', 'SELECT'), 'anon cannot read cards');
select ok(not has_table_privilege('anon', 'public.card_progress', 'SELECT'), 'anon cannot read progress');
select ok(not has_table_privilege('anon', 'public.training_sessions', 'SELECT'), 'anon cannot read sessions');
select ok(not has_table_privilege('anon', 'public.answer_history', 'SELECT'), 'anon cannot read answers');
select ok(not has_table_privilege('anon', 'public.user_achievements', 'SELECT'), 'anon cannot read achievements');
select ok(not has_function_privilege('anon', 'public.record_answer(uuid,uuid,uuid,boolean,integer,integer)', 'EXECUTE'), 'anon cannot call record_answer');
select ok(not has_table_privilege('authenticated', 'public.answer_history', 'INSERT'), 'browser cannot directly insert answers');
select ok(not has_table_privilege('authenticated', 'public.card_progress', 'UPDATE'), 'browser cannot directly change progress');

set local role authenticated;
set local request.jwt.claim.sub = '11000000-0000-4000-8000-000000000001';
select is((select count(*)::int from public.profiles), 1, 'owner sees only own profile');
select is((select count(*)::int from public.topics), 1, 'owner sees only own topic');
select is((select count(*)::int from public.cards), 1, 'owner sees only own card');
select is((select count(*)::int from public.card_progress), 1, 'owner sees only own progress');
select is((select count(*)::int from public.training_sessions), 1, 'owner sees only own session');
select is((select count(*)::int from public.answer_history), 1, 'owner sees only own answer');
select is((select count(*)::int from public.user_achievements), 1, 'owner sees only own achievement');
select ok(not has_table_privilege('authenticated', 'public.topics', 'INSERT'), 'browser cannot insert topics');
select is(public.record_answer('66000000-0000-4000-8000-000000000001', '44000000-0000-4000-8000-000000000001', '33000000-0000-4000-8000-000000000001', true, 0, 1000),
  '66000000-0000-4000-8000-000000000001'::uuid, 'owner can record an answer');
select is(public.record_answer('66000000-0000-4000-8000-000000000001', '44000000-0000-4000-8000-000000000001', '33000000-0000-4000-8000-000000000001', true, 0, 1000),
  '66000000-0000-4000-8000-000000000001'::uuid, 'retry returns same event ID');
select is((select count(*)::int from public.answer_history where id = '66000000-0000-4000-8000-000000000001'), 1, 'retry did not duplicate answer');
select throws_ok(
  $$select public.record_answer('66000000-0000-4000-8000-000000000001', '44000000-0000-4000-8000-000000000001', '33000000-0000-4000-8000-000000000001', false, 0, 1000)$$,
  '23505', 'Attempt already answered', 'same event ID cannot change its answer');

reset role;
update public.training_sessions set status = 'completed', finished_at = now()
  where id = '44000000-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claim.sub = '11000000-0000-4000-8000-000000000001';
select is(public.record_answer('66000000-0000-4000-8000-000000000001', '44000000-0000-4000-8000-000000000001', '33000000-0000-4000-8000-000000000001', true, 0, 1000),
  '66000000-0000-4000-8000-000000000001'::uuid, 'retry succeeds after session completion');

set local request.jwt.claim.sub = '11000000-0000-4000-8000-000000000002';
select is((select count(*)::int from public.topics where id = '22000000-0000-4000-8000-000000000001'), 0, 'other user cannot read owner topic');
select is((select count(*)::int from public.cards where id = '33000000-0000-4000-8000-000000000001'), 0, 'other user cannot read owner card');
select ok(not has_column_privilege('authenticated', 'public.topics', 'title', 'UPDATE'), 'browser cannot update topics');
select ok(not has_column_privilege('authenticated', 'public.cards', 'question', 'UPDATE'), 'browser cannot update cards');
select ok(not has_table_privilege('authenticated', 'public.cards', 'DELETE'), 'browser cannot hard-delete cards');
select ok(not has_table_privilege('authenticated', 'public.topics', 'DELETE'), 'browser cannot hard-delete topics');
select is((select count(*)::int from public.answer_history where id = '55000000-0000-4000-8000-000000000001'), 0,
  'other user cannot read owner answer');
select throws_ok(
  $$select public.record_answer('66000000-0000-4000-8000-000000000002', '44000000-0000-4000-8000-000000000001', '33000000-0000-4000-8000-000000000001', true, 0, 1000, '77000000-0000-4000-8000-000000000001')$$,
  '22023', 'Training session not found', 'other user cannot call RPC for owner session');
select is((select count(*)::int from public.answer_history where id = '66000000-0000-4000-8000-000000000002'), 0,
  'rejected RPC did not write an answer');

select * from finish();
rollback;
