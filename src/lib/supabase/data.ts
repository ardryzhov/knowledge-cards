import { supabase } from './client'

export interface TopicRecord {
  id: string
  title: string
  description: string | null
  color: 'green' | 'blue' | 'amber'
  icon: string | null
  sort_order: number
  created_at: string
  updated_at: string
}

export interface TopicSummary extends TopicRecord {
  cardCount: number
}

export interface CardRecord {
  id: string
  topic_id: string
  section: string | null
  category: string | null
  question: string
  context: string | null
  answer: string
  hint_1: string | null
  hint_2: string | null
  difficulty: 'easy' | 'medium' | 'hard'
  code: string | null
  created_at: string
  updated_at: string
}

const pageSize = 500

function client() {
  if (!supabase) throw new Error('Supabase не настроен.')
  return supabase
}

// Only active rows are read. PostgreSQL RLS remains the authority for ownership.
export async function loadTopics(): Promise<TopicSummary[]> {
  const db = client()
  const topics: TopicRecord[] = []
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await db.from('topics')
      .select('id, title, description, color, icon, sort_order, created_at, updated_at')
      .is('deleted_at', null)
      .order('sort_order', { ascending: true })
      .order('created_at', { ascending: true })
      .order('id', { ascending: true })
      .range(offset, offset + pageSize - 1)
      .retry(false)
    if (error) throw error
    topics.push(...(data as TopicRecord[]))
    if (data.length < pageSize) break
  }

  const counts = new Map<string, number>()
  if (topics.length) {
    const ids = topics.map(topic => topic.id)
    for (let offset = 0; ; offset += pageSize) {
      const { data, error } = await db.from('cards')
        .select('id, topic_id')
        .in('topic_id', ids)
        .is('deleted_at', null)
        .order('id', { ascending: true })
        .range(offset, offset + pageSize - 1)
        .retry(false)
      if (error) throw error
      for (const card of data) counts.set(card.topic_id, (counts.get(card.topic_id) ?? 0) + 1)
      if (data.length < pageSize) break
    }
  }
  return topics.map(topic => ({ ...topic, cardCount: counts.get(topic.id) ?? 0 }))
}

export async function loadCards(topicId: string): Promise<CardRecord[]> {
  const db = client()
  const cards: CardRecord[] = []
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await db.from('cards')
      .select('id, topic_id, section, category, question, context, answer, hint_1, hint_2, difficulty, code, created_at, updated_at')
      .eq('topic_id', topicId)
      .is('deleted_at', null)
      .order('created_at', { ascending: true })
      .order('id', { ascending: true })
      .range(offset, offset + pageSize - 1)
      .retry(false)
    if (error) throw error
    cards.push(...(data as CardRecord[]))
    if (data.length < pageSize) break
  }
  return cards
}
