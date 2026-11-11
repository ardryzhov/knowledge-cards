begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

insert into auth.users (id, email) values
  ('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70', 'java-core-owner@example.test'),
  ('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a71', 'java-core-other@example.test');
savepoint backend_absent;
select app_private.import_java_core_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70');
select is((select count(*)::integer from public.topics where id = '4535e892-4d68-41c2-a5a8-87935d2f5134'), 1, 'missing Backend created with permanent UUID');
select is((select count(*)::integer from public.cards where topic_id = '4535e892-4d68-41c2-a5a8-87935d2f5134'), 20, 'first import creates all cards');
rollback to savepoint backend_absent;
insert into public.topics (id, user_id, title) values
  ('58461757-2fd1-4df5-b8da-ad858f2a6c81', '7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70', 'Backend');

select ok(not has_function_privilege('authenticated', 'app_private.import_java_core_v1(uuid)', 'EXECUTE'), 'browser cannot invoke content importer');
select ok(not has_table_privilege('authenticated', 'public.cards', 'INSERT'), 'browser cannot insert cards');
select throws_ok($$select app_private.import_java_core_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a71')$$,
  '22023', 'Unexpected content owner', 'importer rejects another owner');
select app_private.import_java_core_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70');

select is((select count(*)::integer from public.topics where user_id = '7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70' and title = 'Backend'), 1, 'existing Backend topic reused');
select is((select count(*)::integer from public.cards where user_id = '7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70'), 20, 'exactly 20 cards imported');
select is((select count(distinct category)::integer from public.cards where user_id = '7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70'), 9, 'nine source groups retained');
select is((select count(*)::integer from public.cards where section = '01-java-core' and topic_id = '58461757-2fd1-4df5-b8da-ad858f2a6c81'), 20, 'all cards use existing Backend and Java Core section');
select is((select count(*)::integer from public.cards where difficulty = 'hard' and topic_id = '58461757-2fd1-4df5-b8da-ad858f2a6c81'), 2, 'source difficulties retained');
select is((select count(*)::integer from public.cards where context is null and code is null), 20, 'optional nulls remain SQL NULL');
select is((select count(*)::integer from public.cards where hint_1 is not null and hint_2 is not null), 2, 'both pairs of hints retained');
select is((select hint_1 from public.cards where id = '18c71a00-5eeb-4933-a175-8efbec615fb9'),
  'Представь, как HashSet сначала ищет место для объекта.', 'original hint text retained');
select is((select answer from public.cards where id = 'a21911e3-7526-4d8a-9a90-7d7cd2e31796'),
  'Java передаёт аргументы по значению. Для объекта значением служит ссылка: метод получает её копию и может через неё изменить доступный объект. Присваивание этой копии другой ссылки не меняет переменную вызывающего кода.', 'original answer text retained');
set local role authenticated;
set local request.jwt.claim.sub = '7d53c0ee-fd2b-401a-ae4d-e6c0caa32a71';
select is((select count(*)::integer from public.cards where section = '01-java-core'), 0, 'other authenticated user cannot read imported cards');
reset role;

insert into public.card_progress (user_id, card_id, status, total_correct, consecutive_correct)
  values ('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70', 'a21911e3-7526-4d8a-9a90-7d7cd2e31796', 'learning', 2, 2);
select app_private.import_java_core_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70');
select is((select count(*)::integer from public.cards where topic_id = '58461757-2fd1-4df5-b8da-ad858f2a6c81'), 20, 'repeat import creates no cards');
select is((select count(distinct id)::integer from public.cards where topic_id = '58461757-2fd1-4df5-b8da-ad858f2a6c81'), 20, 'UUIDs remain stable');
select is((select total_correct from public.card_progress where card_id = 'a21911e3-7526-4d8a-9a90-7d7cd2e31796'), 2, 'repeat import keeps progress');

select set_config('request.jwt.claim.sub', '7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70', true);
select set_config('test.java.spaced', public.start_section_training_session(
  '58461757-2fd1-4df5-b8da-ad858f2a6c81', 'spaced', 'named', '01-java-core',
  'named', 'Полиморфизм', 'hard')::text, true);
select set_config('test.java.spaced_attempt', public.next_training_attempt((current_setting('test.java.spaced')::jsonb ->> 'session_id')::uuid)::text, true);
select is((current_setting('test.java.spaced_attempt')::jsonb -> 'attempt' -> 'card' ->> 'id'),
  '3925522e-b319-4203-b6a2-00d017ea7bd0', 'new spaced card selected by all filters');
select public.record_answer('3771d472-5be9-4d6a-aa6f-38ea487d1fe1',
  (current_setting('test.java.spaced')::jsonb ->> 'session_id')::uuid,
  '3925522e-b319-4203-b6a2-00d017ea7bd0', true, 0, null,
  (current_setting('test.java.spaced_attempt')::jsonb -> 'attempt' ->> 'attempt_id')::uuid);
select ok((select next_review_at between clock_timestamp() + interval '23 hours' and clock_timestamp() + interval '25 hours'
  from public.card_progress where card_id = '3925522e-b319-4203-b6a2-00d017ea7bd0'), 'known answer schedules one day');
select public.finish_training_session((current_setting('test.java.spaced')::jsonb ->> 'session_id')::uuid, 'completed');

select set_config('test.java.infinite', public.start_section_training_session(
  '58461757-2fd1-4df5-b8da-ad858f2a6c81', 'infinite', 'named', '01-java-core',
  'named', 'Полиморфизм', 'hard')::text, true);
select set_config('test.java.infinite_attempt', public.next_training_attempt((current_setting('test.java.infinite')::jsonb ->> 'session_id')::uuid)::text, true);
select is((current_setting('test.java.infinite_attempt')::jsonb -> 'attempt' -> 'card' ->> 'id'),
  '3925522e-b319-4203-b6a2-00d017ea7bd0', 'infinite uses real filtered card');
select public.record_answer('3771d472-5be9-4d6a-aa6f-38ea487d1fe2',
  (current_setting('test.java.infinite')::jsonb ->> 'session_id')::uuid,
  '3925522e-b319-4203-b6a2-00d017ea7bd0', false, 0, null,
  (current_setting('test.java.infinite_attempt')::jsonb -> 'attempt' ->> 'attempt_id')::uuid);
select is((select total_incorrect from public.card_progress where card_id = '3925522e-b319-4203-b6a2-00d017ea7bd0'), 0, 'infinite does not change spaced progress');
select public.finish_training_session((current_setting('test.java.infinite')::jsonb ->> 'session_id')::uuid, 'completed');

select set_config('test.java.mistakes_empty', public.start_section_training_session(
  '58461757-2fd1-4df5-b8da-ad858f2a6c81', 'mistakes', 'named', '01-java-core',
  'named', 'Исключения', 'hard')::text, true);
select is((public.next_training_attempt((current_setting('test.java.mistakes_empty')::jsonb ->> 'session_id')::uuid) ->> 'total')::integer,
  0, 'mistakes initially empty');
select public.finish_training_session((current_setting('test.java.mistakes_empty')::jsonb ->> 'session_id')::uuid, 'completed');

select set_config('test.java.wrong', public.start_section_training_session(
  '58461757-2fd1-4df5-b8da-ad858f2a6c81', 'spaced', 'named', '01-java-core',
  'named', 'Исключения', 'hard')::text, true);
select set_config('test.java.wrong_attempt', public.next_training_attempt((current_setting('test.java.wrong')::jsonb ->> 'session_id')::uuid)::text, true);
select public.record_answer('3771d472-5be9-4d6a-aa6f-38ea487d1fe3',
  (current_setting('test.java.wrong')::jsonb ->> 'session_id')::uuid,
  '004caa4b-21a4-4f34-9d8e-690785a01ddd', false, 0, null,
  (current_setting('test.java.wrong_attempt')::jsonb -> 'attempt' ->> 'attempt_id')::uuid);
select is((select total_incorrect from public.card_progress where card_id = '004caa4b-21a4-4f34-9d8e-690785a01ddd'), 1, 'wrong answer records a mistake');
select public.finish_training_session((current_setting('test.java.wrong')::jsonb ->> 'session_id')::uuid, 'completed');
select set_config('test.java.mistakes', public.start_section_training_session(
  '58461757-2fd1-4df5-b8da-ad858f2a6c81', 'mistakes', 'named', '01-java-core',
  'named', 'Исключения', 'hard')::text, true);
select is((public.next_training_attempt((current_setting('test.java.mistakes')::jsonb ->> 'session_id')::uuid) -> 'attempt' -> 'card' ->> 'id'),
  '004caa4b-21a4-4f34-9d8e-690785a01ddd', 'mistakes selects wrong card in requested group');

select * from finish();
rollback;
