import { randomUUID } from 'node:crypto'
import type { Page } from '@playwright/test'
import { sampleCards, type MockCard } from './mock-owner'
import type { TrainingFilters } from '../src/lib/training-filters'

type Mode = 'spaced' | 'infinite' | 'mistakes'
type Card = MockCard
type Attempt = { id: string; card: Card; position: number; status: 'queued' | 'issued' | 'answered' | 'skipped'; eventId?: string; payload?: Record<string, unknown> }
type Session = { id: string; topicId: string; mode: Mode; filters: TrainingFilters; status: 'active' | 'completed' | 'abandoned'; attempts: Attempt[] }

export async function mockTrainingApi(page: Page, cards: Card[] = sampleCards) {
  const sessions: Session[] = []
  const history: { cardId: string; correct: boolean; mode: Mode; sessionId: string }[] = []
  const progress = new Map<string, { correct: number; incorrect: number; due: boolean }>()
  let failAnswerResponse = false
  const activeCards = () => cards.filter(card => !card.deleted_at)
  const matches = (card: Card, filters: TrainingFilters) =>
    (filters.section_mode === 'all' || (filters.section_mode === 'unsectioned'
      ? !card.section?.trim() : card.section?.trim() === filters.section))
    && (filters.category_mode === 'all' || (filters.category_mode === 'uncategorized'
      ? !card.category?.trim() : card.category?.trim() === filters.category))
    && (!filters.difficulty || card.difficulty === filters.difficulty)
  const jsonError = (message: string, status = 400) => ({ status, json: { message, code: status === 409 ? '23505' : '22023' } })

  await page.route('**/rest/v1/rpc/**', async route => {
    const name = new URL(route.request().url()).pathname.split('/').pop()
    const input = (route.request().postDataJSON() ?? {}) as Record<string, string | boolean | number | null>
    if (name === 'get_training_stats') {
      const active = activeCards()
      const visibleHistory = history.filter(item => active.some(card => card.id === item.cardId))
      return route.fulfill({ json: {
        answers: visibleHistory.length,
        correct: visibleHistory.filter(item => item.correct).length,
        incorrect: visibleHistory.filter(item => !item.correct).length,
        learning: active.filter(card => progress.has(card.id) && progress.get(card.id)!.correct < 5).length,
        mastered: active.filter(card => (progress.get(card.id)?.correct ?? 0) >= 5).length,
        due: active.filter(card => !progress.has(card.id) || progress.get(card.id)!.due).length,
      } })
    }
    if (name === 'start_section_training_session') {
      const topicId = input.p_topic_id as string
      const mode = input.p_mode as Mode
      const filters: TrainingFilters = {
        section_mode: input.p_section_mode as TrainingFilters['section_mode'],
        section: input.p_section as string | null,
        category_mode: input.p_category_mode as TrainingFilters['category_mode'],
        category: input.p_category as string | null,
        difficulty: input.p_difficulty as TrainingFilters['difficulty'],
      }
      const existing = sessions.find(session => session.topicId === topicId && session.mode === mode && session.status === 'active')
      if (existing) return route.fulfill({ json: { session_id: existing.id, filters: existing.filters,
        conflict: JSON.stringify(existing.filters) !== JSON.stringify(filters) } })
      if (filters.section_mode !== 'all' && !activeCards().some(card => card.topic_id === topicId &&
        (filters.section_mode === 'named' ? card.section?.trim() === filters.section : !card.section?.trim())))
        return route.fulfill(jsonError('Active section not found'))
      if (filters.category_mode !== 'all' && !activeCards().some(card => card.topic_id === topicId &&
        (filters.section_mode === 'all' || (filters.section_mode === 'named' ? card.section?.trim() === filters.section : !card.section?.trim())) &&
        (filters.category_mode === 'named' ? card.category?.trim() === filters.category : !card.category?.trim())))
        return route.fulfill(jsonError('Active category not found'))
      const eligible = activeCards().filter(card => card.topic_id === topicId && matches(card, filters) && (
        mode === 'infinite' || (mode === 'spaced' ? !progress.has(card.id) || progress.get(card.id)!.due : (progress.get(card.id)?.incorrect ?? 0) > 0)
      ))
      const session: Session = { id: randomUUID(), topicId, mode, filters, status: 'active', attempts: mode === 'infinite' ? [] : eligible.map((card, index) => ({ id: randomUUID(), card, position: index + 1, status: 'queued' })) }
      sessions.push(session)
      return route.fulfill({ json: { session_id: session.id, filters, conflict: false } })
    }
    if (name === 'next_training_attempt') {
      const session = sessions.find(item => item.id === input.p_session_id)
      if (!session || session.status !== 'active') return route.fulfill(jsonError('Active training session not found'))
      let attempt = session.attempts.find(item => item.status === 'issued')
      if (attempt && (!activeCards().some(card => card.id === attempt!.card.id) || !matches(attempt.card, session.filters))) {
        attempt.status = 'skipped'
        attempt = undefined
      }
      if (!attempt && session.mode === 'infinite') {
        const candidates = activeCards().filter(card => card.topic_id === session.topicId && matches(card, session.filters))
        const lastCard = session.attempts.at(-1)?.card.id
        const chosen = candidates.find(card => card.id !== lastCard) ?? candidates[0]
        if (chosen) {
          attempt = { id: randomUUID(), card: chosen, position: session.attempts.length + 1, status: 'issued' }
          session.attempts.push(attempt)
        }
      } else if (!attempt) {
        session.attempts.filter(item => item.status === 'queued' &&
          (!activeCards().some(card => card.id === item.card.id) || !matches(item.card, session.filters)))
          .forEach(item => { item.status = 'skipped' })
        attempt = session.attempts.find(item => item.status === 'queued')
        if (attempt) attempt.status = 'issued'
      }
      const answers = history.filter(item => item.sessionId === session.id)
      return route.fulfill({ json: {
        session_id: session.id, mode: session.mode, filters: session.filters,
        total: session.mode === 'infinite' ? null : session.attempts.filter(item => item.status !== 'skipped').length,
        viewed: session.attempts.filter(item => item.status === 'answered').length,
        correct: answers.filter(item => item.correct).length,
        incorrect: answers.filter(item => !item.correct).length,
        attempt: attempt ? {
          attempt_id: attempt.id, position: attempt.position,
          issued_at: new Date().toISOString(),
          card: {
            id: attempt.card.id, section: attempt.card.section, category: attempt.card.category, question: attempt.card.question,
            context: attempt.card.context, answer: attempt.card.answer,
            hint_1: attempt.card.hint_1, hint_2: attempt.card.hint_2,
            difficulty: attempt.card.difficulty, code: attempt.card.code,
          },
        } : null,
      } })
    }
    if (name === 'record_answer') {
      const session = sessions.find(item => item.id === input.p_session_id)
      const attempt = session?.attempts.find(item => item.id === input.p_attempt_id)
      if (!session || !attempt || attempt.card.id !== input.p_card_id) return route.fulfill(jsonError('Attempt not found'))
      if (attempt.status === 'answered') {
        if (attempt.eventId !== input.p_event_id || JSON.stringify(attempt.payload) !== JSON.stringify(input))
          return route.fulfill(jsonError('Attempt already answered', 409))
        return route.fulfill({ json: attempt.eventId })
      }
      if (session.status !== 'active' || attempt.status !== 'issued') return route.fulfill(jsonError('Active issued attempt required'))
      if (!activeCards().some(card => card.id === attempt.card.id) || !matches(attempt.card, session.filters))
        return route.fulfill(jsonError('Card no longer matches session filters'))
      attempt.status = 'answered'
      attempt.eventId = input.p_event_id as string
      attempt.payload = input
      history.push({ cardId: attempt.card.id, correct: input.p_is_correct as boolean, mode: session.mode, sessionId: session.id })
      if (session.mode === 'spaced') {
        const prior = progress.get(attempt.card.id) ?? { correct: 0, incorrect: 0, due: true }
        progress.set(attempt.card.id, {
          correct: input.p_is_correct ? prior.correct + 1 : 0,
          incorrect: prior.incorrect + (input.p_is_correct ? 0 : 1),
          due: false,
        })
      }
      if (failAnswerResponse) {
        failAnswerResponse = false
        return route.abort('failed')
      }
      return route.fulfill({ json: attempt.eventId })
    }
    if (name === 'finish_training_session') {
      const session = sessions.find(item => item.id === input.p_session_id)
      if (!session) return route.fulfill(jsonError('Training session not found'))
      session.status = input.p_status as Session['status']
      session.attempts.filter(item => item.status === 'issued' || item.status === 'queued').forEach(item => { item.status = 'skipped' })
      return route.fulfill({ json: session.id })
    }
    return route.fulfill({ status: 404 })
  })

  return {
    sessions,
    history,
    progress,
    loseNextAnswerResponse: () => { failAnswerResponse = true },
  }
}
