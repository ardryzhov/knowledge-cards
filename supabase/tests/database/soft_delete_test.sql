begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, email) values
  ('11000000-0000-4000-8000-000000000011', 'cards-soft-owner@example.test'),
  ('11000000-0000-4000-8000-000000000012', 'cards-soft-other@example.test');
insert into public.topics (id, user_id, title) values
  ('22000000-0000-4000-8000-000000000011', '11000000-0000-4000-8000-000000000011', 'Recoverable topic'),
  ('22000000-0000-4000-8000-000000000012', '11000000-0000-4000-8000-000000000012', 'Other topic');
insert into public.cards (id, user_id, topic_id, question, answer) values
  ('33000000-0000-4000-8000-000000000011', '11000000-0000-4000-8000-000000000011', '22000000-0000-4000-8000-000000000011', 'Card one', 'Answer'),
  ('33000000-0000-4000-8000-000000000012', '11000000-0000-4000-8000-000000000011', '22000000-0000-4000-8000-000000000011', 'Card two', 'Answer');

select ok(not has_table_privilege('authenticated', 'public.topics', 'INSERT'), 'browser cannot insert topics');
select ok(not has_table_privilege('authenticated', 'public.cards', 'INSERT'), 'browser cannot insert cards');
select ok(not has_column_privilege('authenticated', 'public.topics', 'title', 'UPDATE'), 'browser cannot edit topics');
select ok(not has_column_privilege('authenticated', 'public.cards', 'question', 'UPDATE'), 'browser cannot edit cards');
select ok(not has_function_privilege('authenticated', 'public.soft_delete_topic(uuid)', 'EXECUTE'), 'browser cannot soft-delete topic');
select ok(not has_function_privilege('authenticated', 'public.restore_card(uuid)', 'EXECUTE'), 'browser cannot restore card');

set local request.jwt.claim.sub = '11000000-0000-4000-8000-000000000011';
select is(public.soft_delete_card('33000000-0000-4000-8000-000000000011'),
  '33000000-0000-4000-8000-000000000011'::uuid, 'elevated migration can soft-delete owner card');
select is(public.soft_delete_topic('22000000-0000-4000-8000-000000000011'),
  '22000000-0000-4000-8000-000000000011'::uuid, 'elevated migration can soft-delete owner topic');
select throws_ok(
  $$insert into public.cards (user_id, topic_id, question, answer) values ('11000000-0000-4000-8000-000000000011', '22000000-0000-4000-8000-000000000011', 'New card', 'Answer')$$,
  '23514', 'Active topic required for card', 'deleted topic rejects new active cards');
select throws_ok(
  $$select public.restore_card('33000000-0000-4000-8000-000000000011')$$,
  '23514', 'Active topic required for card', 'card cannot be restored before its topic');
select is(public.restore_topic('22000000-0000-4000-8000-000000000011'),
  '22000000-0000-4000-8000-000000000011'::uuid, 'elevated migration can restore owner topic');
select is(public.restore_card('33000000-0000-4000-8000-000000000011'),
  '33000000-0000-4000-8000-000000000011'::uuid, 'elevated migration can restore owner card');
select ok((select deleted_at is null from public.cards where id = '33000000-0000-4000-8000-000000000011'), 'restored card is active');

set local request.jwt.claim.sub = '11000000-0000-4000-8000-000000000012';
select throws_ok(
  $$select public.soft_delete_card('33000000-0000-4000-8000-000000000011')$$,
  'P0002', 'Card not found', 'content RPC owner check still protects elevated use');

select * from finish();
rollback;
