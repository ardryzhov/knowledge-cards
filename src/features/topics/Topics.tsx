import { useEffect, useState } from 'react'
import { ArrowLeft, ArrowRight } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import {
  categoryName, difficultyNames, readTrainingFilters, sectionName, sectionTitle,
  topicHash, trainingHash, type Difficulty, type TrainingFilters,
} from '@/lib/training-filters'
import { loadCards, type CardRecord, type TopicSummary } from '@/lib/supabase/data'
import { TopicRows } from './TopicRows'

function compareNames(left: string | null, right: string | null) {
  return left === null ? 1 : right === null ? -1
    : left.localeCompare(right, 'ru', { numeric: true })
}

export function Topics({ topicId, topicItems }: { topicId?: string; topicItems: readonly TopicSummary[] }) {
  const topic = topicItems.find(item => item.id === topicId)
  const [cards, setCards] = useState<CardRecord[]>([])
  const [state, setState] = useState<'loading' | 'ready' | 'error'>('loading')
  const [reloadKey, setReloadKey] = useState(0)
  const [filters, setFilters] = useState<TrainingFilters>(() =>
    readTrainingFilters(new URLSearchParams(window.location.hash.split('?')[1])))

  useEffect(() => {
    if (!topic) return
    let active = true
    loadCards(topic.id).then(items => {
      if (!active) return
      setCards(items)
      setState('ready')
    }).catch(() => {
      if (!active) return
      setCards([])
      setState('error')
    })
    return () => { active = false }
  }, [topic, reloadKey])

  function chooseFilters(next: TrainingFilters) {
    setFilters(next)
    if (topic) window.history.replaceState(null, '', topicHash(topic.id, next))
  }

  if (!topicId) return <div className="dashboard-related">
    <a className="db-back" href="#dashboard"><ArrowLeft size={16} />На главную</a>
    <header className="db-heading"><span>Твоя база знаний</span><h1>Направления<span>.</span></h1></header>
    <TopicRows items={topicItems} />
  </div>

  if (!topic) return <div className="dashboard-related">
    <Card className="db-empty"><h1>Направление не найдено</h1><p>Направление отсутствует или недоступно.</p>
      <Button asChild variant="outline"><a href="#topics">Все направления<ArrowRight size={16} /></a></Button>
    </Card>
  </div>

  const sections = new Map<string | null, number>()
  for (const card of cards) {
    const name = sectionName(card.section)
    sections.set(name, (sections.get(name) ?? 0) + 1)
  }
  const sortedSections = [...sections.entries()].sort(([a], [b]) => compareNames(a, b))
  const sectionCards = cards.filter(card => filters.section_mode === 'all'
    || (filters.section_mode === 'unsectioned'
      ? sectionName(card.section) === null : sectionName(card.section) === filters.section))
  const groups = new Map<string | null, number>()
  if (filters.section_mode !== 'all') for (const card of sectionCards) {
    const name = categoryName(card.category)
    groups.set(name, (groups.get(name) ?? 0) + 1)
  }
  const sortedGroups = [...groups.entries()].sort(([a], [b]) => compareNames(a, b))
  const visibleCards = sectionCards.filter(card => {
    const name = categoryName(card.category)
    return (filters.category_mode === 'all'
      || (filters.category_mode === 'uncategorized' ? name === null : name === filters.category))
      && (!filters.difficulty || card.difficulty === filters.difficulty)
  })
  const displaySections = new Map<string | null, Map<string | null, CardRecord[]>>()
  for (const card of visibleCards) {
    const section = sectionName(card.section)
    const group = categoryName(card.category)
    const sectionGroups = displaySections.get(section) ?? new Map<string | null, CardRecord[]>()
    const items = sectionGroups.get(group) ?? []
    items.push(card)
    sectionGroups.set(group, items)
    displaySections.set(section, sectionGroups)
  }
  const sortedDisplay = [...displaySections.entries()].sort(([a], [b]) => compareNames(a, b))

  return <div className="dashboard-related">
    <a className="db-back" href="#topics"><ArrowLeft size={16} />Все направления</a>
    <header className="db-heading"><span>Направление</span><h1>{topic.title}<span>.</span></h1>{topic.description && <p>{topic.description}</p>}</header>
    <Card className="db-topic-overview">
      <div><strong>{state === 'ready' ? cards.length : topic.cardCount}</strong><span>активных карточек</span></div>
      <div className="db-topic-filters">
        <div className="db-subtopic-heading"><strong>Разделы</strong><span>Выберите раздел или тренируйте всё направление</span></div>
        <div className="db-subtopic-list" aria-label="Разделы">
          <button type="button" aria-pressed={filters.section_mode === 'all'} onClick={() =>
            chooseFilters({ ...filters, section_mode: 'all', section: null, category_mode: 'all', category: null })}>
            Все разделы <span>{cards.length}</span>
          </button>
          {sortedSections.map(([name, count]) => <button key={name ?? '__unsectioned__'} type="button"
            aria-pressed={name === null ? filters.section_mode === 'unsectioned'
              : filters.section_mode === 'named' && filters.section === name}
            onClick={() => chooseFilters({ ...filters,
              section_mode: name === null ? 'unsectioned' : 'named', section: name,
              category_mode: 'all', category: null,
            })}>
            {sectionTitle(name)} <span>{count}</span>
          </button>)}
        </div>
        {filters.section_mode !== 'all' && <>
          <div className="db-subtopic-heading"><strong>Группы вопросов</strong><span>{filters.section_mode === 'named' ? filters.section : 'Карточки без раздела'}</span></div>
          <div className="db-subtopic-list" aria-label="Группы вопросов">
            <button type="button" aria-pressed={filters.category_mode === 'all'} onClick={() =>
              chooseFilters({ ...filters, category_mode: 'all', category: null })}>
              Все группы <span>{sectionCards.length}</span>
            </button>
            {sortedGroups.map(([name, count]) => <button key={name ?? '__uncategorized__'} type="button"
              aria-pressed={name === null ? filters.category_mode === 'uncategorized'
                : filters.category_mode === 'named' && filters.category === name}
              onClick={() => chooseFilters({ ...filters,
                category_mode: name === null ? 'uncategorized' : 'named', category: name,
              })}>
              {name ?? 'Без группы'} <span>{count}</span>
            </button>)}
          </div>
        </>}
        <label className="db-difficulty-filter">Сложность
          <select value={filters.difficulty ?? ''} onChange={event =>
            chooseFilters({ ...filters, difficulty: (event.target.value || null) as Difficulty | null })}>
            <option value="">Все сложности</option>
            <option value="easy">Легко</option>
            <option value="medium">Средне</option>
            <option value="hard">Сложно</option>
          </select>
        </label>
      </div>
      <div className="db-topic-modes">
        {visibleCards.length > 0 ? <Button asChild><a href={trainingHash(topic.id, filters)}>Тренироваться<ArrowRight size={15} /></a></Button>
          : <Button disabled>Нет карточек для тренировки</Button>}
      </div>
    </Card>
    <div className="db-section-heading"><h2>Карточки · {visibleCards.length}</h2></div>
    {state === 'loading' ? <Card className="db-empty" role="status"><p>Загружаем карточки…</p></Card>
      : state === 'error' ? <Card className="db-empty" role="alert"><p>Не удалось загрузить карточки.</p><small>Проверьте подключение к сети и попробуйте снова.</small><Button variant="outline" onClick={() => { setState('loading'); setReloadKey(value => value + 1) }}>Повторить загрузку</Button></Card>
        : sortedDisplay.length ? <div className="db-topic-groups">{sortedDisplay.map(([section, sectionGroups]) => <section key={section ?? '__unsectioned__'} aria-label={sectionTitle(section)}>
          <div className="db-section-heading"><h2>{sectionTitle(section)}</h2><span>{[...sectionGroups.values()].reduce((sum, items) => sum + items.length, 0)}</span></div>
          {[...sectionGroups.entries()].sort(([a], [b]) => compareNames(a, b)).map(([group, items]) => <div className="db-question-group" key={group ?? '__uncategorized__'}>
            <h3>{group ?? 'Без группы'} <span>{items.length}</span></h3>
            <div className="db-topic-examples">{items.map(card => <Card key={card.id}>
              <h2>{card.question}</h2><small>{sectionTitle(card.section)} · {categoryName(card.category) ?? 'Без группы'} · {difficultyNames[card.difficulty]}</small>
              {card.context && <p>{card.context}</p>}
              <details className="db-card-answer"><summary>Показать ответ и подсказки</summary>
                {card.hint_1 && <p><strong>Подсказка 1:</strong> {card.hint_1}</p>}
                {card.hint_2 && <p><strong>Подсказка 2:</strong> {card.hint_2}</p>}
                <p><strong>Ответ:</strong> {card.answer}</p>
                {card.code && <pre><code>{card.code}</code></pre>}
              </details>
            </Card>)}</div>
          </div>)}
        </section>)}</div>
          : <Card className="db-empty"><p>{cards.length ? 'Нет карточек с выбранными фильтрами' : 'В этом направлении пока нет карточек'}</p>
            <small>{cards.length ? 'Выберите другой раздел, группу или сложность.' : 'Карточки появятся после добавления контента через SQL-миграцию.'}</small>
          </Card>}
  </div>
}
