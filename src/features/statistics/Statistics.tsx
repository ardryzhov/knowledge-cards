import { BookOpen, Check, Layers3, RotateCcw } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { SectionHeading } from '@/components/layout/Layout'
import type { TopicSummary } from '@/lib/supabase/data'
import { useTrainingStats } from './useTrainingStats'

export function Statistics({ topicItems }: { topicItems: readonly TopicSummary[] }) {
  const total = topicItems.reduce((sum, topic) => sum + topic.cardCount, 0)
  const stats = useTrainingStats()
  const newCards = stats.data && total >= stats.data.learning + stats.data.mastered
    ? total - stats.data.learning - stats.data.mastered : null
  const accuracy = stats.data && stats.data.answers > 0
    ? `${Math.round(stats.data.correct / stats.data.answers * 100)}%` : '—'
  return <>
    <SectionHeading eyebrow="ПРОГРЕСС ОБУЧЕНИЯ" title="Статистика" description="Состояние активных карточек и сохранённые ответы." />
    {stats.state === 'loading' && <Card className="db-empty" role="status"><p>Загружаем статистику…</p></Card>}
    {stats.state === 'error' && <Card className="db-empty" role="alert"><p>Не удалось загрузить статистику.</p><Button variant="outline" onClick={stats.retry}>Повторить загрузку</Button></Card>}
    {stats.state === 'ready' && stats.data && <div className="metric-grid stats-metrics">
      {[
        { label: 'Активных карточек', value: total, icon: Layers3 },
        { label: 'Новые', value: newCards ?? '—', icon: BookOpen },
        { label: 'Изучаются', value: stats.data.learning, icon: BookOpen },
        { label: 'Освоены', value: stats.data.mastered, icon: Check },
        { label: 'Пора повторить', value: stats.data.due, icon: RotateCcw },
        { label: 'Всего ответов', value: stats.data.answers, icon: Layers3 },
        { label: 'Процент правильных ответов', value: accuracy, icon: Check },
      ].map(({ label, value, icon: Icon }) => <Card className="metric" key={label}><div className="metric-label">{label}<Icon size={18} /></div><div className="metric-value">{value}</div></Card>)}
    </div>}
  </>
}
