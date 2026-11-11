import { ArrowRight, Layers3, LogOut } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { TopicRows } from '@/features/topics/TopicRows'
import { useTrainingStats } from '@/features/statistics/useTrainingStats'
import type { TopicSummary } from '@/lib/supabase/data'

interface DashboardProps {
  topicItems: readonly TopicSummary[]
  onSignOut?: () => void
}

export function Dashboard({ topicItems, onSignOut }: DashboardProps) {
  const total = topicItems.reduce((sum, topic) => sum + topic.cardCount, 0)
  const stats = useTrainingStats()
  return <div className="dashboard-home dashboard-focus">
    <header className="db-heading"><span><i className="status-dot" />KNOWLEDGE CARDS</span>{onSignOut && <button className="signout-button" onClick={onSignOut} type="button" aria-label="Выйти из аккаунта" title="Выйти"><LogOut size={17} /></button>}<h1>Что повторить сегодня<span>?</span></h1></header>

    <Card className="db-review" aria-labelledby="db-review-title">
      <span className="db-review-icon"><Layers3 size={28} /></span>
      <div className="db-review-copy"><h2 id="db-review-title">К повторению сейчас</h2><div className="db-review-count"><strong>{stats.state === 'ready' ? stats.data?.due ?? '—' : '—'}</strong><span>карточек</span></div></div>
      <div className="db-review-action">{total > 0 ? <Button asChild><a href="#training">Начать тренировку<ArrowRight size={15} /></a></Button> : <Button disabled>Нет карточек</Button>}</div>
    </Card>
    {stats.state === 'loading' && <Card className="db-empty" role="status"><p>Загружаем прогресс…</p></Card>}
    {stats.state === 'error' && <Card className="db-empty" role="alert"><p>Не удалось загрузить прогресс.</p><Button variant="outline" onClick={stats.retry}>Повторить загрузку</Button></Card>}

    <section aria-labelledby="db-topics-title"><div className="db-section-heading"><h2 id="db-topics-title">Направления</h2><span>{total} активных карточек</span></div><TopicRows items={topicItems} /></section>
    <a className="db-statistics-link" href="#statistics">Посмотреть статистику обучения<ArrowRight size={16} /></a>
  </div>
}
