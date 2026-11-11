import { useEffect, useMemo, useRef, useState } from 'react'
import { motion, useReducedMotion } from 'motion/react'
import { ArrowLeft, Check, Eye, Lightbulb, LogOut, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  allFilters, categoryName, filterLabels, readTrainingFilters, sectionTitle, topicHash, trainingHash,
  type TrainingFilters,
} from '@/lib/training-filters'
import type { TopicSummary } from '@/lib/supabase/data'
import {
  finishTrainingSession, nextTrainingAttempt, recordTrainingAnswer, startTrainingSession,
  type TrainingMode, type TrainingSnapshot, type TrainingStart,
} from '@/lib/supabase/training'
import { MarkdownAnswer } from './MarkdownAnswer'
import './training.css'

type Phase = 'select' | 'loading' | 'conflict' | 'active' | 'empty' | 'completed' | 'error'
type PendingAnswer = {
  eventId: string
  sessionId: string
  attemptId: string
  cardId: string
  correct: boolean
  hintsUsed: number
  durationMs: number
}

const modeNames: Record<TrainingMode, string> = {
  spaced: 'Интервальное повторение',
  infinite: 'Свободная практика',
  mistakes: 'Работа над ошибками',
}
const difficultyNames = { easy: 'Легко', medium: 'Средне', hard: 'Сложно' }

function trainingRequest(topics: readonly TopicSummary[]): { topicId: string | null; mode: TrainingMode | null; filters: TrainingFilters } {
  const params = new URLSearchParams(window.location.hash.split('?')[1])
  const topicId = params.get('topic')
  const mode = params.get('mode')
  return {
    topicId: topicId && topics.some(topic => topic.id === topicId) ? topicId : null,
    mode: mode === 'spaced' || mode === 'infinite' || mode === 'mistakes' ? mode : null,
    filters: readTrainingFilters(params),
  }
}

export function Training({ topicItems, onSignOut }: { topicItems: readonly TopicSummary[]; onSignOut?: () => void }) {
  const request = useMemo(() => trainingRequest(topicItems), [topicItems])
  const requested: { topicId: string; mode: TrainingMode; filters: TrainingFilters } | null = useMemo(() =>
    request.topicId && request.mode ? { topicId: request.topicId, mode: request.mode, filters: request.filters } : null,
  [request])
  const [selectedTopic, setSelectedTopic] = useState(request.topicId ?? topicItems[0]?.id ?? '')
  const [selectedMode, setSelectedMode] = useState<TrainingMode>('spaced')
  const [selectedFilters, setSelectedFilters] = useState<TrainingFilters>(request.filters)
  const [phase, setPhase] = useState<Phase>(requested ? 'loading' : 'select')
  const [conflict, setConflict] = useState<TrainingStart | null>(null)
  const [sessionId, setSessionId] = useState<string | null>(null)
  const [snapshot, setSnapshot] = useState<TrainingSnapshot | null>(null)
  const [revealed, setRevealed] = useState(false)
  const [hintsUsed, setHintsUsed] = useState(0)
  const [openHint, setOpenHint] = useState<number | null>(null)
  const [pending, setPending] = useState<PendingAnswer | null>(null)
  const [pendingFinal, setPendingFinal] = useState<TrainingSnapshot | null>(null)
  const [needsNext, setNeedsNext] = useState(false)
  const [error, setError] = useState('')
  const [retryKey, setRetryKey] = useState(0)
  const busy = useRef(false)
  const shownAt = useRef(performance.now())
  const reducedMotion = useReducedMotion()

  useEffect(() => {
    if (!requested) return
    let active = true
    const { topicId, mode, filters } = requested
    startTrainingSession(topicId, mode, filters).then(async started => {
      if (!active) return
      if (started.conflict) {
        setConflict(started)
        setPhase('conflict')
        return
      }
      const id = started.session_id
      setSessionId(id)
      const next = await nextTrainingAttempt(id)
      if (!active) return
      setSnapshot(next)
      shownAt.current = performance.now()
      if (!next.attempt) {
        await finishTrainingSession(id, 'completed')
        if (!active) return
        setPhase(next.viewed === 0 ? 'empty' : 'completed')
      } else setPhase('active')
    }).catch(() => {
      if (!active) return
      setError('Не удалось открыть тренировку. Проверьте подключение и повторите попытку.')
      setPhase('error')
    })
    return () => { active = false }
    // A hash change remounts this component; retryKey is used for explicit retry.
  }, [retryKey, requested])

  const attempt = snapshot?.attempt
  const topicTitle = topicItems.find(topic => topic.id === request.topicId)?.title
  const activeFilters = snapshot?.filters ?? request.filters
  const backHref = request.topicId ? topicHash(request.topicId, activeFilters) : '#topics'

  async function finishExhausted(id: string, next: TrainingSnapshot) {
    setPendingFinal(next)
    await finishTrainingSession(id, 'completed')
    setPendingFinal(null)
    setSnapshot(next)
    setNeedsNext(false)
    setPhase(next.viewed === 0 ? 'empty' : 'completed')
  }

  async function loadNext(id: string) {
    const next = await nextTrainingAttempt(id)
    if (!next.attempt) {
      await finishExhausted(id, next)
      return
    }
    setSnapshot(next)
    setNeedsNext(false)
    setRevealed(false)
    setHintsUsed(0)
    setOpenHint(null)
    shownAt.current = performance.now()
    setPhase('active')
  }

  async function saveAnswer(value: PendingAnswer) {
    if (busy.current) return
    busy.current = true
    setError('')
    try {
      await recordTrainingAnswer(value)
      setPending(null)
      setNeedsNext(true)
      await loadNext(value.sessionId)
    } catch (cause) {
      const code = typeof cause === 'object' && cause !== null && 'code' in cause ? cause.code : null
      const message = typeof cause === 'object' && cause !== null && 'message' in cause ? String(cause.message) : ''
      if (code === '23505') {
        setPending(null)
        setNeedsNext(true)
        setError('Эта попытка уже оценена в другом окне. Загрузите актуальную карточку.')
      } else if (code === '22023' && /Card no longer matches session filters|Active card not found/.test(message)) {
        setPending(null)
        setNeedsNext(true)
        setError('Карточка изменилась или стала недоступна. Загрузите актуальную карточку.')
      } else {
        setError('Не удалось сохранить ответ или загрузить следующую карточку. Повторите попытку.')
      }
    } finally {
      busy.current = false
    }
  }

  function evaluate(correct: boolean) {
    if (!revealed || !attempt || !sessionId || busy.current || pending || needsNext) return
    const value: PendingAnswer = {
      eventId: crypto.randomUUID(), sessionId,
      attemptId: attempt.attempt_id, cardId: attempt.card.id,
      correct, hintsUsed,
      durationMs: Math.max(0, Math.round(performance.now() - shownAt.current)),
    }
    setPending(value)
    void saveAnswer(value)
  }

  async function closeSession(status: 'completed' | 'abandoned') {
    if (!sessionId || busy.current) return
    busy.current = true
    setError('')
    try {
      await finishTrainingSession(sessionId, status)
      if (status === 'abandoned') window.location.hash = '#dashboard'
      else setPhase('completed')
    } catch {
      setError('Не удалось завершить тренировку. Повторите попытку.')
    } finally {
      busy.current = false
    }
  }

  function choose() {
    if (!selectedTopic) return
    window.location.hash = trainingHash(selectedTopic, selectedFilters, selectedMode)
  }

  async function replaceSession() {
    if (!conflict || busy.current) return
    busy.current = true
    setError('')
    try {
      await finishTrainingSession(conflict.session_id, 'abandoned')
      setConflict(null)
      setPhase('loading')
      setRetryKey(value => value + 1)
    } catch {
      setError('Не удалось завершить прежнюю сессию. Повторите попытку.')
    } finally {
      busy.current = false
    }
  }

  const header = <div className="training-topbar">
    <a href={backHref} className="training-back" aria-label="К выбору раздела"><ArrowLeft size={23} /></a>
    <span className="training-counter">{requested ? modeNames[requested.mode] : 'Тренировка'}</span>
    <div className="training-top-actions">{sessionId && phase === 'active' && <button className="training-cancel" type="button" onClick={() => void closeSession('abandoned')}>Отменить</button>}{onSignOut && <button className="signout-button" onClick={onSignOut} type="button" aria-label="Выйти из аккаунта" title="Выйти"><LogOut size={17} /></button>}</div>
  </div>

  if (!requested) return <section className="training-screen" aria-label="Выбор тренировки">{header}<div className="training-card-slot"><div className="training-finished training-surface training-setup"><h1>Начать тренировку</h1>{topicItems.length ? <><label>Направление<select value={selectedTopic} onChange={event => { setSelectedTopic(event.target.value); setSelectedFilters(allFilters) }}>{topicItems.map(topic => <option key={topic.id} value={topic.id}>{topic.title}</option>)}</select></label><p className="training-filter-summary">{filterLabels(selectedFilters).join(' · ')}</p><fieldset><legend>Режим</legend>{(Object.keys(modeNames) as TrainingMode[]).map(mode => <label key={mode}><input type="radio" name="training-mode" value={mode} checked={selectedMode === mode} onChange={() => setSelectedMode(mode)} />{modeNames[mode]}</label>)}</fieldset><Button onClick={choose}>Продолжить</Button><a className="training-select-content" href={topicHash(selectedTopic, selectedFilters)}>Выбрать раздел и группу</a></> : <p>Пока нет направлений для тренировки.</p>}</div></div><div className="training-session-stats" /></section>

  if (phase === 'conflict' && conflict) return <section className="training-screen" aria-label="Выбор активной сессии">{header}<div className="training-card-slot"><div className="training-finished training-surface"><h1>Уже есть активная тренировка</h1><p>Текущие фильтры: {filterLabels(conflict.filters).join(' · ')}.</p><p>Вы выбрали: {filterLabels(request.filters).join(' · ')}.</p>{error && <p role="alert">{error}</p>}<div className="training-conflict-actions"><Button onClick={() => { window.location.hash = trainingHash(request.topicId!, conflict.filters, request.mode!) }}>Продолжить текущую</Button><Button variant="outline" onClick={() => void replaceSession()}>Завершить и начать новую</Button></div></div></div><div className="training-session-stats" /></section>

  if (phase === 'loading' || phase === 'error') return <section className="training-screen" aria-label="Тренировка">{header}<div className="training-card-slot"><div className="training-finished training-surface"><h1>{phase === 'loading' ? 'Загружаем тренировку…' : 'Не удалось открыть тренировку'}</h1>{phase === 'error' && <><p role="alert">{error}</p><Button onClick={() => { setError(''); setPhase('loading'); setRetryKey(value => value + 1) }}>Повторить</Button></>}</div></div><div className="training-session-stats" /></section>

  if (phase === 'completed' || phase === 'empty') return <section className="training-screen" aria-label="Тренировка">{header}<div className="training-card-slot"><div className="training-finished training-surface"><h1>{phase === 'empty' ? 'Нет доступных карточек' : 'Тренировка завершена'}</h1><p>{phase === 'empty' ? 'Для этого режима сейчас нет доступных карточек. Попробуйте другие фильтры или вернитесь позже.' : `Просмотрено: ${snapshot?.viewed ?? 0}. Знал: ${snapshot?.correct ?? 0}. Не знал: ${snapshot?.incorrect ?? 0}.`}</p><Button asChild><a href={backHref}>К выбору раздела</a></Button></div></div><div className="training-session-stats" /></section>

  if (!attempt) return null
  const card = attempt.card
  const metadata = <div className="training-card-meta"><span>{sectionTitle(card.section)} · {categoryName(card.category) ?? 'Без группы'}</span><span className={`training-difficulty training-difficulty-${card.difficulty}`}>{difficultyNames[card.difficulty]}</span></div>
  return <section className="training-screen" aria-label="Тренировка">
    {header}
    <div className="training-card-slot">
      <motion.div key={attempt.attempt_id} className="training-card" data-attempt-id={attempt.attempt_id} initial={{ opacity: 0, y: reducedMotion ? 0 : 10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: reducedMotion ? 0 : 0.18 }}>
        <motion.div className="training-card-inner" animate={{ rotateY: revealed && !reducedMotion ? 180 : 0 }} transition={{ duration: reducedMotion ? 0 : 0.45 }}>
          <div className="training-face training-front training-surface" aria-hidden={revealed} inert={revealed} style={reducedMotion && revealed ? { visibility: 'hidden' } : undefined}>
            {metadata}
            <div className="training-question-scroll" tabIndex={0} aria-label="Вопрос"><div><h1>{card.question}</h1>{card.context && <p className="training-context">{card.context}</p>}{card.code && <pre className="training-question-code"><code>{card.code}</code></pre>}</div></div>
            <div className="training-card-controls">
              {(card.hint_1 || card.hint_2) && <div className="training-hint-buttons">
                {card.hint_1 && <Button variant="outline" aria-expanded={openHint === 0} onClick={() => { setHintsUsed(Math.max(hintsUsed, 1)); setOpenHint(openHint === 0 ? null : 0) }}><Lightbulb size={19} />Подсказка 1</Button>}
                {card.hint_2 && <Button variant="outline" disabled={hintsUsed === 0} aria-expanded={openHint === 1} onClick={() => { setHintsUsed(2); setOpenHint(openHint === 1 ? null : 1) }}><Lightbulb size={19} />Подсказка 2</Button>}
              </div>}
              {openHint !== null && <p className="training-hint-text" role="status">{openHint === 0 ? card.hint_1 : card.hint_2}</p>}
              <Button onClick={() => setRevealed(true)} className="training-reveal"><Eye size={22} />Показать ответ</Button>
            </div>
          </div>
          <div className="training-face training-answer training-surface" aria-hidden={!revealed} inert={!revealed} style={reducedMotion ? { transform: 'none', visibility: revealed ? 'visible' : 'hidden' } : undefined}>
            {metadata}
            <div className="training-answer-scroll" tabIndex={revealed ? 0 : -1} aria-label="Ответ"><span className="training-answer-label">Ответ</span><h2 className="training-answer-title">{card.question.replace('\n', ' ')}</h2><MarkdownAnswer answer={card.answer} code={card.code ?? undefined} /></div>
            <div className="training-card-controls"><div className="training-rating"><Button variant="danger" disabled={busy.current || !!pending || needsNext} onClick={() => evaluate(false)}><X size={21} />Не знал</Button><Button disabled={busy.current || !!pending || needsNext} onClick={() => evaluate(true)}><Check size={22} />Знал</Button></div>{error && <div className="training-save-error" role="alert"><p>{error}</p><Button variant="outline" onClick={() => {
              if (busy.current) return
              if (pending) { void saveAnswer(pending); return }
              if (!sessionId || !needsNext) return
              busy.current = true
              const action = pendingFinal ? finishExhausted(sessionId, pendingFinal) : loadNext(sessionId)
              void action.then(() => setError('')).catch(() => setError('Не удалось загрузить следующую карточку. Повторите попытку.')).finally(() => { busy.current = false })
            }}>Повторить</Button></div>}</div>
          </div>
        </motion.div>
      </motion.div>
    </div>
    <div className="training-session-stats" aria-label="Прогресс сессии"><span>{topicTitle}</span><span>{filterLabels(activeFilters).join(' · ')}</span><span>Просмотрено: {(snapshot?.viewed ?? 0) + 1}</span><span>Оценено: {snapshot?.viewed ?? 0}{snapshot?.total !== null ? ` / ${snapshot?.total ?? 0}` : ''}</span><span>Знал: {snapshot?.correct ?? 0}</span><span>Не знал: {snapshot?.incorrect ?? 0}</span>{requested.mode === 'infinite' && <button type="button" onClick={() => void closeSession('completed')}>Завершить</button>}</div>
  </section>
}
