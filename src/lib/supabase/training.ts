import { supabase } from './client'
import type { TrainingFilters } from '@/lib/training-filters'

export type TrainingMode = 'spaced' | 'infinite' | 'mistakes'
export type SessionEndStatus = 'completed' | 'abandoned'

export interface TrainingCard {
  id: string
  section: string | null
  category: string | null
  question: string
  context: string | null
  answer: string
  hint_1: string | null
  hint_2: string | null
  difficulty: 'easy' | 'medium' | 'hard'
  code: string | null
}

export interface TrainingAttempt {
  attempt_id: string
  position: number
  issued_at: string
  card: TrainingCard
}

export interface TrainingSnapshot {
  session_id: string
  mode: TrainingMode
  filters: TrainingFilters
  total: number | null
  viewed: number
  correct: number
  incorrect: number
  attempt: TrainingAttempt | null
}

export interface TrainingStart {
  session_id: string
  filters: TrainingFilters
  conflict: boolean
}

export interface TrainingStats {
  answers: number
  correct: number
  incorrect: number
  learning: number
  mastered: number
  due: number
}

function client() {
  if (!supabase) throw new Error('Supabase не настроен.')
  return supabase
}

export async function startTrainingSession(topicId: string, mode: TrainingMode, filters: TrainingFilters): Promise<TrainingStart> {
  const { data, error } = await client().rpc('start_section_training_session', {
    p_topic_id: topicId,
    p_mode: mode,
    p_section_mode: filters.section_mode,
    p_section: filters.section,
    p_category_mode: filters.category_mode,
    p_category: filters.category,
    p_difficulty: filters.difficulty,
  }).retry(false)
  if (error) throw error
  return data as TrainingStart
}

export async function nextTrainingAttempt(sessionId: string): Promise<TrainingSnapshot> {
  const { data, error } = await client().rpc('next_training_attempt', {
    p_session_id: sessionId,
  }).retry(false)
  if (error) throw error
  return data as TrainingSnapshot
}

export async function recordTrainingAnswer(input: {
  eventId: string
  sessionId: string
  attemptId: string
  cardId: string
  correct: boolean
  hintsUsed: number
  durationMs: number | null
}): Promise<string> {
  const { data, error } = await client().rpc('record_answer', {
    p_event_id: input.eventId,
    p_session_id: input.sessionId,
    p_card_id: input.cardId,
    p_is_correct: input.correct,
    p_hints_used: input.hintsUsed,
    p_answer_duration_ms: input.durationMs,
    p_attempt_id: input.attemptId,
  }).retry(false)
  if (error) throw error
  return data as string
}

export async function finishTrainingSession(sessionId: string, status: SessionEndStatus): Promise<string> {
  const { data, error } = await client().rpc('finish_training_session', {
    p_session_id: sessionId,
    p_status: status,
  }).retry(false)
  if (error) throw error
  return data as string
}

export async function loadTrainingStats(): Promise<TrainingStats> {
  const { data, error } = await client().rpc('get_training_stats').retry(false)
  if (error) throw error
  return data as TrainingStats
}
