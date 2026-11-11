import { readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import process from 'node:process'
import { Console } from 'node:console'
import { parseDocument } from 'yaml'

const console = new Console(process.stdout, process.stderr)

const sourcePath = resolve('cards/Backend/01-java-core/01-java-core-draft.yaml')
const migrationPath = resolve('supabase/migrations/20261112000100_java_core_content.sql')
const ownerId = '7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70'
const backendId = '4535e892-4d68-41c2-a5a8-87935d2f5134'
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const requiredKeys = ['id', 'question', 'answer', 'category', 'context', 'hint_1', 'hint_2', 'difficulty', 'code']

const document = parseDocument(await readFile(sourcePath, 'utf8'), { uniqueKeys: true })
if (document.errors.length) throw new Error(document.errors.map(String).join('\n'))
const source = document.toJS()
if (source?.topic !== 'Java Core' || !Array.isArray(source.cards) || source.cards.length !== 20) {
  throw new Error('Expected Java Core source with exactly 20 cards')
}
const ids = new Set()
const questions = new Set()
for (const [index, card] of source.cards.entries()) {
  if (Object.keys(card).sort().join(',') !== [...requiredKeys].sort().join(',')) {
    throw new Error(`Card ${index + 1}: unexpected or missing fields`)
  }
  if (typeof card.id !== 'string' || !uuid.test(card.id) || ids.has(card.id)) {
    throw new Error(`Card ${index + 1}: missing or repeated UUID`)
  }
  ids.add(card.id)
  if (typeof card.question !== 'string' || !card.question.trim()
    || typeof card.answer !== 'string' || !card.answer.trim()) {
    throw new Error(`Card ${index + 1}: blank question or answer`)
  }
  if (questions.has(card.question.trim())) throw new Error(`Card ${index + 1}: repeated question`)
  questions.add(card.question.trim())
  if (typeof card.category !== 'string' || !card.category.trim() || card.category.length > 160) {
    throw new Error(`Card ${index + 1}: invalid category`)
  }
  if (!['easy', 'medium', 'hard'].includes(card.difficulty)) {
    throw new Error(`Card ${index + 1}: invalid difficulty`)
  }
  for (const key of ['context', 'hint_1', 'hint_2', 'code']) {
    if (card[key] !== null && typeof card[key] !== 'string') {
      throw new Error(`Card ${index + 1}: invalid ${key}`)
    }
  }
}

const payload = JSON.stringify(source.cards, null, 2)
if (payload.includes('$java_core_cards$')) throw new Error('SQL delimiter appears in source')
const sql = `-- Java Core content snapshot. Source: cards/Backend/01-java-core/01-java-core-draft.yaml
-- Owner UUID was supplied for this migration. Never change this file after applying it.
-- On a clean local database without this auth user, installation is a no-op;
-- local SQL tests create the user and call the private import routine explicitly.
begin;

create or replace function app_private.import_java_core_v1(p_owner uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $import$
declare
  v_topic uuid;
  v_topic_count integer;
  v_changed integer;
  v_cards jsonb := $java_core_cards$${payload}$java_core_cards$::jsonb;
begin
  if p_owner is distinct from '${ownerId}'::uuid then
    raise exception 'Unexpected content owner' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users where id = p_owner) then
    raise exception 'Content owner account not found' using errcode = '22023';
  end if;

  -- Elevated migration rights bypass RLS. Every lookup and mutation below is owner scoped.
  select count(*) into v_topic_count
    from public.topics where user_id = p_owner and title = 'Backend';
  if v_topic_count > 1 then
    raise exception 'Multiple Backend topics for content owner' using errcode = '23505';
  elsif v_topic_count = 1 then
    select id into v_topic from public.topics
      where user_id = p_owner and title = 'Backend';
    if exists (select 1 from public.topics where id = v_topic and deleted_at is not null) then
      raise exception 'Backend topic is soft deleted; restore it separately' using errcode = '22023';
    end if;
  else
    v_topic := '${backendId}'::uuid;
    if exists (select 1 from public.topics where id = v_topic) then
      raise exception 'Reserved Backend UUID is already in use' using errcode = '23505';
    end if;
    insert into public.topics (id, user_id, title, description, color, icon, sort_order)
      values (v_topic, p_owner, 'Backend', 'Вопросы по backend-разработке', 'green', 'development', 10);
  end if;

  if exists (
    select 1 from public.cards c
    join jsonb_to_recordset(v_cards)
      as source(id uuid, question text) on source.id = c.id
    where c.user_id <> p_owner or c.topic_id <> v_topic or c.deleted_at is not null
  ) then
    raise exception 'Imported card UUID belongs to another scope or is soft deleted' using errcode = '23505';
  end if;
  if exists (
    select 1 from public.cards c
    join jsonb_to_recordset(v_cards)
      as source(id uuid, question text) on source.question = c.question and source.id <> c.id
    where c.user_id = p_owner and c.topic_id = v_topic and c.section = '01-java-core'
      and c.deleted_at is null
  ) then
    raise exception 'A Java Core question already exists with another UUID' using errcode = '23505';
  end if;

  insert into public.cards
    (id, user_id, topic_id, section, category, question, answer, context,
     hint_1, hint_2, difficulty, code)
  select source.id, p_owner, v_topic, '01-java-core', source.category,
         source.question, source.answer, source.context, source.hint_1,
         source.hint_2, source.difficulty, source.code
    from jsonb_to_recordset(v_cards)
      as source(id uuid, question text, answer text, category text, context text,
                hint_1 text, hint_2 text, difficulty text, code text)
  on conflict (id) do update set
    section = excluded.section,
    category = excluded.category,
    question = excluded.question,
    answer = excluded.answer,
    context = excluded.context,
    hint_1 = excluded.hint_1,
    hint_2 = excluded.hint_2,
    difficulty = excluded.difficulty,
    code = excluded.code
  where public.cards.user_id = p_owner and public.cards.topic_id = v_topic
    and public.cards.deleted_at is null;
  get diagnostics v_changed = row_count;
  if v_changed <> 20 then
    raise exception 'Java Core import affected % cards, expected 20', v_changed;
  end if;
end;
$import$;
revoke all on function app_private.import_java_core_v1(uuid) from public, anon, authenticated;

do $install$
begin
  if exists (select 1 from auth.users where id = '${ownerId}'::uuid) then
    perform app_private.import_java_core_v1('${ownerId}'::uuid);
  elsif exists (select 1 from auth.users) then
    raise exception 'Configured content owner not found; import cancelled' using errcode = '22023';
  else
    raise notice 'Java Core import skipped: owner account is absent in this database';
  end if;
end;
$install$;
commit;
`

if (process.argv.includes('--check')) {
  const current = await readFile(migrationPath, 'utf8')
  if (current !== sql) throw new Error('Java Core SQL migration differs from source')
  console.log('Java Core source and SQL migration match: 20 stable UUIDs')
} else {
  await writeFile(migrationPath, sql)
  console.log(`Wrote ${migrationPath}: 20 cards`)
}
