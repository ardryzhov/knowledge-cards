import { execFile } from 'node:child_process'
import process from 'node:process'
import { setTimeout as delay } from 'node:timers/promises'
import { promisify } from 'node:util'

// Uses only the local Supabase Docker database. All fixture IDs are fixed and
// removed at the end; no remote connection string or key is involved.
const exec = promisify(execFile)
const container = 'supabase_db_knowledge-cards'
const owner = '11000000-0000-4000-8000-000000000031'
const topicA = '22000000-0000-4000-8000-000000000031'
const topicB = '22000000-0000-4000-8000-000000000032'
const cardA = '33000000-0000-4000-8000-000000000031'
const cardB = '33000000-0000-4000-8000-000000000032'
const cardA2 = '33000000-0000-4000-8000-000000000033'
const cardA3 = '33000000-0000-4000-8000-000000000034'
const sessionA = '44000000-0000-4000-8000-000000000031'
const sessionB = '44000000-0000-4000-8000-000000000032'
const attemptA = '77000000-0000-4000-8000-000000000031'
const attemptB = '77000000-0000-4000-8000-000000000032'
const attemptA2 = '77000000-0000-4000-8000-000000000033'
const attemptA3 = '77000000-0000-4000-8000-000000000034'

async function sql(query) {
  const result = await exec('docker', ['exec', container, 'psql', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1', '-Atc', query])
  return result.stdout.trim()
}
function responseJson(output) {
  const line = output.split('\n').find(value => value.trim().startsWith('{'))
  if (!line) throw new Error(`No JSON response: ${output}`)
  return JSON.parse(line)
}

const cleanup = `
  delete from public.answer_history where user_id = '${owner}';
  delete from public.card_progress where user_id = '${owner}';
  delete from public.training_attempts where user_id = '${owner}';
  delete from public.training_sessions where user_id = '${owner}';
  delete from public.cards where user_id = '${owner}';
  delete from public.topics where user_id = '${owner}';
  delete from auth.users where id = '${owner}';
`

try {
  await sql(cleanup)
  await sql(`
    insert into auth.users(id,email) values ('${owner}','cards-concurrency@example.test');
    insert into public.topics(id,user_id,title) values
      ('${topicA}','${owner}','Concurrent answers'),
      ('${topicB}','${owner}','Finish race');
    insert into public.cards(id,user_id,topic_id,question,answer) values
      ('${cardA}','${owner}','${topicA}','A','A'),
      ('${cardB}','${owner}','${topicB}','B','B'),
      ('${cardA2}','${owner}','${topicA}','A2','A2'),
      ('${cardA3}','${owner}','${topicA}','A3','A3');
    insert into public.training_sessions(id,user_id,topic_id,mode) values
      ('${sessionA}','${owner}','${topicA}','spaced'),
      ('${sessionB}','${owner}','${topicB}','spaced');
    insert into public.training_attempts(id,user_id,session_id,card_id,position,status,issued_at) values
      ('${attemptA}','${owner}','${sessionA}','${cardA}',1,'issued',clock_timestamp()),
      ('${attemptB}','${owner}','${sessionB}','${cardB}',1,'issued',clock_timestamp());
    insert into public.training_attempts(id,user_id,session_id,card_id,position,status) values
      ('${attemptA2}','${owner}','${sessionA}','${cardA2}',2,'queued'),
      ('${attemptA3}','${owner}','${sessionA}','${cardA3}',3,'queued');
  `)

  const answer = event => `
    begin;
    set local request.jwt.claim.sub = '${owner}';
    select public.record_answer('${event}','${sessionA}','${cardA}',true,0,null,'${attemptA}');
    select pg_sleep(1);
    commit;
  `
  const first = sql(answer('66000000-0000-4000-8000-000000000031'))
  await delay(300)
  const second = sql(answer('66000000-0000-4000-8000-000000000032'))
  const results = await Promise.allSettled([first, second])
  if (results.filter(result => result.status === 'fulfilled').length !== 1) {
    throw new Error('Concurrent answer race did not accept exactly one event')
  }
  const answerState = await sql(`
    select (select count(*) from public.answer_history where attempt_id = '${attemptA}'),
           (select total_correct from public.card_progress where card_id = '${cardA}');
  `)
  if (answerState !== '1|1') throw new Error(`Unexpected answer state: ${answerState}`)

  const secondAttempt = responseJson(await sql(`
    set request.jwt.claim.sub = '${owner}';
    select public.next_training_attempt('${sessionA}');
  `))
  if (secondAttempt.attempt.attempt_id !== attemptA2) throw new Error('Second attempt was not issued')
  const answerSecond = sql(`
    begin;
    set local request.jwt.claim.sub = '${owner}';
    select public.record_answer('66000000-0000-4000-8000-000000000034',
      '${sessionA}','${cardA2}',true,0,null,'${attemptA2}');
    select pg_sleep(1);
    commit;
  `)
  await delay(300)
  const nextAfterAnswer = sql(`
    set request.jwt.claim.sub = '${owner}';
    select public.next_training_attempt('${sessionA}');
  `)
  const [savedSecond, nextResult] = await Promise.all([answerSecond, nextAfterAnswer])
  if (!savedSecond || responseJson(nextResult).attempt.attempt_id !== attemptA3) {
    throw new Error('Next attempt raced ahead of the previous answer')
  }

  const finish = sql(`
    begin;
    set local request.jwt.claim.sub = '${owner}';
    select public.finish_training_session('${sessionB}','completed');
    select pg_sleep(1);
    commit;
  `)
  await delay(300)
  const lateAnswer = sql(`
    begin;
    set local request.jwt.claim.sub = '${owner}';
    select public.record_answer('66000000-0000-4000-8000-000000000033',
      '${sessionB}','${cardB}',true,0,null,'${attemptB}');
    commit;
  `)
  const finishResults = await Promise.allSettled([finish, lateAnswer])
  if (finishResults[0].status !== 'fulfilled' || finishResults[1].status !== 'rejected') {
    throw new Error('Finish/answer race did not reject the late answer')
  }
  const finishState = await sql(`
    select (select status from public.training_sessions where id = '${sessionB}'),
           (select count(*) from public.answer_history where attempt_id = '${attemptB}');
  `)
  if (finishState !== 'completed|0') throw new Error(`Unexpected finished state: ${finishState}`)
  process.stdout.write('Concurrent answers, answer/next and finish/answer races: PASS\n')
} finally {
  await sql(cleanup)
}
