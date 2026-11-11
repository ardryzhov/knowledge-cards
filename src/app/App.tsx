import { useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { AnimatePresence, MotionConfig, motion } from 'motion/react'
import { Layout } from '@/components/layout/Layout'
import { Dashboard } from '@/features/dashboard/Dashboard'
import { Training } from '@/features/training/Training'
import { Statistics } from '@/features/statistics/Statistics'
import { Topics } from '@/features/topics/Topics'
import type { Screen } from '@/types/navigation'
import { loadTopics, type TopicSummary } from '@/lib/supabase/data'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Login } from '@/features/auth/Login'
import { signOut } from '@/lib/supabase/auth'
import { supabase } from '@/lib/supabase/client'
import '@/features/dashboard/dashboard.css'

function currentScreen(): Screen {
  const screen = window.location.hash.slice(1).split(/[/?]/)[0]
  return screen === 'training' || screen === 'statistics' || screen === 'topics' ? screen : 'dashboard'
}

function topicFromHash(hash: string) {
  const id = hash.slice(1).split('?')[0].split('/')[1]
  if (!id) return undefined
  try { return decodeURIComponent(id) } catch { return id }
}

function PrototypeApp({ onSignOut }: { onSignOut: () => void }) {
  const [topicItems, setTopicItems] = useState<readonly TopicSummary[]>([])
  const [contentState, setContentState] = useState<'loading' | 'ready' | 'error'>('loading')
  const [reloadKey, setReloadKey] = useState(0)
  const [route, setRoute] = useState(() => ({ screen: currentScreen(), hash: window.location.hash }))
  useEffect(() => {
    let active = true
    loadTopics().then(items => {
      if (!active) return
      setTopicItems(items)
      setContentState('ready')
    }).catch(() => {
      if (!active) return
      setContentState('error')
    })
    return () => { active = false }
  }, [reloadKey])
  useEffect(() => {
    const onHash = () => {
      setRoute({ screen: currentScreen(), hash: window.location.hash })
      window.scrollTo({ top: 0, behavior: 'instant' })
    }
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])
  useEffect(() => {
    const title = { dashboard: 'Обзор', training: 'Тренировка', statistics: 'Статистика', topics: 'Направления' }[route.screen]
    document.title = `${title} · Knowledge Cards`
    document.getElementById('main-content')?.focus({ preventScroll: true })
  }, [route.screen])
  const topicId = route.screen === 'topics' ? topicFromHash(route.hash) : undefined
  const content = contentState === 'loading'
    ? <Card className="db-empty" role="status"><p>Загружаем темы и карточки…</p></Card>
    : contentState === 'error'
      ? <Card className="db-empty" role="alert"><p>Не удалось загрузить темы и карточки.</p><small>Проверьте подключение к сети и попробуйте снова.</small><Button variant="outline" onClick={() => { setContentState('loading'); setReloadKey(value => value + 1) }}>Повторить загрузку</Button></Card>
      : null
  return <MotionConfig reducedMotion="user"><a className="skip-link" href="#main-content" onClick={event => { event.preventDefault(); document.getElementById('main-content')?.focus() }}>К содержимому</a><Layout screen={route.screen} onSignOut={onSignOut}><AnimatePresence mode="wait"><motion.div key={route.hash} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} transition={{ duration: 0.18 }}>{content ?? (route.screen === 'training' ? <Training topicItems={topicItems} onSignOut={onSignOut} /> : route.screen === 'dashboard' ? <Dashboard topicItems={topicItems} onSignOut={onSignOut} /> : route.screen === 'topics' ? <Topics topicId={topicId} topicItems={topicItems} /> : <Statistics topicItems={topicItems} />)}</motion.div></AnimatePresence></Layout></MotionConfig>
}

export function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [ready, setReady] = useState(false)
  const [authError, setAuthError] = useState('')

  useEffect(() => {
    if (!supabase) return
    let active = true
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, current) => {
      if (!active) return
      setSession(current)
      setReady(true)
      setAuthError('')
    })
    supabase.auth.getSession().then(({ data, error }) => {
      if (!active) return
      if (error) setAuthError('Не удалось восстановить сессию. Попробуйте войти снова.')
      else setSession(data.session)
      setReady(true)
    }).catch(() => {
      if (!active) return
      setAuthError('Не удалось восстановить сессию. Проверьте подключение к сети.')
      setReady(true)
    })
    return () => { active = false; subscription.unsubscribe() }
  }, [])

  useEffect(() => {
    if (!session) document.title = 'Вход · Knowledge Cards'
  }, [session])

  async function handleSignOut() {
    try { await signOut() }
    catch { setAuthError('Не удалось выйти. Проверьте подключение к сети и попробуйте снова.') }
  }

  if (!supabase) return <main className="auth-status"><div className="panel" role="alert">Supabase не настроен. Добавьте VITE_SUPABASE_URL и VITE_SUPABASE_PUBLISHABLE_KEY в .env.local и перезапустите приложение.</div></main>
  if (!ready) return <main className="auth-status" aria-live="polite">Восстанавливаем сессию…</main>
  return <>{session ? <PrototypeApp onSignOut={handleSignOut} /> : <Login />}{authError && <div className="auth-notice" role="alert">{authError}</div>}</>
}
