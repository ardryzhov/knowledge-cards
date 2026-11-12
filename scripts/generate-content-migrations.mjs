import { readFile, readdir, writeFile } from 'node:fs/promises'
import { basename, join } from 'node:path'
import process from 'node:process'
import { Console } from 'node:console'
import { parseDocument } from 'yaml'

const console = new Console(process.stdout, process.stderr)
const ownerId = '7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70'
const root = 'cards'
const output = 'supabase/migrations'
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const directions = [
  { name: 'Backend', topicId: '4535e892-4d68-41c2-a5a8-87935d2f5134', color: 'green', icon: 'development', order: 10, migration: '20261112000200_backend_content.sql' },
  { name: 'Analysis', topicId: '33b96b1c-61f5-415a-acce-090b50c1695f', color: 'blue', icon: null, order: 20, migration: '20261112000300_analysis_content.sql' },
  { name: 'Testing', topicId: 'abd157bc-5080-44c5-b397-21e54624946e', color: 'amber', icon: null, order: 30, migration: '20261112000400_testing_content.sql' },
  { name: 'DevOps', topicId: '5246f12a-cc72-4c26-88c2-a0ccab034f22', color: 'green', icon: 'devops', order: 40, migration: '20261112000500_devops_content.sql' },
  { name: 'LiveCoding', topicId: '21a9807d-0934-4abc-8e0b-dad2b7bbf564', color: 'blue', icon: 'development', order: 50, migration: '20261112000600_livecoding_content.sql' },
  { name: 'ProductEngineering', topicId: '61bffec6-354c-4ddb-a7c8-3f04d8ca8635', color: 'amber', icon: null, order: 60, migration: '20261112000700_productengineering_content.sql' },
]
const fields = ['id', 'question', 'answer', 'category', 'context', 'hint_1', 'hint_2', 'difficulty', 'code']
const allIds = new Map()
const mode = process.argv[2]
if (!['--write', '--check'].includes(mode)) throw new Error('Use --write before application or --check to verify existing migrations')

for (const direction of directions) {
  const names = (await readdir(join(root, direction.name))).filter(name => name.endsWith('.yaml')).sort()
  if (!names.length) throw new Error(`${direction.name}: no YAML files`)
  const cards = []
  for (const name of names) {
    const file = join(root, direction.name, name)
    const document = parseDocument(await readFile(file, 'utf8'), { uniqueKeys: true })
    if (document.errors.length) throw new Error(`${file}: ${document.errors.map(String).join('; ')}`)
    const source = document.toJS()
    if (typeof source?.topic !== 'string' || !source.topic.trim() || !Array.isArray(source.cards) || !source.cards.length) {
      throw new Error(`${file}: expected topic and a nonempty cards list`)
    }
    const section = basename(name, '.yaml')
    if (section.length > 160) throw new Error(`${file}: section too long`)
    const questions = new Set()
    for (const [index, card] of source.cards.entries()) {
      if (Object.keys(card).sort().join(',') !== [...fields].sort().join(',')) throw new Error(`${file} #${index + 1}: unexpected fields`)
      if (typeof card.id !== 'string' || !uuid.test(card.id)) throw new Error(`${file} #${index + 1}: invalid UUID`)
      const oldFile = allIds.get(card.id)
      if (oldFile) throw new Error(`${file} #${index + 1}: duplicate UUID from ${oldFile}`)
      allIds.set(card.id, file)
      if (typeof card.question !== 'string' || !card.question.trim()
        || typeof card.answer !== 'string' || !card.answer.trim()) throw new Error(`${file} #${index + 1}: blank question or answer`)
      if (questions.has(card.question.trim())) throw new Error(`${file} #${index + 1}: duplicate question`)
      questions.add(card.question.trim())
      if (card.category !== null && (typeof card.category !== 'string' || card.category.length > 160)) {
        throw new Error(`${file} #${index + 1}: invalid category`)
      }
      if (!['easy', 'medium', 'hard'].includes(card.difficulty)) throw new Error(`${file} #${index + 1}: invalid difficulty`)
      for (const key of ['context', 'hint_1', 'hint_2', 'code']) {
        if (card[key] !== null && typeof card[key] !== 'string') throw new Error(`${file} #${index + 1}: invalid ${key}`)
      }
      cards.push({ ...card, section })
    }
  }
  const tag = `$cards_${direction.name.toLowerCase()}_v1$`
  const payload = JSON.stringify(cards, null, 2)
  if (payload.includes(tag)) throw new Error(`${direction.name}: SQL delimiter appears in content`)
  const functionName = `import_content_${direction.name.toLowerCase()}_v1`
  const sql = `-- Immutable reviewed snapshot from cards/${direction.name}/*.yaml.
-- ${cards.length} cards in ${names.length} sections; no content is deleted or restored.
begin;

create or replace function app_private.${functionName}(p_owner uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $import$
declare
  v_topic uuid;
  v_topic_count integer;
  v_changed integer;
  v_cards jsonb := ${tag}${payload}${tag}::jsonb;
begin
  if p_owner is distinct from '${ownerId}'::uuid then
    raise exception 'Unexpected content owner' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users where id = p_owner) then
    raise exception 'Content owner account not found' using errcode = '22023';
  end if;

  -- Migrations have elevated rights. Scope every lookup and write to this owner.
  select count(*) into v_topic_count from public.topics
    where user_id = p_owner and title = '${direction.name}';
  if v_topic_count > 1 then
    raise exception 'Multiple ${direction.name} topics for content owner' using errcode = '23505';
  elsif v_topic_count = 1 then
    select id into v_topic from public.topics
      where user_id = p_owner and title = '${direction.name}';
    if exists (select 1 from public.topics where id = v_topic and deleted_at is not null) then
      raise exception '${direction.name} topic is soft deleted; restore separately' using errcode = '22023';
    end if;
  else
    v_topic := '${direction.topicId}'::uuid;
    if exists (select 1 from public.topics where id = v_topic) then
      raise exception 'Reserved ${direction.name} UUID is in use' using errcode = '23505';
    end if;
    insert into public.topics (id, user_id, title, color, icon, sort_order)
      values (v_topic, p_owner, '${direction.name}', '${direction.color}', ${direction.icon === null ? 'null' : `'${direction.icon}'`}, ${direction.order});
  end if;

  if exists (
    select 1 from public.cards c
    join jsonb_to_recordset(v_cards) as source(id uuid) on source.id = c.id
    where c.user_id <> p_owner or c.topic_id <> v_topic or c.deleted_at is not null
  ) then
    raise exception 'Content UUID belongs to another scope or a soft-deleted card' using errcode = '23505';
  end if;
  if exists (
    select 1 from public.cards c
    join jsonb_to_recordset(v_cards) as source(id uuid, section text, question text)
      on source.question = c.question and source.section = c.section and source.id <> c.id
    where c.user_id = p_owner and c.topic_id = v_topic and c.deleted_at is null
  ) then
    raise exception 'Question already exists with a different UUID in its section' using errcode = '23505';
  end if;

  insert into public.cards
    (id, user_id, topic_id, section, category, question, answer, context,
     hint_1, hint_2, difficulty, code)
  select source.id, p_owner, v_topic, source.section, source.category,
         source.question, source.answer, source.context, source.hint_1,
         source.hint_2, source.difficulty, source.code
    from jsonb_to_recordset(v_cards)
      as source(id uuid, section text, category text, question text, answer text,
                context text, hint_1 text, hint_2 text, difficulty text, code text)
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
  if v_changed <> ${cards.length} then
    raise exception '${direction.name} import affected % cards, expected ${cards.length}', v_changed;
  end if;
end;
$import$;
revoke all on function app_private.${functionName}(uuid) from public, anon, authenticated;

do $install$
begin
  if exists (select 1 from auth.users where id = '${ownerId}'::uuid) then
    perform app_private.${functionName}('${ownerId}'::uuid);
  elsif exists (select 1 from auth.users) then
    raise exception 'Configured content owner not found; import cancelled' using errcode = '22023';
  else
    raise notice '${direction.name} content import skipped: no auth users in this database';
  end if;
end;
$install$;
commit;
`
  const target = join(output, direction.migration)
  if (mode === '--check') {
    if (await readFile(target, 'utf8') !== sql) throw new Error(`${target}: snapshot differs from YAML`)
  } else {
    await writeFile(target, sql)
  }
  console.log(`${direction.name}: ${names.length} sections, ${cards.length} cards, ${target}`)
}
console.log(`${allIds.size} distinct stable UUIDs validated`)
