import { BookOpen, ChevronRight, Code2, Languages, Server, type LucideIcon } from 'lucide-react'
import { Card } from '@/components/ui/card'
import type { TopicSummary } from '@/lib/supabase/data'

const icons: Record<string, LucideIcon> = { development: Code2, english: Languages, devops: Server }
const cardWord = (count: number) => {
  const form = new Intl.PluralRules('ru').select(count)
  return form === 'one' ? 'карточка' : form === 'few' ? 'карточки' : 'карточек'
}

export function TopicRows({ items }: { items: readonly TopicSummary[] }) {
  if (!items.length) return <Card className="db-empty"><p>Пока нет направлений</p><small>Темы появятся после добавления контента через SQL-миграцию.</small></Card>
  return <div className="topic-rows">{items.map(topic => {
    const Icon = icons[topic.icon ?? ''] ?? BookOpen
    return <a href={`#topics/${encodeURIComponent(topic.id)}`} className={`topic-row panel topic-row-${topic.color}`} key={topic.id}>
      <span className="topic-row-icon"><Icon size={23} /></span>
      <span className="topic-row-text"><strong>{topic.title}</strong><small title={topic.description ?? ''}>{topic.description ?? 'Учебные карточки'}</small></span>
      <span className="topic-row-progress"><span>{topic.cardCount}<small> {cardWord(topic.cardCount)}</small></span></span>
      <ChevronRight size={18} className="topic-row-arrow" />
    </a>
  })}</div>
}
