export type Difficulty = 'easy' | 'medium' | 'hard'
export type CategoryMode = 'all' | 'named' | 'uncategorized'
export type SectionMode = 'all' | 'named' | 'unsectioned'

export interface TrainingFilters {
  section_mode: SectionMode
  section: string | null
  category_mode: CategoryMode
  category: string | null
  difficulty: Difficulty | null
}

export const allFilters: TrainingFilters = {
  section_mode: 'all',
  section: null,
  category_mode: 'all',
  category: null,
  difficulty: null,
}

export const difficultyNames: Record<Difficulty, string> = {
  easy: 'Легко',
  medium: 'Средне',
  hard: 'Сложно',
}

export function categoryName(value: string | null): string | null {
  return value?.trim() || null
}

export function sectionName(value: string | null): string | null {
  return value?.trim() || null
}

export function sectionTitle(value: string | null): string {
  const name = sectionName(value)
  if (!name) return 'Без раздела'
  return name.replace(/^\d+[-_]/, '').split(/[-_]+/).map(part =>
    part ? part[0]!.toLocaleUpperCase('ru') + part.slice(1) : '').join(' ')
}

export function readTrainingFilters(params: URLSearchParams): TrainingFilters {
  const rawSectionMode = params.get('section_mode')
  const section = sectionName(params.get('section'))
  const section_mode: SectionMode = rawSectionMode === 'unsectioned' ? 'unsectioned'
    : rawSectionMode === 'named' && section ? 'named' : 'all'
  const rawMode = params.get('category_mode')
  const category = categoryName(params.get('category'))
  const category_mode: CategoryMode =
    rawMode === 'uncategorized' ? 'uncategorized'
      : rawMode === 'named' && category ? 'named' : 'all'
  const rawDifficulty = params.get('difficulty')
  const difficulty = rawDifficulty === 'easy' || rawDifficulty === 'medium' || rawDifficulty === 'hard'
    ? rawDifficulty : null
  return { section_mode, section: section_mode === 'named' ? section : null,
    category_mode, category: category_mode === 'named' ? category : null, difficulty }
}

export function filterQuery(topicId: string, filters: TrainingFilters, mode?: string): string {
  const params = new URLSearchParams({ topic: topicId })
  if (mode) params.set('mode', mode)
  if (filters.section_mode !== 'all') {
    params.set('section_mode', filters.section_mode)
    if (filters.section_mode === 'named' && filters.section) params.set('section', filters.section)
  }
  if (filters.category_mode !== 'all') {
    params.set('category_mode', filters.category_mode)
    if (filters.category_mode === 'named' && filters.category) params.set('category', filters.category)
  }
  if (filters.difficulty) params.set('difficulty', filters.difficulty)
  return params.toString()
}

export function trainingHash(topicId: string, filters: TrainingFilters, mode?: string): string {
  return `#training?${filterQuery(topicId, filters, mode)}`
}

export function topicHash(topicId: string, filters: TrainingFilters): string {
  const params = new URLSearchParams()
  if (filters.section_mode !== 'all') {
    params.set('section_mode', filters.section_mode)
    if (filters.section_mode === 'named' && filters.section) params.set('section', filters.section)
  }
  if (filters.category_mode !== 'all') {
    params.set('category_mode', filters.category_mode)
    if (filters.category_mode === 'named' && filters.category) params.set('category', filters.category)
  }
  if (filters.difficulty) params.set('difficulty', filters.difficulty)
  const suffix = params.toString()
  return `#topics/${encodeURIComponent(topicId)}${suffix ? `?${suffix}` : ''}`
}

export function filterLabels(filters: TrainingFilters): string[] {
  return [
    filters.section_mode === 'named' ? sectionTitle(filters.section)
      : filters.section_mode === 'unsectioned' ? 'Без раздела' : 'Все разделы',
    filters.category_mode === 'named' ? filters.category ?? 'Все группы'
      : filters.category_mode === 'uncategorized' ? 'Без группы' : 'Все группы',
    filters.difficulty ? difficultyNames[filters.difficulty] : 'Все сложности',
  ]
}
