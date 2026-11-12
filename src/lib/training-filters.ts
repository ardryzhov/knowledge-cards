export type Difficulty = 'easy' | 'medium' | 'hard'
export type CategoryMode = 'all' | 'named' | 'uncategorized'
export type SectionMode = 'all' | 'named' | 'unsectioned' | 'multi'

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

export function selectedSections(filters: TrainingFilters): string[] {
  if (filters.section_mode === 'named') return filters.section ? [filters.section] : []
  if (filters.section_mode === 'unsectioned') return ['']
  if (filters.section_mode !== 'multi') return []
  try {
    const values: unknown = JSON.parse(filters.section ?? '[]')
    return Array.isArray(values) && values.every(value => typeof value === 'string')
      ? [...new Set(values.map(value => value.trim()))].sort() : []
  } catch { return [] }
}

export function sectionSelection(values: string[]): Pick<TrainingFilters, 'section_mode' | 'section'> {
  const names = [...new Set(values.map(value => value.trim()))].sort()
  if (names.length === 1) return names[0] === ''
    ? { section_mode: 'unsectioned', section: null }
    : { section_mode: 'named', section: names[0]! }
  return { section_mode: 'multi', section: JSON.stringify(names) }
}

export function readTrainingFilters(params: URLSearchParams): TrainingFilters {
  const rawSectionMode = params.get('section_mode')
  const section = sectionName(params.get('section'))
  const section_mode: SectionMode = rawSectionMode === 'unsectioned' ? 'unsectioned'
    : rawSectionMode === 'named' && section ? 'named'
      : rawSectionMode === 'multi' ? 'multi' : 'all'
  const multi = section_mode === 'multi'
    ? sectionSelection(selectedSections({ ...allFilters, section_mode, section: params.get('section') })) : null
  const rawMode = params.get('category_mode')
  const category = categoryName(params.get('category'))
  const category_mode: CategoryMode =
    rawMode === 'uncategorized' ? 'uncategorized'
      : rawMode === 'named' && category ? 'named' : 'all'
  const rawDifficulty = params.get('difficulty')
  const difficulty = rawDifficulty === 'easy' || rawDifficulty === 'medium' || rawDifficulty === 'hard'
    ? rawDifficulty : null
  return { section_mode: multi?.section_mode ?? section_mode,
    section: multi?.section ?? (section_mode === 'named' ? section : null),
    category_mode, category: category_mode === 'named' ? category : null, difficulty }
}

export function filterQuery(topicId: string, filters: TrainingFilters, mode?: string): string {
  const params = new URLSearchParams({ topic: topicId })
  if (mode) params.set('mode', mode)
  if (filters.section_mode !== 'all') {
    params.set('section_mode', filters.section_mode)
    if ((filters.section_mode === 'named' || filters.section_mode === 'multi') && filters.section) params.set('section', filters.section)
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
    if ((filters.section_mode === 'named' || filters.section_mode === 'multi') && filters.section) params.set('section', filters.section)
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
  const chosen = selectedSections(filters)
  return [
    filters.section_mode === 'named' ? sectionTitle(filters.section)
      : filters.section_mode === 'unsectioned' ? 'Без раздела'
        : filters.section_mode === 'multi' ? (chosen.length
          ? `Разделы (${chosen.length}): ${chosen.slice(0, 3).map(name => sectionTitle(name || null)).join(', ')}${chosen.length > 3 ? ` +${chosen.length - 3}` : ''}`
          : 'Разделы не выбраны') : 'Все разделы',
    filters.category_mode === 'named' ? filters.category ?? 'Все группы'
      : filters.category_mode === 'uncategorized' ? 'Без группы' : 'Все группы',
    filters.difficulty ? difficultyNames[filters.difficulty] : 'Все сложности',
  ]
}
