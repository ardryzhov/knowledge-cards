begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

insert into auth.users (id, email) values
  ('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70', 'all-content-owner@example.test'),
  ('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a71', 'all-content-other@example.test');

select ok(not has_function_privilege('authenticated', 'app_private.import_content_backend_v1(uuid)', 'EXECUTE'), 'browser cannot run content importer');
select ok(not has_table_privilege('authenticated', 'public.cards', 'INSERT'), 'browser cannot create cards');
select throws_ok($$select app_private.import_content_backend_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a71')$$,
  '22023', 'Unexpected content owner', 'other owner cannot import content');

select app_private.import_content_backend_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70');
select app_private.import_content_analysis_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70');
select app_private.import_content_testing_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70');
select app_private.import_content_devops_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70');
select app_private.import_content_livecoding_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70');
select app_private.import_content_productengineering_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70');

select is((select count(*)::integer from public.topics where user_id = '7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70'), 6, 'six directions created');
select is((select count(*)::integer from public.cards where user_id = '7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70'), 1797, 'all 1797 cards imported');
select is((select count(*)::integer from (select distinct topic_id, section from public.cards) sections), 69, 'all 69 sections imported');
select is((select count(*)::integer from public.cards c join public.topics t on t.id = c.topic_id where t.title = 'Backend'), 425, 'Backend count');
select is((select count(*)::integer from public.cards c join public.topics t on t.id = c.topic_id where t.title = 'Analysis'), 354, 'Analysis count');
select is((select count(*)::integer from public.cards c join public.topics t on t.id = c.topic_id where t.title = 'Testing'), 268, 'Testing count');
select is((select count(*)::integer from public.cards c join public.topics t on t.id = c.topic_id where t.title = 'DevOps'), 286, 'DevOps count');
select is((select count(*)::integer from public.cards c join public.topics t on t.id = c.topic_id where t.title = 'LiveCoding'), 184, 'LiveCoding count');
select is((select count(*)::integer from public.cards c join public.topics t on t.id = c.topic_id where t.title = 'ProductEngineering'), 280, 'ProductEngineering count');
select is((select count(*)::integer from public.cards where section = '01-java-core' and topic_id = '4535e892-4d68-41c2-a5a8-87935d2f5134'), 40, 'Java Core extended to 40 cards');
select is((select count(*)::integer from public.cards where id = 'a21911e3-7526-4d8a-9a90-7d7cd2e31796'), 1, 'existing Java Core UUID retained');
select is((select code from public.cards where id = '769ee6d9-5791-46dc-946e-2c51b6d2913d'),
  'throw new ProcessingException("order " + id, e);', 'code string from repaired YAML retained');

insert into public.card_progress (user_id, card_id, status, total_correct, consecutive_correct)
  values ('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70', 'a21911e3-7526-4d8a-9a90-7d7cd2e31796', 'learning', 2, 2);
select app_private.import_content_backend_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70');
select app_private.import_content_analysis_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70');
select app_private.import_content_testing_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70');
select app_private.import_content_devops_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70');
select app_private.import_content_livecoding_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70');
select app_private.import_content_productengineering_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70');
select is((select count(*)::integer from public.cards), 1797, 'repeat import creates no duplicates');
select is((select total_correct from public.card_progress where card_id = 'a21911e3-7526-4d8a-9a90-7d7cd2e31796'), 2, 'repeat import keeps progress');

set local role authenticated;
set local request.jwt.claim.sub = '7d53c0ee-fd2b-401a-ae4d-e6c0caa32a71';
select is((select count(*)::integer from public.cards), 0, 'other authenticated user cannot read imported cards');
select is((select count(*)::integer from public.topics), 0, 'other authenticated user cannot read directions');
reset role;
select set_config('request.jwt.claim.sub', '7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70', true);
select is((select count(*)::integer from public.cards), 1797, 'owner can read imported cards');

select * from finish();
rollback;
